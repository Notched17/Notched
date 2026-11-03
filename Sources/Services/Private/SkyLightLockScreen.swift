// SPDX-License-Identifier: GPL-3.0-or-later
//
// Showing a window above the lock screen by moving it into a SkyLight Space at
// an absolute level above the lock screen is the technique of
// Lakr233/SkyLightWindow (MIT, https://github.com/Lakr233/SkyLightWindow).
// This is a fresh dlopen/dlsym wrapper, not a copy: every symbol is checked,
// Space ids are 64-bit, and the Space exists only while it is needed and is
// hidden first when it goes (ADR-0031). See THIRD_PARTY_NOTICES.md.

import AppKit
import Foundation

/// A private-API wrapper for one Space above the lock screen (#59, ADR-0031).
///
/// `make()` returns nil, logged once, if SkyLight or any symbol is missing, and
/// the feature then hides itself. Nothing here crashes; the caller destroys
/// everything on the first failure.
///
/// **macOS 27 (spike round 2):** in an AppKit app, SkyLight sends the Space
/// calls through an asynchronous "window management bridge". Set level, show,
/// hide, add windows and destroy then return **no status** (the register holds
/// whatever an autorelease-pool pop left there; round 2 read `0xB0000000` and
/// took it for an error). So those calls are declared `Void` and success is
/// checked by observation instead (`state(of:)`): which Spaces the window
/// server says the window is in, and whether it is on screen. Only
/// `SLSSpaceCreate` and `SLSCopySpacesForWindows` are synchronous and return
/// real values.
@MainActor
final class SkyLightLockScreen {
    enum Failure: Error, Equatable {
        case spaceNotCreated
        case windowHasNoNumber
    }

    /// Absolute Space levels, from SkyLight's private headers (as listed by SkyLightWindow).
    /// 300 is the lock screen; 400 is where notifications show above it.
    nonisolated static let levelAboveLockScreen: Int32 = 400

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias ShowOrHideSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Void
    /// (connection, selector 7 = every kind of Space, window ids) → +1 array of Space ids.
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private struct Symbols {
        var connection: MainConnectionID
        var create: SpaceCreate
        var setLevel: SpaceSetAbsoluteLevel
        var show: ShowOrHideSpaces
        var hide: ShowOrHideSpaces
        var addWindows: SpaceAddWindows
        var destroy: SpaceDestroy
        var copySpaces: CopySpacesForWindows
    }

    /// What the window server says about one of our windows.
    ///
    /// On macOS 27 `SLSCopySpacesForWindows` lists the desktop Spaces only, not
    /// ours: a window that moved into our Space reports **no Spaces at all**
    /// (spike round 2: the desktop test showed such a window in front of every
    /// app window, while the control, still on Space 1, stayed hidden).
    struct WindowState: Equatable, CustomStringConvertible {
        /// Nil when the window list has no entry for it (closed, or never made).
        var onScreen: Bool?
        var layer: Int?
        /// Nil when SkyLight returned nothing.
        var spaces: [UInt64]?
        var space: UInt64

        /// The window left the desktop Spaces, which is what moving into ours looks like.
        var leftDesktopSpaces: Bool { spaces?.isEmpty ?? false }

