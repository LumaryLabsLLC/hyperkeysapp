import AppKit
import KeyBindings
import SwiftUI

// MARK: - Processes

/// One row in the list: an app with all its helper processes, or a single process.
struct ProcessRow: Identifiable, Equatable, Sendable {
    /// "app:<bundle path>" or "pid:<pid>", stable across refreshes.
    let id: String
    let name: String
    let pids: [pid_t]
    /// Percent of one core, summed over the processes.
    let cpu: Double
    let memoryBytes: Int64
    /// The .app the processes run from, when there is one.
    let appPath: String?
    /// Whether every process belongs to you (others need an administrator to stop).
    let isYours: Bool

    var processCount: Int { pids.count }
}

/// One line of `ps`.
struct RawProcess: Equatable, Sendable {
    let pid: pid_t
    let uid: uid_t
    let cpu: Double
    let rssKilobytes: Int64
    let path: String
}

enum ProcessSampler {
    /// Lists every process with `ps` and groups the ones inside an app bundle. Takes a few dozen ms.
    static func sample() -> (rows: [ProcessRow], total: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,uid=,%cpu=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ([], 0)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let raw = parse(String(decoding: data, as: UTF8.self))
        return (group(raw, currentUser: getuid(), ownPID: getpid()), raw.count)
    }

    static func parse(_ output: String) -> [RawProcess] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5,
                  let pid = pid_t(fields[0]), let uid = uid_t(fields[1]),
                  let cpu = Double(fields[2]), let rss = Int64(fields[3])
            else { return nil }
            return RawProcess(pid: pid, uid: uid, cpu: cpu, rssKilobytes: rss, path: String(fields[4]))
        }
    }

    /// Processes under the same outermost `.app` become one row (Claude and its 20 helpers);
    /// everything else stays on its own. HyperKeys leaves itself out.
    static func group(_ processes: [RawProcess], currentUser: uid_t, ownPID: pid_t) -> [ProcessRow] {
        var apps: [String: [RawProcess]] = [:]
        var rows: [ProcessRow] = []
        for process in processes where process.pid != ownPID && process.pid > 0 {
            if let bundle = appBundlePath(of: process.path) {
                apps[bundle, default: []].append(process)
            } else {
                rows.append(ProcessRow(
                    id: "pid:\(process.pid)",
                    name: (process.path as NSString).lastPathComponent,
                    pids: [process.pid],
                    cpu: process.cpu,
                    memoryBytes: process.rssKilobytes * 1024,
                    appPath: nil,
                    isYours: process.uid == currentUser
                ))
            }
        }
        for (bundle, members) in apps {
            rows.append(ProcessRow(
                id: "app:\(bundle)",
                name: ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension,
                pids: members.map(\.pid).sorted(),
                cpu: members.reduce(0) { $0 + $1.cpu },
                memoryBytes: members.reduce(0) { $0 + $1.rssKilobytes } * 1024,
                appPath: bundle,
                isYours: members.allSatisfy { $0.uid == currentUser }
            ))
        }
        return rows
    }

    /// "/Applications/Claude.app/Contents/Frameworks/…/Helper" → "/Applications/Claude.app"
    static func appBundlePath(of path: String) -> String? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else {
            return nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory, name

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU Usage"
        case .memory: "Memory Usage"
        case .name: "Name"
        }
    }
}

@MainActor
enum ProcessKiller {
    /// Quits (or force quits) the row. Returns a message when something couldn't be stopped.
    static func kill(_ row: ProcessRow, force: Bool) -> String? {
        if let appPath = row.appPath,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == appPath }) {
            // A real app gets asked to quit, so it can save first; force quit ends it and its helpers.
            if force {
                app.forceTerminate()
                for pid in row.pids where pid != app.processIdentifier {
                    Darwin.kill(pid, SIGKILL)
                }
            } else {
                app.terminate()
            }
            return nil
        }

        var denied = false
        for pid in row.pids {
            if Darwin.kill(pid, force ? SIGKILL : SIGTERM) != 0, errno == EPERM {
                denied = true
            }
        }
        return denied ? "\(row.name) is a system process, so it can't be stopped from here." : nil
    }
}

// MARK: - Model

