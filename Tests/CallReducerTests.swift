// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("CallReducer")
struct CallReducerTests {
    typealias Reducer = CallReducer
    let t0 = Date(timeIntervalSinceReferenceDate: 50_000)
    let zoom = Reducer.App(id: "us.zoom.xos", name: "Zoom")
    let facetime = Reducer.App(id: "com.apple.FaceTime", name: "FaceTime")

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func model(_ app: Reducer.App, startedAt: TimeInterval?, camera: Bool = false) -> Reducer.Model {
        Reducer.Model(app: app, startedAt: startedAt.map(at), camera: camera)
    }

    /// A reducer past its first (empty) reading.
    private func running() -> Reducer {
        var reducer = Reducer()
        _ = reducer.reduce(.micUsers([]), now: t0)
        return reducer
    }

    /// A call that has been going since `start`, with the clock at `start + 1`.
    private func inCall(_ app: Reducer.App, start: TimeInterval = 10) -> Reducer {
        var reducer = running()
        _ = reducer.reduce(.micUsers([app]), now: at(start))
        _ = reducer.reduce(.tick, now: at(start + 1))
        return reducer
    }

    @Test("Mic use shorter than a second is not a call; the app is claimed meanwhile so no mic dot flashes")
    func shortMicUseIsNotACall() {
        var reducer = running()
        let started = reducer.reduce(.micUsers([zoom]), now: at(5))
        #expect(started == [.claims(CallClaims(identities: ["us.zoom.xos"], isCallActive: false)), .schedule(at(6))])
        let stopped = reducer.reduce(.micUsers([]), now: at(5.5))
        #expect(stopped == [.claims(CallClaims()), .schedule(nil)])
        #expect(reducer.reduce(.tick, now: at(6)).isEmpty)
    }

    @Test("A call starts after a second of continuous mic use, timed from when the mic started")
    func callStartsAfterOneSecond() {
        var reducer = running()
        _ = reducer.reduce(.micUsers([zoom]), now: at(5))
        let effects = reducer.reduce(.tick, now: at(6))
        #expect(effects == [.post(model(zoom, startedAt: 5)),
                            .claims(CallClaims(identities: ["us.zoom.xos"], isCallActive: true)), .schedule(nil)])
    }

    @Test("A call already running when the module starts shows at once, with no duration")
    func callAlreadyRunning() {
        var reducer = Reducer()
        let effects = reducer.reduce(.micUsers([zoom]), now: at(5))
        #expect(effects == [.post(model(zoom, startedAt: nil)),
                            .claims(CallClaims(identities: ["us.zoom.xos"], isCallActive: true))])
    }

    @Test("A mic gap of 2.9 s keeps the same call and its start time")
    func shortGapKeepsCall() {
        var reducer = inCall(zoom)
        #expect(reducer.reduce(.micUsers([]), now: at(20)) == [.schedule(at(23))])
        #expect(reducer.reduce(.micUsers([zoom]), now: at(22.9)) == [.schedule(nil)])
        #expect(reducer.reduce(.tick, now: at(23)).isEmpty)
    }

    @Test("A gap of 3.1 s ends the call, and the next use is a new call")
    func longGapEndsCall() {
        var reducer = inCall(zoom)
        _ = reducer.reduce(.micUsers([]), now: at(20))
        #expect(reducer.reduce(.tick, now: at(23.1)) == [.end("us.zoom.xos"), .claims(CallClaims()), .schedule(nil)])
        _ = reducer.reduce(.micUsers([zoom]), now: at(30))
        let effects = reducer.reduce(.tick, now: at(31))
        #expect(effects.first == .post(model(zoom, startedAt: 30)))
    }

    @Test("Two call apps at once are two calls, ending independently")
    func twoCallsAtOnce() {
        var reducer = inCall(zoom, start: 10)
        let second = reducer.reduce(.micUsers([zoom, facetime]), now: at(12))
        #expect(second == [.claims(CallClaims(identities: ["us.zoom.xos", "com.apple.FaceTime"], isCallActive: true)), .schedule(at(13))])
        let started = reducer.reduce(.tick, now: at(13))
        #expect(started.first == .post(model(facetime, startedAt: 12)))
        _ = reducer.reduce(.micUsers([facetime]), now: at(20))
        let ended = reducer.reduce(.tick, now: at(23))
        #expect(ended == [.end("us.zoom.xos"),
                          .claims(CallClaims(identities: ["com.apple.FaceTime"], isCallActive: true)), .schedule(nil)])
    }

    @Test("A call app quitting ends its call at once, with no grace")
    func appQuitEndsAtOnce() {
        var reducer = inCall(zoom)
        #expect(reducer.reduce(.appQuit("us.zoom.xos"), now: at(15)) == [.end("us.zoom.xos"), .claims(CallClaims())])
    }

    @Test("Quitting some other app changes nothing")
    func otherAppQuitIsIgnored() {
        var reducer = inCall(zoom)
        #expect(reducer.reduce(.appQuit("com.example.other"), now: at(15)).isEmpty)
    }

    @Test("The camera shows on the call while it runs, and the call updates in place")
    func cameraMerges() {
        var reducer = inCall(zoom)
        #expect(reducer.reduce(.camera(true), now: at(15)) == [.post(model(zoom, startedAt: 10, camera: true))])
        #expect(reducer.reduce(.camera(true), now: at(16)).isEmpty)
        #expect(reducer.reduce(.camera(false), now: at(17)) == [.post(model(zoom, startedAt: 10))])
    }

    @Test("The camera on with no call changes nothing here")
    func cameraWithoutCall() {
        var reducer = running()
        #expect(reducer.reduce(.camera(true), now: at(5)).isEmpty)
    }

    @Test("A different helper process of the same app is the same call")
    func sameAppSameCall() {
        var reducer = inCall(zoom)
        #expect(reducer.reduce(.micUsers([zoom]), now: at(20)).isEmpty)
    }

    @Test("After wake a call that is still using the mic carries on; one that isn't ends at once")
    func wakeReconciles() {
        var reducer = inCall(zoom, start: 10)
        _ = reducer.reduce(.wake, now: at(500))
        #expect(reducer.reduce(.micUsers([zoom]), now: at(501)).isEmpty)
        _ = reducer.reduce(.wake, now: at(600))
        #expect(reducer.reduce(.micUsers([]), now: at(601)) == [.end("us.zoom.xos"), .claims(CallClaims())])
    }

    @Test("Switching which apps count (settings) is just a different set of mic users")
    func appNoLongerCounting() {
        var reducer = inCall(zoom)
        _ = reducer.reduce(.micUsers([]), now: at(20))
        #expect(reducer.reduce(.tick, now: at(23)).first == .end("us.zoom.xos"))
    }

    @Test("However events arrive, calls are only ended after being posted, and everything settles")
    func fuzz() {
        var generator = SplitMix(seed: 0xCA11)
        let apps = [zoom, facetime]
        for _ in 0..<300 {
            var reducer = Reducer()
            var clock = t0
            var posted = Set<String>()
            var deadline: Date?
            func apply(_ effects: [Reducer.Effect]) {
                for effect in effects {
                    switch effect {
                    case .post(let model): posted.insert(model.app.id)
                    case .end(let id): #expect(posted.remove(id) != nil, "ended a call that wasn't posted")
                    case .claims: break
                    case .schedule(let date): deadline = date
                    }
                }
            }
            for _ in 0..<40 {
                clock += Double(generator.next() % 2500) / 1000
                let event: Reducer.Event
                switch generator.next() % 6 {
                case 0, 1: event = .micUsers(Set(apps.filter { _ in generator.next() % 2 == 0 }))
                case 2: event = .appQuit(apps[Int(generator.next() % 2)].id)
                case 3: event = .camera(generator.next() % 2 == 0)
                case 4: event = .wake
                default: event = .tick
                }
                apply(reducer.reduce(event, now: clock))
            }
            apply(reducer.reduce(.micUsers([]), now: clock))
            for _ in 0..<4 {
                clock += 5
                apply(reducer.reduce(.tick, now: clock))
            }
            #expect(posted.isEmpty, "a call outlived its mic use: \(posted)")
            #expect(deadline == nil, "a deadline was left behind")
        }
    }
}

