// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The per-app volume mixer's brain (#17, ADR-0029). Pure: Foundation only.
///
/// - An app is **tapped only while its volume is below 100 %** (or it is
///   muted). At 100 % nothing exists, so the purple recording dot shows only
///   while a volume is actually being changed.
/// - **Probation.** macOS can't be asked whether audio capture was allowed,
///   and a refused tap silences the app (`mutedWhenTapped`) while delivering
///   only zeros. So a new tap is on probation until it delivers sound. If it
///   delivers none for `probationWindow` while the app is playing, the tap is
///   removed (the app comes back at full volume), the app is marked
///   "couldn't hear", and nothing tries again until the user does
///   (slider, Try Again). Once any tap has delivered sound in this launch the
///   permission is proven and later taps skip probation.
/// - Volumes live in memory only. Nothing is tapped at launch.
struct MixerReducer: Sendable {
    /// Sound reached granted taps in about 0.16 s (ADR-0029); four to five times that.
    static let probationWindow: TimeInterval = 0.75

    enum Problem: Equatable, Sendable {
        /// The tap only ever heard silence while the app played: probably refused.
        case silent
        /// Core Audio refused to build the tap.
        case failed
    }

    enum TapState: Equatable, Sendable {
        case none
        /// Asked of the engine, not running yet (may be waiting on the system prompt).
        case starting
        /// Running, not yet heard to deliver sound. `until` is nil while the app
        /// isn't playing: nothing can be judged until it does.
        case probation(until: Date?)
        case running
    }

    struct App: Equatable, Sendable, Identifiable {
        /// The app's bundle id.
        let id: String
        var name: String
        var isPlaying: Bool
        var volume = 1.0
        var isMuted = false
        var tap = TapState.none
        var problem: Problem?

        /// What the tap's gain should be.
        var gain: Float { isMuted ? 0 : Float(volume) }
        var wantsTap: Bool { gain < 1 && problem == nil }
        /// Listed in the tab: playing, or still changed from normal.
        var isListed: Bool { isPlaying || gain < 1 || problem != nil }
    }

    /// One app as the process monitor sees it.
    struct Observed: Equatable, Sendable {
        let id: String
        let name: String
        let isPlaying: Bool
    }

    enum Event: Equatable, Sendable {
        /// Every app that currently has an audio process.
        case apps([Observed])
        case setVolume(String, Double)
        case setMuted(String, Bool)
        /// The engine built (or rebuilt) the tap and it is running.
        case tapStarted(String)
        case tapFailed(String)
        /// Sound has arrived through the app's tap.
        case heard(String)
        /// The probation deadline the reducer asked for.
        case tick
        /// The default output changed: the engine rebuilds every tap.
        case outputChanged
        /// Try Again.
        case retry(String)
        /// Every app back to 100 %.
        case resetAll
    }

    enum Effect: Equatable, Sendable {
        case startTap(String, gain: Float)
        case setGain(String, Float)
        case stopTap(String)
        case rebuildTap(String)
        case wake(Date)
        /// What the probation learned about the audio-capture permission.
        case recordPermission(granted: Bool)
    }

    private(set) var apps: [App] = []
    /// Some tap has delivered sound in this launch: the permission is granted.
    private(set) var isPermissionProven = false

