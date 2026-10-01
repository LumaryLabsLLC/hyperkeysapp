import CommonCrypto
import CryptoKit
import EventEngine
import Foundation
import Testing
@testable import KeyBindings
import WindowEngine

/// Raycast exports are built here from made-up data, the same way Raycast writes them.
private enum Fixture {
    static let hyper: [[String: String]] = [["modifier": "Ctrl"], ["modifier": "Alt"], ["modifier": "Shift"], ["modifier": "Meta"]]

    static func hotkey(_ code: Int, _ modifiers: [[String: String]] = hyper) -> [String: Any] {
        ["kind": ["shortcut": ["key": ["type": "LayoutIndependent", "code": code], "modifiers": modifiers]]]
    }

    static func command(_ extensionId: String, _ id: String, _ code: Int, _ modifiers: [[String: String]] = hyper) -> [String: Any] {
        ["extensionId": extensionId, "id": id, "macosHotkey": hotkey(code, modifiers)]
    }

    static var settings: [String: Any] { [
        "settings": [
            "general": ["globalHotkey": hotkey(49, [["modifier": "Alt"]]), "hyperKeyCode": "caps_lock", "hyperKeyIncludeShift": true],
            "commands": [
                command("e:r:applications", "ra::=::/System/Applications/Calculator.app", 17), // T
                command("e:r:window-management", "e:r:window-management::left-half", 4), // H
                command("e:r:window-management", "e:r:window-management::almost-maximize", 46), // M
                command("e:r:clipboard-history", "e:r:clipboard-history::clipboard-history", 9), // V
                command("e:r:emoji-picker", "e:r:emoji-picker::search-emoji-symbols", 14), // E
                command("e:r:quicklinks", "e:r:quicklinks::ql-1", 3), // F
                ["extensionId": "e:r:applications", "id": "ra::=::/Applications/Mail.app"], // no hotkey
            ] as [[String: Any]],
        ] as [String: Any],
        "snippets": ["snippets": [
            ["title": "Email", "text": "me@example.com", "keyword": "!em"],
            ["title": "Sign-off", "text": "Thanks,\n{cursor}"],
        ]],
        "quicklinks": ["quicklinks": [["id": "ql-1", "name": "Downloads", "link": "~/Downloads"]]],
        "clipboardHistory": [["text": "something private"]],
    ] }

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// RAYCFG3: magic, header length, gzipped header with salt and nonce, AES-GCM payload and tag.
    static func rayconfig(_ payload: Data, password: String) -> Data {
        let salt = (0..<16).map { UInt8($0 * 7 % 256) }
        let iv = (0..<16).map { UInt8(255 - $0) }
        let hex: ([UInt8]) -> String = { $0.map { String(format: "%02x", $0) }.joined() }
        let header = gzip(json(["schemaVersion": 3, "encryption": ["iv": hex(iv), "salt": hex(salt)]]))

        let key = Scrypt.derive(password: Array(password.utf8), salt: salt, n: 16384, r: 8, p: 1, length: 32)
        let box = try! AES.GCM.seal(gzip(payload), using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: iv))

        var file = Data("RAYCFG3\n".utf8)
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(header)
        file.append(box.ciphertext)
        file.append(box.tag)
        return file
    }

    /// Older exports: OpenSSL-style AES-256-CBC over a 16-byte header and the gzipped payload.
    static func legacyRayconfig(_ payload: Data, password: String) -> Data {
        let passwordBytes = Array(password.utf8)
        let key = Array(SHA256.hash(data: passwordBytes))
        let iv = Array(SHA256.hash(data: key + passwordBytes).prefix(16))
        let plain = [UInt8](repeating: 0xAB, count: 16) + [UInt8](gzip(payload))
        var output = [UInt8](repeating: 0, count: plain.count + kCCBlockSizeAES128)
        let capacity = output.count
        var length = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, plain, plain.count, &output, capacity, &length)
        precondition(status == kCCSuccess)
        return Data(output.prefix(length))
    }

    static func gzip(_ data: Data) -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        out.append(try! (data as NSData).compressed(using: .zlib) as Data)
        withUnsafeBytes(of: crc32(data).littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(data.count).littleEndian) { out.append(contentsOf: $0) }
        return out
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    static func resolver(_ path: String) -> (bundleId: String, name: String)? {
        path.hasSuffix("Calculator.app") ? ("com.apple.calculator", "Calculator") : nil
    }
}

