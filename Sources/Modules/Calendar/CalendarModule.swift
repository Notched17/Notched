// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Calendar (#48) with one-click Join (#49): a compact countdown to the next
/// event, an alert a minute before it starts, and an agenda for today and
/// tomorrow in the Today tab. A thin shell around `CalendarReducer`.
///
/// Event-driven: it reloads on `EKEventStoreChanged`, on wake, and at the
/// moments the reducer asks for (one timer). Without calendar access it asks
/// once when turned on, then shows how to allow it.
@MainActor
final class CalendarModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "calendar",
        name: "Calendar",
        symbol: "calendar",
        summary: "Counts down to your next event, shows today and tomorrow in the Today tab, and joins Zoom, Meet, Teams and Webex calls in one click.",
        permissions: [.calendars],
        isDebugOnly: false,
        isOnByDefault: false
    )
    static let activityID: ActivityID = "calendar.next"
    static let sectionID = "calendar"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(CalendarSettingsPane(settings: context.settings.calendar, registry: context.registry, permissions: context.permissions))
    }

    let model = CalendarModel()
    private let context: ModuleContext
    private let source: any CalendarEventSource
    private let wake = OneShotTimer()
    private let observers = NotificationTokens()
    private var reducer = CalendarReducer()
    private var isRunning = false
    private let log = Log.module("calendar")

    private var settings: CalendarSettings { context.settings.calendar }

    convenience init(context: ModuleContext) {
        self.init(context: context, source: EventStoreService())
    }

    init(context: ModuleContext, source: any CalendarEventSource) {
        self.context = context
        self.source = source
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = CalendarActions(
            join: { link in NSWorkspace.shared.open(link.url) },
            openCalendar: { Self.openCalendarApp() },
            openSettings: { [weak self] in self?.context.services.permissions?.openSystemSettings(for: .calendars) }
        )
        wake.action = { [weak self] in self?.send(.tick) }
        source.onChange = { [weak self] in self?.reload() }
        source.startObserving()
        // Sleep, the clock or time zone changing, and midnight can all move
        // the next event without EventKit saying so.
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in self?.reload() }
        observers.observe(.NSSystemClockDidChange) { [weak self] in self?.reload() }
        observers.observe(.NSSystemTimeZoneDidChange) { [weak self] in self?.reload() }
        observers.observe(.NSCalendarDayChanged) { [weak self] in self?.reload() }

        let model = model
        context.services.today.set(TodaySection(
            id: Self.sectionID, moduleID: Self.descriptor.id, slot: .leading,
            content: IslandRegion { CalendarSectionView(model: model) }
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
        isRunning = false
        wake.schedule(at: nil)
        source.stopObserving()
        source.onChange = nil
        observers.invalidate()
        context.services.today.remove(moduleID: Self.descriptor.id)
        context.activities.endAll()
        model.actions = CalendarActions()
        model.reset()
        reducer = CalendarReducer()
    }

    /// The settings pane changed the countdown, the alert or the calendars.
    func settingsChanged() {
        send(.configure(settings.reducerConfig))
    }

    /// The calendars to offer in the settings pane. Empty without access.
    func availableCalendars() -> [CalendarInfo] { source.calendars() }

    // MARK: Events and effects

    func reload() {
        guard isRunning else { return }
        let authorization = source.authorization
        model.authorization = authorization
        send(.access(authorization == .granted))
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard authorization == .granted, let end = calendar.date(byAdding: .day, value: 2, to: start) else {
            send(.events([]))
            return
        }
        send(.events(source.events(from: start, to: end)))
    }

    func send(_ event: CalendarReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .post(let info, let alert):
                context.activities.post(CalendarPresentation.activity(info), alert: alert ? AlertRequest() : nil)
            case .endCountdown:
                context.activities.end(Self.activityID, dismissal: .immediate)
            case .agendaChanged(let items):
                model.agenda = items
            case .wake(let date):
                wake.schedule(at: date)
            }
        }
        model.hasLoaded = true
    }

    private static func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: Model

@MainActor
struct CalendarActions {
    var join: (MeetingLink) -> Void = { _ in }
    var openCalendar: () -> Void = {}
    var openSettings: () -> Void = {}
}

@MainActor
@Observable
final class CalendarModel {
    var authorization: CalendarAuthorization = .notDetermined
    var agenda: [AgendaItem] = []
    var hasLoaded = false
    @ObservationIgnored var actions = CalendarActions()

    func reset() {
        authorization = .notDetermined
        agenda = []
        hasLoaded = false
    }
}

// MARK: Compact and expanded presentation

