// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("ClaudeSessionsReducer")
struct ClaudeSessionsReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 300_000)

    private func hook(_ kind: ClaudeHookEvent.Kind, session: String = "s1", project: String = "Notched", tool: String? = nil,
                      detail: String? = nil, suggestion: AlwaysAllowSuggestion? = nil) -> ClaudeHookEvent {
        ClaudeHookEvent(kind: kind, sessionID: session, cwd: "/x/\(project)", project: project, title: nil, toolName: tool, detail: detail, suggestion: suggestion)
    }

    private func snapshots(_ effects: [ClaudeSessionsReducer.Effect]) -> [(ClaudeSessionsReducer.Snapshot, Bool)] {
        effects.compactMap { if case .post(let snapshot, let alert) = $0 { (snapshot, alert) } else { nil } }
    }

    private func banners(_ effects: [ClaudeSessionsReducer.Effect]) -> [ClaudeSessionsReducer.Banner] {
        effects.compactMap { if case .banner(let banner, _) = $0 { banner } else { nil } }
    }

    private func replies(_ effects: [ClaudeSessionsReducer.Effect]) -> [(String, ClaudeHookReply?)] {
        effects.compactMap { if case .reply(let id, let reply) = $0 { (id, reply) } else { nil } }
    }

    private func ends(_ effects: [ClaudeSessionsReducer.Effect]) -> [(String, Bool)] {
        effects.compactMap { if case .end(let id, let immediate) = $0 { (id, immediate) } else { nil } }
    }

    @Test("A session sitting at its prompt shows nothing; a prompt starts 'working'")
    func startAndWork() {
        var sut = ClaudeSessionsReducer()
        let start = sut.reduce(.hook(hook(.sessionStart), approvalID: nil), now: t0)
        #expect(snapshots(start).isEmpty)
        let work = snapshots(sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0 + 1))
        #expect(work.count == 1)
        #expect(work.first?.0.phase == .working)
        #expect(work.first?.0.project == "Notched")
        #expect(work.first?.0.since == t0 + 1)
        #expect(work.first?.1 == false)
    }

    @Test("A permission request alerts, and Allow replies and goes back to working")
    func approvalAllow() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let request = snapshots(sut.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "npm test"), approvalID: "a1"), now: t0 + 5))
        #expect(request.first?.0.phase == .waitingForApproval)
        #expect(request.first?.0.approval?.detail == "npm test")
        #expect(request.first?.1 == true)

        let answer = sut.reduce(.answered(approvalID: "a1", .allow), now: t0 + 8)
        #expect(replies(answer).first?.0 == "a1")
        #expect(replies(answer).first?.1 == .allow)
        #expect(snapshots(answer).first?.0.phase == .working)
        #expect(snapshots(answer).first?.1 == false)
    }

    @Test("Each answer maps to the right reply")
    func answers() {
        let suggestion = AlwaysAllowSuggestion(json: Data("{}".utf8), label: "Bash(ls)")
        let cases: [(ClaudeSessionsReducer.Answer, ClaudeHookReply?)] = [
            (.allow, .allow),
            (.alwaysAllow, .alwaysAllow(suggestion)),
            (.deny, .deny(message: "Denied from Notched", interrupt: false)),
            (.denyAndStop, .deny(message: "Denied from Notched", interrupt: true)),
            (.terminal, nil),
        ]
        for (answer, expected) in cases {
            var sut = ClaudeSessionsReducer()
            _ = sut.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "ls", suggestion: suggestion), approvalID: "a"), now: t0)
            let effects = sut.reduce(.answered(approvalID: "a", answer), now: t0 + 1)
            #expect(replies(effects).first?.1 == expected, "\(answer)")
        }
    }

    @Test("Always Allow without a suggestion falls back to a plain allow")
    func alwaysWithoutSuggestion() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "ls"), approvalID: "a"), now: t0)
        #expect(replies(sut.reduce(.answered(approvalID: "a", .alwaysAllow), now: t0)).first?.1 == .allow)
    }

    @Test("Several requests queue in order, and only the first alerts")
    func queue() {
        var sut = ClaudeSessionsReducer()
        let first = snapshots(sut.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "one"), approvalID: "a1"), now: t0))
        let second = snapshots(sut.reduce(.hook(hook(.permissionRequest, tool: "Edit", detail: "two"), approvalID: "a2"), now: t0 + 1))
        #expect(first.first?.1 == true)
        #expect(second.first?.1 == false)
        #expect(second.first?.0.approval?.id == "a1")
        #expect(second.first?.0.moreApprovals == 1)
        let next = snapshots(sut.reduce(.answered(approvalID: "a1", .allow), now: t0 + 2))
        #expect(next.first?.0.phase == .waitingForApproval)
        #expect(next.first?.0.approval?.id == "a2")
        #expect(next.first?.1 == true)
    }

    @Test("When the hook hangs up the request disappears with no reply")
    func closed() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "ls"), approvalID: "a"), now: t0)
        let effects = sut.reduce(.approvalClosed(approvalID: "a"), now: t0 + 30)
        #expect(replies(effects).isEmpty)
        #expect(snapshots(effects).first?.0.approval == nil)
        #expect(snapshots(effects).first?.0.phase == .working)
        // A late answer for it is ignored.
        #expect(replies(sut.reduce(.answered(approvalID: "a", .allow), now: t0 + 31)).isEmpty)
    }

    @Test("Answering something unknown does nothing")
    func unknownAnswer() {
        var sut = ClaudeSessionsReducer()
        #expect(replies(sut.reduce(.answered(approvalID: "nope", .allow), now: t0)).isEmpty)
        #expect(replies(sut.reduce(.approvalClosed(approvalID: "nope"), now: t0)).isEmpty)
    }

    @Test("A long turn finishes with a banner; a short one with none and the island just goes away")
    func finish() {
        var long = ClaudeSessionsReducer()
        _ = long.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let done = long.reduce(.hook(hook(.stop), approvalID: nil), now: t0 + 30)
        #expect(banners(done) == [.finished(project: "Notched")])
        #expect(snapshots(done).first?.0.phase == .finished)

        var short = ClaudeSessionsReducer()
        _ = short.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let quick = short.reduce(.hook(hook(.stop), approvalID: nil), now: t0 + 4)
        #expect(banners(quick).isEmpty)
        #expect(snapshots(quick).isEmpty)
        #expect(ends(quick).first?.1 == true)
        #expect(short.sessions["s1"]?.phase == .idle)
    }

    @Test("A finished session leaves the island after a few seconds, but is remembered")
    func linger() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let done = sut.reduce(.hook(hook(.stop), approvalID: nil), now: t0 + 30)
        #expect(done.contains(.wake(t0 + 30 + ClaudeSessionsReducer.finishedLinger)))
        #expect(ends(sut.reduce(.tick, now: t0 + 35)).isEmpty)
        let later = sut.reduce(.tick, now: t0 + 39)
        #expect(ends(later).first?.1 == false)
        #expect(sut.sessions["s1"]?.phase == .idle)
        // A new prompt works again.
        #expect(snapshots(sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0 + 100)).first?.0.phase == .working)
    }

    @Test("Banners for one session are rate limited")
    func bannerCooldown() {
        var sut = ClaudeSessionsReducer()
        var count = 0
        for turn in 0..<3 {
            let start = t0 + Double(turn) * 15
            _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: start)
            count += banners(sut.reduce(.hook(hook(.stop), approvalID: nil), now: start + 12)).count
        }
        #expect(count == 2)
    }

    @Test("A stop failure shows its reason once and returns to idle")
    func failure() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let effects = sut.reduce(.hook(hook(.stopFailure(error: "rate_limit")), approvalID: nil), now: t0 + 3)
        #expect(banners(effects) == [.failed(project: "Notched", error: "rate_limit")])
        #expect(sut.sessions["s1"]?.phase == .idle)
        #expect(ends(effects).count == 1)
    }

    @Test("Idle prompt shows 'waiting for you' and no banner")
    func idlePrompt() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let effects = sut.reduce(.hook(hook(.notification(type: "idle_prompt")), approvalID: nil), now: t0 + 60)
        #expect(snapshots(effects).first?.0.phase == .waitingForInput)
        #expect(banners(effects).isEmpty)
        // A permission_prompt notification changes nothing.
        var pending = ClaudeSessionsReducer()
        _ = pending.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "ls"), approvalID: "a"), now: t0)
        #expect(snapshots(pending.reduce(.hook(hook(.notification(type: "permission_prompt")), approvalID: nil), now: t0 + 6)).isEmpty)
        #expect(pending.sessions["s1"]?.phase == .waitingForApproval)
    }

    @Test("Ending a session removes it and gives its pending requests 'no decision'")
    func sessionEnd() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "ls"), approvalID: "a"), now: t0)
        let effects = sut.reduce(.hook(hook(.sessionEnd(reason: "clear")), approvalID: nil), now: t0 + 1)
        #expect(replies(effects).count == 1)
        #expect(replies(effects).first?.1 == nil)
        #expect(ends(effects).first?.1 == true)
        #expect(sut.sessions.isEmpty)
    }

    @Test("Two sessions in one project are numbered; different projects are not")
    func naming() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit, session: "s1"), approvalID: nil), now: t0)
        _ = sut.reduce(.hook(hook(.userPromptSubmit, session: "s2"), approvalID: nil), now: t0 + 1)
        _ = sut.reduce(.hook(hook(.userPromptSubmit, session: "s3", project: "Other"), approvalID: nil), now: t0 + 2)
        #expect(sut.snapshot(of: "s1")?.displayName == "Notched (1)")
        #expect(sut.snapshot(of: "s2")?.displayName == "Notched (2)")
        #expect(sut.snapshot(of: "s3")?.displayName == "Other")
    }

    @Test("A session that goes silent for an hour is forgotten; one waiting for an approval is not")
    func watchdog() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        let wake = sut.reduce(.tick, now: t0 + 60).last
        #expect(wake == .wake(t0 + ClaudeSessionsReducer.forgetAfter))
        let forgotten = sut.reduce(.tick, now: t0 + ClaudeSessionsReducer.forgetAfter)
        #expect(ends(forgotten).first?.1 == false)
        #expect(sut.sessions.isEmpty)

        var waiting = ClaudeSessionsReducer()
        _ = waiting.reduce(.hook(hook(.permissionRequest, tool: "Bash", detail: "ls"), approvalID: "a"), now: t0)
        #expect(ends(waiting.reduce(.tick, now: t0 + 7200)).isEmpty)
        #expect(waiting.sessions["s1"] != nil)
    }

    @Test("Reset forgets everything quietly")
    func reset() {
        var sut = ClaudeSessionsReducer()
        _ = sut.reduce(.hook(hook(.userPromptSubmit), approvalID: nil), now: t0)
        #expect(sut.reduce(.reset, now: t0) == [.wake(nil)])
        #expect(sut.sessions.isEmpty)
    }

    @Test("Fuzz: random event sequences never crash, and every reply is for a real approval")
    func fuzz() {
        var seed: UInt64 = 7
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for _ in 0..<200 {
            var sut = ClaudeSessionsReducer()
            var clock = t0
            var issued: Set<String> = []
            var answered: Set<String> = []
            for step in 0..<60 {
                clock += Double(next(40))
                let session = "s\(next(3))"
                let event: ClaudeSessionsReducer.Event
                switch next(9) {
                case 0: event = .hook(hook(.userPromptSubmit, session: session), approvalID: nil)
                case 1:
                    let id = "a\(step)"
                    issued.insert(id)
                    event = .hook(hook(.permissionRequest, session: session, tool: "Bash", detail: "x"), approvalID: id)
                case 2: event = .hook(hook(.stop, session: session), approvalID: nil)
                case 3: event = .hook(hook(.sessionEnd(reason: "x"), session: session), approvalID: nil)
                case 4: event = .answered(approvalID: "a\(next(60))", .allow)
                case 5: event = .approvalClosed(approvalID: "a\(next(60))")
                case 6: event = .hook(hook(.notification(type: "idle_prompt"), session: session), approvalID: nil)
                case 7: event = .hook(hook(.stopFailure(error: "x"), session: session), approvalID: nil)
                default: event = .tick
                }
                for (id, _) in replies(sut.reduce(event, now: clock)) {
                    #expect(issued.contains(id))
                    #expect(!answered.contains(id), "\(id) answered twice")
                    answered.insert(id)
                }
            }
        }
    }
}