        var description: String {
            let screen = onScreen.map { $0 ? "on screen" : "off screen" } ?? "not in the window list"
            let list = spaces.map { $0.map(String.init).joined(separator: ", ") } ?? "unknown"
            return "\(screen), layer \(layer.map(String.init) ?? "-"), desktop Spaces [\(list)], \(leftDesktopSpaces ? "moved out of the desktop Spaces (expected)" : "STILL on a desktop Space")"
        }
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            Log.privateAPI.error("SkyLight could not be loaded; lock-screen widgets are unavailable")
            return nil
        }
        func find(_ name: String) -> UnsafeMutableRawPointer? { dlsym(handle, name) }
        guard let connection = find("SLSMainConnectionID"),
              let create = find("SLSSpaceCreate"),
              let setLevel = find("SLSSpaceSetAbsoluteLevel"),
              let show = find("SLSShowSpaces"),
              let hide = find("SLSHideSpaces"),
              let addWindows = find("SLSSpaceAddWindowsAndRemoveFromSpaces"),
              let destroy = find("SLSSpaceDestroy"),
              let copySpaces = find("SLSCopySpacesForWindows") else {
            Log.privateAPI.error("SkyLight Space symbols are missing; lock-screen widgets are unavailable")
            return nil
        }
        return Symbols(
            connection: unsafeBitCast(connection, to: MainConnectionID.self),
            create: unsafeBitCast(create, to: SpaceCreate.self),
            setLevel: unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self),
            show: unsafeBitCast(show, to: ShowOrHideSpaces.self),
            hide: unsafeBitCast(hide, to: ShowOrHideSpaces.self),
            addWindows: unsafeBitCast(addWindows, to: SpaceAddWindows.self),
            destroy: unsafeBitCast(destroy, to: SpaceDestroy.self),
            copySpaces: unsafeBitCast(copySpaces, to: CopySpacesForWindows.self)
        )
    }()

    static var isAvailable: Bool { symbols != nil }

    private let symbols: Symbols
    private let connection: Int32
    private var space: UInt64 = 0

    private init(symbols: Symbols) {
        self.symbols = symbols
        connection = symbols.connection()
    }

    /// Nil when the private API isn't there.
    static func make() -> SkyLightLockScreen? {
        symbols.map(SkyLightLockScreen.init(symbols:))
    }

    /// The Space's id, 0 when there is none.
    var spaceID: UInt64 { space }

    /// Creates the Space above the lock screen and asks for it to be shown.
    /// Call only while locked (the spike's desktop test is the one exception).
    /// Level and show return no status on macOS 27; check with `state(of:)`.
    func createSpace(level: Int32 = SkyLightLockScreen.levelAboveLockScreen) throws {
        guard space == 0 else { return }
        let id = symbols.create(connection, 1, 0)
        guard id != 0 else { throw Failure.spaceNotCreated }
        space = id
        symbols.setLevel(connection, id, level)
        symbols.show(connection, [NSNumber(value: id)] as CFArray)
    }

    /// Asks for a window (already created) to move into the Space. Returns no
    /// status on macOS 27; check with `state(of:)` after a moment.
    func add(_ window: NSWindow) throws {
        guard space != 0 else { throw Failure.spaceNotCreated }
        guard window.windowNumber > 0 else { throw Failure.windowHasNoNumber }
        // 7 is the flag every known caller passes (SkyLightWindow, yabai).
        symbols.addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }

    /// The window server's view of a window: its Spaces (SkyLight, synchronous)
    /// and its on-screen flag and layer (the public window list).
    func state(of window: NSWindow) -> WindowState {
        state(windowNumber: window.windowNumber)
    }

    /// By number, so it can also confirm that a closed window is really gone.
    func state(windowNumber: Int) -> WindowState {
        var state = WindowState(space: space)
        guard windowNumber > 0 else { return state }
        if let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]])?.first {
            state.onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            state.layer = info[kCGWindowLayer as String] as? Int
        }
        if let array = symbols.copySpaces(connection, 7, [NSNumber(value: windowNumber)] as CFArray)?.takeRetainedValue() {
            state.spaces = (array as? [NSNumber])?.map(\.uint64Value)
        }
        return state
    }

    /// Takes everything down, in the order ADR-0031 §2 sets: hide the Space (so
    /// nothing is visible from here on), close the windows, destroy the Space.
    /// Safe to call at any time, any number of times; it never throws.
    func tearDown(closing windows: [NSWindow]) {
        if space != 0 { _ = symbols.hide(connection, [NSNumber(value: space)] as CFArray) }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        if space != 0 { _ = symbols.destroy(connection, space) }
        space = 0
    }
}
