import CryptoKit
import Foundation

/// scrypt (RFC 7914). Raycast derives the key for a `.rayconfig` export from its password with it.
enum Scrypt {
    static func derive(password: [UInt8], salt: [UInt8], n: Int, r: Int, p: Int, length: Int) -> [UInt8] {
        precondition(n > 1 && n & (n - 1) == 0, "N must be a power of two")
        let blockBytes = 128 * r
        let blockWords = 32 * r

        var b = pbkdf2SHA256(password: password, salt: salt, length: p * blockBytes)
        let x = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords)
        let y = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords)
        let t = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        let v = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords * n)
        defer {
            x.deallocate()
            y.deallocate()
            t.deallocate()
            v.deallocate()
        }

        for chunk in 0..<p {
            let start = chunk * blockBytes
            for i in 0..<blockWords {
                let o = start + i * 4
                x[i] = UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
            }
            roMix(x, v: v, y: y, t: t, r: r, n: n)
            for i in 0..<blockWords {
                let o = start + i * 4
                b[o] = UInt8(truncatingIfNeeded: x[i])
                b[o + 1] = UInt8(truncatingIfNeeded: x[i] >> 8)
                b[o + 2] = UInt8(truncatingIfNeeded: x[i] >> 16)
                b[o + 3] = UInt8(truncatingIfNeeded: x[i] >> 24)
            }
        }
        return pbkdf2SHA256(password: password, salt: b, length: length)
    }

    /// PBKDF2-HMAC-SHA256 with a single iteration — the only count scrypt uses —
    /// so each output block is just HMAC(password, salt ‖ blockIndex).
    private static func pbkdf2SHA256(password: [UInt8], salt: [UInt8], length: Int) -> [UInt8] {
        let key = SymmetricKey(data: password)
        var output: [UInt8] = []
        output.reserveCapacity(length + 32)
        var index: UInt32 = 1
        while output.count < length {
            var message = salt
            withUnsafeBytes(of: index.bigEndian) { message.append(contentsOf: $0) }
            output.append(contentsOf: HMAC<SHA256>.authenticationCode(for: message, using: key))
            index += 1
        }
        return Array(output.prefix(length))
    }

    private static func roMix(
        _ x: UnsafeMutablePointer<UInt32>,
        v: UnsafeMutablePointer<UInt32>,
        y: UnsafeMutablePointer<UInt32>,
        t: UnsafeMutablePointer<UInt32>,
        r: Int,
        n: Int
    ) {
        let words = 32 * r
        for i in 0..<n {
            (v + i * words).update(from: x, count: words)
            blockMix(x, y: y, t: t, r: r)
        }
        let mask = UInt32(n - 1)
        let last = (2 * r - 1) * 16
        for _ in 0..<n {
            let vj = v + Int(x[last] & mask) * words
            for k in 0..<words { x[k] ^= vj[k] }
            blockMix(x, y: y, t: t, r: r)
        }
    }

    /// BlockMix with Salsa20/8 over 2r 64-byte blocks. Even outputs go to the first half, odd to the second.
    private static func blockMix(
        _ b: UnsafeMutablePointer<UInt32>,
        y: UnsafeMutablePointer<UInt32>,
        t: UnsafeMutablePointer<UInt32>,
        r: Int
    ) {
        t.update(from: b + (2 * r - 1) * 16, count: 16)
        for i in 0..<(2 * r) {
            let block = b + i * 16
            for k in 0..<16 { t[k] ^= block[k] }
            salsa20_8(t)
            (y + ((i & 1) * r + (i >> 1)) * 16).update(from: t, count: 16)
        }
        b.update(from: y, count: 32 * r)
    }

    @inline(__always)
    private static func rotl(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value &<< count) | (value &>> (32 &- count))
    }

    private static func salsa20_8(_ b: UnsafeMutablePointer<UInt32>) {
        var x0 = b[0], x1 = b[1], x2 = b[2], x3 = b[3]
        var x4 = b[4], x5 = b[5], x6 = b[6], x7 = b[7]
        var x8 = b[8], x9 = b[9], x10 = b[10], x11 = b[11]
        var x12 = b[12], x13 = b[13], x14 = b[14], x15 = b[15]

        for _ in 0..<4 {
            // Columns
            x4 ^= rotl(x0 &+ x12, 7); x8 ^= rotl(x4 &+ x0, 9)
            x12 ^= rotl(x8 &+ x4, 13); x0 ^= rotl(x12 &+ x8, 18)
            x9 ^= rotl(x5 &+ x1, 7); x13 ^= rotl(x9 &+ x5, 9)
            x1 ^= rotl(x13 &+ x9, 13); x5 ^= rotl(x1 &+ x13, 18)
            x14 ^= rotl(x10 &+ x6, 7); x2 ^= rotl(x14 &+ x10, 9)
            x6 ^= rotl(x2 &+ x14, 13); x10 ^= rotl(x6 &+ x2, 18)
            x3 ^= rotl(x15 &+ x11, 7); x7 ^= rotl(x3 &+ x15, 9)
            x11 ^= rotl(x7 &+ x3, 13); x15 ^= rotl(x11 &+ x7, 18)
            // Rows
            x1 ^= rotl(x0 &+ x3, 7); x2 ^= rotl(x1 &+ x0, 9)
            x3 ^= rotl(x2 &+ x1, 13); x0 ^= rotl(x3 &+ x2, 18)
            x6 ^= rotl(x5 &+ x4, 7); x7 ^= rotl(x6 &+ x5, 9)
            x4 ^= rotl(x7 &+ x6, 13); x5 ^= rotl(x4 &+ x7, 18)
            x11 ^= rotl(x10 &+ x9, 7); x8 ^= rotl(x11 &+ x10, 9)
            x9 ^= rotl(x8 &+ x11, 13); x10 ^= rotl(x9 &+ x8, 18)
            x12 ^= rotl(x15 &+ x14, 7); x13 ^= rotl(x12 &+ x15, 9)
            x14 ^= rotl(x13 &+ x12, 13); x15 ^= rotl(x14 &+ x13, 18)
        }

        b[0] &+= x0; b[1] &+= x1; b[2] &+= x2; b[3] &+= x3
        b[4] &+= x4; b[5] &+= x5; b[6] &+= x6; b[7] &+= x7
        b[8] &+= x8; b[9] &+= x9; b[10] &+= x10; b[11] &+= x11
        b[12] &+= x12; b[13] &+= x13; b[14] &+= x14; b[15] &+= x15
    }
}
