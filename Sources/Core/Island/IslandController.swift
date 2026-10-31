// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Owns the panels and model for the island on one display, and turns pointer
/// events into one continuous compact ↔ expanded morph.
///
/// Click-through (ADR-0002, ADR-0007): the island panel has a fixed size and
/// never resizes during interaction, so the morph can't glitch. While compact
/// it ignores the mouse completely, and invisible sensor windows, exactly the
/// size of the compact island and of each minimal bubble, detect hover,
/// clicks, right-clicks and swipes. Everything around and between them stays
/// clickable. While expanded the island panel takes the mouse and detects the
/// pointer leaving.
@MainActor
final class IslandController {
    let displayID: DisplayID
    let model: IslandViewModel
    var behavior: IslandBehavior
    /// Told when the user starts or stops interacting with this island, so
    /// alerts and banners can wait (`ActivityCoordinator.isInteracting`).
    var onInteractionChange: () -> Void = {}

    private let panel: IslandPanel
    private let hostingView: IslandHostingView
    /// The island's sensor first, then one per minimal bubble.
    private var sensors: [IslandSensorPanel] = []
    private var hover = HoverStateMachine()
    private var hoverTimer: Task<Void, Never>?
    /// Identifies the latest presentation change, so a superseded animation's
    /// completion can't switch mouse handling under a newer one.
    private var transitionID = 0
    private var isHidden = false
    /// When the pointer last entered the compact island, to recognise bounces.
    private var enteredAt: ContinuousClock.Instant?
    /// The compact region the pointer is on (or last clicked).
    private var target: IslandViewModel.IslandTarget = .island
    private var compactSwipe = SwipeRecognizer()
    private var expandedSwipe = SwipeRecognizer()
    private var lastAlertSerial: Int?

    var isInteracting: Bool { hover.isInteracting }
    private var activities: ActivityCoordinator { model.activities }

    init(displayID: DisplayID, geometry: NotchGeometry, behavior: IslandBehavior,
         accessibility: AccessibilityOptions, activities: ActivityCoordinator, actions: IslandActions) {
        self.displayID = displayID
        self.behavior = behavior
        model = IslandViewModel(geometry: geometry, accessibility: accessibility, activities: activities)
        let frame = model.panelFrame
        panel = IslandPanel(contentRect: frame)
        hostingView = IslandHostingView(rootView: IslandRootView(model: model))
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        model.actions = IslandActions(
            openSettings: { [weak self] in
                self?.send(.forceCollapse)
                actions.openSettings()
            },
            pauseIsland: { [weak self] in
                self?.send(.forceCollapse)
                actions.pauseIsland()
            }
        )
        model.onSurfaceTap = { [weak self] in self?.send(.clicked) }
        hostingView.onPointer = { [weak self] event in self?.islandPointer(event) }
        hostingView.onMouseDown = { [weak self] in self?.takeKeyFocus() }
        hostingView.onScroll = { [weak self] sample in self?.expandedScroll(sample) }
        panel.onCancel = { [weak self] in self?.send(.forceCollapse) }
        panel.onKeyCommand = { [weak self] command in
            guard let self else { return false }
            let reduceMotion = model.accessibility.reduceMotion
            let handled = withAnimation(reduceMotion ? Motion.reduced : Motion.content) { model.handle(command) }
            if handled { feedback(.alignment) }
            return handled
        }
        model.onTabChanged = { [weak self] in self?.feedback(.alignment) }

        layoutWindows()
        observeLayout()
        observeAlerts()
        panel.orderFrontRegardless()
        Log.island.info("Island on \(displayID, privacy: .public): \(String(describing: geometry.kind), privacy: .public) panel \(NSStringFromRect(frame), privacy: .public)")
    }

    // MARK: Lifecycle

    func update(geometry: NotchGeometry, appearance: IslandAppearance) {
        let theme = appearance.theme(for: geometry.kind)
        if model.theme != theme { model.theme = theme }
        if model.multipleActivityMode != appearance.multipleActivities { model.multipleActivityMode = appearance.multipleActivities }
        if model.keylineEnabled != appearance.keyline { model.keylineEnabled = appearance.keyline }
        guard geometry != model.geometry || appearance.expandedScale != model.expandedScale else { return }
        model.geometry = geometry
        model.expandedScale = appearance.expandedScale
        layoutWindows()
        Log.island.info("Island on \(self.displayID, privacy: .public) moved to \(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            send(.forceCollapse)
            panel.orderOut(nil)
            for sensor in sensors { sensor.orderOut(nil) }
        } else {
            layoutWindows()
            panel.orderFrontRegardless()
        }
    }

