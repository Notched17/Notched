// SPDX-License-Identifier: GPL-3.0-or-later
//
// The notch maths (width = screen width minus the two auxiliary top areas,
// height = the top safe-area inset) follows MrKai77/DynamicNotchKit (MIT) and
// TheBoredTeam/boring.notch (GPL-3.0). See THIRD_PARTY_NOTICES.md.

import CoreGraphics

/// The facts about one screen that island placement depends on. Built from
/// `NSScreen` in the app and from fixtures in tests, so the maths stays pure.
struct ScreenDescriptor: Equatable, Sendable {
    /// `NSScreen.frame`, in global AppKit coordinates (bottom-left origin).
    var frame: CGRect
    /// `NSScreen.visibleFrame`, used to measure the menu bar.
    var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`: the notch height, or 0 without a notch.
    var safeAreaTop: CGFloat
    /// Widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, the menu-bar areas beside the notch.
    var auxiliaryTopLeftWidth: CGFloat?
    var auxiliaryTopRightWidth: CGFloat?
    /// `NSScreen.backingScaleFactor`, for pixel alignment.
    var backingScale: CGFloat
}

/// Where the island sits on one screen, in global AppKit coordinates.
///
/// On a notched screen the island hangs from the top edge and, when idle,
/// covers exactly the hardware notch. On other screens it is a floating pill
/// just below the menu bar. All rects are centred and pixel-aligned, and they
/// stay symmetric about the same centre line, so resizing the panel never
/// moves the island on screen.
struct NotchGeometry: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case notch
        case pill
    }

    /// Size of the idle pill on screens without a notch.
    static let pillSize = CGSize(width: 190, height: 32)
    /// Gap between the menu bar and the pill.
    static let pillGap: CGFloat = 6
    /// Menu-bar height assumed when the menu bar auto-hides.
    static let fallbackMenuBarHeight: CGFloat = 24
    /// Minimum distance between the expanded island and the screen's sides.
    static let screenMargin: CGFloat = 16

    let kind: Kind
    let screenFrame: CGRect
    /// The hardware notch, when the screen has one (even if the pill is forced).
    let hardwareNotch: CGSize?
    /// The idle compact island: the notch (plus any width offset) or the pill.
    let compactBaseSize: CGSize
    let menuBarHeight: CGFloat
    let scale: CGFloat
    /// The vertical centre line every island rect is symmetric about.
    let centerX: CGFloat

    static func resolve(_ screen: ScreenDescriptor, widthOffset: CGFloat = 0, forcePill: Bool = false) -> NotchGeometry {
        let scale = max(screen.backingScale, 1)
        let measuredMenuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let menuBarHeight = measuredMenuBar > 0 ? measuredMenuBar : fallbackMenuBarHeight

        var hardwareNotch: CGSize?
        var notchCenterX = screen.frame.midX
        if screen.safeAreaTop > 0,
           let left = screen.auxiliaryTopLeftWidth,
           let right = screen.auxiliaryTopRightWidth {
            let width = screen.frame.width - left - right
            if width > 0 {
                hardwareNotch = CGSize(width: width, height: align(screen.safeAreaTop, scale: scale))
                notchCenterX = screen.frame.minX + left + width / 2
            }
        }

        if let notch = hardwareNotch, !forcePill {
            // Never narrower than the hardware, or the notch's edges would show.
            let width = notch.width + max(widthOffset, 0)
            return NotchGeometry(
                kind: .notch, screenFrame: screen.frame, hardwareNotch: notch,
                compactBaseSize: CGSize(width: width, height: notch.height),
                menuBarHeight: menuBarHeight, scale: scale, centerX: notchCenterX
            )
        }

        let width = max(pillSize.width + widthOffset, pillSize.height)
        return NotchGeometry(
            kind: .pill, screenFrame: screen.frame, hardwareNotch: hardwareNotch,
            compactBaseSize: CGSize(width: width, height: pillSize.height),
            menuBarHeight: menuBarHeight, scale: scale, centerX: screen.frame.midX
        )
    }

    /// The top edge of every island rect: the screen edge for a notch, below the menu bar for a pill.
    var islandTop: CGFloat {
        switch kind {
        case .notch: screenFrame.maxY
        case .pill: screenFrame.maxY - menuBarHeight - Self.pillGap
        }
    }

    /// The compact island. It grows by the wider of the two slots on *both*
    /// sides, so it stays centred on the notch (content can't sit under the camera).
    func compactRect(leadingWidth: CGFloat, trailingWidth: CGFloat) -> CGRect {
        let side = max(leadingWidth, trailingWidth, 0)
        return centeredRect(width: compactBaseSize.width + 2 * side, height: compactBaseSize.height)
    }

    /// The compact island reaching `leading` points left of the notch (or the
    /// pill's middle) and `trailing` points right of it. The sides can differ:
    /// an activity without a trailing region leaves that side at the notch.
    func compactRect(leading: CGFloat, trailing: CGFloat) -> CGRect {
        let base = centeredRect(width: compactBaseSize.width, height: compactBaseSize.height)
        let rect = CGRect(x: base.minX - max(leading, 0), y: base.minY,
                          width: base.width + max(leading, 0) + max(trailing, 0), height: base.height)
        return Self.align(rect, scale: scale)
    }

    /// The expanded island, hanging from `islandTop`, clamped to the screen width.
    func expandedRect(size: CGSize) -> CGRect {
        let maxWidth = screenFrame.width - 2 * Self.screenMargin
        return centeredRect(width: min(size.width, maxWidth), height: size.height)
    }

    /// The panel that hosts `islandRect`, padded for shadows on the sides and
    /// bottom. On a notch nothing goes above the screen edge; on a pill the top
    /// padding stops at the menu bar.
    func panelFrame(for islandRect: CGRect, padding: CGFloat) -> CGRect {
        let top: CGFloat = switch kind {
        case .notch: 0
        case .pill: min(padding, Self.pillGap)
        }
        let rect = CGRect(
            x: islandRect.minX - padding,
            y: islandRect.minY - padding,
            width: islandRect.width + 2 * padding,
            height: islandRect.height + padding + top
        )
        return Self.align(rect, scale: scale)
    }

    // MARK: Pixel alignment

    private func centeredRect(width: CGFloat, height: CGFloat) -> CGRect {
        let halfWidth = Self.align(width / 2, scale: scale)
        let alignedHeight = Self.align(height, scale: scale)
        let top = Self.align(islandTop, scale: scale)
        let center = Self.align(centerX, scale: scale)
        return CGRect(x: center - halfWidth, y: top - alignedHeight, width: 2 * halfWidth, height: alignedHeight)
    }

    static func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    static func align(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = align(rect.minX, scale: scale)
        let minY = align(rect.minY, scale: scale)
        return CGRect(x: minX, y: minY, width: align(rect.maxX, scale: scale) - minX, height: align(rect.maxY, scale: scale) - minY)
    }
}
