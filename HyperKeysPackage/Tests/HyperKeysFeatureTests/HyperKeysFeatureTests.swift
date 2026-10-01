import AppSwitcher
import CoreGraphics
import EventEngine
import Foundation
import KeyBindings
import Shared
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings
import WindowEngine

@MainActor
struct AppSearchScoringTests {
    private func score(_ name: String, _ query: String) -> Int? {
        AppSearchModel.score(name.lowercased(), query: query.lowercased())
    }

    @Test func exactBeatsPrefix() throws {
        let exact = try #require(score("Notes", "notes"))
        let prefix = try #require(score("Notes Plus", "notes"))
        #expect(exact > prefix)
    }

    @Test func prefixBeatsWordPrefix() throws {
        let prefix = try #require(score("Safari", "saf"))
        let wordPrefix = try #require(score("Apple Safari Beta", "saf"))
        #expect(prefix > wordPrefix)
    }

    @Test func initialsMatch() throws {
        let initials = try #require(score("Visual Studio Code", "vsc"))
        let substring = try #require(score("Mavscan", "vsc"))
        #expect(initials > substring)
    }

    @Test func lettersInOrderStillMatch() {
        #expect(score("Spotify", "sptfy") != nil)
    }

    @Test func noMatchReturnsNil() {
        #expect(score("Calendar", "xyz") == nil)
        #expect(score("Calendar", "radnelac") == nil)
    }

    @Test(arguments: ["Code", "Xcode", "Visual Studio Code"])
    func everyCandidateMatchesItsOwnName(name: String) {
        #expect(score(name, name) == 1000)
    }
}

struct KeyAssignabilityTests {
    @Test func hyperKeyIsNotAssignable() {
        #expect(!KeyCode.grave.isAssignable(hyperKey: .grave))
        #expect(KeyCode.grave.isAssignable(hyperKey: .capsLock))
    }

    @Test func capsLockAndEscapeAreNeverAssignable() {
        #expect(!KeyCode.capsLock.isAssignable(hyperKey: .grave))
        #expect(!KeyCode.escape.isAssignable(hyperKey: .capsLock))
    }

    @Test func lettersAreAssignable() {
        #expect(KeyCode.t.isAssignable(hyperKey: .capsLock))
    }
}

// MARK: - Keyboard Hyper (⌃⌥⇧⌘) mode

/// Collects engine callbacks. The engine calls back synchronously, so a lock is enough.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _combos: [KeyCode] = []
    private var _states: [Bool] = []
    private var _doubleTaps = 0
    private var _repeats: [KeyCode] = []

    var combos: [KeyCode] { lock.withLock { _combos } }
    var states: [Bool] { lock.withLock { _states } }
    var doubleTaps: Int { lock.withLock { _doubleTaps } }
    var repeats: [KeyCode] { lock.withLock { _repeats } }

    func combo(_ key: KeyCode) { lock.withLock { _combos.append(key) } }
    func state(_ down: Bool) { lock.withLock { _states.append(down) } }
    func doubleTap() { lock.withLock { _doubleTaps += 1 } }
    func repeated(_ key: KeyCode) { lock.withLock { _repeats.append(key) } }
}

struct ModifierHyperEngineTests {
    private static let hyperFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    private func makeEngine(handling: @escaping @Sendable (KeyCode) -> Bool = { _ in true }) -> (HyperKeyEngine, Recorder) {
        let engine = HyperKeyEngine()
        let recorder = Recorder()
        engine.hyperKeyCode = KeyCode.modifierHyper.rawValue
        engine.logicalHyperKey = .modifierHyper
        engine.shouldHandleModifierCombo = handling
        engine.onHyperKeyActivated = { recorder.combo($0) }
        engine.onHyperKeyStateChanged = { recorder.state($0) }
        engine.onDoubleTap = { recorder.doubleTap() }
        return (engine, recorder)
    }

