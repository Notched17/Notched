// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Decides what the island shows when several live activities run at once,
/// the way the iPhone Dynamic Island does (ADR-0006, ISLAND-BEHAVIOR.md §1–§2).
/// Pure and clock-injected, so every rule is unit-tested:
///
/// - **Ranking:** system first, then the user's pinned modules, then the user's
///   class order (default media > live > passive, ADR-0011/0016), then relevance,
///   then start order, so a newcomer never steals the island from an equal.
/// - **Primary and minimal:** the top visible activity owns both compact
///   sides; the next two show as minimal bubbles (trailing, then leading).
///   Any more are only listed in the expanded view.
/// - **User overrides:** a swap (make primary, or cycle) is sticky until
///   either swapped activity ends or a new system activity arrives. Hiding
///   keeps an activity running and listed; non-hideable activities ignore it.
/// - **Lifecycle:** past its stale date an activity turns stale; ending one
///   takes it off the island at once and lists it under Recent until its
///   dismissal date.
/// - **Alerts** expand the island for their activity, one at a time, and wait
///   while the user is on the island. **Banners** pre-empt the compact island
///   briefly. They queue (by priority, one per id) while an alert shows, the
///   island is expanded, or another banner is up; an alert cuts a banner
///   short (ADR-0012).
///
/// Every time-based change has a deadline; the coordinator reports the next
/// one through `scheduleWake` and the app calls `advance(to:)` then. No polling.
@MainActor
@Observable
final class ActivityCoordinator {
    struct Configuration: Equatable, Sendable {
        var alertExpansionEnabled = true
        var alertDuration: Duration = .seconds(4)
        var bannerDuration: Duration = .seconds(2)
        var recentRetention: Duration = .seconds(15 * 60)
        /// The user's priority: class order and pinned modules (#8).
        var ranking = RankingPolicy.default

        /// At most this many activities show on the island at once.
        static let maxVisible = 3
        /// Ended activities never stay in Recent longer than this (as on iPhone).
        static let maxRetention: Duration = .seconds(4 * 60 * 60)
    }

    /// The alert expansion on screen.
    struct ActiveAlert: Equatable, Sendable {
        let activityID: ActivityID
        let endsAt: Date
        let sound: String?
        /// Increments for every alert shown, so the island reacts once per alert.
        let serial: Int
    }

    /// Changing it re-ranks at once; setting an equal value does nothing, since
    /// the app reassigns it on every settings change.
    var configuration: Configuration {
        didSet {
            guard configuration != oldValue else { return }
            refresh(at: now())
        }
    }

    /// Every activity that hasn't ended, best first, with the user's swap
    /// applied. Hidden activities are included.
    private(set) var live: [ActivityRecord] = []
    /// The activity attached to the island, owning both compact sides.
    private(set) var primary: ActivityRecord?
    /// Detached bubbles: the trailing one first, then the leading one.
    private(set) var minimal: [ActivityRecord] = []
    /// Ended activities, newest first, until their dismissal date.
    private(set) var recent: [ActivityRecord] = []
    private(set) var alert: ActiveAlert?
    private(set) var banner: TransientBanner?
    /// Quick actions modules offer on Home, grouped by module in catalogue order.
    private(set) var homeActions: [HomeAction] = []
    /// The module catalogue's order (set by `ModuleHost`), so Home's row
    /// doesn't depend on which module happened to start first.
    @ObservationIgnored var moduleOrder: [ModuleID] = []
    /// Increments for each banner shown, and for alerts while alert expansion
    /// is off, so the island bounces once each.
    private(set) var bounceSerial = 0

    var visible: [ActivityRecord] { live.filter { !$0.isHidden } }
    var hidden: [ActivityRecord] { live.filter(\.isHidden) }
    /// Visible activities that don't fit on the island; listed in the expanded view.
    var listedOnly: [ActivityRecord] {
        let shown = Set(([primary].compactMap { $0 } + minimal).map(\.id))
        return visible.filter { !shown.contains($0.id) }
    }

    /// True while the pointer is on an island or the user has it expanded.
    /// Alerts and banners wait so they never interrupt the user.
    var isInteracting = false {
        didSet {
            guard isInteracting != oldValue, !isInteracting else { return }
            showWaitingAlertOrBanner(at: now())
            refresh(at: now())
        }
    }

