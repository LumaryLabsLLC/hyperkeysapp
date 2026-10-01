import CommonCrypto
import CryptoKit
import Foundation

public enum RaycastImportError: LocalizedError, Equatable, Sendable {
    case passwordRequired
    case wrongPassword
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .passwordRequired: "This export is protected with a password."
        case .wrongPassword: "That password didn’t unlock the export."
        case .unreadable: "This doesn’t look like a Raycast export. Choose a snippets .json file or a .rayconfig file."
        }
    }
}

/// Reads the files Raycast exports: the `.json` from Export Snippets, and the encrypted
/// `.rayconfig` from Export Settings & Data.
public enum RaycastArchive {
    /// Whether the file needs its export password before it can be read.
    public static func needsPassword(_ data: Data) -> Bool {
        if isJSON(data) || Gzip.isGzip(data) { return false }
        return isCurrentFormat(data) || (data.count >= 32 && data.count.isMultiple(of: kCCBlockSizeAES128))
    }

    public static func read(_ data: Data, password: String?) throws -> RaycastExport {
        try RaycastExport.parse(json(from: data, password: password))
    }

    static func json(from data: Data, password: String?) throws -> Any {
        if isJSON(data) {
            return try parseJSON(data)
        }
        if Gzip.isGzip(data) {
            return try parseJSON(Gzip.decompress(data))
        }
        guard needsPassword(data) else { throw RaycastImportError.unreadable }
        guard let password, !password.isEmpty else { throw RaycastImportError.passwordRequired }
        if isCurrentFormat(data) {
            return try parseJSON(decryptCurrent(data, password: password))
        }
        return try parseJSON(decryptLegacy(data, password: password))
    }

    private static func isJSON(_ data: Data) -> Bool {
        let first = data.first { !($0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw RaycastImportError.unreadable
        }
    }

    // MARK: - Current format

    static let magic = Data("RAYCFG3\n".utf8)
    private static let tagLength = 16

    private static func isCurrentFormat(_ data: Data) -> Bool {
        data.starts(with: Data("RAYCFG".utf8))
    }

    /// `RAYCFG3\n`, a little-endian UInt32 header length, a gzipped JSON header with the
    /// scrypt salt and AES-GCM nonce (hex), then the encrypted gzipped payload and its 16-byte tag.
    private static func decryptCurrent(_ data: Data, password: String) throws -> Data {
        let bytes = [UInt8](data)
        let fixed = magic.count + 4
        guard bytes.count > fixed, bytes.starts(with: magic) else { throw RaycastImportError.unreadable }

        let headerLength = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        let payloadStart = fixed + headerLength
        guard headerLength > 0, payloadStart + tagLength <= bytes.count else { throw RaycastImportError.unreadable }

        var header = Data(bytes[fixed..<payloadStart])
        if Gzip.isGzip(header) {
            header = try Gzip.decompress(header)
        }
        guard let object = try? JSONSerialization.jsonObject(with: header) as? [String: Any],
              let encryption = object["encryption"] as? [String: Any],
              let iv = (encryption["iv"] as? String).flatMap(bytesFromHex), iv.count >= 12,
              let salt = (encryption["salt"] as? String).flatMap(bytesFromHex), !salt.isEmpty
        else { throw RaycastImportError.unreadable }

        let key = Scrypt.derive(password: Array(password.utf8), salt: salt, n: 16384, r: 8, p: 1, length: 32)
        let tagStart = bytes.count - tagLength
        let opened: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: iv),
                ciphertext: Data(bytes[payloadStart..<tagStart]),
                tag: Data(bytes[tagStart...])
            )
            opened = try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw RaycastImportError.wrongPassword
        }
        return try Gzip.decompress(opened)
    }

    // MARK: - Older format

    /// Older Raycast versions: AES-256-CBC with the key and IV from OpenSSL's `-k` (SHA-256, no salt),
    /// then a 16-byte header before the gzipped payload.
    private static func decryptLegacy(_ data: Data, password: String) throws -> Data {
        guard data.count >= 32, data.count % kCCBlockSizeAES128 == 0 else { throw RaycastImportError.unreadable }

        let passwordBytes = Array(password.utf8)
        let key = Array(SHA256.hash(data: passwordBytes))
        let iv = Array(SHA256.hash(data: key + passwordBytes).prefix(16))
        let input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var outputLength = 0

        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, key.count,
            iv,
            input, input.count,
            &output, capacity,
            &outputLength
        )
        guard status == kCCSuccess, outputLength > 16 else { throw RaycastImportError.wrongPassword }
        do {
            return try Gzip.decompress(Data(output[16..<outputLength]))
        } catch {
            // A wrong key still "decrypts" sometimes — into bytes that aren't gzip.
            throw RaycastImportError.wrongPassword
        }
    }

    private static func bytesFromHex(_ hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = hexValue(chars[index]), let low = hexValue(chars[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    private static func hexValue(_ char: UInt8) -> UInt8? {
        switch char {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): char - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): char - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): char - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}

/// Just enough gzip (RFC 1952) to unwrap Raycast's payloads; the inflating is Apple's.
enum Gzip {
    static func isGzip(_ data: Data) -> Bool {
        data.count >= 18 && data.starts(with: [0x1F, 0x8B])
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard isGzip(data), bytes[2] == 8 else { throw RaycastImportError.unreadable }

        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw RaycastImportError.unreadable }
            offset += 2 + (Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8))
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 { // FNAME, FCOMMENT: zero-terminated
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        let end = bytes.count - 8 // CRC32 and size trailer
        guard offset < end else { throw RaycastImportError.unreadable }

        do {
            return try (Data(bytes[offset..<end]) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw RaycastImportError.unreadable
        }
    }
}