    private func key(_ code: KeyCode, down: Bool, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code.rawValue, keyDown: down)!
        event.flags = flags
        return event
    }

    private func modifiers(_ flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true)!
        event.flags = flags
        return event
    }

    @Test func comboWithAllFourModifiersIsHandledAndSwallowed() {
        let (engine, recorder) = makeEngine()
        _ = engine.process(type: .flagsChanged, event: modifiers(Self.hyperFlags))
        let down = engine.process(type: .keyDown, event: key(.t, down: true, flags: Self.hyperFlags))
        let up = engine.process(type: .keyUp, event: key(.t, down: false, flags: Self.hyperFlags))

        #expect(down == nil)
        #expect(up == nil)
        #expect(recorder.combos == [.t])
        #expect(recorder.states == [true])
    }

    @Test func unassignedComboPassesThroughToOtherApps() {
        let (engine, recorder) = makeEngine(handling: { _ in false })
        let down = engine.process(type: .keyDown, event: key(.t, down: true, flags: Self.hyperFlags))
        let up = engine.process(type: .keyUp, event: key(.t, down: false, flags: Self.hyperFlags))

        #expect(down != nil)
        #expect(up != nil)
        #expect(recorder.combos.isEmpty)
    }

    @Test func partialModifiersAreNotHyper() {
        let (engine, recorder) = makeEngine()
        let event = engine.process(type: .keyDown, event: key(.t, down: true, flags: [.maskCommand, .maskShift]))

        #expect(event != nil)
        #expect(recorder.combos.isEmpty)
    }

    @Test func modifierChangesAlwaysPassThroughAndReportState() {
        let (engine, recorder) = makeEngine()
        let pressed = engine.process(type: .flagsChanged, event: modifiers(Self.hyperFlags))
        let released = engine.process(type: .flagsChanged, event: modifiers([]))

        #expect(pressed != nil)
        #expect(released != nil)
        #expect(recorder.states == [true, false])
    }

    @Test func twoQuickTapsAreADoubleTap() {
        let (engine, recorder) = makeEngine()
        for _ in 0..<2 {
            _ = engine.process(type: .flagsChanged, event: modifiers(Self.hyperFlags))
            _ = engine.process(type: .flagsChanged, event: modifiers([]))
        }
        #expect(recorder.doubleTaps == 1)
    }

    @Test func aComboInBetweenIsNotATap() {
        let (engine, recorder) = makeEngine()
        _ = engine.process(type: .flagsChanged, event: modifiers(Self.hyperFlags))
        _ = engine.process(type: .keyDown, event: key(.t, down: true, flags: Self.hyperFlags))
        _ = engine.process(type: .flagsChanged, event: modifiers([]))
        _ = engine.process(type: .flagsChanged, event: modifiers(Self.hyperFlags))
        _ = engine.process(type: .flagsChanged, event: modifiers([]))
        #expect(recorder.doubleTaps == 0)
    }
}

struct HyperKeyRepeatTests {
    private func key(_ code: UInt16, down: Bool, isRepeat: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        return event
    }

    @Test func holdingAComboKeyReportsRepeatsAndNeverLeaksThem() {
        let engine = HyperKeyEngine()
        let recorder = Recorder()
        engine.hyperKeyCode = KeyCode.f18.rawValue
        engine.logicalHyperKey = .capsLock
        engine.onHyperKeyActivated = { recorder.combo($0) }
        engine.onHyperKeyRepeat = { recorder.repeated($0) }

        _ = engine.process(type: .keyDown, event: key(KeyCode.f18.rawValue, down: true))
        let first = engine.process(type: .keyDown, event: key(KeyCode.tab.rawValue, down: true))
        let repeat1 = engine.process(type: .keyDown, event: key(KeyCode.tab.rawValue, down: true, isRepeat: true))
        let repeat2 = engine.process(type: .keyDown, event: key(KeyCode.tab.rawValue, down: true, isRepeat: true))

        #expect(first == nil)
        #expect(repeat1 == nil)
        #expect(repeat2 == nil)
        #expect(recorder.combos == [.tab])
        #expect(recorder.repeats == [.tab, .tab])
    }
}

