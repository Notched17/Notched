// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The fallback backend: Music and Spotify only (#10, ADR-0008).
///
/// Their own playback notifications say when anything changes (no polling,
/// no permission). AppleScript then fills in what they leave out: the
/// position, the artwork and, for Music, whether the track is a favourite.
/// Scripts only ever target a running player, because a `tell` would
/// otherwise launch it.
@MainActor
final class ScriptingNowPlayingProvider: NowPlayingProvider {
    var onUpdate: (NowPlayingSnapshot?) -> Void = { _ in }
    /// The user declined Automation for a player.
    var onAutomationDenied: (ScriptablePlayer) -> Void = { _ in }

    private let runner: AppleScriptRunner
    private let watcher = PlayerNotificationWatcher()
    private let log = Log.module("media")
    private var states: [ScriptablePlayer: NowPlayingSnapshot] = [:]
    /// The player that most recently started playing; it's the one shown and controlled.
    private var current: ScriptablePlayer?
    private var refreshes: [ScriptablePlayer: Task<Void, Never>] = [:]
    private var artworkTrack: [ScriptablePlayer: TrackKey] = [:]
    private var isRunning = false
    /// One ephemeral session for Spotify artwork: no cookies, no disk cache.
    private static let artworkSession = URLSession(configuration: .ephemeral)

    init(runner: AppleScriptRunner) {
        self.runner = runner
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        watcher.onEvent = { [weak self] player, info in self?.handle(player, info) }
        watcher.start()
        for player in ScriptablePlayer.allCases where Self.isRunning(player) { refresh(player) }
    }

    func stop() {
        isRunning = false
        watcher.stop()
        for task in refreshes.values { task.cancel() }
        refreshes.removeAll()
        states.removeAll()
        artworkTrack.removeAll()
        current = nil
    }

