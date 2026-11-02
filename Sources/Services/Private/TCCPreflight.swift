// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A private-API wrapper around TCC's `TCCAccessPreflight`, which says whether
/// a privacy permission is granted **without** showing a prompt. Core Audio
/// has no public way to ask about the audio-capture permission (process taps,
/// #17), so the M6 spike checks whether this one answers.
///
/// If the framework or symbol is missing, `isAvailable` is false, the failure
/// is logged once, and callers treat the answer as unknown.
enum TCCPreflight {
    enum Answer: String, Sendable {
        case granted, denied, unknown
    }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32

    private static let preflight: Preflight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(handle, "TCCAccessPreflight") else {
            Log.privateAPI.error("TCCAccessPreflight is unavailable; permission state stays unknown until it is used")
            return nil
        }
        return unsafeBitCast(symbol, to: Preflight.self)
    }()

    static var isAvailable: Bool { preflight != nil }

    /// `service` is a TCC service name such as `kTCCServiceAudioCapture`.
    /// The private function answers 0 for granted and 1 for denied; anything
    /// else (not asked yet) is unknown.
    static func check(_ service: String) -> Answer {
        guard let preflight else { return .unknown }
        switch preflight(service as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }
}
