import Foundation

public enum Persistence {
    public static var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HyperKeys", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func save<T: Encodable>(_ value: T, to filename: String) throws {
        let url = appSupportURL.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    public static func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T {
        let url = appSupportURL.appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    public static func exists(_ filename: String) -> Bool {
        let url = appSupportURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func delete(_ filename: String) throws {
        let url = appSupportURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
