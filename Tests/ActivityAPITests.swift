// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

private let now = Date(timeIntervalSinceReferenceDate: 100_000)

private func parse(_ json: String, at date: Date = now) -> Result<ActivitySpec, APIFieldError> {
    ActivityPayload.parse(Data(json.utf8), now: date)
}

private func spec(of json: String, _ comment: Comment? = nil) -> ActivitySpec? {
    if case .success(let spec) = parse(json) { return spec }
    return nil
}

private func failure(of json: String) -> APIFieldError? {
    if case .failure(let error) = parse(json) { return error }
    return nil
}

@Suite("ActivityPayload")
struct ActivityPayloadTests {
    @Test("A minimal status activity gets sensible defaults")
    func minimal() {
        let spec = spec(of: #"{"template":"status","title":"Deploy"}"#)
        #expect(spec?.title == "Deploy")
        #expect(spec?.tint == .white)
        #expect(spec?.alert == false)
        #expect(spec?.isPassive == false)
        #expect(spec?.staleAfter == 600)
        #expect(spec?.expiresAfter == 3600)
        #expect(spec?.progress == nil)
    }

    @Test("Every field is read")
    func everything() {
        let json = """
        {"template":"progress","title":"Build","subtitle":"Compiling","symbol":"hammer.fill","tint":"orange",
         "progress":0.42,"trailing":"42%","openURL":"https://ci.example.com/run/1","alert":true,"kind":"passive",
         "staleAfter":30,"expiresAfter":120}
        """
        let spec = spec(of: json)
        #expect(spec?.subtitle == "Compiling")
        #expect(spec?.symbol == "hammer.fill")
        #expect(spec?.tint == .orange)
        #expect(spec?.progress == 0.42)
        #expect(spec?.trailing == "42%")
        #expect(spec?.openURL?.host == "ci.example.com")
        #expect(spec?.alert == true)
        #expect(spec?.isPassive == true)
        #expect(spec?.staleAfter == 30)
        #expect(spec?.expiresAfter == 120)
    }

    @Test("Numbers are clamped")
    func clamping() {
        #expect(spec(of: #"{"template":"progress","title":"x","progress":7}"#)?.progress == 1)
        #expect(spec(of: #"{"template":"progress","title":"x","progress":-3}"#)?.progress == 0)
        #expect(spec(of: #"{"template":"status","title":"x","staleAfter":1}"#)?.staleAfter == 10)
        #expect(spec(of: #"{"template":"status","title":"x","staleAfter":99999999}"#)?.staleAfter == 14_400)
        #expect(spec(of: #"{"template":"status","title":"x","expiresAfter":5}"#)?.expiresAfter == 60)
        #expect(spec(of: #"{"template":"status","title":"x","expiresAfter":1e300}"#)?.expiresAfter == 28_800)
    }

    @Test("Required fields are enforced per template")
    func required() {
        #expect(failure(of: #"{"title":"x"}"#)?.field == "template")
        #expect(failure(of: #"{"template":"video","title":"x"}"#)?.field == "template")
        #expect(failure(of: #"{"template":"status"}"#)?.field == "title")
        #expect(failure(of: #"{"template":"status","title":"   "}"#)?.field == "title")
        #expect(failure(of: #"{"template":"progress","title":"x"}"#)?.field == "progress")
        #expect(failure(of: #"{"template":"countdown","title":"x"}"#)?.field == "endsAt")
    }

    @Test("Types are checked: strings aren't numbers and booleans aren't numbers")
    func types() {
        #expect(failure(of: #"{"template":"progress","title":"x","progress":"0.5"}"#)?.field == "progress")
        #expect(failure(of: #"{"template":"progress","title":"x","progress":true}"#)?.field == "progress")
        #expect(failure(of: #"{"template":"status","title":"x","alert":1}"#)?.field == "alert")
        #expect(failure(of: #"{"template":"status","title":5}"#)?.field == "title")
        #expect(failure(of: #"{"template":"status","title":"x","kind":"system"}"#)?.field == "kind")
        #expect(failure(of: ##"{"template":"status","title":"x","tint":"#ff0000"}"##)?.field == "tint")
    }

    @Test("Symbols must look like SF Symbol names")
    func symbols() {
        #expect(ActivityPayload.isValidSymbolName("bolt.fill"))
        #expect(ActivityPayload.isValidSymbolName("1.circle"))
        #expect(!ActivityPayload.isValidSymbolName(""))
        #expect(!ActivityPayload.isValidSymbolName("Bolt"))
        #expect(!ActivityPayload.isValidSymbolName("../../x"))
        #expect(!ActivityPayload.isValidSymbolName("a b"))
        #expect(!ActivityPayload.isValidSymbolName(String(repeating: "a", count: 65)))
        #expect(failure(of: #"{"template":"status","title":"x","symbol":"<b>"}"#)?.field == "symbol")
    }

    @Test("Only http and https links are accepted")
    func urls() {
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "notched://timer?minutes=1", "ftp://x.example", "https://", "//evil.example", "https:///x", String(repeating: "a", count: 600)] {
            #expect(failure(of: #"{"template":"status","title":"x","openURL":"\#(bad)"}"#)?.field == "openURL", "\(bad)")
        }
        #expect(spec(of: #"{"template":"status","title":"x","openURL":"http://localhost:3000/x"}"#) != nil)
    }