// MARK: - App Switcher grid

@MainActor
struct AppSwitcherModelTests {
    private func window(_ pid: pid_t, _ app: String, _ title: String?, count: Int) -> OpenWindowEntry {
        OpenWindowEntry(
            id: "\(pid)-\(title ?? "")",
            app: AppInfo(bundleIdentifier: "test.\(app)", name: app, path: ""),
            pid: pid,
            windowTitle: title,
            isMinimized: false,
            windowCountForApp: count
        )
    }

    /// Front-to-back: Notes (current app), three Terminal windows, then Mail.
    private func loadedModel() -> AppSwitcherModel {
        let model = AppSwitcherModel()
        model.load(entries: [
            window(1, "Notes", "Groceries", count: 1),
            window(2, "Terminal", "build", count: 3),
            window(2, "Terminal", "server", count: 3),
            window(2, "Terminal", "logs", count: 3),
            window(3, "Mail", "Inbox", count: 1),
        ])
        return model
    }

    @Test func appsWithSeveralWindowsAreStacked() {
        let model = loadedModel()
        #expect(model.items.map(\.app.name) == ["Notes", "Terminal", "Mail"])
        #expect(model.items[1].isStack)
        #expect(model.items[1].windows.count == 3)
    }

    @Test func previousAppIsPreselected() {
        let model = loadedModel()
        #expect(model.selectedItem?.app.name == "Terminal")
    }

    @Test func expandingShowsTheStacksWindowsAndCollapseReturns() {
        let model = loadedModel()
        model.expand(model.items[1])
        #expect(model.items.map { $0.frontWindow.windowTitle } == ["build", "server", "logs"])

        model.collapse()
        #expect(model.items.count == 3)
        #expect(model.selectedItem?.app.name == "Terminal")
    }

    @Test func searchingShowsMatchingWindowsIndividually() {
        let model = loadedModel()
        model.query = "term"
        #expect(model.items.count == 3)
        #expect(model.items.allSatisfy { !$0.isStack })

        model.query = "server"
        #expect(model.items.map { $0.frontWindow.windowTitle } == ["server"])
    }

    @Test func hintLabelsAreSingleLettersWhenTheyFit() {
        let model = loadedModel()
        #expect(model.hintLabels == ["a", "s", "d"])
    }

    @Test func hintLabelsAreEqualLengthPairsWhenThereAreMany() {
        let model = AppSwitcherModel()
        model.load(entries: (0..<30).map { window(pid_t($0 + 10), "App\($0)", nil, count: 1) })
        let labels = model.hintLabels
        #expect(labels.count == 30)
        #expect(Set(labels).count == 30)
        #expect(labels.allSatisfy { $0.count == 2 })
    }
}

// MARK: - Emoji & Symbols

@MainActor
struct EmojiPickerTests {
    /// Loading checks fonts for ~1,900 emoji, so do it once for the whole suite.
    private static let catalog = EmojiCatalog.load()

