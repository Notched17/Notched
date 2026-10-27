// SPDX-License-Identifier: GPL-3.0-or-later
//
// Reading the managed display spaces to detect fullscreen spaces is the
// technique used by TheBoredTeam/MacroVisionKit (MIT). This is a fresh
// dlopen/dlsym wrapper that fails gracefully. See THIRD_PARTY_NOTICES.md.

import Foundation

/// A private-API wrapper around SkyLight's `CGSCopyManagedDisplaySpaces`,
/// which describes every display's Spaces and which one is current.
///
/// If the symbols ever disappear, `isAvailable` is false, the failure is logged
/// once, and callers fall back to `WindowListFullscreenHeuristic`.
@MainActor
enum SkyLightSpaces {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let symbols: (connection: MainConnectionID, copySpaces: CopyManagedDisplaySpaces)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            Log.privateAPI.error("SkyLight could not be loaded; using the window-list fallback for fullscreen detection")
            return nil
        }
        let connection = dlsym(handle, "SLSMainConnectionID") ?? dlsym(handle, "CGSMainConnectionID")
        let copySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces") ?? dlsym(handle, "CGSCopyManagedDisplaySpaces")
        guard let connection, let copySpaces else {
            Log.privateAPI.error("SkyLight space symbols are missing; using the window-list fallback for fullscreen detection")
            return nil
        }
        return (unsafeBitCast(connection, to: MainConnectionID.self), unsafeBitCast(copySpaces, to: CopyManagedDisplaySpaces.self))
    }()

    static var isAvailable: Bool { symbols != nil }

    /// One dictionary per display, or nil when the private API is unavailable.
    static func managedDisplaySpaces() -> [[String: Any]]? {
        guard let symbols else { return nil }
        let array = symbols.copySpaces(symbols.connection())?.takeRetainedValue()
        return array as? [[String: Any]]
    }
}
