// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The rules for Claude Code on the island (#63): which sessions are
/// working, which wait for an approval, when to say one finished. Pure; the
/// module turns hook calls into events and carries out the effects.
struct ClaudeSessionsReducer: Sendable {
    /// A turn shorter than this finishes without a banner.
    static let bannerAfterWork: TimeInterval = 10
    static let finishedLinger: TimeInterval = 8
    /// A banner for the same session at most this often.
    static let bannerCooldown: TimeInterval = 20
    /// With no hook call for this long, a working session looks outdated.
    static let staleAfter: TimeInterval = 15 * 60
    /// With no hook call for this long, the session is forgotten.
    static let forgetAfter: TimeInterval = 60 * 60

    enum Phase: Equatable, Sendable {
        case idle
        case working
        case waitingForApproval
        case waitingForInput
        case finished
    }

    struct Approval: Equatable, Sendable {
        var id: String
        var toolName: String
        var detail: String
        var suggestion: AlwaysAllowSuggestion?
    }

    enum Answer: Equatable, Sendable {
        case allow
        case alwaysAllow
        case deny
        case denyAndStop
        /// Let Claude Code's own prompt decide.
        case terminal
    }

    struct Session: Equatable, Sendable {
        var id: String
        var project: String
        var title: String?
        var phase: Phase = .idle
        var workStartedAt: Date?
        var lastEvent: Date
        var startOrder: Int
        var approvals: [Approval] = []
        var endAt: Date?
        var lastBanner: Date?
    }

    /// What the island shows for one session.
    struct Snapshot: Equatable, Sendable {
        var sessionID: String
        var project: String
        /// The project, with " (2)" when two sessions share it.
        var displayName: String
        var title: String?
        var phase: Phase
        var since: Date?
        var lastEvent: Date
        var approval: Approval?
        var moreApprovals: Int
    }

    enum Banner: Equatable, Sendable {
        case finished(project: String)
        case failed(project: String, error: String)
    }

    enum Event: Equatable, Sendable {
        /// `approvalID` is set for a permission request that waits for an answer.
        case hook(ClaudeHookEvent, approvalID: String?)
        case answered(approvalID: String, Answer)
        /// The hook process hung up (it timed out, or Claude Code was answered in the terminal).
        case approvalClosed(approvalID: String)
        case tick
        case reset
    }

    enum Effect: Equatable, Sendable {
        case post(Snapshot, alert: Bool)
        case end(sessionID: String, immediate: Bool)
        case banner(Banner, sessionID: String)
        /// nil: no decision, Claude Code asks in the terminal.
        case reply(approvalID: String, ClaudeHookReply?)
        case wake(Date?)
    }

    private(set) var sessions: [String: Session] = [:]
    private var nextOrder = 0

