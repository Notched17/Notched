// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Camera & Microphone (#31): when the camera or microphone is in use, one
/// activity says so, like iPhone's green and orange dots. The rules that are
/// easy to get wrong:
///
/// - **Debounce, both ways.** A sensor shows after 500 ms of continuous use
///   and goes after 500 ms of none, so a glitchy listener can't flash a dot.
/// - **What was already on when the module started shows at once.** A privacy
///   indicator mustn't wait. The same after wake: the next snapshot is taken
///   as it is.
/// - **A call owns its own microphone and camera.** While a call is on (the
///   Calls module's `CallClaims`) the call's app isn't listed under the
///   microphone, and the camera is merged into the call. Any *other* app using
///   the microphone still shows.
/// - **Only proven names.** An app with no proven owner counts as "an app".
///
/// Foundation only: the shell turns listener callbacks into events.
struct SensorIndicatorReducer: Sendable {
    static let debounce: TimeInterval = 0.5

    struct Preferences: Equatable, Sendable {
        var showMicrophone = true
        var showCamera = true
    }

    /// What the island says.
    struct Model: Equatable, Sendable {
        var camera: Bool
        var mic: Bool
        /// Apps proven to be using the microphone, unique and sorted.
        var micApps: [String]
        /// Something uses the microphone that we can't name.
        var micHasUnnamedApp: Bool
    }

    enum Phase: Equatable, Sendable {
        case off
        case pendingOn(since: Date)
        case on
        case pendingOff(since: Date)

        var isShowing: Bool {
            switch self {
            case .on, .pendingOff: true
            case .off, .pendingOn: false
            }
        }
    }

    enum Event: Equatable, Sendable {
        case snapshot(SensorSnapshot)
        case claims(CallClaims)
        case preferences(Preferences)
        /// The wake the reducer asked for.
        case tick
        /// The Mac woke: what we knew may be stale.
        case wake
    }

    enum Effect: Equatable, Sendable {
        case post(Model)
        case end
        case schedule(Date?)
    }

    private var camera = Phase.off
    private var mic = Phase.off
    private var snapshot = SensorSnapshot.idle
    private var claims = CallClaims()
    private var preferences = Preferences()
    private var hasSnapshot = false
    private var seedNext = true
    private var posted: Model?
    private var scheduled: Date?

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .snapshot(let next):
            snapshot = next
            hasSnapshot = true
            if seedNext {
                seedNext = false
                let wanted = self.wanted()
                camera = wanted.camera ? .on : .off
                mic = wanted.mic ? .on : .off
                return effects(wanted: wanted)
            }
        case .claims(let next): claims = next
        case .preferences(let next): preferences = next
        case .tick: break
        case .wake:
            seedNext = true
            return []
        }
        guard hasSnapshot else { return [] }
        let wanted = self.wanted()
        camera = Self.step(camera, wanted: wanted.camera, now: now)
        mic = Self.step(mic, wanted: wanted.mic, now: now)
        return effects(wanted: wanted)
    }

    // MARK: Rules

    private struct Wanted {
        var camera: Bool
        var mic: Bool
        var apps: [String]
        var hasUnnamedApp: Bool
    }

    private func wanted() -> Wanted {
        let call = claims.isCallActive
        let others = snapshot.micUsers.filter { !claims.identities.contains($0.identity) }
        let unattributed = snapshot.micRunningUnattributed && !call
        let mic = preferences.showMicrophone && (!others.isEmpty || unattributed)
        return Wanted(
            camera: preferences.showCamera && snapshot.cameraRunning && !call,
            mic: mic,
            apps: Array(Set(others.compactMap(\.appName))).sorted(),
            hasUnnamedApp: others.contains { $0.appName == nil } || unattributed
        )
    }

    private static func step(_ phase: Phase, wanted: Bool, now: Date) -> Phase {
        let settled = { (since: Date) in now.timeIntervalSince(since) >= debounce - 0.001 }
        switch (phase, wanted) {
        case (.off, true): return .pendingOn(since: now)
        case (.off, false): return .off
        case (.pendingOn, false): return .off
        case (.pendingOn(let since), true): return settled(since) ? .on : phase
        case (.on, false): return .pendingOff(since: now)
        case (.on, true): return .on
        case (.pendingOff, true): return .on
        case (.pendingOff(let since), false): return settled(since) ? .off : phase
        }
    }

    private mutating func effects(wanted: Wanted) -> [Effect] {
        var result: [Effect] = []
        if camera.isShowing || mic.isShowing {
            // While a microphone drops out, its last names stay up until it goes.
            let model = Model(
                camera: camera.isShowing,
                mic: mic.isShowing,
                micApps: !mic.isShowing ? [] : wanted.mic ? wanted.apps : posted?.micApps ?? [],
                micHasUnnamedApp: !mic.isShowing ? false : wanted.mic ? wanted.hasUnnamedApp : posted?.micHasUnnamedApp ?? false
            )
            if model != posted {
                posted = model
                result.append(.post(model))
            }
        } else if posted != nil {
            posted = nil
            result.append(.end)
        }
        let next = [camera, mic].compactMap { phase -> Date? in
            switch phase {
            case .pendingOn(let since), .pendingOff(let since): since.addingTimeInterval(Self.debounce)
            case .off, .on: nil
            }
        }.min()
        if next != scheduled {
            scheduled = next
            result.append(.schedule(next))
        }
        return result
    }
}