    var nextDeadline: Date? {
        var deadlines: [Date] = []
        if let alert { deadlines.append(alert.endsAt) }
        if let bannerEndsAt { deadlines.append(bannerEndsAt) }
        for record in entries.values where record.state == .active {
            if let staleDate = record.activity.staleDate { deadlines.append(staleDate) }
        }
        for record in recent {
            if case .ended(let dismissAt) = record.state { deadlines.append(dismissAt) }
        }
        return deadlines.min()
    }

    private struct Swap {
        let promoted: ActivityID
        let demoted: ActivityID?
    }

    private struct QueuedAlert {
        let activityID: ActivityID
        let duration: Duration
        let sound: String?
    }

    @ObservationIgnored private var entries: [ActivityID: ActivityRecord] = [:]
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var swap: Swap?
    @ObservationIgnored private var alertQueue: [QueuedAlert] = []
    @ObservationIgnored private var alertSerial = 0
    @ObservationIgnored private var bannerEndsAt: Date?
    @ObservationIgnored private var waitingBanners = BannerQueue<TransientBanner>()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let scheduleWake: @MainActor (Date?) -> Void

    /// - Parameters:
    ///   - now: the clock (injected in tests).
    ///   - scheduleWake: told the next deadline after every change, so the app
    ///     can call `advance(to:)` then. No polling.
    init(configuration: Configuration = Configuration(), now: @escaping () -> Date = Date.init,
         scheduleWake: @escaping @MainActor (Date?) -> Void = { _ in }) {
        self.configuration = configuration
        self.now = now
        self.scheduleWake = scheduleWake
    }

    // MARK: Modules

    /// Adds an activity, or updates the one with the same id in place. A new
    /// system activity alerts unless it's an update.
    func post(_ activity: LiveActivity, alert request: AlertRequest? = nil) {
        let date = now()
        var request = request
        if var record = entries[activity.id] {
            record.activity = activity
            record.revision += 1
            // An activity that has become non-hideable (the camera turned on
            // under a hidden mic indicator) comes back.
            if !activity.isHideable { record.isHidden = false }
            entries[activity.id] = record
        } else {
            sequence += 1
            entries[activity.id] = ActivityRecord(activity: activity, sequence: sequence)
            recent.removeAll { $0.id == activity.id }
            if activity.kind == .system {
                swap = nil
                request = request ?? AlertRequest()
            }
        }
        if let request { enqueueAlert(for: activity.id, request, at: date) }
        refresh(at: date)
    }

    /// Takes an activity off the island at once. It stays under Recent until
    /// its dismissal date.
    func end(_ id: ActivityID, dismissal: DismissalPolicy = .default) {
        guard var record = entries.removeValue(forKey: id) else { return }
        let date = now()
        forget(id, at: date)
        if let dismissAt = dismissalDate(dismissal, from: date) {
            record.state = .ended(dismissAt: dismissAt)
            record.isHidden = false
            recent.insert(record, at: 0)
        }
        refresh(at: date)
    }

    /// Removes everything a module shows, without Recent entries (the module
    /// was turned off).
    func endAll(from module: ModuleID) {
        let date = now()
        for (id, record) in entries where record.activity.moduleID == module {
            entries[id] = nil
            forget(id, at: date)
        }
        recent.removeAll { $0.activity.moduleID == module }
        if banner?.moduleID == module {
            banner = nil
            bannerEndsAt = nil
        }
        waitingBanners.removeAll { _, banner in banner.moduleID == module }
        if homeActions.contains(where: { $0.moduleID == module }) { setHomeActions([], from: module) }
        showWaitingAlertOrBanner(at: date)
        refresh(at: date)
    }

    /// Replaces a module's Home quick actions; the row is in catalogue order.
    func setHomeActions(_ actions: [HomeAction], from module: ModuleID) {
        let rank = { (id: ModuleID) in self.moduleOrder.firstIndex(of: id) ?? Int.max }
        let next = homeActions.filter { $0.moduleID != module } + actions.filter { $0.moduleID == module }
        // A stable sort keeps each module's own actions in the order it gave them.
        homeActions = next.enumerated()
            .sorted { (rank($0.element.moduleID), $0.offset) < (rank($1.element.moduleID), $1.offset) }
            .map(\.element)
    }

