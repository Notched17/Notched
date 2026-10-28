// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How sure we are which app owns a microphone stream. The island only ever
/// names an app it can prove; anything weaker says "An app".
enum Attribution: Equatable, Sendable {
    /// The process using the microphone is itself a running app.
    case exact
    /// It's a helper inside an app's bundle (Zoom's helper, a browser's renderer).
    case containingApp
    /// macOS says another process is responsible for it (WebKit's GPU process → Safari).
    case responsible
    /// We can't say.
    case unknown
}

/// An app that is running, as the shell sees it.
struct RunningAppInfo: Equatable, Sendable {
    var pid: Int32
    var bundleID: String?
    var name: String
    /// The app bundle's path, e.g. "/Applications/zoom.us.app".
    var bundlePath: String?
}

/// One process using the microphone, and the app it belongs to.
struct InputUser: Equatable, Sendable {
    var pid: Int32
    /// The process's own bundle ID from CoreAudio, if it has one.
    var processBundleID: String?
    var appBundleID: String?
    /// Nil unless the owner is proven (`attribution != .unknown`).
    var appName: String?
    var attribution: Attribution

    /// Names the owner across the processes it uses, so a call that
    /// switches helper processes keeps its identity.
    var identity: String { appBundleID ?? processBundleID ?? "pid:\(pid)" }
}

/// What the camera and microphone are doing right now.
struct SensorSnapshot: Equatable, Sendable {
    var cameraRunning = false
    /// Processes other than Notched with an input stream running.
    var micUsers: [InputUser] = []
    /// The process list was unreadable but an input device is running: the
    /// microphone is probably in use, by an app we can't name.
    var micRunningUnattributed = false

    var micInUse: Bool { !micUsers.isEmpty || micRunningUnattributed }

    static let idle = SensorSnapshot()
}

/// A process the audio system reports, before attribution.
struct RawInputProcess: Equatable, Sendable {
    var pid: Int32
    var bundleID: String?
    var executablePath: String?
    var isRunningInput: Bool
}

/// Works out which app owns a process. Pure, so the nested-helper, WebKit and
/// daemon cases are all tested without a running system.
enum SensorAttribution {
    /// - Parameters:
    ///   - responsiblePID: the process macOS holds responsible for `process`
    ///     (private lookup, nil if unavailable), used only when the other
    ///     routes fail.
    static func attribute(_ process: RawInputProcess, apps: [RunningAppInfo], responsiblePID: Int32?) -> InputUser {
        func user(_ app: RunningAppInfo?, _ level: Attribution) -> InputUser {
            InputUser(pid: process.pid, processBundleID: process.bundleID, appBundleID: app?.bundleID,
                      appName: app?.name, attribution: app == nil ? .unknown : level)
        }
        if let app = apps.first(where: { $0.pid == process.pid }) { return user(app, .exact) }
        if let path = process.executablePath.flatMap(outermostAppPath),
           let app = apps.first(where: { $0.bundlePath.map(trimSlash) == path }) {
            return user(app, .containingApp)
        }
        if let responsiblePID, responsiblePID != process.pid, responsiblePID > 1,
           let app = apps.first(where: { $0.pid == responsiblePID }) {
            return user(app, .responsible)
        }
        return user(nil, .unknown)
    }

    /// "/Applications/zoom.us.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
    /// → "/Applications/zoom.us.app": the outermost bundle is the app the user launched.
    static func outermostAppPath(_ executablePath: String) -> String? {
        let parts = executablePath.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + parts[...index].joined(separator: "/")
    }

    private static func trimSlash(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The microphone users for a snapshot: only processes with an input
    /// stream running, never Notched itself, and never an ignored daemon.
    /// `attribute` names the owner (the shell caches it per process).
    static func users(from processes: [RawInputProcess], ownPID: Int32, ignoredBundleIDs: Set<String>,
                      attribute: (RawInputProcess) -> InputUser) -> [InputUser] {
        processes
            .filter { $0.isRunningInput && $0.pid != ownPID && !($0.bundleID.map(ignoredBundleIDs.contains) ?? false) }
            .map(attribute)
            .sorted { $0.pid < $1.pid }
    }
}

/// Remembers who owns a process so the system is asked once, not on every
/// change. Processes are keyed by pid *and* start time, because macOS reuses
/// pids: a new process with an old pid must be looked up again.
struct AttributionCache: Sendable {
    struct Key: Hashable, Sendable {
        var pid: Int32
        var startTime: UInt64
    }

    private var entries: [Key: InputUser] = [:]

    mutating func user(for key: Key, compute: () -> InputUser) -> InputUser {
        if let cached = entries[key] { return cached }
        let user = compute()
        entries[key] = user
        return user
    }

    /// Forgets everything except the processes still around, and anything an
    /// app launch or quit may have changed the answer for.
    mutating func prune(keeping live: Set<Key>) {
        entries = entries.filter { live.contains($0.key) }
    }

    mutating func removeAll() { entries.removeAll() }

    var count: Int { entries.count }
}
