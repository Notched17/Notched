// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Public-API fallback for fullscreen detection: a screen counts as fullscreen
/// when a normal-layer window from another app covers the whole screen,
/// including the menu bar. Window bounds need no Screen Recording permission.
enum WindowListFullscreenHeuristic {
    struct Window: Sendable {
        /// Core Graphics coordinates (top-left origin of the primary display).
        var bounds: CGRect
        var layer: Int
        var ownerPID: Int32
    }

    static let tolerance: CGFloat = 1

    static func fullscreenDisplays(windows: [Window], screens: [(id: DisplayID, frame: CGRect)], ownPID: Int32) -> Set<DisplayID> {
        var result = Set<DisplayID>()
        for window in windows where window.layer == 0 && window.ownerPID != ownPID {
            for screen in screens where covers(window.bounds, screen.frame) {
                result.insert(screen.id)
            }
        }
        return result
    }

    private static func covers(_ window: CGRect, _ screen: CGRect) -> Bool {
        abs(window.minX - screen.minX) <= tolerance && abs(window.minY - screen.minY) <= tolerance
            && abs(window.maxX - screen.maxX) <= tolerance && abs(window.maxY - screen.maxY) <= tolerance
    }

    /// Reads the live window list and screens.
    @MainActor
    static func current() -> Set<DisplayID> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = info.compactMap { entry -> Window? in
            guard let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            return Window(
                bounds: bounds,
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                ownerPID: entry[kCGWindowOwnerPID as String] as? Int32 ?? 0
            )
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.compactMap { screen -> (id: DisplayID, frame: CGRect)? in
            guard let id = screen.displayID else { return nil }
            let frame = screen.frame
            return (id, CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height))
        }
        return fullscreenDisplays(windows: windows, screens: screens, ownPID: ProcessInfo.processInfo.processIdentifier)
    }
}