/// The next-event countdown (#48): `.live`, so it sits below whatever plays (ADR-0011).
@MainActor
enum CalendarPresentation {
    static func activity(_ info: CountdownInfo) -> LiveActivity {
        let tint = info.color.swiftUIColor
        let trailing = info.hasStarted ? "Now" : "\(info.minutesLeft)m"
        let spoken = info.hasStarted ? "\(info.title), started" : "\(info.title), starts in \(info.minutesLeft) \(info.minutesLeft == 1 ? "minute" : "minutes")"
        return LiveActivity(
            id: CalendarModule.activityID,
            moduleID: CalendarModule.descriptor.id,
            kind: .live,
            title: info.title,
            relevance: 30,
            keylineTint: tint,
            accessibilityLabel: spoken,
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                },
                compactTrailing: IslandRegion {
                    Text(trailing)
                        .font(IslandFont.compact)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                },
                minimal: IslandRegion {
                    if info.hasStarted {
                        Image(systemName: "calendar").font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                    } else {
                        Text("\(info.minutesLeft)").font(IslandFont.minimal).monospacedDigit().foregroundStyle(tint)
                    }
                },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile {
                            Image(systemName: "calendar").font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                        }
                        .padding(.top, 6)
                    },
                    trailing: ExpandedRegion {
                        Text(info.hasStarted ? "Now" : "in \(info.minutesLeft)m")
                            .font(IslandFont.hero)
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    },
                    bottom: ExpandedRegion {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(info.title).font(IslandFont.title).lineLimit(1)
                                Text(CalendarFormat.timeRange(start: info.start, end: info.end))
                                    .font(IslandFont.subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            if let join = info.join {
                                Button("Join \(join.service.rawValue)", systemImage: "video.fill") { NSWorkspace.shared.open(join.url) }
                                    .buttonStyle(.island(prominent: tint))
                                    .accessibilityHint("Opens the meeting")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            )
        )
    }
}

enum CalendarFormat {
    static func timeRange(start: Date, end: Date) -> String {
        "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: Today section

/// Calendar's column on the Today tab: today's remaining events, then tomorrow's.
struct CalendarSectionView: View {
    let model: CalendarModel
    @Environment(\.todayRowLimit) private var rowLimit

    private enum Row: Identifiable {
        case tomorrow
        case event(AgendaItem)

        var id: String {
            switch self {
            case .tomorrow: "tomorrow"
            case .event(let item): item.id
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Calendar")
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
            if model.agenda.isEmpty {
                note(model.hasLoaded ? "No more events today" : "Loading…")
            } else {
                let (rows, more) = visibleRows()
                ForEach(rows) { row in
                    switch row {
                    case .tomorrow:
                        Text("Tomorrow").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    case .event(let item):
                        AgendaRow(item: item, model: model)
                    }
                }
                if more > 0 {
                    Button("\(more) more") { model.actions.openCalendar() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        case .denied:
            note("Calendar access is off.")
            Button("Open Settings") { model.actions.openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
        case .notDetermined:
            note("Waiting for your answer…")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(IslandFont.subtitle).foregroundStyle(.secondary)
    }

    /// As many rows as fit, with a "Tomorrow" label where the day changes.
    private func visibleRows() -> (rows: [Row], more: Int) {
        var all: [Row] = []
        var sawTomorrow = false
        for item in model.agenda {
            if item.isTomorrow, !sawTomorrow { all.append(.tomorrow); sawTomorrow = true }
            all.append(.event(item))
        }
        var shown = Array(all.prefix(rowLimit))
        if case .tomorrow? = shown.last { shown.removeLast() }
        let shownEvents = shown.filter { if case .event = $0 { true } else { false } }.count
        return (shown, model.agenda.count - shownEvents)
    }
}

private struct AgendaRow: View {
    let item: AgendaItem
    let model: CalendarModel

    var body: some View {
        HStack(spacing: Spacing.s - 2) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(item.color.swiftUIColor)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(timeText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            if let join = item.join {
                Button { model.actions.join(join) } label: {
                    Text("Join")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.color.prefersDarkText ? Color.black : Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(item.color.swiftUIColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(join.service.rawValue) meeting")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        if item.isAllDay { return "All day" }
        let start = item.start.formatted(date: .omitted, time: .shortened)
        return item.isInProgress ? "\(start) · Now" : start
    }
}

// MARK: Settings

struct CalendarSettingsPane: View {
    @Bindable var settings: CalendarSettings
    let registry: ModuleRegistry
    let permissions: PermissionCenter?

    private var module: CalendarModule? { registry.module(CalendarModule.descriptor.id) as? CalendarModule }

    var body: some View {
        Form {
            Section {
                if let permissions {
                    LabeledContent("Calendar access", value: permissions.status(.calendars).title)
                    if permissions.status(.calendars) != .granted {
                        Button("Open System Settings") { permissions.openSystemSettings(for: .calendars) }
                    }
                }
            } footer: {
                Text("Notched reads your events to count down and list them. Titles, places and notes stay on this Mac and are never logged.")
            }

            Section {
                Picker("Show the countdown", selection: $settings.countdownMinutes) {
                    ForEach(CalendarSettings.countdownChoices, id: \.self) { Text("\($0) minutes before").tag($0) }
                }
                Toggle("Expand the island a minute before", isOn: $settings.alertBeforeStart)
            } footer: {
                Text("All-day events are listed but never start a countdown. Declined and cancelled events are hidden.")
            }

            let calendars = module?.availableCalendars() ?? []
            if !calendars.isEmpty {
                Section("Calendars") {
                    ForEach(calendars) { calendar in
                        Toggle(isOn: Binding(
                            get: { !settings.excludedCalendars.contains(calendar.id) },
                            set: { included in
                                settings.excludedCalendars.removeAll { $0 == calendar.id }
                                if !included { settings.excludedCalendars.append(calendar.id) }
                            }
                        )) {
                            Label { Text(calendar.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(calendar.color.swiftUIColor) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
        .onChange(of: settings.countdownMinutes) { module?.settingsChanged() }
        .onChange(of: settings.alertBeforeStart) { module?.settingsChanged() }
        .onChange(of: settings.excludedCalendars) { module?.settingsChanged() }
    }
}