    /// Shows a transient banner, or queues it while an alert shows, the
    /// island is expanded, or an equally important banner is up.
    func show(_ newBanner: TransientBanner) {
        let date = now()
        if banner?.id == newBanner.id {
            // The same event again (another volume press): restart, no new bounce.
            banner = newBanner
            bannerEndsAt = date.addingTimeInterval(bannerDuration(newBanner))
        } else if alert != nil || isInteracting || (banner.map { newBanner.priority <= $0.priority } ?? false) {
            waitingBanners.enqueue(id: newBanner.id, priority: newBanner.priority, payload: newBanner, at: date)
        } else {
            // Nothing showing, or this one matters more than the one up.
            present(newBanner, at: date)
        }
        refresh(at: date)
    }

    /// Takes the banner off the island at once (the user clicked it) and lets
    /// a waiting one follow.
    func dismissBanner(_ id: String) {
        guard banner?.id == id else { return }
        banner = nil
        bannerEndsAt = nil
        let date = now()
        showWaitingAlertOrBanner(at: date)
        refresh(at: date)
    }

    // MARK: User

    /// Makes an activity the primary one until either it or the activity it
    /// displaced ends, or a new system activity arrives.
    func makePrimary(_ id: ActivityID) {
        guard let target = entries[id], !target.isHidden else { return }
        if naturalVisibleOrder().first?.id == id {
            swap = nil
        } else {
            swap = Swap(promoted: id, demoted: primary?.id)
        }
        refresh(at: now())
    }

    /// Moves the primary slot to the next (or previous) visible activity in rank order.
    func cyclePrimary(forward: Bool) {
        let order = naturalVisibleOrder()
        guard order.count > 1, let current = primary,
              let index = order.firstIndex(where: { $0.id == current.id }) else { return }
        let next = (index + (forward ? 1 : -1) + order.count) % order.count
        makePrimary(order[next].id)
    }

    /// Takes an activity off the island without ending it.
    func hide(_ id: ActivityID) {
        guard var record = entries[id], record.activity.isHideable, !record.isHidden else { return }
        record.isHidden = true
        entries[id] = record
        if swap?.promoted == id { swap = nil }
        refresh(at: now())
    }

    func unhide(_ id: ActivityID) {
        guard var record = entries[id], record.isHidden else { return }
        record.isHidden = false
        entries[id] = record
        refresh(at: now())
    }

    func dismissRecent(_ id: ActivityID) {
        recent.removeAll { $0.id == id }
        refresh(at: now())
    }

    // MARK: Island

    /// The pointer arrived during an alert expansion: the island stays
    /// expanded as a normal hover, and the alert is done.
    func userTookOverAlert() {
        guard alert != nil else { return }
        alert = nil
        let date = now()
        showWaitingAlertOrBanner(at: date)
        refresh(at: date)
    }

    /// Applies everything that fell due by `date`.
    func advance(to date: Date) {
        if let alert, alert.endsAt <= date { self.alert = nil }
        if let bannerEndsAt, bannerEndsAt <= date {
            banner = nil
            self.bannerEndsAt = nil
        }
        recent.removeAll { record in
            if case .ended(let dismissAt) = record.state { return dismissAt <= date }
            return false
        }
        // The next alert, or a banner queued behind the one that just ended.
        showWaitingAlertOrBanner(at: date)
        refresh(at: date)
    }

    // MARK: Internals

    private func enqueueAlert(for id: ActivityID, _ request: AlertRequest, at date: Date) {
        guard configuration.alertExpansionEnabled else {
            bounceSerial += 1
            return
        }
        let queued = QueuedAlert(activityID: id, duration: request.duration ?? configuration.alertDuration, sound: request.sound)
        if alert?.activityID == id {
            // Alerting again while it shows: restart it.
            alertSerial += 1
            alert = ActiveAlert(activityID: id, endsAt: date.addingTimeInterval(queued.duration.timeInterval),
                                sound: queued.sound, serial: alertSerial)
        } else if let index = alertQueue.firstIndex(where: { $0.activityID == id }) {
            alertQueue[index] = queued
        } else {
            alertQueue.append(queued)
        }
        showWaitingAlertOrBanner(at: date)
    }