    func send(_ command: MediaCommand) {
        guard let player = current ?? states.keys.first, Self.isRunning(player) else { return }
        let verb: String = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .skipForward15: "set player position to (player position + 15)"
        case .skipBackward15: "set player position to (player position - 15)"
        case .seek(let seconds): "set player position to \(max(seconds, 0))"
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.runner.run(Self.script(for: player, "\(verb)"))
            self.check(outcome, from: player)
        }
    }

    // MARK: Events

    private func handle(_ player: ScriptablePlayer, _ info: PlayerNotificationInfo?) {
        guard isRunning else { return }
        guard let info, info.state != .stopped, let title = info.title, !title.isEmpty else {
            states[player] = nil
            if current == player { current = nil }
            publish()
            return
        }
        let playing = info.state == .playing
        let previous = states[player]
        let key = TrackKey(title: title, artist: info.artist ?? "", album: info.album ?? "")
        let sameTrack = previous?.trackKey == key
        let now = Date()
        let elapsed = info.position ?? (sameTrack ? previous?.timeline.elapsed(at: now) : nil) ?? 0
        states[player] = NowPlayingSnapshot(
            title: title,
            artist: info.artist.flatMap { $0.isEmpty ? nil : $0 },
            album: info.album.flatMap { $0.isEmpty ? nil : $0 },
            timeline: PlaybackTimeline(elapsed: elapsed, timestamp: now, rate: playing ? 1 : 0, duration: info.duration),
            isPlaying: playing,
            sourceBundleID: player.bundleID,
            artwork: sameTrack ? previous?.artwork : nil
        )
        if playing || current == nil { current = player }
        publish()
        refresh(player)
    }

    private func publish() {
        let shown = current.flatMap { states[$0] } ?? states.values.first { $0.isPlaying } ?? states.values.first
        onUpdate(shown)
    }

    // MARK: Scripting

    /// Reads the exact position (and artwork once per track) from the player.
    private func refresh(_ player: ScriptablePlayer) {
        refreshes[player]?.cancel()
        refreshes[player] = Task { [weak self] in
            guard let self, Self.isRunning(player) else { return }
            let outcome = await self.runner.run(Self.script(for: player, Self.stateScript(player)))
            guard !Task.isCancelled, self.isRunning else { return }
            self.check(outcome, from: player)
            guard let items = outcome.value?.items, items.count >= 6, let title = items[0].string, !title.isEmpty else { return }
            let playing = items[5].string == "playing"
            let key = TrackKey(title: title, artist: items[1].string ?? "", album: items[2].string ?? "")
            let duration = items[3].double.flatMap { $0 > 0 ? $0 : nil }
            var snapshot = self.states[player] ?? NowPlayingSnapshot(
                title: title, artist: nil, album: nil,
                timeline: PlaybackTimeline(elapsed: 0, timestamp: Date(), rate: 0, duration: duration),
                isPlaying: playing, sourceBundleID: player.bundleID, artwork: nil)
            if snapshot.trackKey != key { snapshot.artwork = nil }
            snapshot.title = title
            snapshot.artist = items[1].string.flatMap { $0.isEmpty ? nil : $0 }
            snapshot.album = items[2].string.flatMap { $0.isEmpty ? nil : $0 }
            snapshot.isPlaying = playing
            snapshot.timeline = PlaybackTimeline(elapsed: items[4].double ?? 0, timestamp: Date(), rate: playing ? 1 : 0, duration: duration)
            if player == .music { snapshot.liked = items.count > 6 ? items[6].bool : nil }
            self.states[player] = snapshot
            if playing || self.current == nil { self.current = player }
            self.publish()
            if self.artworkTrack[player] != key || snapshot.artwork == nil {
                self.artworkTrack[player] = key
                let artworkURL = player == .spotify && items.count > 6 ? items[6].string : nil
                await self.loadArtwork(for: player, track: key, url: artworkURL)
            }
        }
    }

    private func loadArtwork(for player: ScriptablePlayer, track: TrackKey, url: String?) async {
        let data: Data?
        switch player {
        case .music:
            data = await runner.run(Self.script(for: player, "return raw data of artwork 1 of current track")).value.flatMap {
                if case .data(let data) = $0 { data } else { nil }
            }
        case .spotify:
            // Spotify only gives a URL on its own image CDN.
            guard let url = url.flatMap(URL.init(string:)), url.scheme == "https" else { return }
            data = try? await Self.artworkSession.data(from: url).0
        }
        guard isRunning, let data, var snapshot = states[player], snapshot.trackKey == track else { return }
        snapshot.artwork = data
        states[player] = snapshot
        publish()
    }

    private func check(_ outcome: AppleScriptOutcome, from player: ScriptablePlayer) {
        guard case .failure(let code, let message) = outcome else { return }
        if code == AppleScriptOutcome.notPermitted {
            log.notice("Automation for \(player.name, privacy: .public) is off")
            onAutomationDenied(player)
        } else {
            log.debug("Script for \(player.name, privacy: .public) failed: \(code) \(message, privacy: .public)")
        }
    }

    nonisolated static func isRunning(_ player: ScriptablePlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    /// Wraps a script so it only runs while the player is running.
    nonisolated static func script(for player: ScriptablePlayer, _ body: String) -> String {
        """
        if application id "\(player.bundleID)" is running then
        tell application id "\(player.bundleID)"
        \(body)
        end tell
        end if
        """
    }

    /// {title, artist, album, duration (s), position (s), state, favourite (Music) or artwork URL (Spotify)}.
    private nonisolated static func stateScript(_ player: ScriptablePlayer) -> String {
        switch player {
        case .music:
            """
            if player state is stopped then return {}
            set t to current track
            return {name of t, artist of t, album of t, duration of t, player position, player state as text, favorited of t}
            """
        case .spotify:
            """
            if player state is stopped then return {}
            set t to current track
            return {name of t, artist of t, album of t, (duration of t) / 1000, player position, player state as text, artwork url of t}
            """
        }
    }
}

/// Favourites in Apple Music (#15). Music's tracks have `favorited` on
/// macOS 27.2 (the older `loved` is gone).
struct MusicFavorites: Sendable {
    let runner: AppleScriptRunner

    /// Nil when Music isn't running, isn't playing, or Automation is off.
    func isFavorited() async -> AppleScriptOutcome {
        await runner.run(ScriptingNowPlayingProvider.script(for: .music, "return favorited of current track"))
    }

    func setFavorited(_ value: Bool) async -> AppleScriptOutcome {
        await runner.run(ScriptingNowPlayingProvider.script(
            for: .music, "set favorited of current track to \(value)\nreturn favorited of current track"))
    }
}
