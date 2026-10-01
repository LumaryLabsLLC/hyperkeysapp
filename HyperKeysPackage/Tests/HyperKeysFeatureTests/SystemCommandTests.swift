import EventEngine
import Foundation
import Testing
@testable import HyperKeysFeature
@testable import KeyBindings

struct ProcessListTests {
    private let output = """
          1     0   4.6  25120 /sbin/launchd
        501   501  12.5 900000 /Applications/Claude.app/Contents/MacOS/Claude
        502   501  30.0 400000 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)
        610   501   0.4   2048 /usr/local/bin/node
        700   501   0.0   1024 /Applications/HyperKeys.app/Contents/MacOS/HyperKeys
        garbage line
        """

    @Test func readsPsOutput() {
        let raw = ProcessSampler.parse(output)
        #expect(raw.count == 5)
        #expect(raw[2].path.hasSuffix("Claude Helper (Renderer)"))
        #expect(raw[1].cpu == 12.5)
    }

    @Test func groupsAppsWithTheirHelpers() throws {
        let rows = ProcessSampler.group(ProcessSampler.parse(output), currentUser: 501, ownPID: 700)
        let claude = try #require(rows.first { $0.name == "Claude" })
        #expect(claude.pids == [501, 502])
        #expect(claude.cpu == 42.5)
        #expect(claude.memoryBytes == 1_300_000 * 1024)
        #expect(claude.appPath == "/Applications/Claude.app")
        #expect(claude.isYours)

        let launchd = try #require(rows.first { $0.name == "launchd" })
        #expect(!launchd.isYours)
        #expect(rows.contains { $0.name == "node" })
        // HyperKeys leaves itself out.
        #expect(!rows.contains { $0.name == "HyperKeys" })
    }

    @Test func findsTheOutermostApp() {
        #expect(ProcessSampler.appBundlePath(of: "/Applications/A.app/Contents/Frameworks/B.app/Contents/MacOS/B") == "/Applications/A.app")
        #expect(ProcessSampler.appBundlePath(of: "/usr/bin/top") == nil)
    }

    @MainActor
    @Test func sortsByCpuMemoryOrName() {
        let rows = ProcessSampler.group(ProcessSampler.parse(output), currentUser: 501, ownPID: 700)
        #expect(KillProcessModel.sorted(rows, by: .cpu).map(\.name) == ["Claude", "launchd", "node"])
        #expect(KillProcessModel.sorted(rows, by: .memory).map(\.name) == ["Claude", "launchd", "node"])
        #expect(KillProcessModel.sorted(rows, by: .name).map(\.name) == ["Claude", "launchd", "node"])
    }
}

@MainActor
struct SystemCommandConfigTests {
    @Test func systemCommandsRoundTripThroughConfig() throws {
        let settings = ConfigSettings(
            bindings: [
                KeyBinding(keyCode: .l, action: .system(.lockScreen)),
                KeyBinding(keyCode: .c, action: .system(.caffeinate)),
                KeyBinding(keyCode: .k, action: .killProcess),
            ],
            snippets: []
        )
        let data = try ConfigCodec.encode(ConfigCodec.document(from: settings))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""command" : "lockScreen""#))
        #expect(text.contains(#""command" : "caffeinate""#))
        #expect(text.contains(#""command" : "killProcess""#))

        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        #expect(loaded.bindings.first { $0.keyCode == .l }?.action == .system(.lockScreen))
        #expect(loaded.bindings.first { $0.keyCode == .c }?.action == .system(.caffeinate))
        #expect(loaded.bindings.first { $0.keyCode == .k }?.action == .killProcess)
    }

    @Test func raycastSystemCommandsMapOver() {
        let resolve: RaycastImportPlan.AppResolver = { _ in nil }
        func map(_ ext: String, _ id: String) -> BoundAction? {
            if case .action(let action, _) = RaycastImportPlan.map(.command(extensionId: ext, id: id, title: nil), resolveApp: resolve) {
                return action
            }
            return nil
        }
        #expect(map("e:r:system", "e:r:system::lock-screen") == .system(.lockScreen))
        #expect(map("e:r:system", "e:r:system::shut-down") == .system(.shutDown))
        #expect(map("e:ext:coffee", "e:ext:coffee::caffeinate") == .system(.caffeinate))
        #expect(map("e:ext:kill-process", "e:ext:kill-process::index-kill-process") == .killProcess)
        #expect(map("e:r:system", "e:r:system::toggle-system-appearance") == .system(.toggleDarkMode))
        #expect(map("e:r:system", "e:r:system::sleep-displays") == .system(.sleepDisplays))
        #expect(map("e:r:system", "e:r:system::quit-all-apps-except-frontmost") == .system(.quitOtherApps))
        #expect(map("e:r:system", "e:r:system::toggle-microphone-mute") == .system(.toggleMicrophone))
        // A window command named like a system one stays a window command.
        #expect(map("e:r:window-management", "e:r:window-management::restore") == .windowAction(.restore))
    }

    @Test func caffeinateTurnsOnAndOff() {
        let caffeinate = Caffeinate()
        caffeinate.toggle()
        #expect(caffeinate.isActive)
        caffeinate.toggle()
        #expect(!caffeinate.isActive)
    }
}

@MainActor
struct AppSearchSystemSectionTests {
    @Test func homeListsEverySystemCommand() throws {
        let model = AppSearchModel()
        model.prepare(bindings: [], hyperKey: .capsLock, commands: AppSearchController.shared.makeCommands())

        let system = try #require(model.sections.first { $0.title == "System" })
        #expect(system.items.map(\.title) == [
            "Lock Screen", "Sleep", "Caffeinate", "Kill Process", "Empty Trash", "Log Out", "Restart", "Shut Down",
        ])
        let commands = model.sections.first { $0.title == "Commands" }?.items.map(\.title) ?? []
        #expect(!commands.contains("Lock Screen") && !commands.contains("Kill Process"))
        #expect(model.sections.map(\.title).last == "System")
    }
}

@MainActor
struct SystemSearchTests {
    @Test func searchingSystemListsEverySystemCommand() {
        let model = AppSearchModel()
        model.prepare(bindings: [], hyperKey: .capsLock, commands: AppSearchController.shared.makeCommands())
        model.query = "system"
        let titles = Set(model.items.compactMap { item -> String? in
            if case .command(let command) = item, command.isSystem { return command.title }
            return nil
        })
        let expected = Set(SystemAction.allCases.filter { $0 != .caffeinate }.map(\.title))
            .union(["Caffeinate", "Kill Process", "Empty Trash"])
        #expect(titles == expected)
    }

    @Test func everySystemActionRoundTripsThroughConfig() throws {
        let keys: [KeyCode] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
                               .one, .two, .three, .four]
        let actions = SystemAction.allCases
        #expect(actions.count <= keys.count)
        let bindings = zip(keys, actions).map { KeyBinding(keyCode: $0, action: .system($1)) }
        let data = try ConfigCodec.encode(ConfigCodec.document(from: ConfigSettings(bindings: bindings, snippets: [])))
        let (loaded, warnings) = ConfigCodec.settings(from: try ConfigCodec.decode(data))
        #expect(warnings.isEmpty)
        let byKey = Dictionary(uniqueKeysWithValues: loaded.bindings.map { ($0.keyCode, $0.action) })
        for binding in bindings {
            #expect(byKey[binding.keyCode] == binding.action)
        }
    }
}