struct ScryptTests {
    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test func matchesRFC7914() {
        let empty = Scrypt.derive(password: [], salt: [], n: 16, r: 1, p: 1, length: 64)
        #expect(hex(empty) == "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")

        let nacl = Scrypt.derive(password: Array("password".utf8), salt: Array("NaCl".utf8), n: 1024, r: 8, p: 16, length: 64)
        #expect(hex(nacl) == "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640")
    }
}

struct RaycastArchiveTests {
    @Test func readsSnippetsExport() throws {
        let data = Fixture.json([
            ["name": "Address", "text": "1 Infinite Loop", "keyword": "!addr"],
            ["name": "Empty", "text": ""],
        ])
        #expect(!RaycastArchive.needsPassword(data))
        let export = try RaycastArchive.read(data, password: nil)
        #expect(export.snippets == [RaycastExport.Snippet(name: "Address", text: "1 Infinite Loop", keyword: "!addr")])
        #expect(export.hotkeys.isEmpty)
    }

    @Test func readsEncryptedSettingsExport() throws {
        let file = Fixture.rayconfig(Fixture.json(Fixture.settings), password: "correct horse")
        #expect(RaycastArchive.needsPassword(file))
        #expect(throws: RaycastImportError.passwordRequired) { try RaycastArchive.read(file, password: nil) }
        #expect(throws: RaycastImportError.wrongPassword) { try RaycastArchive.read(file, password: "wrong") }

        let export = try RaycastArchive.read(file, password: "correct horse")
        #expect(export.snippets.map(\.name) == ["Email", "Sign-off"])
        #expect(export.snippets.first?.keyword == "!em")
        #expect(export.hotkeys.count == 7) // Raycast's own hotkey + six commands
        #expect(export.hotkeys.first == RaycastExport.Hotkey(target: .raycast, keyCode: 49, modifiers: .option))
        #expect(export.hotkeys.contains { $0.target == .app(path: "/System/Applications/Calculator.app") && $0.modifiers == .hyper })
        #expect(export.hotkeys.contains { $0.target == .quicklink(name: "Downloads", link: "~/Downloads") })
    }

    @Test func readsOlderEncryptedExport() throws {
        let file = Fixture.legacyRayconfig(Fixture.json(Fixture.settings), password: "12345678")
        #expect(RaycastArchive.needsPassword(file))
        #expect(throws: RaycastImportError.wrongPassword) { try RaycastArchive.read(file, password: "nope") }
        let export = try RaycastArchive.read(file, password: "12345678")
        #expect(export.snippets.count == 2)
        #expect(export.hotkeys.count == 7)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: RaycastImportError.unreadable) { try RaycastArchive.read(Data("hello".utf8), password: nil) }
        #expect(throws: RaycastImportError.unreadable) { try RaycastArchive.read(Fixture.json(["name": "x"]), password: nil) }
        #expect(throws: RaycastImportError.unreadable) { try RaycastArchive.read(Fixture.json([["a": 1]]), password: nil) }
    }

    @Test func readsOlderHotkeyStrings() throws {
        let hotkey = try #require(RaycastExport.parseHotkey("Control-Option-Shift-Command-17"))
        #expect(hotkey.keyCode == 17)
        #expect(hotkey.modifiers == .hyper)
    }
}

struct RaycastImportPlanTests {
    private func plan(
        bindings: [KeyBinding] = [],
        snippets: [Snippet] = [],
        export: RaycastExport? = nil
    ) throws -> RaycastImportPlan {
        let export = try export ?? RaycastArchive.read(Fixture.json(Fixture.settings), password: nil)
        return RaycastImportPlan(
            export: export,
            hyperKey: .capsLock,
            existingBindings: bindings,
            existingSnippets: snippets,
            resolveApp: Fixture.resolver
        )
    }

    @Test func mapsRaycastCommandsToHyperKeysActions() throws {
        let plan = try plan()
        let actions = Dictionary(uniqueKeysWithValues: plan.shortcuts.map { ($0.key, $0.action) })
        #expect(actions[.t] == .launchApp(bundleId: "com.apple.calculator", appName: "Calculator"))
        #expect(actions[.h] == .windowAction(.leftHalf))
        #expect(actions[.e] == .emojiPicker)
        #expect(actions[.f] == .openFolder(path: "~/Downloads"))
        #expect(actions[.space] == .appSearch)

        // Almost Maximize isn't Maximize, and clipboard history has no equivalent.
        #expect(actions[.m] == nil)
        #expect(Set(plan.skipped.map(\.title)) == ["Almost Maximize", "Clipboard History"])
    }