    /// Starts the next queued alert, or else the next waiting banner, if the
    /// island is free. An alert cuts a banner short: on iPhone an expanding
    /// activity takes the whole island, and the banner is old news after it.
    private func showWaitingAlertOrBanner(at date: Date) {
        guard alert == nil, !isInteracting else { return }
        while !alertQueue.isEmpty {
            let next = alertQueue.removeFirst()
            guard entries[next.activityID] != nil else { continue }
            alertSerial += 1
            alert = ActiveAlert(activityID: next.activityID, endsAt: date.addingTimeInterval(next.duration.timeInterval),
                                sound: next.sound, serial: alertSerial)
            banner = nil
            bannerEndsAt = nil
            return
        }
        guard banner == nil, let next = waitingBanners.next(at: date) else { return }
        present(next.payload, at: date)
    }

    private func present(_ newBanner: TransientBanner, at date: Date) {
        banner = newBanner
        bannerEndsAt = date.addingTimeInterval(bannerDuration(newBanner))
        bounceSerial += 1
    }

    private func bannerDuration(_ banner: TransientBanner) -> TimeInterval {
        (banner.duration ?? configuration.bannerDuration).timeInterval
    }

    /// Drops an ended activity's swap and alerts.
    private func forget(_ id: ActivityID, at date: Date) {
        if let swap, swap.promoted == id || swap.demoted == id { self.swap = nil }
        alertQueue.removeAll { $0.activityID == id }
        if alert?.activityID == id {
            alert = nil
            showWaitingAlertOrBanner(at: date)
        }
    }

    private func dismissalDate(_ policy: DismissalPolicy, from date: Date) -> Date? {
        let latest = date.addingTimeInterval(Configuration.maxRetention.timeInterval)
        let dismissAt: Date = switch policy {
        case .default: min(date.addingTimeInterval(configuration.recentRetention.timeInterval), latest)
        case .immediate: date
        case .after(let requested): min(requested, latest)
        }
        return dismissAt > date ? dismissAt : nil
    }

    /// Visible activities by class, relevance and start order, ignoring the swap.
    private func naturalVisibleOrder() -> [ActivityRecord] {
        entries.values.filter { !$0.isHidden }.sorted { ranksHigher($0, $1) }
    }

    private func ranksHigher(_ lhs: ActivityRecord, _ rhs: ActivityRecord) -> Bool {
        let left = configuration.ranking.key(kind: lhs.activity.kind, module: lhs.activity.moduleID)
        let right = configuration.ranking.key(kind: rhs.activity.kind, module: rhs.activity.moduleID)
        if left != right { return left < right }
        if lhs.activity.relevance != rhs.activity.relevance { return lhs.activity.relevance > rhs.activity.relevance }
        return lhs.sequence < rhs.sequence
    }

    /// The activities that get the island's visible slots, in rank order.
    /// A non-hideable activity (a call, the camera indicator) always gets a
    /// slot, ahead of better-ranked hideable ones, so the user never loses
    /// sight of it; an explicit swap target also keeps its slot. Hideable
    /// activities fill what's left in rank order.
    private static func shownSlots(from visible: [ActivityRecord], promoted: ActivityID?) -> [ActivityRecord] {
        let pinned = visible.filter { $0.id == promoted }
            + visible.filter { !$0.activity.isHideable && $0.id != promoted }
        var chosen = Set(pinned.prefix(Configuration.maxVisible).map(\.id))
        for record in visible where chosen.count < Configuration.maxVisible { chosen.insert(record.id) }
        return visible.filter { chosen.contains($0.id) }
    }

    /// Recomputes stale states and the island's arrangement, then reports the
    /// next deadline.
    private func refresh(at date: Date) {
        for (id, var record) in entries {
            let state: ActivityState = record.activity.staleDate.map { $0 <= date } == true ? .stale : .active
            if record.state != state {
                record.state = state
                entries[id] = record
            }
        }
        var ranked = entries.values.sorted { ranksHigher($0, $1) }
        if let swap, let index = ranked.firstIndex(where: { $0.id == swap.promoted && !$0.isHidden }) {
            ranked.insert(ranked.remove(at: index), at: 0)
        }
        live = ranked
        let shown = Self.shownSlots(from: ranked.filter { !$0.isHidden }, promoted: swap?.promoted)
        primary = shown.first
        minimal = Array(shown.dropFirst())
        scheduleWake(nextDeadline)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
