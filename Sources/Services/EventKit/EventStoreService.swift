// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit

/// The calendar as the Calendar module needs it. A protocol so tests can
/// supply events without EventKit or a permission prompt.
@MainActor
protocol CalendarEventSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    /// Asks macOS for full calendar access (shows its prompt the first time).
    func requestAccess() async -> Bool
    /// Events overlapping `start..<end`, as plain values.
    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot]
    func calendars() -> [CalendarInfo]
    /// Called when the calendar database changes (`EKEventStoreChanged`): no polling.
    var onChange: (() -> Void)? { get set }
    func startObserving()
    func stopObserving()
}

/// EventKit (#48). Titles, locations and notes are copied into snapshots and
/// never logged.
@MainActor
final class EventStoreService: CalendarEventSource {
    private let store = EKEventStore()
    private var token: (any NSObjectProtocol)?
    var onChange: (() -> Void)?

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied   // denied, restricted, or write-only (not enough to read)
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func startObserving() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    func stopObserving() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        guard authorization == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.snapshot)
    }

    func calendars() -> [CalendarInfo] {
        guard authorization == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, name: $0.title, color: Self.color($0.color)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        let me = event.attendees?.first(where: \.isCurrentUser)
        let identifier = event.eventIdentifier ?? UUID().uuidString
        return CalendarEventSnapshot(
            id: "\(identifier)@\(Int(event.startDate.timeIntervalSince1970))",
            title: event.title ?? "Untitled",
            start: event.startDate, end: event.endDate,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            isDeclined: me?.participantStatus == .declined,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarName: event.calendar?.title ?? "",
            color: color(event.calendar?.color),
            location: event.location?.isEmpty == false ? event.location : nil,
            urlString: event.url?.absoluteString,
            notes: event.notes.map { String($0.prefix(20_000)) }
        )
    }

    private static func color(_ color: NSColor?) -> ColorValue {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return ColorValue(red: 10, green: 132, blue: 255) }
        return ColorValue.fromUnit(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent)).value
    }
}