    func setHiddenFromCapture(_ hidden: Bool) {
        panel.hiddenFromCapture = hidden
    }

    func tearDown() {
        hoverTimer?.cancel()
        for window in [panel] + sensors as [NSWindow] {
            window.orderOut(nil)
            window.close()
        }
    }

    // MARK: Interaction

    /// Expands to the primary activity (or Home), e.g. from a debug command.
    func expand() {
        model.selectPage(for: .island)
        send(.forceExpand)
    }

    /// Expands to a given page, e.g. from a debug command or the context menu.
    func expand(to page: IslandViewModel.ExpandedPage) {
        model.selectedPage = page
        send(.forceExpand)
    }

    /// The frame of the display this island is on.
    var screenFrame: CGRect? { panel.screen?.frame }

    /// Expands onto a module tab (a hotkey, the status menu). With `focus`,
    /// takes keyboard focus once the island is open, so its search field works.
    func expand(toTab id: String, focus: Bool) {
        model.selectedPage = .home
        send(.forceExpand)
        model.selectTab(id)
        if focus {
            // The state machine has moved on by the next turn of the run loop.
            DispatchQueue.main.async { [weak self] in self?.takeKeyFocus() }
        }
    }

    func collapse() { send(.forceCollapse) }

    /// Events from the sensors only matter while the island is compact.
    private func sensorEvent(_ event: IslandSensorPanel.Event, sensor index: Int) {
        guard hover.state == .compact || hover.state == .pendingExpand else { return }
        let regionTarget = model.compactTargets.indices.contains(index) ? model.compactTargets[index].target : .island
        switch event {
        case .entered:
            target = regionTarget
            enteredAt = .now
            send(.pointerEntered)
        case .exited(let location):
            compactPointerLeft(at: location)
        case .clicked:
            target = regionTarget
            send(.clicked)
        case .rightClicked:
            target = regionTarget
            showContextMenu(for: regionTarget)
        case .scrolled(let sample):
            if let gesture = compactSwipe.handle(sample) { compactSwipe(gesture, on: regionTarget) }
        }
    }

    /// Mouse-moved events from the top-edge watcher (see `IslandManager`).
    /// AppKit tracking areas never report a pointer that lands exactly on the
    /// screen's top row, which is where a pointer thrown at the notch ends up.
    func pointerMoved(to location: CGPoint) {
        // A paused or fullscreen-hidden island must not wake (or buzz) when the
        // pointer goes to the top of the screen, e.g. to reveal the menu bar.
        guard !isHidden else { return }
        switch hover.state {
        case .compact:
            guard model.isOnNotchTopEdge(location), let regionTarget = model.compactTarget(at: location) else { return }
            Log.island.debug("pointer reached the notch's top edge at \(NSStringFromPoint(location), privacy: .public)")
            target = regionTarget
            enteredAt = .now
            send(.pointerEntered)
        case .pendingExpand:
            // The tracking area may never have seen this pointer, so it won't
            // report it leaving either.
            if let regionTarget = model.compactTarget(at: location) {
                target = regionTarget
                return
            }
            compactPointerLeft(at: location)
        case .expanded, .pendingCollapse, .alerting:
            return
        }
    }

    private func compactPointerLeft(at location: CGPoint) {
        if hover.state == .pendingExpand, let enteredAt,
           model.isSystemBounce(exitAt: location, after: .now - enteredAt) {
            // macOS pushed a thrown pointer out from behind the camera:
            // the user meant to hover, so let the pending expand go ahead.
            Log.island.debug("pointer bounced out of the notch to \(NSStringFromPoint(location), privacy: .public); still expanding")
            return
        }
        pointerExited(at: location, from: .compact)
    }

    /// Events from the island panel only matter while it is expanded.
    private func islandPointer(_ event: IslandHostingView.PointerEvent) {
        Log.island.debug("island \(String(describing: event), privacy: .public) at \(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)")
        guard [.expanded, .pendingCollapse, .alerting].contains(hover.state) else { return }
        switch event {
        case .entered: send(.pointerEntered)
        case .exited(let location): pointerExited(at: location, from: .expanded)
        }
    }

    /// Ignores false exits: a pointer pinned to the top row of the screen is
    /// reported as outside even though it's on the island. Moving from the
    /// island onto one of its bubbles isn't leaving either.
    private func pointerExited(at location: CGPoint, from presentation: IslandPresentation) {
        if model.containsPointer(location, for: presentation) {
            if presentation == .compact, let regionTarget = model.compactTarget(at: location) { target = regionTarget }
            Log.island.debug("ignored false exit at \(NSStringFromPoint(location), privacy: .public)")
            return
        }
        send(.pointerExited)
    }

