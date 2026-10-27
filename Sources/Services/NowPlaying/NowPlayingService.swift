// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

/// What's playing, from the best backend that works (#9, #10, ADR-0008).
///
/// Runs only while the Now Playing module is on. It picks a backend with
/// `BackendSelector`, switches when the adapter turns out to be broken, and
/// applies commands optimistically so the island responds at once.
@MainActor
@Observable
final class NowPlayingService {
    /// What to show; nil when nothing plays (or only ignored apps do).
    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var selection: BackendSelection = .active(.adapter)
    private(set) var adapterHealth: AdapterHealth = .unknown
    private(set) var scripting = ScriptingAvailability(installedApps: [], deniedApps: [])
    private(set) var isCheckingAdapter = false

    @ObservationIgnored var preference: BackendPreference {
        didSet { if preference != oldValue { reselect() } }
    }
    @ObservationIgnored var ignoredApps: Set<String> {
        didSet { if ignoredApps != oldValue { publish() } }
    }
    /// DEBUG: make the adapter fail, to check that the fallback takes over.
    @ObservationIgnored var simulateAdapterFailure = false {
        didSet {
            guard simulateAdapterFailure != oldValue else { return }
            adapter?.stop()
            adapter = nil
            adapterHealth = .unknown
            reselect()
        }
    }

    @ObservationIgnored private let runner = AppleScriptRunner()
    @ObservationIgnored private let log = Log.module("media")
    @ObservationIgnored private var adapter: AdapterNowPlayingProvider?
    @ObservationIgnored private var scriptingProvider: ScriptingNowPlayingProvider?
    @ObservationIgnored private let watcher = PlayerNotificationWatcher()
    @ObservationIgnored private var raw: NowPlayingSnapshot?
    @ObservationIgnored private var crossCheck: Task<Void, Never>?
    @ObservationIgnored private var lastCrossCheck: Date?
    @ObservationIgnored private var isRunning = false

