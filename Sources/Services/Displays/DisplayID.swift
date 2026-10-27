// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// A stable identifier for a display: the UUID from `CGDisplayCreateUUIDFromDisplayID`.
/// Unlike `CGDirectDisplayID` it survives reconnects and reboots.
struct DisplayID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    var description: String { rawValue }
}

extension NSScreen {
    /// The Core Graphics display number for this screen.
    var directDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var displayID: DisplayID? {
        guard let number = directDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return DisplayID(rawValue: string)
    }

    var isBuiltIn: Bool {
        directDisplayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    /// The pure description of this screen that `NotchGeometry` works from.
    var screenDescriptor: ScreenDescriptor {
        ScreenDescriptor(
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width,
            backingScale: backingScaleFactor
        )
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }
}