    private func send(_ event: HoverStateMachine.Event) {
        let before = hover.state
        let wasInteracting = hover.isInteracting
        let effects = hover.handle(event, hoverEnabled: behavior.expandOnHover, hoverDelay: behavior.hoverDelay,
                                   clickExpands: behavior.clickExpands)
        Log.island.debug("hover \(String(describing: event), privacy: .public): \(String(describing: before), privacy: .public) → \(String(describing: self.hover.state), privacy: .public)")
        for effect in effects { perform(effect) }
        if hover.isInteracting != wasInteracting { onInteractionChange() }
    }

    private func perform(_ effect: HoverStateMachine.Effect) {
        switch effect {
        case .scheduleExpand(let delay):
            schedule(.expandDelayElapsed, after: delay)
        case .scheduleCollapse(let delay):
            schedule(.collapseGraceElapsed, after: delay)
        case .cancelTimers:
            hoverTimer?.cancel()
            hoverTimer = nil
        case .expand(let reason):
            if reason == .hover || reason == .click { model.selectPage(for: target) }
            if reason == .hover && behavior.hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            present(.expanded)
            // A hover expand can follow a bounce, after which the pointer may
            // already have moved away; if it isn't on the island, collapse.
            let location = NSEvent.mouseLocation
            if reason == .hover, !model.containsPointer(location, for: .expanded) {
                Log.island.debug("pointer not on the expanded island at \(NSStringFromPoint(location), privacy: .public); collapsing")
                send(.pointerExited)
            }
        case .collapse:
            present(.compact)
        case .activate:
            activate(target)
        case .userTookOverAlert:
            // Keep showing the alerting activity; the hover is the user's now.
            if let alert = activities.alert { model.selectedPage = .activity(alert.activityID) }
            activities.userTookOverAlert()
        }
    }