@Suite("CallApps")
struct CallAppsTests {
    private func user(_ id: String, name: String? = nil, pid: Int32 = 1) -> InputUser {
        InputUser(pid: pid, processBundleID: id, appBundleID: id, appName: name, attribution: .exact)
    }

    @Test("Known call apps are recognised, with their own names")
    func knownApps() {
        let apps = CallApps.apps(from: [user("us.zoom.xos", name: "zoom.us"), user("com.apple.FaceTime"), user("com.hnc.Discord")], browsers: [])
        #expect(Set(apps.map(\.name)) == ["Zoom", "FaceTime", "Discord"])
    }

    @Test("Other apps using the microphone are not calls")
    func otherAppsAreNotCalls() {
        #expect(CallApps.apps(from: [user("com.apple.VoiceMemos"), user("pid:9")], browsers: []).isEmpty)
    }

    @Test("A browser counts as a call only when the user has ticked it")
    func browsersNeedTicking() {
        let chrome = user("com.google.Chrome")
        #expect(CallApps.apps(from: [chrome], browsers: []).isEmpty)
        #expect(CallApps.apps(from: [chrome], browsers: ["com.google.Chrome"]).map(\.name) == ["Chrome"])
        #expect(CallApps.apps(from: [chrome], browsers: ["com.apple.Safari"]).isEmpty)
    }

    @Test("Both Teams generations are Microsoft Teams, and many processes of one app are one call app")
    func teamsAndDuplicates() {
        let apps = CallApps.apps(from: [user("com.microsoft.teams2", pid: 1), user("com.microsoft.teams", pid: 2),
                                        user("com.microsoft.teams2", pid: 3)], browsers: [])
        #expect(apps.count == 2)
        #expect(Set(apps.map(\.name)) == ["Microsoft Teams"])
    }

    @Test("Every id in the catalogue is unique across calls and browsers")
    func noOverlap() {
        #expect(Set(CallApps.known.keys).isDisjoint(with: CallApps.browsers.keys))
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
