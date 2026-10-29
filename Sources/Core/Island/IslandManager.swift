// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The settings that decide which displays show an island and how it's placed.
struct IslandConfiguration: Equatable, Sendable {
    var displaySelection: DisplaySelection = .main
    var widthOffset: CGFloat = 0
    /// Debug aid: show the pill even on a notched display.
    var forcePill = false
}

/// Keeps one `IslandController` per selected display, in sync with the
/// connected screens, their resolutions, sleep/wake and the configuration.
@MainActor
final class IslandManager {
    private(set) var controllers: [DisplayID: IslandController] = [:]

    var configuration: IslandConfiguration {
        didSet { if configuration != oldValue { reconcileScreens() } }
    }

    var appearance = IslandAppearance() {
        didSet { if appearance != oldValue { reconcileScreens() } }
    }

    var behavior: IslandBehavior {
        didSet { for controller in controllers.values { controller.behavior = behavior } }
    }

    /// At least one island is on screen: not paused, and not hidden over a
    /// fullscreen app. The HUD needs to know, since a swallowed key with no
    /// island to show it would leave the user with no feedback.
    private(set) var anyIslandShown = false {
        didSet { if anyIslandShown != oldValue { onShownChange(anyIslandShown) } }
    }
    var onShownChange: (Bool) -> Void = { _ in }

    /// Pause hides every island until resumed (status menu or Settings).
    var isPaused = false {
        didSet { if isPaused != oldValue { applyVisibility() } }
    }

    /// Hide the island on displays showing a fullscreen app (#5).
    var hideInFullscreen = true {
        didSet { if hideInFullscreen != oldValue { applyVisibility() } }
    }

    /// …unless an activity asks to stay, like media playing from another app.
    var keepShowingForMedia = true {
        didSet { if keepShowingForMedia != oldValue { applyVisibility() } }
    }
    private var activitiesKeepIsland = false

    var hideFromScreenCapture = false {
        didSet { for controller in controllers.values { controller.setHiddenFromCapture(hideFromScreenCapture) } }
    }

    let accessibility: AccessibilityOptions
    let activities: ActivityCoordinator
    let fullscreen: FullscreenMonitor
    var actions = IslandActions()

    private let observers = NotificationTokens()
    private var pendingReconcile: Task<Void, Never>?
    private var pointerMonitors: [Any] = []
    private var lastSoundSerial: Int?