@MainActor
@Observable
final class KillProcessModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var sort: ProcessSort = .cpu {
        didSet {
            guard sort != oldValue else { return }
            rebuild()
            selection = 0
        }
    }
    var selection = 0
    /// Until you move the selection, it stays on the top row as the list re-sorts;
    /// after that it follows the same process.
    var hasChosen = false
    /// Shown in the footer for a few seconds after a kill that didn't work.
    var message: String?
    private(set) var focusRequest = 0
    private(set) var items: [ProcessRow] = []
    private(set) var totalCount = 0
    private(set) var hasLoaded = false

    @ObservationIgnored private var all: [ProcessRow] = []
    @ObservationIgnored private var isSampling = false

    func requestFocus() {
        focusRequest += 1
    }

    func prepare() {
        query = ""
        sort = .cpu
        message = nil
        selection = 0
        hasChosen = false
        requestFocus()
        refresh()
    }

    var selectedRow: ProcessRow? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        hasChosen = true
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    /// Samples off the main thread, then updates the list, keeping the same row selected.
    func refresh() {
        guard !isSampling else { return }
        isSampling = true
        Task {
            let sample = await Task.detached(priority: .userInitiated) { ProcessSampler.sample() }.value
            isSampling = false
            all = sample.rows
            totalCount = sample.total
            hasLoaded = true
            let selectedId = hasChosen ? selectedRow?.id : nil
            rebuild()
            if let selectedId, let index = items.firstIndex(where: { $0.id == selectedId }) {
                selection = index
            } else {
                selection = hasChosen ? min(selection, max(items.count - 1, 0)) : 0
            }
        }
    }

    func rebuild() {
        let needle = query.trimmingCharacters(in: .whitespaces)
        var rows = all
        if !needle.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(needle) || $0.pids.contains { String($0) == needle } }
        }
        items = Self.sorted(rows, by: sort)
    }

    static func sorted(_ rows: [ProcessRow], by sort: ProcessSort) -> [ProcessRow] {
        rows.sorted { lhs, rhs in
            switch sort {
            case .cpu where lhs.cpu != rhs.cpu: lhs.cpu > rhs.cpu
            case .memory where lhs.memoryBytes != rhs.memoryBytes: lhs.memoryBytes > rhs.memoryBytes
            default: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }
}

// MARK: - Controller

/// Raycast-style process list: Return quits the selected app or process, ⌘Return force quits it.
@MainActor
public final class KillProcessController {
    public static let shared = KillProcessController()

    let model = KillProcessModel()
    private var host: FloatingPanelHost?
    private var timer: Timer?

    public var isVisible: Bool {
        host?.isVisible ?? false
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    public func warmUp() {
        _ = makeHostIfNeeded()
    }

    public func show(returningTo app: NSRunningApplication? = nil) {
        let host = makeHostIfNeeded()
        model.prepare()
        host.show(returningTo: app)
        DispatchQueue.main.async { [model] in
            model.requestFocus()
        }
        startRefreshing()
    }

    public func hide() {
        host?.hide(restoringFocus: true)
        stopRefreshing()
    }

    func kill(_ row: ProcessRow, force: Bool) {
        if let problem = ProcessKiller.kill(row, force: force) {
            model.message = problem
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [model] in
                if model.message == problem { model.message = nil }
            }
        }
        // Give it a moment to go, then show the list without it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [model] in
            model.refresh()
        }
    }

    /// Updates CPU and memory every two seconds while the panel is open.
    private func startRefreshing() {
        stopRefreshing()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isVisible {
                    self.model.refresh()
                } else {
                    self.stopRefreshing()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    private func makeHostIfNeeded() -> FloatingPanelHost {
        if let host { return host }
        let root = KillProcessPanelView(
            model: model,
            onKill: { [weak self] row, force in self?.kill(row, force: force) }
        )
        let host = FloatingPanelHost(width: KillProcessPanelView.width, rootView: root)
        host.topFraction = 0.18
        host.onKeyDown = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        self.host = host
        return host
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        switch event.keyCode {
        case 53: // escape
            if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case 125: model.moveSelection(by: 1); return true
        case 126: model.moveSelection(by: -1); return true
        case 36, 76: // return, enter
            if let row = model.selectedRow {
                kill(row, force: flags.contains(.command))
            }
            return true
        default:
            break
        }
        if flags == .control, characters == "n" {
            model.moveSelection(by: 1)
            return true
        }
        if flags == .control, characters == "p" {
            model.moveSelection(by: -1)
            return true
        }
        return false
    }
}