    /// Apps whose taps are on probation, for the shell to check for sound
    /// before it sends `.tick`.
    var onProbation: [String] {
        apps.compactMap { if case .probation = $0.tap { $0.id } else { nil } }
    }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .apps(let observed):
            update(observed, now: now, effects: &effects)
        case .setVolume(let id, let volume):
            guard let index = index(of: id) else { return [] }
            apps[index].volume = min(max(volume, 0), 1)
            apps[index].problem = nil   // moving the slider is a deliberate try
            changed(index, effects: &effects)
        case .setMuted(let id, let muted):
            guard let index = index(of: id) else { return [] }
            apps[index].isMuted = muted
            apps[index].problem = nil
            changed(index, effects: &effects)
        case .tapStarted(let id):
            guard let index = index(of: id), apps[index].tap != .none else { return [] }
            if isPermissionProven {
                apps[index].tap = .running
            } else if apps[index].isPlaying {
                apps[index].tap = .probation(until: now.addingTimeInterval(Self.probationWindow))
                effects.append(.wake(now.addingTimeInterval(Self.probationWindow)))
            } else {
                apps[index].tap = .probation(until: nil)
            }
        case .tapFailed(let id):
            guard let index = index(of: id), apps[index].tap != .none else { return [] }
            apps[index].tap = .none
            apps[index].problem = .failed
            effects.append(.stopTap(id))
        case .heard(let id):
            guard let index = index(of: id), apps[index].tap != .none else { return [] }
            if !isPermissionProven {
                isPermissionProven = true
                effects.append(.recordPermission(granted: true))
            }
            // The permission is granted for every tap.
            for other in apps.indices where apps[other].tap != .none { apps[other].tap = .running }
        case .tick:
            tick(now: now, effects: &effects)
        case .outputChanged:
            for index in apps.indices where apps[index].tap != .none {
                effects.append(.rebuildTap(apps[index].id))
                // Until proven, a rebuilt tap has to be heard again.
                if !isPermissionProven { apps[index].tap = .starting }
            }
        case .retry(let id):
            guard let index = index(of: id) else { return [] }
            apps[index].problem = nil
            changed(index, effects: &effects)
        case .resetAll:
            for index in apps.indices {
                apps[index].volume = 1
                apps[index].isMuted = false
                apps[index].problem = nil
                changed(index, effects: &effects)
            }
        }
        return effects
    }

    // MARK: Pieces

    private func index(of id: String) -> Int? { apps.firstIndex { $0.id == id } }

    private mutating func update(_ observed: [Observed], now: Date, effects: inout [Effect]) {
        let present = Set(observed.map(\.id))
        for index in apps.indices.reversed() where !present.contains(apps[index].id) {
            if apps[index].tap != .none { effects.append(.stopTap(apps[index].id)) }
            apps.remove(at: index)
        }
        for item in observed {
            guard let index = index(of: item.id) else {
                apps.append(App(id: item.id, name: item.name, isPlaying: item.isPlaying))
                continue
            }
            apps[index].name = item.name
            let startedPlaying = item.isPlaying && !apps[index].isPlaying
            apps[index].isPlaying = item.isPlaying
            // A tap that couldn't be judged while the app was quiet starts its clock now.
            if startedPlaying, case .probation(until: nil) = apps[index].tap {
                apps[index].tap = .probation(until: now.addingTimeInterval(Self.probationWindow))
                effects.append(.wake(now.addingTimeInterval(Self.probationWindow)))
            }
        }
    }

    /// The app's volume, mute or problem changed: start, adjust or stop its tap.
    private mutating func changed(_ index: Int, effects: inout [Effect]) {
        let app = apps[index]
        switch (app.wantsTap, app.tap) {
        case (true, .none):
            effects.append(.startTap(app.id, gain: app.gain))
            apps[index].tap = .starting
        case (true, _):
            effects.append(.setGain(app.id, app.gain))
        case (false, .none):
            break
        case (false, _):
            effects.append(.stopTap(app.id))
            apps[index].tap = .none
        }
    }

    private mutating func tick(now: Date, effects: inout [Effect]) {
        for index in apps.indices {
            guard case .probation(let deadline?) = apps[index].tap, deadline <= now else { continue }
            if apps[index].isPlaying {
                // Playing, but only silence came through: refused. Give the app its sound back.
                apps[index].tap = .none
                apps[index].problem = .silent
                effects.append(.stopTap(apps[index].id))
                if !isPermissionProven { effects.append(.recordPermission(granted: false)) }
            } else {
                apps[index].tap = .probation(until: nil)
            }
        }
        let next = apps.compactMap { app -> Date? in
            if case .probation(let deadline?) = app.tap { deadline } else { nil }
        }.min()
        if let next { effects.append(.wake(next)) }
    }
}