    init(preference: BackendPreference, ignoredApps: Set<String>) {
        self.preference = preference
        self.ignoredApps = ignoredApps
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scripting.installedApps = Set(ScriptablePlayer.allCases.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }.map(\.bundleID))
        watcher.onEvent = { [weak self] player, info in self?.playerChanged(player, info) }
        watcher.start()
        reselect()
    }

    func stop() {
        isRunning = false
        watcher.stop()
        crossCheck?.cancel()
        adapter?.stop()
        adapter = nil
        scriptingProvider?.stop()
        scriptingProvider = nil
        raw = nil
        snapshot = nil
    }

    // MARK: Commands

    func send(_ command: MediaCommand) {
        if var shown = raw {
            let now = Date()
            let elapsed = shown.timeline.elapsed(at: now)
            switch command {
            case .play, .pause, .togglePlayPause:
                shown.isPlaying = command == .play || (command == .togglePlayPause && !shown.isPlaying)
                shown.timeline = PlaybackTimeline(elapsed: elapsed, timestamp: now, rate: shown.isPlaying ? 1 : 0,
                                                  duration: shown.timeline.duration)
            case .seek(let seconds):
                shown.timeline.elapsed = seconds
                shown.timeline.timestamp = now
            case .skipForward15, .skipBackward15:
                shown.timeline.elapsed = elapsed + (command == .skipForward15 ? 15 : -15)
                shown.timeline.timestamp = now
            case .next, .previous:
                break
            }
            raw = shown
            publish()
        }
        activeProvider?.send(command)
    }

    /// Whether the current Music track is a favourite (#15); nil if unknown.
    func musicFavorite() async -> Bool? {
        guard snapshot?.sourceBundleID == ScriptablePlayer.music.bundleID else { return nil }
        return handleFavorite(await MusicFavorites(runner: runner).isFavorited())
    }

    func setMusicFavorite(_ value: Bool) async -> Bool? {
        guard snapshot?.sourceBundleID == ScriptablePlayer.music.bundleID else { return nil }
        return handleFavorite(await MusicFavorites(runner: runner).setFavorited(value))
    }

    private func handleFavorite(_ outcome: AppleScriptOutcome) -> Bool? {
        if case .failure(let code, _) = outcome, code == AppleScriptOutcome.notPermitted {
            automationDenied(.music)
        }
        return outcome.value?.bool
    }

    /// Settings ▸ Check Again: runs the adapter's self-test.
    func checkAdapterAgain() async {
        guard let paths = AdapterPaths.bundled else { return }
        isCheckingAdapter = true
        let probe = adapter ?? AdapterNowPlayingProvider(paths: paths, simulateFailure: simulateAdapterFailure)
        let passed = await probe.runSelfTest()
        isCheckingAdapter = false
        // The running adapter reports its own health; a stand-in probe's result is applied here.
        if probe !== adapter { adapterHealth = passed ? .unknown : .failed("The adapter's self-test failed.") }
        reselect()
    }

    // MARK: Backends

    private var activeProvider: (any NowPlayingProvider)? {
        switch selection.backend {
        case .adapter: adapter
        case .scripting: scriptingProvider
        case nil: nil
        }
    }

    private func reselect() {
        guard isRunning else { return }
        let next = BackendSelector.select(preference: preference, health: adapterHealth, scripting: scripting)
        if next != selection {
            log.info("Now Playing backend: \(String(describing: next), privacy: .public)")
            selection = next
        }
        switch next.backend {
        case .adapter:
            scriptingProvider?.stop()
            scriptingProvider = nil
            startAdapter()
        case .scripting:
            adapter?.stop()
            adapter = nil
            startScripting()
        case nil:
            adapter?.stop()
            adapter = nil
            scriptingProvider?.stop()
            scriptingProvider = nil
            receive(nil)
        }
    }

    private func startAdapter() {
        guard adapter == nil else { return }
        guard let paths = AdapterPaths.bundled else {
            adapterHealth = .failed("The adapter is missing from Notched.app.")
            reselect()
            return
        }
        let provider = AdapterNowPlayingProvider(paths: paths, simulateFailure: simulateAdapterFailure)
        provider.onUpdate = { [weak self] snapshot in self?.receive(snapshot) }
        provider.onHealthChange = { [weak self] health in
            guard let self else { return }
            self.adapterHealth = health
            if case .failed = health { self.reselect() }
        }
        adapter = provider
        provider.start()
    }

    private func startScripting() {
        guard scriptingProvider == nil else { return }
        let provider = ScriptingNowPlayingProvider(runner: runner)
        provider.onUpdate = { [weak self] snapshot in self?.receive(snapshot) }
        provider.onAutomationDenied = { [weak self] player in self?.automationDenied(player) }
        scriptingProvider = provider
        provider.start()
    }

    private func automationDenied(_ player: ScriptablePlayer) {
        guard !scripting.deniedApps.contains(player.bundleID) else { return }
        scripting.deniedApps.insert(player.bundleID)
        if selection.backend == .scripting { reselect() }
    }

    private func receive(_ snapshot: NowPlayingSnapshot?) {
        raw = snapshot
        publish()
    }

    private func publish() {
        let shown = raw.flatMap { ignoredApps.contains($0.sourceBundleID) ? nil : $0 }
        if shown != snapshot { snapshot = shown }
    }

    // MARK: Adapter health check

    /// Music or Spotify says it's playing. If the adapter still sees nothing
    /// three seconds later, it may have stopped working: run its self-test
    /// (at most every 10 minutes) and fall back if it fails.
    private func playerChanged(_ player: ScriptablePlayer, _ info: PlayerNotificationInfo?) {
        guard preference == .auto, selection.backend == .adapter, info?.state == .playing else { return }
        if let last = lastCrossCheck, Date().timeIntervalSince(last) < 600 { return }
        crossCheck?.cancel()
        crossCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.isRunning, self.raw == nil, let adapter = self.adapter else { return }
            self.lastCrossCheck = Date()
            self.log.notice("\(player.name, privacy: .public) is playing but the adapter sees nothing; testing it")
            _ = await adapter.runSelfTest()
        }
    }
}