    @Test func suggestsOnlyHyperShortcutsThatReplaceNothing() throws {
        let plan = try plan(bindings: [KeyBinding(keyCode: .h, action: .windowAction(.rightHalf))])
        let suggested = Set(plan.shortcuts.filter { plan.suggestedShortcuts.contains($0.id) }.map(\.key))
        #expect(suggested == [.t, .e, .f])

        let raycast = try #require(plan.shortcuts.first { $0.key == .space })
        #expect(!raycast.usesHyper)
        #expect(raycast.raycastShortcut == "⌥Space")
        #expect(plan.shortcuts.first { $0.key == .h }?.replacing == .windowAction(.rightHalf))
    }

    @Test func skipsWhatHyperKeysAlreadyHas() throws {
        let plan = try plan(
            bindings: [KeyBinding(keyCode: .e, action: .emojiPicker)],
            snippets: [Snippet(name: "Email", text: "me@example.com")]
        )
        #expect(!plan.shortcuts.contains { $0.key == .e })
        #expect(!plan.snippets.contains { $0.snippet.name == "Email" })
        #expect(plan.alreadyPresent == 2)
    }

    @Test func renamesSnippetsWhoseNameIsTaken() throws {
        let plan = try plan(snippets: [Snippet(name: "email", text: "work@example.com")])
        let email = try #require(plan.snippets.first { $0.originalName == "Email" })
        #expect(email.snippet.name == "Email (Raycast)")
        #expect(email.keyword == "!em")
        #expect(plan.keywordCount == 1)
    }

    @Test func treatsShiftlessHyperAsHyper() throws {
        let export = RaycastExport(
            hotkeys: [.init(target: .command(extensionId: "e:r:system", id: "e:r:system::empty-trash", title: nil), keyCode: 15, modifiers: [.control, .option, .command])],
            hyperIncludesShift: false
        )
        let item = try #require(try plan(export: export).shortcuts.first)
        #expect(item.usesHyper)
        #expect(item.action == .emptyTrash)
        #expect(item.raycastTitle == "Empty Trash")
    }

    @Test func readsWindowCommandsInAnySpelling() {
        #expect(RaycastImportPlan.windowPosition(RaycastImportPlan.normalized("windowManagementTopLeftSixth")) == .topLeftSixth)
        #expect(RaycastImportPlan.windowPosition(RaycastImportPlan.normalized("e:r:window-management::maximize")) == .fullScreen)
        #expect(RaycastImportPlan.windowPosition(RaycastImportPlan.normalized("last-three-fourths")) == nil)
        #expect(RaycastImportPlan.windowPosition(RaycastImportPlan.normalized("first-two-thirds")) == .firstTwoThirds)
    }

    @Test func onlyLocalQuicklinksBecomeFolders() {
        #expect(RaycastImportPlan.localPath("file:///Users/me/Projects") != nil)
        #expect(RaycastImportPlan.localPath("~/Downloads") == "~/Downloads")
        #expect(RaycastImportPlan.localPath("https://github.com") == nil)
        #expect(RaycastImportPlan.localPath("~/notes/{argument}.md") == nil)
    }
}

struct RaycastPlaceholderTests {
    @Test func fillsInRaycastPlaceholders() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let text = SnippetStore.expand("{date format=\"yyyy-MM-dd\"} {day}{cursor} {uuid}", clipboard: nil, now: now)
        #expect(text.hasPrefix("2026-09-"))
        #expect(!text.contains("{"))
        #expect(text.split(separator: " ").last?.count == 36)
    }

    @Test func reportsPlaceholdersItCantFill() {
        let text = "Hi {argument name=\"who\"}, {clipboard} {date offset=\"+1d\"} {snippet name=\"x\"} {argument}"
        #expect(SnippetStore.unsupportedPlaceholders(in: text) == ["{argument}", "{date}", "{snippet}"])
        #expect(SnippetStore.unsupportedPlaceholders(in: "{date format=\"HH:mm\"} {cursor}").isEmpty)
    }
}
