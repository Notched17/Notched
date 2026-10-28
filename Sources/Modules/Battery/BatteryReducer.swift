// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The Mac's battery, as IOKit's power-source info describes it (#26).
struct PowerSnapshot: Equatable, Sendable {
    enum Power: Equatable, Sendable {
        case battery
        case charging
        /// Plugged in but not charging, short of full: Optimised Charging or
        /// a charge limit holding it, or the moment after plugging in.
        case notCharging
        /// Plugged in and full.
        case charged

        var isPluggedIn: Bool { self != .battery }
    }

    var hasBattery = true
    /// 0…100.
    var level: Int
    var power: Power
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    /// The charger's rating, when IOKit knows it.
    var adapterWatts: Int?
}

/// What the user chose in Settings ▸ Battery.
struct BatteryPreferences: Equatable, Sendable {
    /// Levels that announce Low Battery on the way down (default 20 % and 10 %).
    var lowThresholds: [Int] = [20, 10]
    /// Show a charging activity while charging below this level; nil means
    /// banners only (the default).
    var showWhileChargingUntil: Int?
}

/// Battery banners and the opt-in charging activity (#26). Pure.
///
/// - The first reading is silent.
/// - Plugging in or out is announced after 1 s (macOS often reports "not
///   charging" for a moment after plugging in, and a connector that touches
///   briefly says nothing), and not again for the same state within 10 s.
/// - Full is announced once, on reaching it while plugged in.
/// - Each low threshold fires once on the way down, and re-arms only 3 %
///   above it, so a level jittering at 20/21 % doesn't repeat it. A drop past
///   two thresholds at once fires one banner.
struct BatteryReducer: Sendable {
    static let plugPolicy = BannerPolicy(settle: 1, cooldown: 10)
    static let lowRearmMargin = 3

    enum Banner: Equatable, Sendable {
        case charging(level: Int)
        /// Plugged in, not charging (a charge limit or Optimised Charging).
        case pluggedIn(level: Int)
        case charged
        case onBattery(level: Int)
        case low(level: Int)
    }

    enum Event: Equatable, Sendable {
        case snapshot(PowerSnapshot)
        case preferences(BatteryPreferences)
        /// The wake the reducer asked for.
        case tick
    }

    enum Effect: Equatable, Sendable {
        case banner(Banner)
        case wake(Date)
        /// Post (or update) the charging activity.
        case post(PowerSnapshot)
        case end
    }

    struct State: Equatable, Sendable {
        var last: PowerSnapshot?
        /// Low thresholds already announced (or already passed at start).
        var lowFired: Set<Int> = []
        var activityPosted = false
        var preferences: BatteryPreferences
    }

    private(set) var state: State
    private var plug = BannerSource<Bool>(policy: plugPolicy)

    init(preferences: BatteryPreferences = BatteryPreferences()) {
        state = State(preferences: preferences)
    }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .snapshot(let snapshot):
            return observe(snapshot, now: now)
        case .preferences(let preferences):
            state.preferences = preferences
            guard let last = state.last, last.hasBattery else { return [] }
            state.lowFired.formUnion(preferences.lowThresholds.filter { last.level <= $0 })
            return activityEffects(last)
        case .tick:
            guard let last = state.last, last.hasBattery else { return [] }
            return plugEffects(plug.advance(to: now))
        }
    }

    private mutating func observe(_ snapshot: PowerSnapshot, now: Date) -> [Effect] {
        guard snapshot.hasBattery else {
            state.last = snapshot
            return []
        }
        guard let last = state.last, last.hasBattery else {
            // The first reading: what's true now isn't news.
            state.last = snapshot
            plug.seed(snapshot.power.isPluggedIn)
            state.lowFired = Set(state.preferences.lowThresholds.filter { snapshot.level <= $0 })
            return activityEffects(snapshot)
        }
        state.last = snapshot
        var effects = plugEffects(plug.receive(snapshot.power.isPluggedIn, at: now))
        if snapshot.power == .charged, last.power != .charged, last.power.isPluggedIn {
            effects.append(.banner(.charged))
        }
        effects += lowBatteryEffects(snapshot)
        effects += activityEffects(snapshot)
        return effects
    }

    /// The banner for a plug change, worded from the latest reading.
    private func plugEffects(_ output: BannerSource<Bool>.Output) -> [Effect] {
        switch output {
        case .none:
            return []
        case .wake(let date):
            return [.wake(date)]
        case .emit(let pluggedIn):
            guard let snapshot = state.last else { return [] }
            guard pluggedIn else { return [.banner(.onBattery(level: snapshot.level))] }
            return switch snapshot.power {
            case .charging, .battery: [.banner(.charging(level: snapshot.level))]
            case .notCharging: [.banner(.pluggedIn(level: snapshot.level))]
            case .charged: [.banner(.charged)]
            }
        }
    }

    private mutating func lowBatteryEffects(_ snapshot: PowerSnapshot) -> [Effect] {
        let margin = Self.lowRearmMargin
        state.lowFired = state.lowFired.filter { snapshot.level < $0 + margin }
        guard snapshot.power == .battery else { return [] }
        let crossed = state.preferences.lowThresholds.filter { snapshot.level <= $0 && !state.lowFired.contains($0) }
        guard !crossed.isEmpty else { return [] }
        state.lowFired.formUnion(crossed)
        return [.banner(.low(level: snapshot.level))]
    }

    private mutating func activityEffects(_ snapshot: PowerSnapshot) -> [Effect] {
        let wanted = state.preferences.showWhileChargingUntil.map { snapshot.power == .charging && snapshot.level < $0 } ?? false
        if wanted {
            state.activityPosted = true
            return [.post(snapshot)]
        }
        guard state.activityPosted else { return [] }
        state.activityPosted = false
        return [.end]
    }
}
