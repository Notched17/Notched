// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// What to look up: LRCLIB matches on all four (#13).
struct LyricsQuery: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    /// Whole seconds; LRCLIB allows ±2 s.
    var duration: Int
}

enum LyricsFetchResult: Equatable, Sendable {
    /// LRC text with timestamps.
    case synced(String)
    /// Only unsynced lyrics exist, which the island doesn't show.
    case plainOnly
    case instrumental
    case notFound
}

/// Looks lyrics up somewhere; `LRCLIBClient` in the app, a spy in tests.
protocol LyricsFetching: Sendable {
    func fetch(_ query: LyricsQuery) async throws -> LyricsFetchResult
}

/// The cache key: the track normalised (trimmed, lowercased, whitespace
/// collapsed) with its duration rounded to whole seconds, so the same song
/// from two sources shares one entry.
struct LyricsCacheKey: Hashable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: Int

    init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = Self.normalise(title)
        self.artist = Self.normalise(artist)
        self.album = Self.normalise(album)
        self.duration = Int(duration.rounded())
    }

    /// A file name that reveals nothing about the track.
    var fileName: String {
        let digest = SHA256.hash(data: Data("\(title)\n\(artist)\n\(album)\n\(duration)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    private static func normalise(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Synced lyrics for the current track, from a disk cache or LRCLIB (#13).
///
/// Privacy rule (ADR-0009): while `isEnabled` is false the store answers nil
/// without touching the network or the cache. The module only creates a
/// store at all while lyrics are on.
@MainActor
final class LyricsStore {
    var isEnabled = false

    private let fetcher: any LyricsFetching
    private let cacheDirectory: URL
    private let now: () -> Date
    private let log = Log.module("media")
    /// Not-found results are retried after a week, in case lyrics were added.
    private static let notFoundLifetime: TimeInterval = 7 * 24 * 3600

    private struct CacheEntry: Codable {
        /// Nil when there are no synced lyrics.
        var lrc: String?
        var savedAt: Date
    }

    private var memory: [LyricsCacheKey: CacheEntry] = [:]

    init(fetcher: any LyricsFetching, cacheDirectory: URL, now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.cacheDirectory = cacheDirectory
        self.now = now
    }

    /// The default cache: ~/Library/Caches/me.rkck.Notched/Lyrics.
    static var defaultCacheDirectory: URL {
        URL.cachesDirectory.appending(path: "me.rkck.Notched/Lyrics", directoryHint: .isDirectory)
    }

    func lyrics(for snapshot: NowPlayingSnapshot) async -> SyncedLyrics? {
        guard isEnabled, let duration = snapshot.timeline.duration, let artist = snapshot.artist else { return nil }
        let key = LyricsCacheKey(title: snapshot.title, artist: artist, album: snapshot.album ?? "", duration: duration)
        if let entry = cached(key) { return entry.lrc.map(LRCParser.parse) }

        let query = LyricsQuery(title: snapshot.title, artist: artist, album: snapshot.album ?? "", duration: key.duration)
        let result: LyricsFetchResult
        do {
            result = try await fetcher.fetch(query)
        } catch {
            // Network errors aren't cached, so the next play tries again.
            log.notice("Lyrics lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard isEnabled else { return nil }
        let lrc: String? = if case .synced(let text) = result { text } else { nil }
        store(CacheEntry(lrc: lrc, savedAt: now()), for: key)
        return lrc.map(LRCParser.parse)
    }

    // MARK: Cache

    private func cached(_ key: LyricsCacheKey) -> CacheEntry? {
        let entry = memory[key] ?? load(key)
        guard let entry else { return nil }
        if entry.lrc == nil && now().timeIntervalSince(entry.savedAt) > Self.notFoundLifetime { return nil }
        memory[key] = entry
        return entry
    }

    private func load(_ key: LyricsCacheKey) -> CacheEntry? {
        guard let data = try? Data(contentsOf: cacheDirectory.appending(path: key.fileName)) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    private func store(_ entry: CacheEntry, for key: LyricsCacheKey) {
        memory[key] = entry
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: cacheDirectory.appending(path: key.fileName), options: .atomic)
        } catch {
            log.notice("Couldn't cache lyrics: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The LRCLIB API (https://lrclib.net/docs): free, no account, no key.
struct LRCLIBClient: LyricsFetching {
    private static let endpoint = URL(string: "https://lrclib.net/api/get")!
    /// One ephemeral session for the app's life: no cookies, no disk cache.
    private static let session = URLSession(configuration: .ephemeral)

    func fetch(_ query: LyricsQuery) async throws -> LyricsFetchResult {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "album_name", value: query.album),
            URLQueryItem(name: "duration", value: String(query.duration)),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        // LRCLIB asks clients to identify themselves.
        request.setValue("Notched \(version) (https://github.com/charlieauchter/notched)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return .notFound }
        guard status == 200 else { throw URLError(.badServerResponse) }
        struct Body: Decodable {
            var instrumental: Bool?
            var syncedLyrics: String?
            var plainLyrics: String?
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        if body.instrumental == true { return .instrumental }
        if let synced = body.syncedLyrics, !synced.isEmpty { return .synced(synced) }
        return body.plainLyrics?.isEmpty == false ? .plainOnly : .notFound
    }
}
