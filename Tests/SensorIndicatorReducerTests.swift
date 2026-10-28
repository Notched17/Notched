// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("SensorIndicatorReducer")
struct SensorIndicatorReducerTests {
    typealias Reducer = SensorIndicatorReducer
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func user(_ name: String?, id: String, pid: Int32 = 1) -> InputUser {
        InputUser(pid: pid, processBundleID: id, appBundleID: name == nil ? nil : id, appName: name,
                  attribution: name == nil ? .unknown : .exact)
    }

    private func snapshot(camera: Bool = false, users: [InputUser] = [], unattributed: Bool = false) -> SensorSnapshot {
        SensorSnapshot(cameraRunning: camera, micUsers: users, micRunningUnattributed: unattributed)
    }

    private func model(camera: Bool = false, mic: Bool = false, apps: [String] = [], unnamed: Bool = false) -> Reducer.Model {
        Reducer.Model(camera: camera, mic: mic, micApps: apps, micHasUnnamedApp: unnamed)
    }

    /// A reducer that has seen its first (idle) snapshot.
    private func running() -> Reducer {
        var reducer = Reducer()
        _ = reducer.reduce(.snapshot(.idle), now: t0)
        return reducer
    }

    @Test("Nothing in use shows nothing")
    func idleShowsNothing() {
        var reducer = Reducer()
        #expect(reducer.reduce(.snapshot(.idle), now: t0).isEmpty)
    }

    @Test("A blip shorter than 500 ms shows nothing")
    func blipShowsNothing() {
        var reducer = running()
        #expect(reducer.reduce(.snapshot(snapshot(camera: true)), now: at(1)) == [.schedule(at(1.5))])
        #expect(reducer.reduce(.snapshot(snapshot(camera: false)), now: at(1.2)) == [.schedule(nil)])
        #expect(reducer.reduce(.tick, now: at(1.5)).isEmpty)
    }

