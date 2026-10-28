// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Observation

/// Runs exactly the enabled modules (#70) and owns their lifecycle:
/// enabling, disabling, quitting, and protection from a module that crashes
/// the app while starting (`LaunchGuard`).
///
/// It observes only `settings.enabledModules`, and starts and stops modules
/// outside that observation, so a setting a module reads while starting
/// never makes the host (or the app's settings push) run again.
@MainActor
@Observable
final class ModuleHost {
    /// Which modules run, for Settings to observe.
    private(set) var runningIDs: Set<ModuleID> = []
    /// Modules turned off for crashing while starting, until the user turns them back on.
    private(set) var suspendedIDs: Set<ModuleID> = []
    /// After repeated crashes at launch no module starts until the user resumes.
    private(set) var isSafeMode = false
    /// The previous session didn't quit cleanly.
    private(set) var previousSessionCrashed = false

    @ObservationIgnored let services: ModuleServices
    @ObservationIgnored private let moduleTypes: [any IslandModule.Type]
    @ObservationIgnored private let coordinator: ActivityCoordinator
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let scheduler: RefreshScheduler
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var launchGuard: LaunchGuard
    /// In start order.
    @ObservationIgnored private var running: [(id: ModuleID, module: any IslandModule)] = []
    @ObservationIgnored private var isObserving = false
    /// How many times the host has read the enabled set (tests check that
    /// nothing else re-triggers it).
    @ObservationIgnored private(set) var observationPasses = 0
    @ObservationIgnored private let stableTimer = OneShotTimer()
    @ObservationIgnored private let log = Log.modules

    init(moduleTypes: [any IslandModule.Type], coordinator: ActivityCoordinator, settings: SettingsStore,
         scheduler: RefreshScheduler, services: ModuleServices, now: @escaping () -> Date = Date.init) {
        self.moduleTypes = moduleTypes
        self.coordinator = coordinator
        self.settings = settings
        self.scheduler = scheduler
        self.services = services
        self.now = now
        launchGuard = LaunchGuard(record: settings.launchRecord)
        coordinator.moduleOrder = moduleTypes.map { $0.descriptor.id }
    }

    /// Every module this Mac can use, in catalogue order.
    var descriptors: [ModuleDescriptor] { moduleTypes.filter { $0.isAvailable }.map { $0.descriptor } }

    func module(_ id: ModuleID) -> (any IslandModule)? {
        running.first { $0.id == id }?.module
    }

    // MARK: App lifecycle

    /// Judges the last session, applies default-on modules, then runs the
    /// enabled modules and follows the setting from now on.
    func start(debuggerAttached: Bool) {
        guard !isObserving else { return }
        isObserving = true
        launchGuard.launch(at: now(), debuggerAttached: debuggerAttached)
        persistRecord()
        previousSessionCrashed = launchGuard.previousSessionCrashed
        isSafeMode = launchGuard.isSafeMode
        suspendedIDs = launchGuard.record.suspended
        if isSafeMode {
            log.error("Repeated crashes at launch: starting in safe mode, with no modules")
        } else if previousSessionCrashed {
            log.notice("The last session didn't quit cleanly")
        }
        let defaults = ModuleDefaults.apply(descriptors, enabled: settings.enabledModules, seen: settings.seenModules)
        if defaults.seen != settings.seenModules { settings.seenModules = defaults.seen }
        if defaults.enabled != settings.enabledModules { settings.enabledModules = defaults.enabled }
        observeEnabledModules()
        stableTimer.action = { [weak self] in self?.markStable() }
        stableTimer.schedule(at: now().addingTimeInterval(LaunchGuard.stableAfter))
    }

    /// Stops every module, newest first, and records a clean quit.
    func shutDown() {
        stableTimer.schedule(at: nil)
        stopAll()
        launchGuard.cleanExit()
        persistRecord()
    }

    /// The session has stayed up long enough: the modules running now are
    /// trusted again.
    func markStable() {
        launchGuard.markStable(running: Set(running.map(\.id)))
        persistRecord()
    }

    // MARK: Modules

    /// Starts newly enabled modules and stops (and releases) the others.
    func reconcile(enabled: Set<ModuleID>) {
        let unavailable = Set(moduleTypes.filter { !$0.isAvailable }.map { $0.descriptor.id })
        let blocked = isSafeMode ? Set(moduleTypes.map { $0.descriptor.id }) : suspendedIDs.union(unavailable)
        let plan = ModuleLifecyclePlan.make(running: running.map(\.id), enabled: enabled,
                                            catalogOrder: moduleTypes.map { $0.descriptor.id }, blocked: blocked)
        for id in plan.stop { stopModule(id) }
        for id in plan.start { startModule(id) }
        publishRunning()
    }

    func stopAll() {
        for entry in running.reversed() { stopModule(entry.id) }
        publishRunning()
    }

    /// Turns a suspended module back on (Settings ▸ Modules).
    func resume(_ id: ModuleID) {
        launchGuard.resume(id)
        persistRecord()
        suspendedIDs = launchGuard.record.suspended
        reconcile(enabled: settings.enabledModules)
    }

    /// Starts the enabled modules after safe mode (the status menu).
    func leaveSafeMode() {
        launchGuard.leaveSafeMode()
        persistRecord()
        isSafeMode = false
        reconcile(enabled: settings.enabledModules)
    }

    // MARK: Internals

    private func observeEnabledModules() {
        observationPasses += 1
        let enabled = withObservationTracking {
            settings.enabledModules
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeEnabledModules() }
        }
        // Outside the tracking closure: whatever modules read while starting
        // must not be tracked here.
        reconcile(enabled: enabled)
    }

    private func startModule(_ id: ModuleID) {
        guard let type = moduleTypes.first(where: { $0.descriptor.id == id }) else { return }
        let context = ModuleContext(activities: ActivitySink(moduleID: id, coordinator: coordinator), scheduler: scheduler,
                                    settings: settings, services: services, previousSessionCrashed: previousSessionCrashed)
        launchGuard.willStart(id)
        persistRecord()
        let module = type.init(context: context)
        running.append((id: id, module: module))
        module.start()
        launchGuard.didStart(id)
        persistRecord()
        log.info("Started module \(id, privacy: .public)")
    }

    private func stopModule(_ id: ModuleID) {
        guard let index = running.firstIndex(where: { $0.id == id }) else { return }
        let module = running.remove(at: index).module
        module.stop()
        coordinator.endAll(from: id)
        log.info("Stopped module \(id, privacy: .public)")
    }

    private func publishRunning() {
        let ids = Set(running.map(\.id))
        if ids != runningIDs { runningIDs = ids }
    }

    private func persistRecord() {
        if settings.launchRecord != launchGuard.record { settings.launchRecord = launchGuard.record }
    }

    /// True when a debugger (Xcode) is attached to this process.
    nonisolated static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}
