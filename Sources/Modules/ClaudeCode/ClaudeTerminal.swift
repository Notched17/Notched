// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

/// Which app Claude Code is running in, and bringing it to the front, for the
/// "Open Terminal" button. The hook helper reports the app it was started from
/// (`__CFBundleIdentifier`, or `TERM_PROGRAM`); without that (an older helper,
/// or a shell started some other way) the first well-known terminal that is
/// running is used. Pure choosing, tested; the opening is one `NSWorkspace` call.
enum ClaudeTerminal {
    /// Terminal apps and editors with a built-in terminal, in the order tried
    /// when the session didn't say which one it is in.
    static let known: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
    ]

    /// `TERM_PROGRAM` values and the app they mean (the helper uses the same table).
    static let termProgram: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2", "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm", "vscode": "com.microsoft.VSCode", "WarpTerminal": "dev.warp.Warp-Stable",
    ]

    /// A bundle identifier as it may be believed: dotted, plain characters, not absurdly long.
    static func isPlausibleBundleID(_ text: String) -> Bool {
        guard (3...120).contains(text.count), text.contains(".") else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    /// The app to bring forward: the one the session reported if it is running,
    /// else the first known terminal that is, else nil (launch Terminal).
    static func choose(reported: String?, running: Set<String>) -> String? {
        if let reported, isPlausibleBundleID(reported), running.contains(reported) { return reported }
        return known.first { running.contains($0) }
    }

    /// Brings the session's terminal to the front. `ownBundleID` is Notched
    /// itself: a session started in Notched's own Terminal tab opens that tab.
    @MainActor
    static func open(reported: String?, ownBundleID: String? = Bundle.main.bundleIdentifier, showOwnTerminal: () -> Void) {
        if let reported, reported == ownBundleID {
            showOwnTerminal()
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let target = choose(reported: reported, running: running) ?? "com.apple.Terminal"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
