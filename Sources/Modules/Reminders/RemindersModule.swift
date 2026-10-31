// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Reminders (#50): today's and overdue reminders in the Today tab, with a
/// checkbox that completes them and an 8-second undo. A thin shell around
/// `RemindersReducer`.
///
/// Event-driven like Calendar: it refetches on `EKEventStoreChanged`, on
/// wake and at midnight (the reducer's wakes), never on a timer of its own.
@MainActor
final class RemindersModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "reminders",
        name: "Reminders",
        symbol: "checklist",
        summary: "Lists today's and overdue reminders in the Today tab, and lets you tick them off, with a few seconds to undo.",
        permissions: [.reminders],
        isDebugOnly: false,
        isOnByDefault: false
    )
    static let sectionID = "reminders"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(RemindersSettingsPane(settings: context.settings.reminders, registry: context.registry, permissions: context.permissions))
    }

    let model = RemindersModel()
    private let context: ModuleContext
    private let source: any ReminderSource
    private let wake = OneShotTimer()
    private let observers = NotificationTokens()
    private var reducer = RemindersReducer()
    private var isRunning = false
    /// Only the newest fetch may answer; an older one that finishes late is dropped.
    private var fetchGeneration = 0
    private let log = Log.module("reminders")

    private var settings: RemindersSettings { context.settings.reminders }

    convenience init(context: ModuleContext) {
        self.init(context: context, source: ReminderStoreService())
    }

    init(context: ModuleContext, source: any ReminderSource) {
        self.context = context
        self.source = source
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = RemindersActions(
            complete: { [weak self] id in self?.send(.complete(id)) },
            undo: { [weak self] id in self?.send(.undo(id)) },
            openReminders: { Self.openRemindersApp() },
            openSettings: { [weak self] in self?.context.services.permissions?.openSystemSettings(for: .reminders) }
        )
        wake.action = { [weak self] in self?.send(.tick) }
        source.onChange = { [weak self] in self?.reload() }
        source.startObserving()
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in self?.reload() }
        observers.observe(.NSSystemClockDidChange) { [weak self] in self?.reload() }
        observers.observe(.NSSystemTimeZoneDidChange) { [weak self] in self?.reload() }
        observers.observe(.NSCalendarDayChanged) { [weak self] in self?.reload() }
        // Quitting inside an undo window must not lose the tick.
        observers.observe(NSApplication.willTerminateNotification) { [weak self] in self?.send(.quit) }

        let model = model
        context.services.today.set(TodaySection(
            id: Self.sectionID, moduleID: Self.descriptor.id, slot: .trailing,
            content: IslandRegion { RemindersSectionView(model: model) }
        ))
        send(.configure(settings.reducerConfig))
        if source.authorization == .notDetermined {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.source.requestAccess()
                self.reload()
            }
        } else {
            reload()
        }
    }

    func stop() {
        guard isRunning else { return }
        // Anything ticked and still undoable is saved: the user did tick it.
        send(.quit)
        isRunning = false
        fetchGeneration += 1
        wake.schedule(at: nil)
        source.stopObserving()
        source.onChange = nil
        observers.invalidate()
        context.services.today.remove(moduleID: Self.descriptor.id)
        context.activities.endAll()
        model.actions = RemindersActions()
        model.reset()
        reducer = RemindersReducer()
    }

    func settingsChanged() {
        send(.configure(settings.reducerConfig))
    }

    func availableLists() -> [ReminderListInfo] { source.lists() }

    // MARK: Events and effects

    func reload() {
        guard isRunning else { return }
        let authorization = source.authorization
        model.authorization = authorization
        send(.access(authorization == .granted))
        guard authorization == .granted else {
            send(.reminders([]))
            return
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let list = await self.source.incompleteReminders(dueBefore: end)
            guard self.isRunning, generation == self.fetchGeneration else { return }
            self.send(.reminders(list))
        }
    }

    func send(_ event: RemindersReducer.Event) {
        // `.quit` from stop() runs while still marked running.
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .itemsChanged(let items):
                model.items = items
            case .commit(let id):
                do { try source.complete(id: id) } catch {
                    log.error("Couldn't mark a reminder complete")
                    send(.commitFailed(id))
                }
            case .dueSoon(let reminder):
                context.activities.show(RemindersPresentation.banner(reminder))
            case .wake(let date):
                wake.schedule(at: date)
            }
        }
        model.hasLoaded = true
    }

    static func openRemindersApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: Model

@MainActor
struct RemindersActions {
    var complete: (String) -> Void = { _ in }
    var undo: (String) -> Void = { _ in }
    var openReminders: () -> Void = {}
    var openSettings: () -> Void = {}
}