    init(configuration: IslandConfiguration = IslandConfiguration(),
         behavior: IslandBehavior = IslandBehavior(),
         accessibility: AccessibilityOptions,
         activities: ActivityCoordinator,
         fullscreen: FullscreenMonitor) {
        self.configuration = configuration
        self.behavior = behavior
        self.accessibility = accessibility
        self.activities = activities
        self.fullscreen = fullscreen
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.scheduleReconcile()
        }
        observers.observe(NSWorkspace.didWakeNotification, in: workspace) { [weak self] in
            self?.scheduleReconcile()
        }
        observers.observe(NSWorkspace.screensDidWakeNotification, in: workspace) { [weak self] in
            self?.scheduleReconcile()
        }
        fullscreen.onChange = { [weak self] _ in self?.applyVisibility() }
        fullscreen.start()
        reconcileScreens()
        observeAlertSounds()
        observeKeepIsland()
    }

    func stop() {
        fullscreen.stop()
        removePointerMonitors()
        observers.invalidate()
        pendingReconcile?.cancel()
        for controller in controllers.values { controller.tearDown() }
        controllers.removeAll()
    }

    func expandAll() { for controller in controllers.values { controller.expand() } }
    func expandAll(to page: IslandViewModel.ExpandedPage) { for controller in controllers.values { controller.expand(to: page) } }
    #if DEBUG
    /// Expands to Home with a quick action's panel open (screenshots).
    func openHomeAction(_ id: String) {
        for controller in controllers.values {
            controller.expand(to: .home)
            controller.model.openHomeAction = id
        }
    }
    #endif
    func collapseAll() { for controller in controllers.values { controller.collapse() } }

    /// Screen notifications arrive in bursts; settle for 200 ms before rebuilding.
    private func scheduleReconcile() {
        pendingReconcile?.cancel()
        pendingReconcile = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.reconcileScreens()
        }
    }

    func reconcileScreens() {
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { (id: $0, screen: screen) } }
        let candidates = screens.map { DisplayCandidate(id: $0.id, isBuiltIn: $0.screen.isBuiltIn, hasNotch: $0.screen.hasNotch) }
        let wanted = Set(configuration.displaySelection.resolve(among: candidates))

        for (id, controller) in controllers where !wanted.contains(id) {
            controller.tearDown()
            controllers[id] = nil
            Log.displays.info("Removed island from \(id, privacy: .public)")
        }
        defer { updateInteraction() }
        for (id, screen) in screens where wanted.contains(id) {
            let geometry = NotchGeometry.resolve(
                screen.screenDescriptor,
                widthOffset: configuration.widthOffset,
                forcePill: configuration.forcePill
            )
            if let controller = controllers[id] {
                controller.update(geometry: geometry, appearance: appearance)
            } else {
                let controller = IslandController(
                    displayID: id, geometry: geometry, behavior: behavior,
                    accessibility: accessibility, activities: activities, actions: actions
                )
                controller.update(geometry: geometry, appearance: appearance)
                controller.setHiddenFromCapture(hideFromScreenCapture)
                controller.onInteractionChange = { [weak self] in self?.updateInteraction() }
                controllers[id] = controller
            }
        }
        updatePointerMonitors()
        applyVisibility()
    }

    // MARK: Top-edge watcher

    /// Tracking areas never report a pointer that lands exactly on the top row
    /// of the screen, which is where a pointer thrown at the notch ends up. A
    /// mouse-moved monitor catches it. It only exists while a notched island
    /// does, needs no permission, and costs nothing while the pointer is still.
    private func updatePointerMonitors() {
        let needsWatcher = controllers.values.contains { $0.model.geometry.kind == .notch }
        if needsWatcher, pointerMonitors.isEmpty {
            let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            }
            pointerMonitors = [global, local].compactMap { $0 }
        } else if !needsWatcher {
            removePointerMonitors()
        }
    }

    private func removePointerMonitors() {
        for monitor in pointerMonitors { NSEvent.removeMonitor(monitor) }
        pointerMonitors.removeAll()
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        for controller in controllers.values { controller.pointerMoved(to: location) }
    }

    /// Alerts and banners wait while the user is on any island.
    private func updateInteraction() {
        let interacting = controllers.values.contains { $0.isInteracting }
        if activities.isInteracting != interacting { activities.isInteracting = interacting }
    }

    /// An alert's sound plays once, however many displays show it.
    private func observeAlertSounds() {
        withObservationTracking {
            _ = activities.alert
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let alert = self.activities.alert, alert.serial != self.lastSoundSerial {
                    self.lastSoundSerial = alert.serial
                    if !self.isPaused, let sound = alert.sound { NSSound(named: NSSound.Name(sound))?.play() }
                }
                self.observeAlertSounds()
            }
        }
    }

    /// Whether any visible activity wants the island kept over fullscreen apps.
    private func observeKeepIsland() {
        let keeps = withObservationTracking {
            activities.visible.contains { $0.activity.keepsIslandInFullscreen && !$0.isStale }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeKeepIsland() }
        }
        guard keeps != activitiesKeepIsland else { return }
        activitiesKeepIsland = keeps
        applyVisibility()
    }

    private func applyVisibility() {
        var shown = false
        for (id, controller) in controllers {
            let fullscreenHere = FullscreenVisibility.shouldHide(
                isFullscreen: fullscreen.fullscreenDisplays.contains(id),
                hideInFullscreen: hideInFullscreen,
                keepForMedia: keepShowingForMedia,
                anyActivityKeepsIsland: activitiesKeepIsland
            )
            let hidden = isPaused || fullscreenHere
            controller.setHidden(hidden)
            if !hidden { shown = true }
        }
        anyIslandShown = shown
    }
}
