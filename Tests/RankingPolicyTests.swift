// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The user's priority (#8): which class wins the island, and which modules
/// are pinned above the rest. System activities (a call) always come first.
@Suite("RankingPolicy")
struct RankingPolicyTests {
    private func key(_ policy: RankingPolicy, _ kind: ActivityKind, _ module: ModuleID = "m") -> RankingPolicy.Key {
        policy.key(kind: kind, module: module)
    }

    @Test("The default order is ADR-0011: system, media, live, passive")
    func defaultOrder() {
        let policy = RankingPolicy.default
        #expect(key(policy, .system) < key(policy, .media))
        #expect(key(policy, .media) < key(policy, .live))
        #expect(key(policy, .live) < key(policy, .passive))
    }

    @Test("The user can put live above media, or passive above media")
    func reorderedClasses() {
        let liveFirst = RankingPolicy(order: [.live, .media, .passive], pinned: [])
        #expect(key(liveFirst, .live) < key(liveFirst, .media))
        let passiveFirst = RankingPolicy(order: [.passive, .live, .media], pinned: [])
        #expect(key(passiveFirst, .passive) < key(passiveFirst, .media))
    }

    @Test("System activities stay first under any order or pin")
    func systemAlwaysFirst() {
        let policy = RankingPolicy(order: [.passive, .live, .media], pinned: ["timers"])
        #expect(key(policy, .system, "calls") < key(policy, .passive))
        #expect(key(policy, .system, "calls") < key(policy, .live, "timers"))
        // Pinning a module that posts system activities doesn't change that.
        let pinnedCall = RankingPolicy(order: RankingPolicy.default.order, pinned: ["calls"])
        #expect(key(pinnedCall, .system, "calls") == key(pinnedCall, .system, "other"))
    }

    @Test("A pinned module beats every class below system, in pin order")
    func pinsBeatClasses() {
        let policy = RankingPolicy(order: RankingPolicy.default.order, pinned: ["timers", "downloads"])
        #expect(key(policy, .live, "timers") < key(policy, .media, "music"))
        #expect(key(policy, .live, "downloads") < key(policy, .media, "music"))
        #expect(key(policy, .live, "timers") < key(policy, .live, "downloads"))
        #expect(key(policy, .system) < key(policy, .live, "timers"))
    }

    @Test("A pin for a module that isn't there changes nothing")
    func unknownPin() {
        let policy = RankingPolicy(order: RankingPolicy.default.order, pinned: ["gone"])
        #expect(key(policy, .media, "music") < key(policy, .live, "timers"))
    }

    @Test("Normalising repairs a bad order: drops system and duplicates, adds missing classes in their default slot")
    func normalizes() {
        #expect(RankingPolicy(order: [.system, .live, .live, .media, .passive], pinned: []).normalized().order == [.live, .media, .passive])
        #expect(RankingPolicy(order: [.live, .passive], pinned: []).normalized().order == [.media, .live, .passive])
        #expect(RankingPolicy(order: [], pinned: []).normalized().order == [.media, .live, .passive])
        #expect(RankingPolicy(order: [.passive, .live], pinned: []).normalized().order == [.media, .passive, .live])
        #expect(RankingPolicy(order: [.media, .live, .passive], pinned: ["a", "b", "a"]).normalized().pinned == ["a", "b"])
    }

    @Test("A policy round-trips through JSON by name")
    func codableRoundTrip() throws {
        let policy = RankingPolicy(order: [.live, .media, .passive], pinned: ["timers"])
        let data = try JSONEncoder().encode(policy)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"live\""))
        #expect(try JSONDecoder().decode(RankingPolicy.self, from: data) == policy)
    }

    @Test("Saved data that is corrupt, from the future or empty falls back to the default")
    func loadingBadData() {
        #expect(RankingPolicy.load(from: nil) == .default)
        #expect(RankingPolicy.load(from: Data("not json".utf8)) == .default)
        #expect(RankingPolicy.load(from: Data(#"{"order":["bogus"],"pinned":[]}"#.utf8)) == .default)
        // A module id is saved as {"rawValue": …}; a bare string isn't that format.
        #expect(RankingPolicy.load(from: Data(#"{"order":["passive","live","media"],"pinned":["x"]}"#.utf8)) == .default)
    }

    @Test("Loading reads what was saved, and normalises it")
    func loadingNormalizes() {
        let json = #"{"order":["system","passive","live"],"pinned":[{"rawValue":"x"},{"rawValue":"x"}]}"#
        let loaded = RankingPolicy.load(from: Data(json.utf8))
        #expect(loaded.order == [.media, .passive, .live])
        #expect(loaded.pinned == ["x"])
        #expect(loaded != .default)
    }

    @Test("Moving a class stops at the ends and keeps the others in order")
    func movingClasses() {
        let policy = RankingPolicy.default
        #expect(policy.moving(.live, by: -1).order == [.live, .media, .passive])
        #expect(policy.moving(.live, by: -5).order == [.live, .media, .passive])
        #expect(policy.moving(.media, by: 1).order == [.live, .media, .passive])
        #expect(policy.moving(.passive, by: 3).order == [.media, .live, .passive])
        #expect(policy.moving(.system, by: -1).order == policy.order)
    }

    @Test("Pinning adds below existing pins, once; unpinning removes; pins move within their list")
    func editingPins() {
        var policy = RankingPolicy.default.pinning("timers").pinning("downloads").pinning("timers")
        #expect(policy.pinned == ["timers", "downloads"])
        policy = policy.movingPin("downloads", by: -1)
        #expect(policy.pinned == ["downloads", "timers"])
        policy = policy.movingPin("downloads", by: -3)
        #expect(policy.pinned == ["downloads", "timers"])
        policy = policy.movingPin("nope", by: 1)
        #expect(policy.pinned == ["downloads", "timers"])
        #expect(policy.unpinning("downloads").pinned == ["timers"])
    }
}
