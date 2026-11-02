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
/// the feature then hides itself. Every call reports failure instead of
/// crashing; the caller destroys everything on the first failure.
@MainActor
final class SkyLightLockScreen {
    enum Failure: Error, Equatable {
        case spaceNotCreated
        case call(String, Int32)
        case windowHasNoNumber
    }

    /// Absolute Space levels, from SkyLight's private headers (as listed by SkyLightWindow).
    /// 300 is the lock screen; 400 is where notifications show above it.
    static let levelAboveLockScreen: Int32 = 400

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowOrHideSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Int32

    private struct Symbols {
        var connection: MainConnectionID
        var create: SpaceCreate
        var setLevel: SpaceSetAbsoluteLevel
        var show: ShowOrHideSpaces
        var hide: ShowOrHideSpaces
        var addWindows: SpaceAddWindows
        var destroy: SpaceDestroy
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
              let destroy = find("SLSSpaceDestroy") else {
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
            destroy: unsafeBitCast(destroy, to: SpaceDestroy.self)
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

    /// Creates the Space above the lock screen and shows it. Call only while locked.
    func createSpace() throws {
        guard space == 0 else { return }
        let id = symbols.create(connection, 1, 0)
        guard id != 0 else { throw Failure.spaceNotCreated }
        space = id
        let level = symbols.setLevel(connection, id, Self.levelAboveLockScreen)
        guard level == 0 else { throw Failure.call("SLSSpaceSetAbsoluteLevel", level) }
        let shown = symbols.show(connection, [NSNumber(value: id)] as CFArray)
        guard shown == 0 else { throw Failure.call("SLSShowSpaces", shown) }
    }

    /// Moves a window (already created, not yet ordered front) into the Space.
    func add(_ window: NSWindow) throws {
        guard space != 0 else { throw Failure.spaceNotCreated }
        guard window.windowNumber > 0 else { throw Failure.windowHasNoNumber }
        // 7 is the flag every known caller passes (SkyLightWindow, yabai).
        let result = symbols.addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        guard result == 0 else { throw Failure.call("SLSSpaceAddWindowsAndRemoveFromSpaces", result) }
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
