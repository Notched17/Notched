// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One countdown timer (#37). Everything is a date or a fixed amount, so it
/// needs no per-second work and survives sleep and relaunch.
struct TimerItem: Codable, Equatable, Sendable, Identifiable {
    enum Phase: Codable, Equatable, Sendable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        /// Finished at `endedAt`; shown as done until `until` (the alert),
        /// then it ends into Recent.
        case done(endedAt: Date, until: Date)
    }

    let id: UUID
    var label: String
    /// The whole length, including any minutes added.
    var duration: TimeInterval
    var phase: Phase

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .running(let endsAt): max(0, endsAt.timeIntervalSince(date))
        case .paused(let remaining): remaining
        case .done: 0
        }
    }

    /// 1 at the start, 0 at the end: the ring's length.
    func fractionLeft(at date: Date) -> Double {
        duration > 0 ? min(1, remaining(at: date) / duration) : 0
    }
}

/// The stopwatch (#37).
struct Stopwatch: Codable, Equatable, Sendable {
    /// When it last started; nil while paused.
    var startedAt: Date?
    /// Time counted before `startedAt`.
    var accumulated: TimeInterval = 0

    var isRunning: Bool { startedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

/// Everything Timers persists, so timers survive a relaunch.
struct TimersState: Codable, Equatable, Sendable {
    var timers: [TimerItem] = []
    var stopwatch: Stopwatch?

    static let stopwatchRelevance = 15.0

    /// Ranking within `.live` (ADR-0011): a done timer first, then running
    /// timers soonest first, then paused ones, then the stopwatch.
    func relevance(of id: UUID) -> Double {
        guard let timer = timers.first(where: { $0.id == id }) else { return 0 }
        switch timer.phase {
        case .done: return 40
        case .paused: return 20
        case .running(let endsAt):
            let later = timers.filter {
                if case .running(let other) = $0.phase { other > endsAt } else { false }
            }.count
            return 30 + Double(later + 1) / 100
        }
    }

    /// The next moment something changes: a running timer ending, or a done one leaving.
    var nextDeadline: Date? {
        timers.compactMap { timer -> Date? in
            switch timer.phase {
            case .running(let endsAt): endsAt
            case .done(_, let until): until
            case .paused: nil
            }
        }.min()
    }
}

/// Timers and the stopwatch (#37). Pure.
///
/// - One deadline is scheduled at a time: the earliest end.
/// - A timer that ends alerts with its sound, stays as done for the alert,
///   then ends into Recent. Woken from sleep, it alerts quietly if it ended
///   over a minute ago, and goes straight to Recent if over ten minutes.
/// - After a relaunch, running and paused timers carry on. One that ended
///   while Notched wasn't running alerts silently if that was in the last
///   ten minutes, otherwise it goes straight to Recent.
/// - At most ten timers; durations from one second to a day.
struct TimersReducer: Sendable {
    static let maxTimers = 10
    static let durationRange: ClosedRange<TimeInterval> = 1...86_400
    static let missedAlertWindow: TimeInterval = 10 * 60
    static let soundWindow: TimeInterval = 60
    static let defaultLabel = "Timer"
    static let labelLimit = 40

    enum Event: Equatable, Sendable {
        case start(duration: TimeInterval, label: String?, id: UUID)
        case pause(UUID)
        case resume(UUID)
        case addMinute(UUID)
        case cancel(UUID)
        /// The wake the reducer scheduled.
        case deadline
        /// The Mac woke from sleep.
        case wake
        /// The saved state, at launch.
        case restore(TimersState)
        case stopwatchStart
        case stopwatchPause
        case stopwatchReset
    }

    enum Effect: Equatable, Sendable {
        case post(TimerItem)
        /// The timer finished: post it as done with an alert, and play the
        /// sound if `sound`.
        case alert(TimerItem, sound: Bool)
        /// Take it off the island; listed under Recent when `toRecent`.
        case end(UUID, toRecent: Bool)
        case postStopwatch(Stopwatch)
        case endStopwatch
        case schedule(Date?)
        case persist(TimersState)
    }

    private(set) var state = TimersState()
    /// How long a finished timer stays as done: the alert's duration.
    let doneHold: TimeInterval

    init(doneHold: TimeInterval = 4) {
        self.doneHold = doneHold
    }

    /// Trims, drops control characters and caps the length; nil when nothing is left.
    static func cleanLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let kept = label.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(labelLimit))
    }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect]
        switch event {
        case .start(let duration, let label, let id):
            guard state.timers.count < Self.maxTimers else { return [] }
            let length = min(max(duration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
            let item = TimerItem(id: id, label: Self.cleanLabel(label) ?? Self.defaultLabel, duration: length,
                                 phase: .running(endsAt: now.addingTimeInterval(length)))
            state.timers.append(item)
            effects = [.post(item)]
        case .pause(let id):
            guard let item = update(id, { item in
                guard case .running(let endsAt) = item.phase else { return false }
                item.phase = .paused(remaining: max(0, endsAt.timeIntervalSince(now)))
                return true
            }) else { return [] }
            effects = [.post(item)]
        case .resume(let id):
            guard let item = update(id, { item in
                guard case .paused(let remaining) = item.phase else { return false }
                item.phase = .running(endsAt: now.addingTimeInterval(remaining))
                return true
            }) else { return [] }
            effects = [.post(item)]
        case .addMinute(let id):
            guard let item = update(id, { item in
                switch item.phase {
                case .running(let endsAt): item.phase = .running(endsAt: endsAt.addingTimeInterval(60))
                case .paused(let remaining): item.phase = .paused(remaining: remaining + 60)
                case .done: return false
                }
                item.duration += 60
                return true
            }) else { return [] }
            effects = [.post(item)]
        case .cancel(let id):
            guard let index = state.timers.firstIndex(where: { $0.id == id }) else { return [] }
            state.timers.remove(at: index)
            effects = [.end(id, toRecent: false)]
        case .deadline, .wake:
            effects = settle(now: now, mayPlaySound: true)
        case .restore(let saved):
            state = saved
            effects = []
            for item in state.timers {
                switch item.phase {
                case .running(let endsAt) where endsAt > now: effects.append(.post(item))
                case .paused: effects.append(.post(item))
                case .running, .done: break
                }
            }
            if let stopwatch = state.stopwatch { effects.append(.postStopwatch(stopwatch)) }
            // Quit while showing as done: it's over, list it under Recent.
            for item in state.timers {
                guard case .done(let endedAt, _) = item.phase else { continue }
                state.timers.removeAll { $0.id == item.id }
                var ended = item
                ended.phase = .done(endedAt: endedAt, until: now)
                effects += [.post(ended), .end(item.id, toRecent: true)]
            }
            effects += settle(now: now, mayPlaySound: false)
        case .stopwatchStart:
            var stopwatch = state.stopwatch ?? Stopwatch()
            guard !stopwatch.isRunning else { return [] }
            stopwatch.startedAt = now
            state.stopwatch = stopwatch
            effects = [.postStopwatch(stopwatch)]
        case .stopwatchPause:
            guard var stopwatch = state.stopwatch, let startedAt = stopwatch.startedAt else { return [] }
            stopwatch.accumulated += max(0, now.timeIntervalSince(startedAt))
            stopwatch.startedAt = nil
            state.stopwatch = stopwatch
            effects = [.postStopwatch(stopwatch)]
        case .stopwatchReset:
            guard state.stopwatch != nil else { return [] }
            state.stopwatch = nil
            effects = [.endStopwatch]
        }
        return effects + [.schedule(state.nextDeadline), .persist(state)]
    }

    /// Changes one timer; nil if it doesn't exist or `change` declines.
    private mutating func update(_ id: UUID, _ change: (inout TimerItem) -> Bool) -> TimerItem? {
        guard let index = state.timers.firstIndex(where: { $0.id == id }) else { return nil }
        var item = state.timers[index]
        guard change(&item) else { return nil }
        state.timers[index] = item
        return item
    }

    /// Finishes timers whose end has passed and retires done ones whose alert is over.
    private mutating func settle(now: Date, mayPlaySound: Bool) -> [Effect] {
        var effects: [Effect] = []
        let ended = state.timers.compactMap { item -> (TimerItem, Date)? in
            if case .running(let endsAt) = item.phase, endsAt <= now { (item, endsAt) } else { nil }
        }.sorted { $0.1 < $1.1 }
        for (item, endedAt) in ended {
            let late = now.timeIntervalSince(endedAt)
            var done = item
            if late > Self.missedAlertWindow {
                done.phase = .done(endedAt: endedAt, until: now)
                state.timers.removeAll { $0.id == item.id }
                effects += [.post(done), .end(item.id, toRecent: true)]
            } else {
                done.phase = .done(endedAt: endedAt, until: now.addingTimeInterval(doneHold))
                if let index = state.timers.firstIndex(where: { $0.id == item.id }) { state.timers[index] = done }
                effects.append(.alert(done, sound: mayPlaySound && late <= Self.soundWindow))
            }
        }
        let retired = state.timers.filter {
            if case .done(_, let until) = $0.phase { until <= now } else { false }
        }
        for item in retired {
            state.timers.removeAll { $0.id == item.id }
            effects.append(.end(item.id, toRecent: true))
        }
        return effects
    }
}

/// A timer asked for by URL.
struct TimerRequest: Equatable, Sendable {
    var duration: TimeInterval
    var label: String?
}

/// `notched://timer?minutes=10&label=Tea` (also `hours=` and `seconds=`,
/// added together). Any app or web page can open it, so it's checked
/// strictly: one second to a day, and a short, clean label.
enum TimerURL {
    static func parse(_ url: URL) -> TimerRequest? {
        guard url.scheme?.lowercased() == "notched", url.host?.lowercased() == "timer",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let units: [String: TimeInterval] = ["hours": 3600, "minutes": 60, "seconds": 1]
        var total: TimeInterval = 0
        var found = false
        for item in items {
            guard let unit = units[item.name.lowercased()] else { continue }
            guard let value = item.value.flatMap(Double.init), value.isFinite, value >= 0 else { return nil }
            total += value * unit
            found = true
        }
        guard found, TimersReducer.durationRange.contains(total) else { return nil }
        let label = items.first { $0.name.lowercased() == "label" }?.value
        return TimerRequest(duration: total, label: TimersReducer.cleanLabel(label))
    }
}
