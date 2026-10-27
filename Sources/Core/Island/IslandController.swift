// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Owns the panels and model for the island on one display, and turns pointer
/// events into one continuous compact ↔ expanded morph.
///
/// Click-through (ADR-0002): the island panel has a fixed size and never
/// resizes during interaction, so the morph can't glitch. While compact it
/// ignores the mouse completely and an invisible sensor window, exactly the
/// size of the compact island, detects hover and clicks. While expanded the
/// island panel takes the mouse and detects the pointer leaving.
@MainActor
final class IslandController {
    let displayID: DisplayID
    let model: IslandViewModel
    var behavior: IslandBehavior

    private let panel: IslandPanel
    private let hostingView: IslandHostingView
    private let sensor: IslandSensorPanel
    private var hover = HoverStateMachine()
    private var hoverTimer: Task<Void, Never>?
    /// Identifies the latest presentation change, so a superseded animation's
    /// completion can't switch mouse handling under a newer one.
    private var transitionID = 0
    private var isHidden = false
    /// When the pointer last entered the compact island, to recognise bounces.
    private var enteredAt: ContinuousClock.Instant?

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
        sensor = IslandSensorPanel(contentRect: model.sensorFrame)

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
        hostingView.onPointer = { [weak self] event in
            self?.islandPointer(event)
        }
        sensor.onEvent = { [weak self] event in
            self?.sensorEvent(event)
        }

        layoutWindows()
        observeCompactLayout()
        sensor.orderFrontRegardless()
        panel.orderFrontRegardless()
        Log.island.info("Island on \(displayID, privacy: .public): \(String(describing: geometry.kind), privacy: .public) panel \(NSStringFromRect(frame), privacy: .public)")
    }

    // MARK: Lifecycle

    func update(geometry: NotchGeometry, appearance: IslandAppearance) {
        let theme = appearance.theme(for: geometry.kind)
        if model.theme != theme { model.theme = theme }
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
            sensor.orderOut(nil)
        } else {
            sensor.orderFrontRegardless()
            panel.orderFrontRegardless()
        }
    }

    func setHiddenFromCapture(_ hidden: Bool) {
        panel.hiddenFromCapture = hidden
    }

    func tearDown() {
        hoverTimer?.cancel()
        for window in [panel, sensor] as [NSWindow] {
            window.orderOut(nil)
            window.close()
        }
    }

    // MARK: Interaction

    func expand() { send(.forceExpand) }
    func collapse() { send(.forceCollapse) }

    /// Events from the sensor only matter while the island is compact.
    private func sensorEvent(_ event: IslandSensorPanel.Event) {
        Log.island.debug("sensor \(String(describing: event), privacy: .public) at \(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)")
        guard hover.state == .compact || hover.state == .pendingExpand else { return }
        switch event {
        case .entered:
            enteredAt = .now
            send(.pointerEntered)
        case .exited(let location):
            compactPointerLeft(at: location)
        case .clicked: send(.clicked)
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
            guard model.isOnNotchTopEdge(location) else { return }
            Log.island.debug("pointer reached the notch's top edge at \(NSStringFromPoint(location), privacy: .public)")
            enteredAt = .now
            send(.pointerEntered)
        case .pendingExpand:
            // The tracking area may never have seen this pointer, so it won't
            // report it leaving either.
            guard !model.containsPointer(location, for: .compact) else { return }
            compactPointerLeft(at: location)
        case .expanded, .pendingCollapse:
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
        guard hover.state == .expanded || hover.state == .pendingCollapse else { return }
        switch event {
        case .entered: send(.pointerEntered)
        case .exited(let location): pointerExited(at: location, from: .expanded)
        }
    }

    /// Ignores false exits: a pointer pinned to the top row of the screen is
    /// reported as outside even though it's on the island.
    private func pointerExited(at location: CGPoint, from presentation: IslandPresentation) {
        if model.containsPointer(location, for: presentation) {
            Log.island.debug("ignored false exit at \(NSStringFromPoint(location), privacy: .public)")
            return
        }
        send(.pointerExited)
    }

    private func send(_ event: HoverStateMachine.Event) {
        let before = hover.state
        let effects = hover.handle(event, hoverEnabled: behavior.expandOnHover, hoverDelay: behavior.hoverDelay)
        Log.island.debug("hover \(String(describing: event), privacy: .public): \(String(describing: before), privacy: .public) → \(String(describing: self.hover.state), privacy: .public)")
        for effect in effects { perform(effect) }
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

    // MARK: Morph

    private func present(_ target: IslandPresentation) {
        guard model.presentation != target else { return }
        transitionID += 1
        let id = transitionID

        if target == .expanded {
            // Take the mouse now, so the expanded content is clickable at once.
            updateMouseHandling(expanded: true)
        }
        withAnimation(animation(for: target), completionCriteria: .removed) {
            model.presentation = target
        } completion: { [weak self] in
            guard let self, self.transitionID == id, self.model.presentation == .compact else { return }
            // Fully collapsed: let clicks through again and hand hover back to the sensor.
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
            sensor.resetTracking()
        }
    }

    /// The compact island grows and shrinks with its activities, and the
    /// expanded island with its content; keep the sensor, the expanded
    /// tracking area (and, rarely, the panel) fitted to them.
    private func observeCompactLayout() {
        withObservationTracking {
            _ = model.islandRect(for: .compact)
            _ = model.islandRect(for: .expanded)
            _ = model.panelFrame
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.layoutWindows()
                self?.observeCompactLayout()
            }
        }
    }

    /// Sizes the island panel (only when geometry or sizes change, never during
    /// the morph) and fits the sensor to the compact island.
    private func layoutWindows() {
        let frame = model.panelFrame
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        let sensorFrame = model.sensorFrame
        if sensor.frame != sensorFrame { sensor.setFrame(sensorFrame, display: false) }
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
