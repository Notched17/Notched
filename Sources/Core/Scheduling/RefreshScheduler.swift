// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The app's only repeating timer. Anything that truly has to poll registers
/// here instead of creating its own timer, so wake-ups are coalesced, slow down
/// on battery and Low Power Mode, and stop entirely while the screens are
/// asleep or locked, or the UI they serve is hidden (CLAUDE.md "Event-driven").
@MainActor
final class RefreshScheduler {
    var context = RefreshContext() {
        didSet { if context != oldValue { reschedule() } }
    }

    private var entries: [RefreshEntry] = []
    private var work: [RefreshToken: @MainActor () -> Void] = [:]
    private var names: [RefreshToken: String] = [:]
    private var nextID = 0
    private var timer: DispatchSourceTimer?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Runs `work` every `interval` (on AC power) while `condition` holds.
    @discardableResult
    func register(
        _ name: String,
        every interval: Duration,
        tolerance: Double = RefreshPlan.minimumTolerance,
        when condition: RefreshCondition = .always,
        scalesWithPower: Bool = true,
        _ work: @escaping @MainActor () -> Void
    ) -> RefreshToken {
        nextID += 1
        let token = RefreshToken(rawValue: nextID)
        entries.append(RefreshEntry(
            id: token, interval: interval.timeInterval, tolerance: tolerance,
            condition: condition, registeredAt: now(), lastFired: nil, scalesWithPower: scalesWithPower
        ))
        self.work[token] = work
        names[token] = name
        reschedule()
        return token
    }

    func unregister(_ token: RefreshToken) {
        entries.removeAll { $0.id == token }
        work[token] = nil
        names[token] = nil
        reschedule()
    }

    func setUIVisible(_ key: String, _ visible: Bool) {
        if visible { context.visibleUI.insert(key) } else { context.visibleUI.remove(key) }
    }

    var registrationCount: Int { entries.count }

    // MARK: Timer

    private func reschedule() {
        guard let deadline = RefreshPlan.nextDeadline(entries, context: context) else {
            timer?.cancel()
            timer = nil
            return
        }
        let timer = self.timer ?? makeTimer()
        let delay = max(0, deadline.date.timeIntervalSince(now()))
        timer.schedule(
            deadline: .now() + delay,
            repeating: .never,
            leeway: .milliseconds(Int(deadline.leeway * 1000))
        )
    }

    private func makeTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.resume()
        self.timer = timer
        return timer
    }

    private func fire() {
        let date = now()
        let due = Set(RefreshPlan.due(entries, at: date, context: context))
        for index in entries.indices where due.contains(entries[index].id) {
            entries[index].lastFired = date
        }
        for token in due.sorted(by: { $0.rawValue < $1.rawValue }) {
            work[token]?()
        }
        reschedule()
    }
}