@MainActor
@Observable
final class RemindersModel {
    var authorization: CalendarAuthorization = .notDetermined
    var items: [ReminderItem] = []
    var hasLoaded = false
    @ObservationIgnored var actions = RemindersActions()

    func reset() {
        authorization = .notDetermined
        items = []
        hasLoaded = false
    }
}

// MARK: Banner

@MainActor
enum RemindersPresentation {
    static let tint = Color.orange

    /// "Due in 15 min: Call Sam" (#50), once per reminder.
    static func banner(_ reminder: ReminderDueSoon) -> TransientBanner {
        let time = reminder.due.formatted(date: .omitted, time: .shortened)
        return TransientBanner(
            id: "reminders.\(reminder.id)",
            moduleID: RemindersModule.descriptor.id,
            leading: IslandRegion {
                Image(systemName: "checklist").font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
            },
            trailing: IslandRegion {
                Text(reminder.title)
                    .font(IslandFont.compact)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .trailing)
            },
            accessibilityLabel: "Reminder due at \(time): \(reminder.title)",
            openAction: { RemindersModule.openRemindersApp() }
        )
    }
}

// MARK: Today section

/// Reminders' column on the Today tab: overdue first, then today.
struct RemindersSectionView: View {
    let model: RemindersModel
    @Environment(\.todayRowLimit) private var rowLimit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Reminders")
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch model.authorization {
        case .granted:
            if model.items.isEmpty {
                Text(model.hasLoaded ? "Nothing due today" : "Loading…")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.items.prefix(rowLimit)) { item in
                    ReminderRow(item: item, model: model)
                }
                let more = model.items.count - rowLimit
                if more > 0 {
                    Button("\(more) more") { model.actions.openReminders() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        case .denied:
            Text("Reminders access is off.").font(IslandFont.subtitle).foregroundStyle(.secondary)
            Button("Open Settings") { model.actions.openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
        case .notDetermined:
            Text("Waiting for your answer…").font(IslandFont.subtitle).foregroundStyle(.secondary)
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let model: RemindersModel

    var body: some View {
        HStack(spacing: Spacing.s - 2) {
            Button {
                if item.isPendingComplete { model.actions.undo(item.id) } else { model.actions.complete(item.id) }
            } label: {
                Image(systemName: item.isPendingComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isPendingComplete ? Color.secondary : item.color.swiftUIColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPendingComplete ? "Undo completing \(item.title)" : "Complete \(item.title)")

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(item.isPendingComplete)
                    .foregroundStyle(item.isPendingComplete ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(item.isOverdue && !item.isPendingComplete ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.xs)
            if item.isPendingComplete {
                Button("Undo") { model.actions.undo(item.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String? {
        guard let due = item.due else { return nil }
        if item.isOverdue {
            return Calendar.current.isDateInToday(due) ? due.formatted(date: .omitted, time: .shortened) : "Overdue"
        }
        return item.hasTime ? due.formatted(date: .omitted, time: .shortened) : nil
    }
}

// MARK: Settings

struct RemindersSettingsPane: View {
    @Bindable var settings: RemindersSettings
    let registry: ModuleRegistry
    let permissions: PermissionCenter?

    private var module: RemindersModule? { registry.module(RemindersModule.descriptor.id) as? RemindersModule }

    var body: some View {
        Form {
            Section {
                if let permissions {
                    LabeledContent("Reminders access", value: permissions.status(.reminders).title)
                    if permissions.status(.reminders) != .granted {
                        Button("Open System Settings") { permissions.openSystemSettings(for: .reminders) }
                    }
                }
            } footer: {
                Text("Notched reads today's and overdue reminders and marks them complete when you tick them. Titles stay on this Mac and are never logged.")
            }

            Section {
                Toggle("Banner 15 minutes before a reminder is due", isOn: $settings.dueSoonBanner)
            } footer: {
                Text("Only for reminders with a time, once each. Ticking a box saves after 8 seconds, so you can undo it; quitting saves it straight away.")
            }

            let lists = module?.availableLists() ?? []
            if !lists.isEmpty {
                Section("Lists") {
                    ForEach(lists) { list in
                        Toggle(isOn: Binding(
                            get: { !settings.excludedLists.contains(list.id) },
                            set: { included in
                                settings.excludedLists.removeAll { $0 == list.id }
                                if !included { settings.excludedLists.append(list.id) }
                            }
                        )) {
                            Label { Text(list.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(list.color.swiftUIColor) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reminders")
        .onChange(of: settings.dueSoonBanner) { module?.settingsChanged() }
        .onChange(of: settings.excludedLists) { module?.settingsChanged() }
    }
}
