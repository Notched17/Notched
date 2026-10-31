// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// How the shell is started (#64). Pure.
struct ShellLaunch: Equatable, Sendable {
    var executable: String
    var args: [String]
}

enum ShellLauncher {
    static let fallbackShell = "/bin/zsh"

    /// `$SHELL` if it names an absolute, executable path; otherwise zsh.
    static func resolveShell(environmentShell: String?, isExecutable: (String) -> Bool) -> String {
        guard let shell = environmentShell, shell.hasPrefix("/"),
              !shell.contains(where: { $0.isNewline || $0 == "\0" }), isExecutable(shell) else { return fallbackShell }
        return shell
    }

    /// A login shell in the home folder. It goes through `sh` so the working
    /// directory is set without changing Notched's own: `$0` is the shell and
    /// `$1` the folder, passed as arguments so nothing is built into a string.
    static func launch(shell: String, home: String) -> ShellLaunch {
        ShellLaunch(executable: "/bin/sh", args: ["-c", #"cd "$1" 2>/dev/null; exec "$0" -l"#, shell, home])
    }
}

/// The shell's life: started the first time the tab is shown, kept while the
/// island collapses, ended when the module goes off, on quit, or by the user.
///
/// A shell that dies at once, twice in a row (a broken `$SHELL` or profile),
/// is not restarted by merely showing the tab, so it can't spin; the user
/// starts a new session explicitly. Each start has a generation, so a late
/// exit report from an old shell can't end the new one.
struct TerminalLifecycleReducer: Sendable {
    static let quickExitWindow: TimeInterval = 1
    static let maxQuickExits = 2

    enum EndReason: Equatable, Sendable { case shellExited, userEnded }

    enum Phase: Equatable, Sendable {
        case notStarted
        case running
        case ended(code: Int32?, reason: EndReason)
    }

    struct State: Equatable, Sendable {
        var phase: Phase = .notStarted
        var generation = 0
        var startedAt: Date?
        var quickExits = 0
    }

    enum Event: Equatable, Sendable {
        /// The Terminal tab appeared.
        case tabShown
        /// The shell of this generation exited.
        case processExited(code: Int32?, generation: Int)
        /// "New Session": start now, replacing any shell.
        case newSession
        /// "End Session".
        case endSession
        /// The module is going off, or Notched is quitting.
        case stop
    }

    enum Effect: Equatable, Sendable {
        case start(generation: Int)
        case terminate
    }

    private(set) var state = State()

    /// True once repeated instant exits stopped automatic restarts.
    var isGivenUp: Bool { state.quickExits >= Self.maxQuickExits }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .tabShown:
            switch state.phase {
            case .running: return []
            case .notStarted: return begin(now: now)
            case .ended: return isGivenUp ? [] : begin(now: now)
            }
        case .processExited(let code, let generation):
            guard state.phase == .running, generation == state.generation else { return [] }
            let quick = state.startedAt.map { now.timeIntervalSince($0) < Self.quickExitWindow } ?? false
            state.quickExits = quick ? state.quickExits + 1 : 0
            state.phase = .ended(code: code, reason: .shellExited)
            return []
        case .newSession:
            let stopOld: [Effect] = state.phase == .running ? [.terminate] : []
            state.quickExits = 0
            return stopOld + begin(now: now)
        case .endSession:
            guard state.phase == .running else { return [] }
            state.phase = .ended(code: nil, reason: .userEnded)
            state.quickExits = 0
            return [.terminate]
        case .stop:
            let effects: [Effect] = state.phase == .running ? [.terminate] : []
            state = State(phase: .notStarted, generation: state.generation, startedAt: nil, quickExits: 0)
            return effects
        }
    }

    private mutating func begin(now: Date) -> [Effect] {
        state.generation += 1
        state.phase = .running
        state.startedAt = now
        return [.start(generation: state.generation)]
    }
}

/// Finds the shell Notched just started. SwiftTerm doesn't expose its pid, but
/// the shell is a direct child of this process, so it is the new child whose
/// program is the launcher (`/bin/sh`) or the shell it then became.
enum ChildProcesses {
    static func pids(of parent: pid_t = getpid()) -> [pid_t] {
        let capacity = 256
        var buffer = [pid_t](repeating: 0, count: capacity)
        let result = proc_listchildpids(parent, &buffer, Int32(capacity * MemoryLayout<pid_t>.size))
        guard result > 0 else { return [] }
        // Whether the return value counts pids or bytes differs between the docs and
        // the SDK, so it is only used as success/failure: the unused part of the
        // buffer is zero, and real pids are all above 1.
        return buffer.filter { $0 > 1 }
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        // `length` excludes the terminating NUL.
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }

    /// The child that wasn't there `before`. If several appeared (another helper
    /// starting at the same moment), the one running one of `programs`. A shell
    /// reached through a symlink reports its real path, so a lone new child is
    /// taken to be the shell even if the name doesn't match.
    static func newChild(before: Set<pid_t>, programs: Set<String>, parent: pid_t = getpid()) -> pid_t? {
        let fresh = pids(of: parent).filter { !before.contains($0) }
        if fresh.count == 1 { return fresh[0] }
        return fresh.first { pid in path(of: pid).map(programs.contains) ?? false }
    }
}

/// Ends a shell so no process outlives Notched or the module.
enum TerminalProcessKiller {
    /// Hangs up the shell's process group (its pty session leader), waits a
    /// moment, then kills whatever is left. Never signals pid 0 or 1.
    static func terminate(pid: pid_t, grace: TimeInterval = 0.4) {
        guard pid > 1 else { return }
        // A forkpty child leads its own group, so the whole job goes with it.
        let target: pid_t = getpgid(pid) == pid ? -pid : pid
        kill(target, SIGHUP)
        let deadline = Date().addingTimeInterval(grace)
        while isAlive(pid), Date() < deadline { usleep(10_000) }
        if isAlive(pid) { kill(target, SIGKILL) }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
