// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Calendar's rules (#48, #49): which event the compact island counts down to,
/// when it alerts, and what the agenda lists. Pure; the shell fetches events
/// from EventKit and carries out the effects.
///
/// - Declined and cancelled events, and calendars the user left out, are ignored.
/// - All-day events appear in the agenda but never start a countdown.
/// - The countdown runs from `countdownMinutes` before the start, in whole
///   minutes rounded up, then reads "Now" for `nowGrace` after the start.
/// - If one event is coming and another just started, the coming one is shown.
/// - It alerts once per event, `alertLead` before the start (or when first
///   seen inside that minute), and never after the start.
/// - Without access, nothing is shown.
struct CalendarReducer: Sendable {
    struct State: Equatable, Sendable {
        var config = CalendarConfig()
        var hasAccess = false
        var events: [CalendarEventSnapshot] = []
        var countdown: CountdownInfo?
        var agenda: [AgendaItem] = []
        var alerted: Set<String> = []
        var scheduledWake: Date?
    }

    enum Event: Equatable, Sendable {
        case configure(CalendarConfig)
        case access(Bool)
        /// Events overlapping today and tomorrow (and the countdown window).
        case events([CalendarEventSnapshot])
        /// The wake the reducer asked for, or any moment worth re-checking (wake from sleep).
        case tick
    }

    enum Effect: Equatable, Sendable {
        /// Show or update the countdown; `alert` also expands the island once.
        case post(CountdownInfo, alert: Bool)
        case endCountdown
        case agendaChanged([AgendaItem])
        case wake(Date?)
    }

    private(set) var state = State()

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .configure(let config): state.config = config
        case .access(let granted): state.hasAccess = granted
        case .events(let events): state.events = events
        case .tick: break
        }
        return evaluate(now: now)
    }

    // MARK: Evaluation

    private mutating func evaluate(now: Date) -> [Effect] {
        var effects: [Effect] = []
        let config = state.config

        // Agenda
        let agenda = state.hasAccess ? makeAgenda(now: now) : []
        if agenda != state.agenda {
            state.agenda = agenda
            effects.append(.agendaChanged(agenda))
        }

        // Countdown
        let next = state.hasAccess ? countdown(now: now) : nil
        if let next {
            let shouldAlert = config.alertBeforeStart && !next.hasStarted
                && next.start.timeIntervalSince(now) <= config.alertLead && !state.alerted.contains(next.eventID)
            if shouldAlert { state.alerted.insert(next.eventID) }
            if next != state.countdown || shouldAlert {
                state.countdown = next
                effects.append(.post(next, alert: shouldAlert))
            }
        } else if state.countdown != nil {
            state.countdown = nil
            effects.append(.endCountdown)
        }

        // Wake
        let wake = nextWake(now: now)
        if wake != state.scheduledWake {
            state.scheduledWake = wake
            effects.append(.wake(wake))
        }
        return effects
    }

    private func isEligible(_ event: CalendarEventSnapshot) -> Bool {
        !event.isCancelled && !event.isDeclined && !state.config.excludedCalendars.contains(event.calendarID)
    }

    private func countdown(now: Date) -> CountdownInfo? {
        let config = state.config
        let window = TimeInterval(config.countdownMinutes * 60)
        let timed = state.events.filter { isEligible($0) && !$0.isAllDay && $0.end > now }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }

        // A coming event beats one that just started.
        if let coming = timed.first(where: { $0.start > now && $0.start.timeIntervalSince(now) <= window }) {
            let minutes = max(1, Int((coming.start.timeIntervalSince(now) / 60).rounded(.up)))
            return info(for: coming, minutes: minutes)
        }
        if let started = timed.last(where: { $0.start <= now && now.timeIntervalSince($0.start) < config.nowGrace }) {
            return info(for: started, minutes: 0)
        }
        return nil
    }

    private func info(for event: CalendarEventSnapshot, minutes: Int) -> CountdownInfo {
        CountdownInfo(eventID: event.id, title: event.title, start: event.start, end: event.end, color: event.color,
                      join: MeetingLinkDetector.detect(url: event.urlString, location: event.location, notes: event.notes), minutesLeft: minutes)
    }

    /// Today's and tomorrow's events still to come or running, all-day first.
    private func makeAgenda(now: Date) -> [AgendaItem] {
        let calendar = state.config.calendar
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let dayAfter = calendar.date(byAdding: .day, value: 2, to: todayStart) else { return [] }
        var items: [AgendaItem] = []
        for (isTomorrow, from, to) in [(false, todayStart, tomorrowStart), (true, tomorrowStart, dayAfter)] {
            let day = state.events
                .filter { isEligible($0) && $0.start < to && $0.end > from && ($0.isAllDay || $0.end > now) }
                .sorted { (lhs, rhs) in
                    (lhs.isAllDay ? 0 : 1, lhs.start, lhs.title, lhs.id) < (rhs.isAllDay ? 0 : 1, rhs.start, rhs.title, rhs.id)
                }
            items += day.map { event in
                AgendaItem(id: "\(event.id)#\(isTomorrow ? 1 : 0)", title: event.title, start: event.start, end: event.end,
                           isAllDay: event.isAllDay, isTomorrow: isTomorrow, isInProgress: !event.isAllDay && event.start <= now && event.end > now,
                           color: event.color, location: event.location,
                           join: MeetingLinkDetector.detect(url: event.urlString, location: event.location, notes: event.notes))
            }
        }
        return items
    }

    /// The soonest moment anything above could change.
    private func nextWake(now: Date) -> Date? {
        guard state.hasAccess else { return nil }
        let config = state.config
        let window = TimeInterval(config.countdownMinutes * 60)
        var candidates: [Date] = []
        let calendar = config.calendar
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) { candidates.append(midnight) }
        for event in state.events where isEligible(event) {
            candidates.append(event.end)
            guard !event.isAllDay else { continue }
            candidates += [event.start - window, event.start - config.alertLead, event.start, event.start + config.nowGrace]
        }
        // The next minute boundary of the countdown on show.
        if let countdown = state.countdown, countdown.minutesLeft > 1 {
            candidates.append(countdown.start - TimeInterval(countdown.minutesLeft - 1) * 60)
        }
        return candidates.filter { $0 > now }.min()
    }
}
