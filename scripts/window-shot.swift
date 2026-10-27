// SPDX-License-Identifier: GPL-3.0-or-later
// Prints the window number of DynamicNotch's titled window whose name contains
// the argument (default "Settings"), for `screencapture -l <number>`.
// Run: swift scripts/window-shot.swift [title]
import AppKit

let wanted = CommandLine.arguments.dropFirst().first ?? "Settings"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info where (window[kCGWindowOwnerName as String] as? String) == "DynamicNotch" {
    let name = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    if layer == 0, name.localizedCaseInsensitiveContains(wanted) || wanted.isEmpty {
        print(window[kCGWindowNumber as String] ?? "")
        exit(0)
    }
}
exit(1)
