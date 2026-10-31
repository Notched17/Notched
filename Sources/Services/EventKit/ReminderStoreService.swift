// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit

/// Reminders as the Reminders module needs them. A protocol so tests can
/// supply reminders without EventKit or a permission prompt.
@MainActor
protocol ReminderSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    func requestAccess() async -> Bool
    /// Incomplete reminders due before `end` (including everything overdue).
    func incompleteReminders(dueBefore end: Date) async -> [ReminderSnapshot]
    /// Marks one reminder complete. Throws if EventKit refuses or it is gone.
    func complete(id: String) throws
    func lists() -> [ReminderListInfo]
    /// Called when the reminders database changes (`EKEventStoreChanged`): no polling.
    var onChange: (() -> Void)? { get set }
    func startObserving()
    func stopObserving()
}

enum ReminderStoreError: Error { case notFound }

/// EventKit reminders (#50). Titles are copied into snapshots and never logged.
@MainActor
final class ReminderStoreService: ReminderSource {
    private let store = EKEventStore()
    private var token: (any NSObjectProtocol)?
    var onChange: (() -> Void)?

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
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

    func incompleteReminders(dueBefore end: Date) async -> [ReminderSnapshot] {
        guard authorization == .granted else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        // EKReminder isn't Sendable, so it is turned into plain values inside the callback.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.snapshot))
            }
        }
    }

    func complete(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw ReminderStoreError.notFound }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    func lists() -> [ReminderListInfo] {
        guard authorization == .granted else { return [] }
        return store.calendars(for: .reminder)
            .map { ReminderListInfo(id: $0.calendarIdentifier, name: $0.title, color: Self.color($0.color)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
        let components = reminder.dueDateComponents
        let calendar = components?.calendar ?? Calendar.current
        return ReminderSnapshot(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled",
            due: components.flatMap { calendar.date(from: $0) },
            hasTime: components?.hour != nil,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listName: reminder.calendar?.title ?? "",
            color: color(reminder.calendar?.color),
            priority: reminder.priority
        )
    }

    private nonisolated static func color(_ color: NSColor?) -> ColorValue {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return ColorValue(red: 10, green: 132, blue: 255) }
        return ColorValue.fromUnit(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent)).value
    }
}
