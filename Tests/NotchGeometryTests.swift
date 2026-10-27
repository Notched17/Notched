// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import DynamicNotch

@Suite("NotchGeometry")
struct NotchGeometryTests {
    // MARK: Fixtures

    /// Charlie's MacBook Air 15" (M4), scaled to "More Space": values read from NSScreen on macOS 27.2.
    static let air15 = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1205),
        safeAreaTop: 37.5,
        auxiliaryTopLeftWidth: 856,
        auxiliaryTopRightWidth: 856,
        backingScale: 2
    )

    /// A 14" MacBook Pro at its default scaling (synthetic auxiliary widths).
    static let pro14 = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 664,
        auxiliaryTopRightWidth: 664,
        backingScale: 2
    )

    /// A 1× external display without a notch, placed to the right of the laptop and a little higher.
    static let external = ScreenDescriptor(
        frame: CGRect(x: 1920, y: 200, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: 200, width: 2560, height: 1415),
        safeAreaTop: 0,
        auxiliaryTopLeftWidth: nil,
        auxiliaryTopRightWidth: nil,
        backingScale: 1
    )

    // MARK: Notch detection and size

    @Test("A notched screen resolves to the hardware notch size")
    func notchSize() {
        let geometry = NotchGeometry.resolve(Self.air15)
        #expect(geometry.kind == .notch)
        #expect(geometry.hardwareNotch == CGSize(width: 208, height: 37.5))
        #expect(geometry.compactBaseSize == CGSize(width: 208, height: 37.5))
    }

    @Test("The idle compact island covers exactly the hardware notch, flush with the top edge")
    func idleCompactCoversNotch() {
        let rect = NotchGeometry.resolve(Self.air15).compactRect(leadingWidth: 0, trailingWidth: 0)
        #expect(rect == CGRect(x: 856, y: 1205.5, width: 208, height: 37.5))
    }

    @Test("Notch width is the frame width minus both auxiliary areas")
    func notchWidthFromAuxiliaryAreas() {
        let geometry = NotchGeometry.resolve(Self.pro14)
        #expect(geometry.hardwareNotch == CGSize(width: 184, height: 32))
        #expect(geometry.compactRect(leadingWidth: 0, trailingWidth: 0) == CGRect(x: 664, y: 950, width: 184, height: 32))
    }

    // MARK: Pill (no notch)

    @Test("A screen without a notch gets a pill just below its menu bar")
    func pillBelowMenuBar() {
        let geometry = NotchGeometry.resolve(Self.external)
        #expect(geometry.kind == .pill)
        #expect(geometry.hardwareNotch == nil)
        #expect(geometry.menuBarHeight == 25)
        let rect = geometry.compactRect(leadingWidth: 0, trailingWidth: 0)
        // Centred on the external screen; top = 1640 (maxY) − 25 (menu bar) − 6 (gap) = 1609.
        #expect(rect == CGRect(x: 3105, y: 1577, width: 190, height: 32))
    }

    @Test("An auto-hidden menu bar falls back to the standard 24 pt height")
    func autoHiddenMenuBar() {
        var screen = Self.external
        screen.visibleFrame = screen.frame
        let geometry = NotchGeometry.resolve(screen)
        let expectedTop: CGFloat = 1640 - 24 - 6
        #expect(geometry.menuBarHeight == 24)
        #expect(geometry.compactRect(leadingWidth: 0, trailingWidth: 0).maxY == expectedTop)
    }

    @Test("Forcing the pill on a notched screen places the pill below its menu bar")
    func forcePill() {
        let geometry = NotchGeometry.resolve(Self.air15, forcePill: true)
        #expect(geometry.kind == .pill)
        #expect(geometry.hardwareNotch == CGSize(width: 208, height: 37.5))
        let rect = geometry.compactRect(leadingWidth: 0, trailingWidth: 0)
        let expectedTop: CGFloat = 1243 - 38 - 6
        #expect(rect.maxY == expectedTop)
        #expect(rect.midX == 960)
    }

    // MARK: Width offset

    @Test("A positive width offset widens the compact island symmetrically")
    func positiveWidthOffset() {
        let rect = NotchGeometry.resolve(Self.air15, widthOffset: 20).compactRect(leadingWidth: 0, trailingWidth: 0)
        #expect(rect == CGRect(x: 846, y: 1205.5, width: 228, height: 37.5))
    }

    @Test("A negative width offset never makes the island narrower than the hardware notch")
    func negativeOffsetClampedOnNotch() {
        let geometry = NotchGeometry.resolve(Self.air15, widthOffset: -20)
        #expect(geometry.compactBaseSize.width == 208)
    }

    @Test("A negative width offset narrows the pill")
    func negativeOffsetOnPill() {
        let geometry = NotchGeometry.resolve(Self.external, widthOffset: -20)
        #expect(geometry.compactBaseSize.width == 170)
    }

    // MARK: Compact with activities

    @Test("Compact slots widen both sides by the wider slot so the island stays centred on the notch")
    func compactSlotsAreSymmetric() {
        let rect = NotchGeometry.resolve(Self.air15).compactRect(leadingWidth: 40, trailingWidth: 24)
        #expect(rect == CGRect(x: 816, y: 1205.5, width: 288, height: 37.5))
        #expect(rect.midX == 960)
    }

    // MARK: Expanded

    @Test("The expanded island hangs from the top edge on a notched screen")
    func expandedOnNotch() {
        let rect = NotchGeometry.resolve(Self.air15).expandedRect(size: CGSize(width: 600, height: 190))
        #expect(rect == CGRect(x: 660, y: 1053, width: 600, height: 190))
    }

    @Test("The expanded pill grows downward from the compact pill's top edge")
    func expandedOnPill() {
        let geometry = NotchGeometry.resolve(Self.external)
        let rect = geometry.expandedRect(size: CGSize(width: 600, height: 190))
        #expect(rect.maxY == geometry.compactRect(leadingWidth: 0, trailingWidth: 0).maxY)
        #expect(rect.midX == 3200)
    }

    @Test("The expanded island never exceeds the screen width minus margins")
    func expandedClampedToScreen() {
        let rect = NotchGeometry.resolve(Self.pro14).expandedRect(size: CGSize(width: 4000, height: 190))
        #expect(rect.width == 1512 - 2 * NotchGeometry.screenMargin)
        #expect(rect.midX == 756)
    }

    // MARK: Pixel alignment

    @Test("Rects are rounded to whole pixels: half points on 2× screens")
    func pixelAlignmentRetina() {
        var screen = Self.air15
        screen.safeAreaTop = 37.3
        let rect = NotchGeometry.resolve(screen).compactRect(leadingWidth: 0, trailingWidth: 0)
        #expect(rect.height == 37.5)
        #expect(rect.maxY == 1243)
    }

    @Test("Rects are rounded to whole points on 1× screens")
    func pixelAlignmentNonRetina() {
        let rect = NotchGeometry.resolve(Self.external, widthOffset: 3.4).compactRect(leadingWidth: 0, trailingWidth: 0)
        #expect(rect.width == 194)
        #expect(rect.minX == rect.minX.rounded())
    }

    // MARK: Panel frame

    @Test("On a notch, panel padding goes on the sides and bottom but never above the screen edge")
    func panelFrameOnNotch() {
        let geometry = NotchGeometry.resolve(Self.air15)
        let island = geometry.expandedRect(size: CGSize(width: 600, height: 190))
        let panel = geometry.panelFrame(for: island, padding: 20)
        #expect(panel == CGRect(x: 640, y: 1033, width: 640, height: 210))
    }

    @Test("With no padding the panel is exactly the island, so clicks beside it pass through")
    func panelFrameWithoutPadding() {
        let geometry = NotchGeometry.resolve(Self.air15)
        let island = geometry.compactRect(leadingWidth: 0, trailingWidth: 0)
        #expect(geometry.panelFrame(for: island, padding: 0) == island)
    }

    @Test("On a pill, panel padding above the island is limited to the gap below the menu bar")
    func panelFrameOnPill() {
        let geometry = NotchGeometry.resolve(Self.external)
        let island = geometry.compactRect(leadingWidth: 0, trailingWidth: 0)
        let panel = geometry.panelFrame(for: island, padding: 20)
        #expect(panel.maxY == island.maxY + NotchGeometry.pillGap)
        #expect(panel.minY == island.minY - 20)
        #expect(panel.width == island.width + 40)
    }
}
