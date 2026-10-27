// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// A source of Now Playing information and a way to control it (#9, #10).
/// Providers report on the main actor; nil means nothing is playing.
@MainActor
protocol NowPlayingProvider: AnyObject {
    var onUpdate: (NowPlayingSnapshot?) -> Void { get set }
    func start()
    /// Releases every process, observer and pending task.
    func stop()
    func send(_ command: MediaCommand)
}

/// The players the scripting fallback understands.
enum ScriptablePlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var bundleID: String { rawValue }

    var name: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// The distributed notification the app posts when playback changes.
    var notificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

/// What a player's own playback notification says. Parsed from `userInfo`
/// before it leaves the notification's thread, so it is `Sendable`.
struct PlayerNotificationInfo: Equatable, Sendable {
    enum State: String, Sendable {
        case playing = "Playing"
        case paused = "Paused"
        case stopped = "Stopped"
    }

    var player: ScriptablePlayer
    var state: State
    var title: String?
    var artist: String?
    var album: String?
    /// Seconds.
    var duration: TimeInterval?
    /// Seconds, when the player includes it (Spotify does, Music doesn't).
    var position: TimeInterval?

    init(player: ScriptablePlayer, state: State, title: String? = nil, artist: String? = nil, album: String? = nil,
         duration: TimeInterval? = nil, position: TimeInterval? = nil) {
        self.player = player
        self.state = state
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
    }

    /// Music: Name, Artist, Album, Player State, Total Time (ms).
    /// Spotify: Name, Artist, Album, Player State, Duration (ms), Playback Position (s).
    init?(player: ScriptablePlayer, userInfo: [AnyHashable: Any]?) {
        guard let userInfo, let state = (userInfo["Player State"] as? String).flatMap(State.init(rawValue:)) else { return nil }
        let milliseconds = { (key: String) in (userInfo[key] as? NSNumber).map { $0.doubleValue / 1000 } }
        self.init(
            player: player,
            state: state,
            title: userInfo["Name"] as? String,
            artist: userInfo["Artist"] as? String,
            album: userInfo["Album"] as? String,
            duration: (player == .music ? milliseconds("Total Time") : milliseconds("Duration")).flatMap { $0 > 0 ? $0 : nil },
            position: (userInfo["Playback Position"] as? NSNumber)?.doubleValue
        )
    }
}

/// Watches Music's and Spotify's own playback notifications, which need no
/// permission. Used by the scripting fallback, and in Automatic mode to
/// notice when the adapter has stopped working (a player says it's playing
/// but the adapter sees nothing).
@MainActor
final class PlayerNotificationWatcher {
    /// A player's new state, or nil info when it quit.
    var onEvent: (ScriptablePlayer, PlayerNotificationInfo?) -> Void = { _, _ in }
    private var tokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    func start() {
        guard tokens.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        for player in ScriptablePlayer.allCases {
            let token = distributed.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                let info = PlayerNotificationInfo(player: player, userInfo: note.userInfo)
                MainActor.assumeIsolated { self?.onEvent(player, info) }
            }
            tokens.append((distributed, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let token = workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let player = bundleID.flatMap(ScriptablePlayer.init(rawValue:)) else { return }
                self?.onEvent(player, nil)
            }
        }
        tokens.append((workspace, token))
    }

    func stop() {
        for entry in tokens { entry.center.removeObserver(entry.token) }
        tokens.removeAll()
    }

    isolated deinit {
        stop()
    }
}