    @Test("countdown: endsAt must be 1 s to 24 h ahead, in ISO 8601")
    func countdown() {
        func json(_ offset: TimeInterval) -> String {
            let stamp = (now + offset).formatted(.iso8601)
            return #"{"template":"countdown","title":"x","endsAt":"\#(stamp)"}"#
        }
        #expect(spec(of: json(600))?.endsAt != nil)
        #expect(failure(of: json(0))?.field == "endsAt")
        #expect(failure(of: json(-60))?.field == "endsAt")
        #expect(failure(of: json(25 * 3600))?.field == "endsAt")
        #expect(failure(of: #"{"template":"countdown","title":"x","endsAt":"tomorrow"}"#)?.field == "endsAt")
        #expect(ActivityPayload.parseDate("2026-10-29T10:30:00.250Z") != nil)
        #expect(ActivityPayload.parseDate("2026-10-29T10:30:00Z") != nil)
    }

    @Test("Text is plain: control characters, bidi overrides and newlines are cleaned and length is capped")
    func sanitising() {
        #expect(ActivityPayload.sanitize("a\u{202E}b\u{0007}c\u{200B}d", limit: 40) == "abcd")
        #expect(ActivityPayload.sanitize("one\ntwo\r\n  three\tfour", limit: 40) == "one two three four")
        #expect(ActivityPayload.sanitize("  padded  ", limit: 40) == "padded")
        #expect(ActivityPayload.sanitize(String(repeating: "x", count: 100), limit: 40).count == 40)
        #expect(ActivityPayload.sanitize("<b>bold</b> **x** [l](http://e)", limit: 80) == "<b>bold</b> **x** [l](http://e)")
        let spec = spec(of: #"{"template":"status","title":"Hi‮there\nyou"}"#)
        #expect(spec?.title == "Hithere you")
    }

    @Test("Activity ids: 1-64 of letters, digits, dot, dash, underscore")
    func ids() {
        #expect(ActivityPayload.isValidID("build-42.main_x"))
        #expect(!ActivityPayload.isValidID(""))
        #expect(!ActivityPayload.isValidID("a/b"))
        #expect(!ActivityPayload.isValidID("a b"))
        #expect(!ActivityPayload.isValidID("é"))
        #expect(!ActivityPayload.isValidID(String(repeating: "a", count: 65)))
        #expect(ActivityPayload.isValidID(String(repeating: "a", count: 64)))
    }

    @Test("Not JSON, or not an object, is an invalid_json error")
    func notJSON() {
        for body in ["", "nope", "[1,2]", "42", "\"x\"", "{", #"{"a":"#, "null"] {
            #expect(failure(of: body)?.code == "invalid_json", "\(body.debugDescription)")
        }
    }

    @Test("Fuzz: mutated payloads and random bytes always give a result and never crash")
    func fuzz() {
        var seed: UInt64 = 42
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
        let base = Array(#"{"template":"progress","title":"Build","subtitle":"Compiling","symbol":"hammer.fill","tint":"orange","progress":0.42,"trailing":"42%","openURL":"https://ci.example.com/run/1","alert":true,"kind":"passive","staleAfter":30,"expiresAfter":120}"#.utf8)
        var accepted = 0
        for _ in 0..<4000 {
            var bytes = base
            for _ in 0..<(Int(next() % 5) + 1) {
                let index = Int(next() % UInt64(bytes.count))
                switch next() % 3 {
                case 0: bytes[index] = UInt8(truncatingIfNeeded: next())
                case 1: bytes.remove(at: index)
                default: bytes.insert(UInt8(truncatingIfNeeded: next()), at: index)
                }
                if bytes.isEmpty { bytes = [0x7B] }
            }
            if case .success(let spec) = ActivityPayload.parse(Data(bytes), now: now) {
                accepted += 1
                #expect(spec.title.count <= ActivityPayload.titleLimit)
                #expect((spec.subtitle?.count ?? 0) <= ActivityPayload.subtitleLimit)
                #expect((0...1).contains(spec.progress ?? 0))
                #expect((10...14_400).contains(spec.staleAfter))
                #expect((60...28_800).contains(spec.expiresAfter))
                #expect(spec.openURL == nil || ["http", "https"].contains(spec.openURL?.scheme))
            }
        }
        #expect(accepted > 0)
        for _ in 0..<1000 {
            _ = ActivityPayload.parse(Data((0..<Int(next() % 200)).map { _ in UInt8(truncatingIfNeeded: next()) }), now: now)
        }
    }

    @Test("Banners are validated too")
    func banners() {
        if case .success(let banner) = ActivityPayload.parseBanner(Data(#"{"title":"Done","subtitle":"ok","symbol":"checkmark","tint":"green"}"#.utf8)) {
            #expect(banner.title == "Done")
            #expect(banner.tint == .green)
        } else {
            Issue.record("expected a banner")
        }
        for bad in ["{}", #"{"title":""}"#, #"{"title":"x","tint":"pink-ish"}"#, #"{"title":"x","symbol":"A B"}"#, "nope"] {
            guard case .failure = ActivityPayload.parseBanner(Data(bad.utf8)) else { Issue.record("accepted \(bad)"); continue }
        }
        if case .success(let long) = ActivityPayload.parseBanner(Data((#"{"title":""# + String(repeating: "a", count: 100) + #""}"#).utf8)) {
            #expect(long.title.count == 24)
        }
    }
}

@Suite("ActivityAPIReducer")
struct ActivityAPIReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 200_000)
    let key = ActivityKey(clientID: "c1", id: "build")

    private func make(alert: Bool = false, expires: TimeInterval = 3600, endsAt: Date? = nil) -> ActivitySpec {
        ActivitySpec(template: endsAt == nil ? .status : .countdown, title: "T", subtitle: nil, symbol: nil, tint: .white, progress: nil,
                     endsAt: endsAt, trailing: nil, openURL: nil, alert: alert, isPassive: false, staleAfter: 600, expiresAfter: expires)
    }

    private func posts(_ effects: [ActivityAPIReducer.Effect]) -> [(ActivityKey, Bool)] {
        effects.compactMap { if case .post(let key, _, let alert) = $0 { (key, alert) } else { nil } }
    }

    @Test("A new activity is created, then updated in place")
    func createUpdate() {
        var sut = ActivityAPIReducer()
        let first = sut.reduce(.put(key, make(), clientName: "CI"), now: t0)
        #expect(first.contains(.accepted(created: true)))
        #expect(posts(first).count == 1)
        let second = sut.reduce(.put(key, make(), clientName: "CI"), now: t0 + 5)
        #expect(second.contains(.accepted(created: false)))
        #expect(sut.entries.count == 1)
        #expect(sut.entries[key]?.createdAt == t0)
        #expect(sut.entries[key]?.updatedAt == t0 + 5)
    }

    @Test("Two clients can use the same id")
    func separateClients() {
        var sut = ActivityAPIReducer()
        _ = sut.reduce(.put(key, make(), clientName: "A"), now: t0)
        _ = sut.reduce(.put(ActivityKey(clientID: "c2", id: "build"), make(), clientName: "B"), now: t0)
        #expect(sut.entries.count == 2)
    }

    @Test("A client can hold five activities; the sixth is refused with 409, but updates still work")
    func cap() {
        var sut = ActivityAPIReducer()
        for index in 0..<5 { _ = sut.reduce(.put(ActivityKey(clientID: "c1", id: "a\(index)"), make(), clientName: "A"), now: t0) }
        let sixth = sut.reduce(.put(ActivityKey(clientID: "c1", id: "a5"), make(), clientName: "A"), now: t0)
        #expect(sixth.contains { if case .rejected(let r) = $0 { r.status == 409 && r.code == "too_many_activities" } else { false } })
        #expect(sut.entries.count == 5)
        let update = sut.reduce(.put(ActivityKey(clientID: "c1", id: "a0"), make(), clientName: "A"), now: t0 + 1)
        #expect(update.contains(.accepted(created: false)))
        #expect(sut.reduce(.put(ActivityKey(clientID: "c2", id: "x"), make(), clientName: "B"), now: t0).contains(.accepted(created: true)))
    }

    @Test("Alerts: one per client per 30 s; the rest post as plain updates")
    func alerts() {
        var sut = ActivityAPIReducer()
        let a = posts(sut.reduce(.put(key, make(alert: true), clientName: "A"), now: t0))
        let b = posts(sut.reduce(.put(key, make(alert: true), clientName: "A"), now: t0 + 10))
        let c = posts(sut.reduce(.put(key, make(alert: true), clientName: "A"), now: t0 + 31))
        let other = posts(sut.reduce(.put(ActivityKey(clientID: "c2", id: "x"), make(alert: true), clientName: "B"), now: t0 + 10))
        let none = posts(sut.reduce(.put(key, make(alert: false), clientName: "A"), now: t0 + 100))
        #expect(a.first?.1 == true)
        #expect(b.first?.1 == false)
        #expect(c.first?.1 == true)
        #expect(other.first?.1 == true)
        #expect(none.first?.1 == false)
    }

    @Test("Delete ends it; deleting something unknown is a 404")
    func delete() {
        var sut = ActivityAPIReducer()
        _ = sut.reduce(.put(key, make(), clientName: "A"), now: t0)
        let ended = sut.reduce(.delete(key), now: t0 + 1)
        #expect(ended.contains(.end(key, immediate: false)))
        #expect(sut.entries.isEmpty)
        #expect(sut.reduce(.delete(key), now: t0 + 2).contains { if case .rejected(let r) = $0 { r.status == 404 } else { false } })
    }

    @Test("An activity that isn't updated expires, and the wake points at the next expiry")
    func expiry() {
        var sut = ActivityAPIReducer()
        let created = sut.reduce(.put(key, make(expires: 100), clientName: "A"), now: t0)
        #expect(created.contains(.wake(t0 + 100)))
        let other = sut.reduce(.put(ActivityKey(clientID: "c1", id: "two"), make(expires: 50), clientName: "A"), now: t0)
        #expect(other.contains(.wake(t0 + 50)))
        let early = sut.reduce(.tick, now: t0 + 49)
        #expect(early == [.wake(t0 + 50)])
        let first = sut.reduce(.tick, now: t0 + 50)
        #expect(first.contains(.end(ActivityKey(clientID: "c1", id: "two"), immediate: false)))
        #expect(first.contains(.wake(t0 + 100)))
        let last = sut.reduce(.tick, now: t0 + 100)
        #expect(last.contains(.end(key, immediate: false)))
        #expect(last.contains(.wake(nil)))
        #expect(sut.entries.isEmpty)
    }

    @Test("Updating pushes the expiry out")
    func refreshExpiry() {
        var sut = ActivityAPIReducer()
        _ = sut.reduce(.put(key, make(expires: 100), clientName: "A"), now: t0)
        _ = sut.reduce(.put(key, make(expires: 100), clientName: "A"), now: t0 + 90)
        #expect(sut.reduce(.tick, now: t0 + 100).allSatisfy { if case .end = $0 { false } else { true } })
        #expect(sut.entries.count == 1)
    }

    @Test("A countdown ends a minute after it reaches zero")
    func countdownExpiry() {
        var sut = ActivityAPIReducer()
        _ = sut.reduce(.put(key, make(expires: 28_800, endsAt: t0 + 600), clientName: "A"), now: t0)
        #expect(sut.entries[key]?.expiresAt == t0 + 660)
    }

    @Test("Revoking a client ends all its activities at once, and only its own")
    func revoke() {
        var sut = ActivityAPIReducer()
        _ = sut.reduce(.put(key, make(), clientName: "A"), now: t0)
        _ = sut.reduce(.put(ActivityKey(clientID: "c1", id: "two"), make(), clientName: "A"), now: t0)
        _ = sut.reduce(.put(ActivityKey(clientID: "c2", id: "x"), make(), clientName: "B"), now: t0)
        let effects = sut.reduce(.revoke(clientID: "c1"), now: t0 + 1)
        let ended = effects.compactMap { if case .end(let key, let immediate) = $0 { (key.clientID, immediate) } else { nil } }
        #expect(ended.count == 2)
        #expect(ended.allSatisfy { $0.0 == "c1" && $0.1 })
        #expect(sut.entries.keys.map(\.clientID) == ["c2"])
    }

    @Test("Reset forgets everything without effects but a cancelled wake")
    func reset() {
        var sut = ActivityAPIReducer()
        _ = sut.reduce(.put(key, make(), clientName: "A"), now: t0)
        #expect(sut.reduce(.reset, now: t0) == [.wake(nil)])
        #expect(sut.entries.isEmpty)
    }
}
