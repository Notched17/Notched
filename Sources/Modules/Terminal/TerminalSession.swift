// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftTerm

/// One shell in one SwiftTerm view (migueldeicaza/SwiftTerm, MIT). The module
/// owns the session, not the tab, so the shell survives the island collapsing
/// and the tab's content being rebuilt; `view` is simply re-hosted.
@MainActor
final class TerminalSession: NSObject {
    let view: LocalProcessTerminalView
    /// The shell exited, with its exit code if known.
    var onExit: (Int32?) -> Void = { _ in }
    private(set) var pid: pid_t = 0
    /// What this process's children were before the shell started, and the programs to look for.
    private var childrenBefore: Set<pid_t> = []
    private var shellPrograms: Set<String> = []

    override init() {
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 380, height: 250))
        super.init()
        view.processDelegate = self
        // Black like the notch; the island is dark in every theme.
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
    }

    func applyFontSize(_ size: Int) {
        view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    /// Starts a login shell in the home folder (see `ShellLauncher`).
    func start(shell: String, home: String) {
        let launch = ShellLauncher.launch(shell: shell, home: home)
        childrenBefore = Set(ChildProcesses.pids())
        shellPrograms = [launch.executable, shell]
        view.startProcess(executable: launch.executable, args: launch.args, environment: nil, execName: nil)
        pid = ChildProcesses.newChild(before: childrenBefore, programs: shellPrograms) ?? 0
    }

    /// Ends the shell and its job. Safe to call twice.
    func terminate() {
        onExit = { _ in }
        // If the shell wasn't found straight after starting (it can take a moment to appear), look again now.
        if pid == 0 { pid = ChildProcesses.newChild(before: childrenBefore, programs: shellPrograms) ?? 0 }
        let pid = pid
        self.pid = 0
        TerminalProcessKiller.terminate(pid: pid)
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.onExit(exitCode) }
    }
}