    private func schedule(_ event: HoverStateMachine.Event, after delay: Duration) {
        hoverTimer?.cancel()
        hoverTimer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.send(event)
        }
    }

    // MARK: Click, swipe, context menu

    /// Click to Open (ISLAND-BEHAVIOR.md §6): the island opens the primary
    /// activity (or expands it if it has nothing to open); a bubble becomes primary.
    private func activate(_ target: IslandViewModel.IslandTarget) {
        switch target {
        case .island:
            if let banner = activities.banner {
                // A click on a banner does what the banner says, if it says anything.
                guard let open = banner.openAction else { return }
                feedback(.generic)
                open()
                activities.dismissBanner(banner.id)
                return
            }
            guard let primary = activities.primary else { return }
            if let open = primary.activity.openAction {
                feedback(.generic)
                open()
            } else {
                expand(to: .activity(primary.id))
            }
        case .bubble(let id):
            feedback(.alignment)
            activities.makePrimary(id)
        }
    }

    /// Two-finger swipes on the compact island: sideways cycles the primary
    /// activity, up hides the activity under the pointer.
    private func compactSwipe(_ gesture: SwipeRecognizer.Gesture, on target: IslandViewModel.IslandTarget) {
        switch gesture {
        case .left: activities.cyclePrimary(forward: true)
        case .right: activities.cyclePrimary(forward: false)
        case .up:
            guard let id = activityID(for: target) else { return }
            activities.hide(id)
        case .down: return
        }
        feedback(.alignment)
    }

    /// Two-finger swipes on the expanded island page between activities and Home.
    private func expandedScroll(_ sample: SwipeRecognizer.Sample) {
        guard hover.state == .expanded || hover.state == .pendingCollapse,
              let gesture = expandedSwipe.handle(sample) else { return }
        let offset: Int = switch gesture {
        case .left: 1
        case .right: -1
        case .up, .down: 0
        }
        guard offset != 0 else { return }
        var moved = false
        withAnimation(model.accessibility.reduceMotion ? Motion.reduced : Motion.content) {
            moved = model.page(by: offset)
        }
        if moved { feedback(.alignment) }
    }

    private func showContextMenu(for target: IslandViewModel.IslandTarget) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let id = activityID(for: target), let record = activities.live.first(where: { $0.id == id }) {
            let hide = ClosureMenuItem(title: "Hide") { [weak self] in self?.activities.hide(id) }
            hide.isEnabled = record.activity.isHideable
            menu.addItem(hide)
            if case .bubble = target {
                menu.addItem(ClosureMenuItem(title: "Make Primary") { [weak self] in self?.activities.makePrimary(id) })
            }
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: "Show All Activities") { [weak self] in self?.expand(to: .home) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func activityID(for target: IslandViewModel.IslandTarget) -> ActivityID? {
        switch target {
        case .island: activities.banner == nil ? activities.primary?.id : nil
        case .bubble(let id): id
        }
    }

    private func feedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard behavior.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: Keyboard focus (Esc)

    /// After a click inside the expanded island, take keyboard focus so Esc
    /// can collapse it. The panel doesn't activate the app, so the user's app
    /// stays frontmost.
    private func takeKeyFocus() {
        guard model.presentation == .expanded, !panel.isKeyWindow else { return }
        panel.allowsKey = true
        panel.makeKey()
    }

    /// Hand keyboard focus back to the app the user was in.
    private func giveBackKeyFocus() {
        guard panel.allowsKey else { return }
        panel.allowsKey = false
        if panel.isKeyWindow {
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    // MARK: Alerts

    /// Alert expansions come from the coordinator; the state machine decides
    /// whether this island can show them (never over a user's own hover).
    private func observeAlerts() {
        withObservationTracking {
            _ = activities.alert
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.alertChanged()
                self?.observeAlerts()
            }
        }
    }

    private func alertChanged() {
        if let alert = activities.alert {
            guard alert.serial != lastAlertSerial else { return }
            lastAlertSerial = alert.serial
            guard !isHidden else { return }
            send(.alertBegan)
        } else {
            send(.alertEnded)
        }
    }

    // MARK: Morph

    private func present(_ target: IslandPresentation) {
        guard model.presentation != target else { return }
        transitionID += 1
        let id = transitionID

        if target == .expanded {
            // Take the mouse now, so the expanded content is clickable at once.
            updateMouseHandling(expanded: true)
        } else {
            giveBackKeyFocus()
        }
        withAnimation(animation(for: target), completionCriteria: .removed) {
            model.presentation = target
        } completion: { [weak self] in
            guard let self, self.transitionID == id, self.model.presentation == .compact else { return }
            // Fully collapsed: let clicks through again and hand hover back to the sensors.
            self.updateMouseHandling(expanded: false)
        }
    }

    private func animation(for target: IslandPresentation) -> Animation {
        if model.accessibility.reduceMotion { return Motion.reduced }
        return target == .expanded ? behavior.animationStyle.expand : behavior.animationStyle.collapse
    }

    private func updateMouseHandling(expanded: Bool) {
        panel.ignoresMouseEvents = !expanded
        if expanded {
            let zone = model.hotZone(for: .expanded)
            hostingView.trackingRectInWindow = zone.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            hostingView.resetTracking()
        } else {
            for sensor in sensors { sensor.resetTracking() }
        }
    }

    /// The compact island and its bubbles grow, shrink and move with the
    /// activities, and the expanded island with its content; keep the sensors,
    /// the expanded tracking area (and, rarely, the panel) fitted to them.
    private func observeLayout() {
        withObservationTracking {
            _ = model.compactTargets.map(\.zone)
            _ = model.islandRect(for: .expanded)
            _ = model.panelFrame
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.layoutWindows()
                self?.observeLayout()
            }
        }
    }

    /// Sizes the island panel (only when geometry or sizes change, never during
    /// the morph) and fits one sensor to each compact region.
    private func layoutWindows() {
        let frame = model.panelFrame
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        let zones = [model.sensorFrame] + model.bubbleSensorFrames
        while sensors.count < zones.count {
            let index = sensors.count
            let sensor = IslandSensorPanel(contentRect: zones[index])
            sensor.onEvent = { [weak self] event in self?.sensorEvent(event, sensor: index) }
            sensors.append(sensor)
        }
        for (index, sensor) in sensors.enumerated() {
            if index < zones.count {
                if sensor.frame != zones[index] { sensor.setFrame(zones[index], display: false) }
                if !isHidden, !sensor.isVisible { sensor.orderFrontRegardless() }
            } else if sensor.isVisible {
                sensor.orderOut(nil)
            }
        }
        if model.presentation == .expanded {
            // Follow the content-sized island without re-arming tracking,
            // which would report the pointer leaving and entering again.
            let zone = model.hotZone(for: .expanded)
            hostingView.trackingRectInWindow = zone.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
        } else {
            updateMouseHandling(expanded: false)
        }
    }
}
