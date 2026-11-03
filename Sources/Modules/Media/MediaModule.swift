// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Now Playing (#9–#13, #15, #16): what's playing in any app, as a `.media`
/// live activity. Off by default; while off it runs nothing at all.
@MainActor
final class MediaModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "media",
        name: "Now Playing",
        symbol: "music.note",
        summary: "Artwork and a live visualiser beside the notch for whatever's playing, in any app. Hover for controls, a seek bar and the output device.",
        permissions: [.automation],
        isDebugOnly: false
    )
    static let activityID: ActivityID = "media.nowPlaying"

    let service: NowPlayingService
    let model = MediaModel()
    /// Shared with other modules; held only while this module runs.
    private let outputs: AudioOutputService
    private var holdsOutputs = false
    private let context: ModuleContext
    private let settings: MediaSettings
    private let log = Log.module("media")
    private let endTimer = OneShotTimer()
    private let observers = NotificationTokens()
    private var isRunning = false
    private var reducer = MediaActivityReducer()
    private var frontmostBundleID: String?
    private var likeTask: Task<Void, Never>?
    /// Exists only while lyrics are on, so nothing can look lyrics up otherwise (ADR-0009).
    private var lyricsStore: LyricsStore?
    private var lyricsTask: Task<Void, Never>?
    /// The lyrics tab, while it is open. Created on first use, closed when the module stops.
    private var lyricsPanel: LyricsPanelController?
    #if DEBUG
    /// Seconds instead of minutes, to check the paused lifecycle quickly.
    var debugLifecycle: MediaLifecycle?
    #endif

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(MediaSettingsPane(settings: context.settings.media, registry: context.registry))
    }

    init(context: ModuleContext) {
        self.context = context
        outputs = context.services.audioOutputs
        settings = context.settings.media
        service = NowPlayingService(preference: settings.backend, ignoredApps: settings.ignoredApps)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = MediaActions(
            send: { [weak self] command in self?.service.send(command) },
            toggleLike: { [weak self] in self?.toggleLike() },
            openSource: { [weak self] in self?.openSource() },
            toggleLyrics: { [weak self] in self?.toggleLyricsPanel() }
        )
        endTimer.action = { [weak self] in self?.refresh() }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observers.observe(NSWorkspace.didActivateApplicationNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.frontmostChanged()
        }
        model.outputs = outputs
        // Artwork decodes off the main thread; repost so the keyline and blur-in follow it.
        model.onArtworkChange = { [weak self] in self?.refresh(force: true) }
        outputs.acquire()
        holdsOutputs = true
        context.services.nowPlaying.publish(model)
        observeSettings()
        observeService()
        service.start()
    }

    func stop() {
        isRunning = false
        lyricsPanel?.close(animated: false)
        lyricsPanel = nil
        observers.invalidate()
        endTimer.schedule(at: nil)
        likeTask?.cancel()
        applyLyricsSetting(false)
        service.stop()
        context.services.nowPlaying.withdraw()
        model.outputs = nil
        if holdsOutputs {
            holdsOutputs = false
            outputs.release()
        }
        model.clear()
        context.activities.endAll()
        reducer = MediaActivityReducer()
    }

    // MARK: Observation

    private func observeService() {
        guard isRunning else { return }
        withObservationTracking {
            _ = service.snapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observeService()
            }
        }
        refresh()
    }

    private func observeSettings() {
        guard isRunning else { return }
        let lyricsEnabled = withObservationTracking {
            service.preference = settings.backend
            service.ignoredApps = settings.ignoredApps
            model.visualizer = settings.visualizer
            model.showsGlow = settings.showGlow
            _ = settings.staleAfterMinutes
            _ = settings.endAfterMinutes
            return settings.lyricsEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeSettings()
                self?.refresh(force: true)
            }
        }
        // Outside the tracking closure: it reads the snapshot, which mustn't
        // re-run this on every playback update.
        applyLyricsSetting(lyricsEnabled)
    }

    private func frontmostChanged() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmost != frontmostBundleID else { return }
        frontmostBundleID = frontmost
        if reducer.state.isPosted { refresh(force: true) }
    }

    // MARK: Activity

    private var lifecycle: MediaLifecycle {
        #if DEBUG
        if let debugLifecycle { return debugLifecycle }
        #endif
        return settings.lifecycle
    }

    /// Brings the activity in line with what's playing (rules in `MediaActivityReducer`).
    private func refresh(force: Bool = false) {
        guard isRunning else { return }
        let snapshot = service.snapshot
        switch reducer.reduce(snapshot, now: Date(), lifecycle: lifecycle) {
        case .none:
            clearActivity()
        case .end:
            clearActivity()
            context.activities.end(Self.activityID)
        case .post(let trackChanged, let isNewSession):
            guard let snapshot else { return }
            if isNewSession {
                trackDidChange(snapshot)
                loadLyrics(for: snapshot)
            }
            let changed = snapshot != model.snapshot
            model.update(snapshot)
            endTimer.schedule(at: lifecycle.endDate(pausedSince: reducer.state.pausedSince))
            guard changed || force || isNewSession else { return }
            let alert = trackChanged && snapshot.isPlaying && settings.expandOnTrackChange ? AlertRequest() : nil
            post(snapshot, alert: alert)
        }
    }

    private func post(_ snapshot: NowPlayingSnapshot, alert: AlertRequest?) {
        let artist = snapshot.artist.map { " by \($0)" } ?? ""
        let state = snapshot.isPlaying ? "playing" : "paused"
        let activity = LiveActivity(
            id: Self.activityID,
            moduleID: Self.descriptor.id,
            kind: .media,
            title: snapshot.title,
            staleDate: lifecycle.staleDate(pausedSince: reducer.state.pausedSince),
            keylineTint: model.artwork == nil ? nil : model.tint,
            accessibilityLabel: "\(snapshot.title)\(artist), \(state)",
            openAction: { [weak self] in self?.openSource() },
            staleNote: nil,
            keepsIslandInFullscreen: snapshot.isPlaying && snapshot.sourceBundleID != frontmostBundleID,
            presentation: MediaPresentation.make(model: model)
        )
        context.activities.post(activity, alert: alert)
    }

    /// Nothing on the island: no end timer, no per-track data.
    private func clearActivity() {
        endTimer.schedule(at: nil)
        likeTask?.cancel()
        lyricsTask?.cancel()
        if model.snapshot != nil { model.clear() }
    }

    /// Liking works for Apple Music only (#15): Spotify's scripting can't
    /// change `starred`, and its Web API is a separate decision.
    private func trackDidChange(_ snapshot: NowPlayingSnapshot) {
        likeTask?.cancel()
        model.liked = nil
        model.canLike = false
        guard snapshot.sourceBundleID == ScriptablePlayer.music.bundleID else { return }
        likeTask = Task { [weak self] in
            guard let self else { return }
            // Read the favourite only if already allowed; otherwise the heart
            // shows empty and the first tap is what asks for permission.
            switch await self.service.musicAutomationStatus() {
            case .granted:
                let liked = await self.service.musicFavorite()
                guard !Task.isCancelled else { return }
                self.model.liked = liked ?? false
                self.model.canLike = true
            case .notDetermined, .unknown:
                guard !Task.isCancelled else { return }
                self.model.liked = snapshot.liked ?? false
                self.model.canLike = true
            case .denied, .notRunning:
                break
            }
        }
    }

    // MARK: Lyrics

    private func applyLyricsSetting(_ enabled: Bool) {
        if enabled {
            guard lyricsStore == nil else { return }
            let store = LyricsStore(fetcher: LRCLIBClient(), cacheDirectory: LyricsStore.defaultCacheDirectory)
            store.isEnabled = true
            lyricsStore = store
            if let snapshot = service.snapshot { loadLyrics(for: snapshot) }
        } else {
            lyricsTask?.cancel()
            lyricsTask = nil
            lyricsStore?.isEnabled = false
            lyricsStore = nil
            model.lyrics = nil
        }
    }

    private func loadLyrics(for snapshot: NowPlayingSnapshot) {
        lyricsTask?.cancel()
        model.lyrics = nil
        guard let store = lyricsStore else { return }
        let track = snapshot.trackKey
        lyricsTask = Task { [weak self] in
            let lyrics = await store.lyrics(for: snapshot)
            guard !Task.isCancelled, let self, self.model.trackKey == track else { return }
            self.model.lyrics = lyrics.flatMap { $0.lines.isEmpty ? nil : $0 }
        }
    }

    // MARK: Actions

    /// The lyrics tab: a card under the island that stays until it is closed (#13).
    func toggleLyricsPanel() {
        if lyricsPanel == nil { lyricsPanel = LyricsPanelController(model: model) }
        lyricsPanel?.toggle()
    }

    #if DEBUG
    /// Screenshots: opens or closes the lyrics tab.
    func debugSetLyricsPanel(open: Bool) {
        if lyricsPanel == nil { lyricsPanel = LyricsPanelController(model: model) }
        if open != (lyricsPanel?.isOpen ?? false) { lyricsPanel?.toggle() }
    }

    /// Screenshots: gives the current track made-up lyrics (long and short lines, one every few
    /// seconds from now), without a lookup, so the lyric views can be checked on any track.
    func debugShowFakeLyrics(_ on: Bool) {
        guard on, let current = service.snapshot else { model.lyrics = nil; return }
        var time = current.timeline.elapsed(at: .now) - 0.5
        let texts = ["Waiting in a car, waiting for a ride in the dark", "Short one", "The night city grows, look at the horizon glow",
                     "Oh", "I bag it like groceries, keep some cash flowing over me", "♪",
                     "Every light a promise, every road a dream", "And the radio plays on", "Until the morning comes around again",
                     "Hold on", "We were only getting started"]
        model.lyrics = SyncedLyrics(lines: texts.map { text in
            defer { time += 5 }
            return SyncedLyrics.Line(time: time, text: text)
        })
    }
    #endif

    private func openSource() {
        guard let bundleID = service.snapshot?.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func toggleLike() {
        guard model.canLike else { return }
        let target = !(model.liked ?? false)
        model.liked = target
        likeTask?.cancel()
        likeTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.setMusicFavorite(target)
            guard !Task.isCancelled else { return }
            if let result {
                self.model.liked = result
            } else {
                // Declined, or Music didn't answer: hide the heart rather than lie.
                self.log.notice("Couldn't favourite the track in Music")
                self.model.canLike = await self.service.musicAutomationStatus() != .denied
                self.model.liked = self.model.canLike ? !target : nil
            }
        }
    }
}

/// The Now Playing activity's regions (#9).
@MainActor
enum MediaPresentation {
    static func make(model: MediaModel) -> ActivityPresentation {
        let showsBars = model.visualizer != .off
        let trailing: IslandRegion? = if showsBars {
            IslandRegion { MediaBarsView(model: model, height: 14) }
        } else {
            nil
        }
        return ActivityPresentation(
            compactLeading: IslandRegion { MediaArtworkView(model: model, size: 20) },
            compactTrailing: trailing,
            minimal: IslandRegion { MediaMinimalView(model: model) },
            expanded: ExpandedPresentation(
                leading: ExpandedRegion { MediaSourceLabel(model: model) },
                trailing: ExpandedRegion { MediaOutputBadge(model: model, showsBars: showsBars) },
                center: ExpandedRegion { MediaExpandedBody(model: model) },
                bottom: model.lyrics != nil ? ExpandedRegion { MediaLyricLine(model: model) } : nil
            )
        )
    }
}