    func snapshot(of id: String) -> Snapshot? {
        guard let session = sessions[id] else { return nil }
        let same = sessions.values.filter { $0.project == session.project }.sorted { $0.startOrder < $1.startOrder }
        let name = same.count > 1 ? "\(session.project) (\((same.firstIndex { $0.id == id } ?? 0) + 1))" : session.project
        return Snapshot(sessionID: id, project: session.project, displayName: name, title: session.title, phase: session.phase,
                        since: session.workStartedAt, lastEvent: session.lastEvent, approval: session.approvals.first,
                        moreApprovals: max(0, session.approvals.count - 1))
    }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .hook(let hook, let approvalID):
            effects += handle(hook, approvalID: approvalID, now: now)
        case .answered(let approvalID, let answer):
            effects += handleAnswer(approvalID, answer, now: now)
        case .approvalClosed(let approvalID):
            if let id = session(holding: approvalID) {
                sessions[id]?.approvals.removeAll { $0.id == approvalID }
                if sessions[id]?.approvals.isEmpty == true, sessions[id]?.phase == .waitingForApproval { sessions[id]?.phase = .working }
                effects.append(post(id, alert: false))
            }
        case .tick:
            effects += expire(now: now)
        case .reset:
            sessions.removeAll()
            return [.wake(nil)]
        }
        effects.append(.wake(nextWake()))
        return effects
    }

    // MARK: Hooks

    private mutating func handle(_ hook: ClaudeHookEvent, approvalID: String?, now: Date) -> [Effect] {
        let id = hook.sessionID
        if sessions[id] == nil {
            sessions[id] = Session(id: id, project: hook.project, title: hook.title, lastEvent: now, startOrder: nextOrder)
            nextOrder += 1
        }
        sessions[id]?.lastEvent = now
        if let title = hook.title { sessions[id]?.title = title }
        var effects: [Effect] = []

        switch hook.kind {
        case .sessionStart:
            // A session sitting at its prompt isn't news; nothing to show yet.
            break

        case .userPromptSubmit:
            if sessions[id]?.phase != .working { sessions[id]?.workStartedAt = now }
            sessions[id]?.phase = .working
            sessions[id]?.endAt = nil
            effects.append(post(id, alert: false))

        case .permissionRequest:
            guard let approvalID else { break }
            if sessions[id]?.workStartedAt == nil { sessions[id]?.workStartedAt = now }
            let approval = Approval(id: approvalID, toolName: hook.toolName ?? "Tool", detail: hook.detail ?? "", suggestion: hook.suggestion)
            let wasShowing = sessions[id]?.approvals.isEmpty == false
            sessions[id]?.approvals.append(approval)
            sessions[id]?.phase = .waitingForApproval
            sessions[id]?.endAt = nil
            effects.append(post(id, alert: !wasShowing))

        case .notification(let type):
            if type == "idle_prompt", sessions[id]?.approvals.isEmpty == true {
                sessions[id]?.phase = .waitingForInput
                effects.append(post(id, alert: false))
            }

        case .stop:
            effects += finish(id, now: now, failure: nil)

        case .stopFailure(let error):
            effects += finish(id, now: now, failure: error)

        case .sessionEnd:
            for approval in sessions[id]?.approvals ?? [] { effects.append(.reply(approvalID: approval.id, nil)) }
            sessions[id] = nil
            effects.append(.end(sessionID: id, immediate: true))

        case .other:
            break
        }
        return effects
    }

    private mutating func finish(_ id: String, now: Date, failure: String?) -> [Effect] {
        guard var session = sessions[id] else { return [] }
        var effects: [Effect] = []
        let worked = session.workStartedAt.map { now.timeIntervalSince($0) } ?? 0
        session.workStartedAt = nil
        session.approvals.removeAll()
        let coolingDown = session.lastBanner.map { now.timeIntervalSince($0) < Self.bannerCooldown } ?? false

        if let failure {
            session.phase = .idle
            if !coolingDown {
                effects.append(.banner(.failed(project: session.project, error: failure), sessionID: id))
                session.lastBanner = now
            }
            sessions[id] = session
            effects.append(.end(sessionID: id, immediate: false))
            return effects
        }

        session.phase = .finished
        session.endAt = now.addingTimeInterval(Self.finishedLinger)
        if worked >= Self.bannerAfterWork, !coolingDown {
            effects.append(.banner(.finished(project: session.project), sessionID: id))
            session.lastBanner = now
        }
        if worked >= Self.bannerAfterWork {
            sessions[id] = session
            effects.append(post(id, alert: false))
        } else {
            // A short turn: the island that showed "working" just goes away.
            session.phase = .idle
            session.endAt = nil
            sessions[id] = session
            effects.append(.end(sessionID: id, immediate: true))
        }
        return effects
    }

    // MARK: Answers

    private mutating func handleAnswer(_ approvalID: String, _ answer: Answer, now: Date) -> [Effect] {
        guard let id = session(holding: approvalID), let approval = sessions[id]?.approvals.first(where: { $0.id == approvalID }) else { return [] }
        sessions[id]?.approvals.removeAll { $0.id == approvalID }
        sessions[id]?.lastEvent = now
        let reply: ClaudeHookReply?
        switch answer {
        case .allow: reply = .allow
        case .alwaysAllow: reply = approval.suggestion.map { .alwaysAllow($0) } ?? .allow
        case .deny: reply = .deny(message: "Denied from Notched", interrupt: false)
        case .denyAndStop: reply = .deny(message: "Denied from Notched", interrupt: true)
        case .terminal: reply = nil
        }
        let next = sessions[id]?.approvals.isEmpty == false
        sessions[id]?.phase = next ? .waitingForApproval : .working
        return [.reply(approvalID: approvalID, reply), post(id, alert: next)]
    }

    // MARK: Time

    private mutating func expire(now: Date) -> [Effect] {
        var effects: [Effect] = []
        for (id, session) in sessions {
            if let endAt = session.endAt, endAt <= now {
                sessions[id]?.endAt = nil
                sessions[id]?.phase = .idle
                effects.append(.end(sessionID: id, immediate: false))
            } else if session.approvals.isEmpty, session.phase != .idle, now.timeIntervalSince(session.lastEvent) >= Self.forgetAfter {
                sessions[id] = nil
                effects.append(.end(sessionID: id, immediate: false))
            }
        }
        return effects
    }

    private func nextWake() -> Date? {
        var dates: [Date] = []
        for session in sessions.values {
            if let endAt = session.endAt { dates.append(endAt) }
            if session.approvals.isEmpty, session.phase != .idle { dates.append(session.lastEvent.addingTimeInterval(Self.forgetAfter)) }
        }
        return dates.min()
    }

    // MARK: Helpers

    private func session(holding approvalID: String) -> String? {
        sessions.values.first { $0.approvals.contains { $0.id == approvalID } }?.id
    }

    private func post(_ id: String, alert: Bool) -> Effect {
        guard let snapshot = snapshot(of: id) else { return .end(sessionID: id, immediate: true) }
        return .post(snapshot, alert: alert)
    }
}