    private func search(_ query: String) -> [String] {
        let all = Self.catalog.flatMap(\.items)
        return all
            .compactMap { item in EmojiPickerModel.score(item, query).map { (item.character, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    @Test func catalogHasEmojiAndSymbolCategories() {
        let names = Self.catalog.map(\.name)
        #expect(names.first == "Smileys & People")
        #expect(names.contains("Flags"))
        #expect(names.contains("Arrows"))
        #expect(names.contains("Keyboard"))
        #expect(Self.catalog.flatMap(\.items).count > 2000)
    }

    @Test func skinToneVariantsAreNotListed() {
        let tones = (0x1F3FB...0x1F3FF).compactMap(Unicode.Scalar.init).map(String.init)
        let all = Self.catalog.flatMap(\.items).map(\.character)
        #expect(!all.contains { item in tones.contains { item.contains($0) } })
    }

    @Test(arguments: [
        ("thumbs", "👍"),
        ("fire", "🔥"),
        ("rocket", "🚀"),
        ("command", "⌘"),
        ("rightwards arrow", "→"),
        ("euro", "€"),
    ])
    func commonSearchesFindTheRightCharacter(query: String, expected: String) {
        #expect(search(query).prefix(5).contains(expected))
    }

    @Test func keywordsFindEmojiByMeaning() {
        // "love" isn't in the name "red heart", only in its CLDR keywords.
        #expect(search("love").contains("❤️"))
    }
}

// MARK: - App Search commands

@MainActor
struct LauncherCommandTests {
    private func command(_ id: String, _ title: String, keywords: [String] = [], suggested: Bool = false) -> LauncherCommand {
        LauncherCommand(id: id, title: title, subtitle: "Test", icon: .symbol("star", .blue), keywords: keywords, isSuggested: suggested) { _ in }
    }

    private func model() -> AppSearchModel {
        let model = AppSearchModel()
        model.prepare(bindingStore: nil, commands: [
            command("emoji", "Emoji & Symbols", keywords: ["smiley"], suggested: true),
            command("settings", "HyperKeys Settings", keywords: ["preferences"], suggested: true),
            command("left", "Left Half", keywords: ["window"]),
        ])
        return model
    }

    @Test func homeListsOnlySuggestedCommands() {
        let model = model()
        let commands = model.sections.first { $0.title == "Commands" }?.items.map(\.title)
        #expect(commands == ["Emoji & Symbols", "HyperKeys Settings"])
    }

    @Test func searchFindsCommandsByTitleAndKeyword() {
        let model = model()
        model.query = "left half"
        #expect(model.items.first?.title == "Left Half")

        model.query = "preferences"
        #expect(model.items.contains { $0.title == "HyperKeys Settings" })
    }

    @Test func commandsAreLabelledAsCommands() {
        let model = model()
        model.query = "smiley"
        let item = model.items.first { $0.title == "Emoji & Symbols" }
        #expect(item?.typeLabel == "Command")
        #expect(item?.actionTitle == "Run Command")
    }
}

// MARK: - config.json

struct ConfigKeyNameTests {
    @Test func everyKeyRoundTripsThroughItsConfigName() {
        for key in KeyCode.allCases {
            #expect(KeyCode(configName: key.configName) == key, "\(key) → \(key.configName)")
        }
    }

    @Test func readableNamesAndAliasesAreAccepted() {
        #expect(KeyCode(configName: "T") == .t)
        #expect(KeyCode(configName: "space") == .space)
        #expect(KeyCode(configName: "`") == .grave)
        #expect(KeyCode(configName: "backtick") == .grave)
        #expect(KeyCode(configName: "esc") == .escape)
        #expect(KeyCode(configName: "keyboardHyper") == .modifierHyper)
        #expect(KeyCode(configName: "nope") == nil)
    }
}

@MainActor
struct ConfigCodecTests {
    @Test func everyKindOfShortcutSurvivesARoundTrip() throws {
        let group = AppGroup(name: "Work", appBundleIdentifiers: ["com.apple.Safari", "com.apple.mail"], windowPositions: ["com.apple.Safari": .leftHalf])
        let settings = ConfigSettings(
            bindings: [
                KeyBinding(keyCode: .t, action: .launchApp(bundleId: "com.apple.Terminal", appName: "Terminal")),
                KeyBinding(keyCode: .w, action: .showAppGroup(groupId: group.id)),
                KeyBinding(keyCode: .h, action: .windowAction(.leftHalf)),
                KeyBinding(keyCode: .m, action: .triggerMenuItem(appBundleId: "com.apple.Safari", menuPath: ["File", "New Window"])),
                KeyBinding(keyCode: .space, action: .appSearch),
                KeyBinding(keyCode: .x, action: .emojiPicker, isEnabled: false),
            ],
            profiles: [ActionGroup(name: "Gaming", bindings: [KeyBinding(keyCode: .tab, action: .appSwitcher)])],
            appGroups: [group],
            hyperKey: .modifierHyper,
            windowGap: .medium,
            switcherStaysOpen: true,
            doubleTapOpensWindow: false
        )

        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))

        #expect(warnings.isEmpty)
        #expect(loaded.hyperKey == .modifierHyper)
        #expect(loaded.windowGap == .medium)
        #expect(loaded.switcherStaysOpen)
        #expect(!loaded.doubleTapOpensWindow)
        #expect(loaded.bindings.count == 6)
        #expect(loaded.bindings.first { $0.keyCode == .x }?.isEnabled == false)
        #expect(loaded.bindings.first { $0.keyCode == .h }?.action == .windowAction(.leftHalf))
        #expect(loaded.bindings.first { $0.keyCode == .m }?.action == .triggerMenuItem(appBundleId: "com.apple.Safari", menuPath: ["File", "New Window"]))
        #expect(loaded.profiles.map(\.name) == ["Gaming"])
        #expect(loaded.profiles.first?.bindings.first?.action == .appSwitcher)

        let loadedGroup = try #require(loaded.appGroups.first)
        #expect(loadedGroup.name == "Work")
        #expect(loadedGroup.appBundleIdentifiers == ["com.apple.Safari", "com.apple.mail"])
        #expect(loadedGroup.windowPositions == ["com.apple.Safari": .leftHalf])
        #expect(loaded.bindings.first { $0.keyCode == .w }?.action == .showAppGroup(groupId: loadedGroup.id))
    }

    @Test func fileUsesReadableNames() throws {
        let settings = ConfigSettings(bindings: [KeyBinding(keyCode: .grave, action: .windowAction(.center))])
        let text = String(decoding: try ConfigCodec.encode(ConfigCodec.document(from: settings)), as: UTF8.self)
        #expect(text.contains("\"key\" : \"backtick\""))
        #expect(text.contains("\"window\" : \"center\""))
        #expect(text.contains("\"hyperKey\" : \"capsLock\""))
    }

    @Test func profilesKeepTheSameIdAcrossLoads() throws {
        let json = #"{ "profiles": [ { "name": "Work", "shortcuts": [] } ] }"#
        let first = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8))).0
        let second = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8))).0
        #expect(first.profiles.first?.id == second.profiles.first?.id)
    }

    @Test func mistakesAreReportedWithoutLosingTheRest() throws {
        let json = #"""
        { "shortcuts": [
            { "key": "t", "window": "leftHalf" },
            { "key": "nope", "window": "leftHalf" },
            { "key": "h", "window": "sideways" },
            { "key": "c", "command": "launchRockets" },
            { "key": "t", "window": "rightHalf" },
            { "key": "e" }
        ] }
        """#
        let (settings, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(Data(json.utf8)))
        #expect(settings.bindings.map(\.keyCode) == [.t])
        #expect(warnings.count == 5)
        #expect(warnings.contains { $0.contains("unknown key “nope”") })
        #expect(warnings.contains { $0.contains("sideways") })
        #expect(warnings.contains { $0.contains("listed twice") })
    }

    @Test func syntaxErrorsSayWhere() {
        let broken = Data("{\n  \"hyperKey\": \"capsLock\",\n  oops\n}".utf8)
        #expect {
            _ = try ConfigCodec.decode(broken)
        } throws: { error in
            (error as? LocalizedError)?.errorDescription?.contains("line") == true
        }
    }
}

@MainActor
struct ConfigFileLinkTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hyperkeys-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func savingWritesThroughADotfilesSymlinkInsteadOfReplacingIt() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let dotfiles = root.appendingPathComponent("dotfiles/hyperkeys/config.json")
        try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dotfiles)
        let link = root.appendingPathComponent("config/hyperkeys/config.json")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dotfiles)

        let store = ConfigStore(fileURL: link)
        try store.writeThroughLinks(Data(#"{ "hyperKey": "tab" }"#.utf8))

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(String(decoding: try Data(contentsOf: dotfiles), as: UTF8.self).contains("tab"))
    }

    @Test func aLinkedFolderIsReportedAsManagedElsewhere() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("dotfiles/hyperkeys")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: real.appendingPathComponent("config.json"))
        let linkedFolder = root.appendingPathComponent("config/hyperkeys")
        try FileManager.default.createDirectory(at: linkedFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedFolder, withDestinationURL: real)

        let store = ConfigStore(fileURL: linkedFolder.appendingPathComponent("config.json"))
        store.reload()
        guard case .linked = store.location else {
            Issue.record("Expected .linked, got \(store.location)")
            return
        }
    }
}

@MainActor
struct ICloudSyncTests {
    /// A fake home: a local config at config/hyperkeys/config.json and a fake iCloud Drive.
    @MainActor
    private struct Sandbox {
        let root: URL
        let config: URL
        let drive: URL
        var cloudFolder: URL { drive.appendingPathComponent("HyperKeys") }
        var cloudConfig: URL { cloudFolder.appendingPathComponent("config.json") }

        init(withDrive: Bool = true) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("hyperkeys-icloud-\(UUID().uuidString)").resolvingSymlinksInPath()
            config = root.appendingPathComponent("config/hyperkeys/config.json")
            drive = root.appendingPathComponent("iCloudDrive")
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            if withDrive {
                try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
            }
            try Data(#"{ "hyperKey": "tab" }"#.utf8).write(to: config)
        }

        func store() -> ConfigStore {
            let store = ConfigStore(fileURL: config, iCloudFolder: cloudFolder)
            store.reload()
            return store
        }

        func isLink(_ url: URL) -> Bool {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
        }

        func text(_ url: URL) -> String {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    @Test func turningSyncOnMovesTheConfigAndLeavesALink() throws {
        let box = try Sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let store = box.store()
        #expect(store.location == .local)

        try store.enableICloudSync(keepingICloudCopy: false)

        #expect(store.location == .iCloud)
        #expect(box.isLink(box.config))
        #expect(box.text(box.cloudConfig).contains("tab"))
    }

    @Test func turningSyncOffBringsBackARegularFile() throws {
        let box = try Sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let store = box.store()
        try store.enableICloudSync(keepingICloudCopy: false)

        try store.disableICloudSync()

        #expect(store.location == .local)
        #expect(!box.isLink(box.config))
        #expect(box.text(box.config).contains("tab"))
    }

    @Test func usingTheICloudCopyKeepsABackupOfThisMacsConfig() throws {
        let box = try Sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        try FileManager.default.createDirectory(at: box.cloudFolder, withIntermediateDirectories: true)
        try Data(#"{ "hyperKey": "capsLock" }"#.utf8).write(to: box.cloudConfig)
        let store = box.store()
        #expect(store.iCloudHasConfig)

        try store.enableICloudSync(keepingICloudCopy: true)

        #expect(box.text(box.config).contains("capsLock"))
        let backup = box.config.deletingLastPathComponent().appendingPathComponent("config.before-icloud.json")
        #expect(box.text(backup).contains("tab"))
    }

    @Test func refusesWhenICloudDriveIsOff() throws {
        let box = try Sandbox(withDrive: false)
        defer { try? FileManager.default.removeItem(at: box.root) }
        let store = box.store()
        #expect(throws: ConfigError.iCloudDriveUnavailable) {
            try store.enableICloudSync(keepingICloudCopy: false)
        }
        #expect(!box.isLink(box.config))
    }

    @Test func refusesWhenTheConfigLivesInDotfiles() throws {
        let box = try Sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let dotfiles = box.root.appendingPathComponent("dotfiles/config.json")
        try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: box.config, to: dotfiles)
        try FileManager.default.createSymbolicLink(at: box.config, withDestinationURL: dotfiles)
        let store = box.store()

        #expect(throws: ConfigError.self) {
            try store.enableICloudSync(keepingICloudCopy: false)
        }
        #expect(box.isLink(box.config))
        #expect(box.text(dotfiles).contains("tab"))
    }
}

@MainActor
struct ReadmeConfigExampleTests {
    /// The example in README.md's "Configuration File" section — keep the two in step.
    private let example = #"""
{
  "hyperKey": "capsLock",
  "windowGap": "small",
  "appSwitcher": "hold",
  "doubleTapOpensWindow": true,
  "shortcuts": [
    { "key": "t", "openApp": "com.mitchellh.ghostty", "name": "Ghostty" },
    { "key": "w", "name": "Work", "openApps": [
        { "app": "com.apple.Safari", "window": "leftHalf" },
        { "app": "com.tinyspeck.slackmacgap", "window": "rightHalf" }
    ] },
    { "key": "h", "window": "leftHalf" },
    { "key": "l", "window": "rightHalf" },
    { "key": "d", "menu": { "app": "com.google.Chrome", "path": ["View", "Developer", "Developer Tools"] } },
    { "key": "f", "openFolder": "~/Downloads" },
    { "key": "g", "quicklink": "Search GitHub" },
    { "key": "space", "command": "appSearch" },
    { "key": "tab", "command": "appSwitcher" }
  ],
  "profiles": [
    { "name": "Gaming", "shortcuts": [ { "key": "s", "openApp": "com.valvesoftware.steam" } ] }
  ],
  "snippets": [
    { "name": "Linkedin", "text": "https://linkedin.com/in/you", "tags": ["social"] },
    { "name": "Sign-off", "text": "Thanks,\nYou\n\nSent {date}" }
  ],
  "quicklinks": [
    { "name": "Search GitHub", "link": "https://github.com/search?q={argument name=\"query\"}" }
  ]
}
"""#

    @Test func readmeExampleLoadsWithoutWarnings() throws {
        let (settings, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(Data(example.utf8)))
        #expect(warnings.isEmpty, "\(warnings)")
        #expect(settings.bindings.count == 9)
        #expect(settings.snippets.count == 2)
        #expect(settings.quicklinks.map(\.name) == ["Search GitHub"])
        #expect(settings.snippets.last?.text == "Thanks,\nYou\n\nSent {date}")
        #expect(settings.profiles.first?.name == "Gaming")
        #expect(settings.windowGap == .small)
    }
}

// MARK: - Folders, Empty Trash, Snippets

@MainActor
struct FolderTrashSnippetConfigTests {
    @Test func foldersCommandsAndSnippetsRoundTrip() throws {
        let settings = ConfigSettings(
            bindings: [
                KeyBinding(keyCode: .d, action: .openFolder(path: "~/Downloads")),
                KeyBinding(keyCode: .delete, action: .emptyTrash),
                KeyBinding(keyCode: .s, action: .snippets),
            ],
            snippets: [
                Snippet(name: "Linkedin", text: "https://linkedin.com/in/someone", tags: ["social"]),
                Snippet(name: "Sign-off", text: "Thanks,\nAdib"),
            ]
        )
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""openFolder" : "~/Downloads""#))
        #expect(text.contains(#""command" : "emptyTrash""#))

        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.bindings.first { $0.keyCode == .d }?.action == .openFolder(path: "~/Downloads"))
        #expect(loaded.bindings.first { $0.keyCode == .delete }?.action == .emptyTrash)
        #expect(loaded.bindings.first { $0.keyCode == .s }?.action == .snippets)
        #expect(loaded.snippets.map(\.name) == ["Linkedin", "Sign-off"])
        #expect(loaded.snippets.first?.tags == ["social"])
        #expect(loaded.snippets.last?.text == "Thanks,\nAdib")
    }

    @Test func placeholdersAreFilledIn() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let text = SnippetStore.expand("Hi {clipboard}, it's {date} {time}", clipboard: "Sam", now: now)
        #expect(text.hasPrefix("Hi Sam, it's "))
        #expect(!text.contains("{"))
        #expect(SnippetStore.expand("{clipboard}!", clipboard: nil) == "!")
    }
}

@MainActor
struct SnippetsPanelTests {
    private let snippets = [
        Snippet(name: "Home Address", text: "1 Infinite Loop"),
        Snippet(name: "Linkedin", text: "https://linkedin.com/in/me", tags: ["social"]),
        Snippet(name: "Github", text: "https://github.com/me", tags: ["social", "code"]),
        Snippet(name: "Phone", text: "+1 555 0100"),
    ]

    @Test func groupsByWhenEachWasLastUsed() {
        let now = Date()
        let usage: [String: SnippetUsage] = [
            "Home Address": SnippetUsage(count: 3, lastUsed: now.addingTimeInterval(-60)),
            "Linkedin": SnippetUsage(count: 40, lastUsed: now.addingTimeInterval(-3 * 86_400)),
            "Github": SnippetUsage(count: 2, lastUsed: now.addingTimeInterval(-60 * 86_400)),
        ]
        let sections = SnippetsPanelModel.groupedByLastUse(snippets, usage: usage, now: now).filter { !$0.snippets.isEmpty }
        #expect(sections.map(\.title) == ["Today", "This Week", "Earlier", "Not Used Yet"])
        #expect(sections.map { $0.snippets.map(\.name) } == [["Home Address"], ["Linkedin"], ["Github"], ["Phone"]])
    }

    @Test func searchPrefersNamesThenTagsThenText() {
        let store = SnippetStore()
        store.replaceAll(snippets)
        let model = SnippetsPanelModel(store: store)
        model.query = "social"
        #expect(Set(model.items.map(\.name)) == ["Linkedin", "Github"])
        model.query = "git"
        #expect(model.items.first?.name == "Github")
        model.query = "infinite"
        #expect(model.items.map(\.name) == ["Home Address"])
    }

    @Test func tagFilterNarrowsTheList() {
        let store = SnippetStore()
        store.replaceAll(snippets)
        let model = SnippetsPanelModel(store: store)
        model.tag = "code"
        #expect(model.items.map(\.name) == ["Github"])
    }
}

// MARK: - Folders in App Search

@MainActor
struct LauncherFolderTests {
    private func model() -> AppSearchModel {
        let model = AppSearchModel()
        model.prepare(
            bindings: [
                KeyBinding(keyCode: .f, action: .openFolder(path: "/Applications")),
                KeyBinding(keyCode: .h, action: .openFolder(path: "~")),
                KeyBinding(keyCode: .g, action: .openFolder(path: "/Applications")), // same folder twice
                KeyBinding(keyCode: .x, action: .openFolder(path: "~/no-such-folder-\(UUID().uuidString)")),
                KeyBinding(keyCode: .t, action: .launchApp(bundleId: "com.apple.Terminal", appName: "Terminal")),
            ],
            hyperKey: .capsLock,
            commands: [LauncherCommand(id: "c", title: "Some Command", subtitle: "", icon: .symbol("star", .blue), isSuggested: true) { _ in }]
        )
        return model
    }

    @Test func homeListsFolderShortcutsBetweenRecentAndCommands() {
        let model = model()
        let folders = model.sections.first { $0.title == "Folders" }?.items.map(\.title)
        #expect(folders == ["Applications", "Home"])
        #expect(model.sections.map(\.title).firstIndex(of: "Folders")! < model.sections.map(\.title).firstIndex(of: "Commands")!)
    }

    @Test func foldersCarryTheirShortcut() {
        let model = model()
        #expect(model.shortcuts["folder-/Applications"] == .f)
        #expect(model.shortcuts["folder-~"] == .h)
    }

    @Test func searchFindsFoldersByNameOrPath() {
        let model = model()
        model.query = "applic"
        let item = model.items.first { $0.typeLabel == "Folder" }
        #expect(item?.title == "Applications")
        #expect(item?.actionTitle == "Open Folder")

        model.query = "folder"
        #expect(model.items.filter { $0.typeLabel == "Folder" }.count == 2)
    }
}