    @Test("A steady signal shows after 500 ms")
    func steadyShowsAfterDebounce() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(camera: true)), now: at(1))
        #expect(reducer.reduce(.tick, now: at(1.5)) == [.post(model(camera: true)), .schedule(nil)])
    }

    @Test("A drop shorter than 500 ms keeps the indicator showing")
    func offBlipKeepsShowing() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(camera: true)), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        #expect(reducer.reduce(.snapshot(snapshot(camera: false)), now: at(3)) == [.schedule(at(3.5))])
        #expect(reducer.reduce(.snapshot(snapshot(camera: true)), now: at(3.2)) == [.schedule(nil)])
        #expect(reducer.reduce(.tick, now: at(3.5)).isEmpty)
    }

    @Test("A signal that stays off for 500 ms ends the indicator")
    func offAfterDebounceEnds() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(camera: true)), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        _ = reducer.reduce(.snapshot(snapshot(camera: false)), now: at(3))
        #expect(reducer.reduce(.tick, now: at(3.5)) == [.end, .schedule(nil)])
    }

    @Test("The microphone names only the apps that are proven, and says so when one isn't")
    func microphoneNames() {
        var reducer = running()
        let users = [user("Zoom", id: "us.zoom.xos", pid: 5), user(nil, id: "com.apple.avconferenced", pid: 6)]
        _ = reducer.reduce(.snapshot(snapshot(users: users)), now: at(1))
        #expect(reducer.reduce(.tick, now: at(1.5)) == [.post(model(mic: true, apps: ["Zoom"], unnamed: true)), .schedule(nil)])
    }

    @Test("Several processes of one app are one name, listed alphabetically")
    func namesAreUniqueAndSorted() {
        var reducer = running()
        let users = [user("Zoom", id: "us.zoom.xos", pid: 5), user("Voice Memos", id: "com.apple.VoiceMemos", pid: 7),
                     user("Zoom", id: "us.zoom.xos", pid: 6)]
        _ = reducer.reduce(.snapshot(snapshot(users: users)), now: at(1))
        let effects = reducer.reduce(.tick, now: at(1.5))
        #expect(effects.first == .post(model(mic: true, apps: ["Voice Memos", "Zoom"])))
    }

    @Test("A change of users while showing updates the activity in place, with no end")
    func usersChangeUpdatesInPlace() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(users: [user("Zoom", id: "us.zoom.xos")])), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        let next = [user("Zoom", id: "us.zoom.xos", pid: 1), user("Voice Memos", id: "com.apple.VoiceMemos", pid: 2)]
        #expect(reducer.reduce(.snapshot(snapshot(users: next)), now: at(4)) == [.post(model(mic: true, apps: ["Voice Memos", "Zoom"]))])
    }

    @Test("An identical snapshot does nothing")
    func identicalSnapshotIsQuiet() {
        var reducer = running()
        let on = snapshot(camera: true)
        _ = reducer.reduce(.snapshot(on), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        #expect(reducer.reduce(.snapshot(on), now: at(2)).isEmpty)
        #expect(reducer.reduce(.tick, now: at(3)).isEmpty)
    }

    // MARK: Calls

    @Test("A call hides its own app from the microphone, but a second app using it still shows")
    func callClaimsHideOnlyTheCallsApp() {
        var reducer = running()
        let users = [user("Zoom", id: "us.zoom.xos", pid: 1), user("Voice Memos", id: "com.apple.VoiceMemos", pid: 2)]
        _ = reducer.reduce(.snapshot(snapshot(users: users)), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        let effects = reducer.reduce(.claims(CallClaims(identities: ["us.zoom.xos"], isCallActive: true)), now: at(2))
        #expect(effects == [.post(model(mic: true, apps: ["Voice Memos"]))])
    }

    @Test("When the call is the only microphone user, the indicator goes after the debounce")
    func callAloneEndsIndicator() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(users: [user("Zoom", id: "us.zoom.xos")])), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        #expect(reducer.reduce(.claims(CallClaims(identities: ["us.zoom.xos"], isCallActive: true)), now: at(2)) == [.schedule(at(2.5))])
        #expect(reducer.reduce(.tick, now: at(2.5)) == [.end, .schedule(nil)])
    }

    @Test("The camera merges into an active call, and comes back after it if still on")
    func cameraMergesIntoCall() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(camera: true)), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        _ = reducer.reduce(.claims(CallClaims(identities: [], isCallActive: true)), now: at(2))
        #expect(reducer.reduce(.tick, now: at(2.5)) == [.end, .schedule(nil)])
        _ = reducer.reduce(.claims(CallClaims()), now: at(60))
        #expect(reducer.reduce(.tick, now: at(60.5)) == [.post(model(camera: true)), .schedule(nil)])
    }

    @Test("An unattributed microphone is the call's while a call is active")
    func unattributedFallbackDuringCall() {
        var reducer = running()
        _ = reducer.reduce(.claims(CallClaims(identities: [], isCallActive: true)), now: at(0.5))
        _ = reducer.reduce(.snapshot(snapshot(unattributed: true)), now: at(1))
        #expect(reducer.reduce(.tick, now: at(2)).isEmpty)
        _ = reducer.reduce(.claims(CallClaims()), now: at(3))
        #expect(reducer.reduce(.tick, now: at(3.5)) == [.post(model(mic: true, unnamed: true)), .schedule(nil)])
    }

    // MARK: First observation, sleep, settings

    @Test("What's already in use when the module starts shows at once, with no debounce")
    func firstObservationIsImmediate() {
        var reducer = Reducer()
        #expect(reducer.reduce(.snapshot(snapshot(camera: true)), now: t0) == [.post(model(camera: true))])
    }

    @Test("After wake the next snapshot is taken as it is: unchanged is quiet, changed is immediate")
    func wakeReseeds() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(camera: true)), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        #expect(reducer.reduce(.wake, now: at(100)).isEmpty)
        #expect(reducer.reduce(.snapshot(snapshot(camera: true)), now: at(101)).isEmpty)
        _ = reducer.reduce(.wake, now: at(200))
        #expect(reducer.reduce(.snapshot(snapshot(camera: false)), now: at(201)) == [.end])
    }

    @Test("Turning the microphone off in settings ends its indicator; the camera is unaffected")
    func preferencesSwitchSensorsOff() {
        var reducer = running()
        _ = reducer.reduce(.snapshot(snapshot(camera: true, users: [user("Zoom", id: "us.zoom.xos")])), now: at(1))
        _ = reducer.reduce(.tick, now: at(1.5))
        _ = reducer.reduce(.preferences(.init(showMicrophone: false, showCamera: true)), now: at(2))
        #expect(reducer.reduce(.tick, now: at(2.5)) == [.post(model(camera: true)), .schedule(nil)])
        _ = reducer.reduce(.preferences(.init(showMicrophone: false, showCamera: false)), now: at(3))
        #expect(reducer.reduce(.tick, now: at(3.5)) == [.end, .schedule(nil)])
    }

    @Test("Events before the first snapshot only remember their values")
    func eventsBeforeFirstSnapshot() {
        var reducer = Reducer()
        #expect(reducer.reduce(.claims(CallClaims(identities: ["x"], isCallActive: true)), now: t0).isEmpty)
        #expect(reducer.reduce(.preferences(.init(showMicrophone: true, showCamera: false)), now: t0).isEmpty)
        #expect(reducer.reduce(.tick, now: at(1)).isEmpty)
        #expect(reducer.reduce(.snapshot(snapshot(camera: true)), now: at(2)).isEmpty)
    }

    // MARK: Fuzz

    @Test("However events arrive, an activity is posted exactly while something is shown, and it ends once things settle")
    func fuzzSettlesCorrectly() {
        var generator = SplitMix(seed: 0xC0FFEE)
        for _ in 0..<200 {
            var reducer = Reducer()
            var clock = t0
            var posted = false
            var deadline: Date?
            func apply(_ effects: [Reducer.Effect]) {
                for effect in effects {
                    switch effect {
                    case .post: posted = true
                    case .end: #expect(posted, "ended an activity that wasn't posted"); posted = false
                    case .schedule(let date): deadline = date
                    }
                }
            }
            for _ in 0..<40 {
                clock += Double(generator.next() % 900) / 1000
                let event: Reducer.Event
                switch generator.next() % 6 {
                case 0:
                    event = .snapshot(snapshot(camera: generator.next() % 2 == 0,
                                               users: generator.next() % 2 == 0 ? [user("Zoom", id: "us.zoom.xos")] : [],
                                               unattributed: generator.next() % 5 == 0))
                case 1:
                    event = .claims(generator.next() % 2 == 0 ? CallClaims(identities: ["us.zoom.xos"], isCallActive: true) : CallClaims())
                case 2:
                    event = .preferences(.init(showMicrophone: generator.next() % 3 != 0, showCamera: generator.next() % 3 != 0))
                case 3: event = .wake
                default: event = .tick
                }
                apply(reducer.reduce(event, now: clock))
            }
            // Let everything settle: ticks past every deadline, with no new input.
            for _ in 0..<4 {
                clock += 1
                apply(reducer.reduce(.tick, now: clock))
            }
            #expect(deadline == nil, "a deadline was left behind")
        }
    }
}

/// A small deterministic generator, so a failing fuzz run can be replayed.
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
