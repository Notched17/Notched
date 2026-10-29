// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Calls: "In a call" with a running duration for the known call apps, from
/// which of them are using the microphone. Caller names and ringing can't be
/// seen, so nothing pretends to show them. The rules that are easy to get wrong:
///
/// - **A second of mic use makes a call.** A mic check or a stray blip isn't one.
///   While it's pending the app is already *claimed*, so the Camera & Microphone
///   indicator doesn't flash its dot for it.
/// - **A 3 s grace period.** Many apps drop the microphone for a moment (mute,
///   a reconnect). The call carries on, with its start time, if the mic comes
///   back within 3 s, and ends after that.
/// - **An app that quits ends its call at once.**
/// - **Only a call we saw start has a duration.** One already running when the
///   module starts (or that we can't be sure about after wake) says "In a call"
///   and nothing more.
/// - **One call per app**, each its own activity.
///
/// Foundation only: the shell turns the shared sensor reading into events.
struct CallReducer: Sendable {
    static let startDelay: TimeInterval = 1
    static let grace: TimeInterval = 3

    struct App: Hashable, Sendable {
        /// The app's identity (`InputUser.identity`), e.g. its bundle ID.
        var id: String
        var name: String
    }

    /// What the island says about one call.
    struct Model: Equatable, Sendable {
        var app: App
        /// When the call was seen to start; nil if it was already going.
        var startedAt: Date?
        /// The camera is running, so the call shows a camera dot.
        var camera: Bool
    }

    enum Event: Equatable, Sendable {
        /// The call apps using the microphone right now.
        case micUsers(Set<App>)
        case appQuit(String)
        case camera(Bool)
        /// The wake the reducer asked for.
        case tick
        /// The Mac woke: what we knew may be stale.
        case wake
    }

    enum Effect: Equatable, Sendable {
        case post(Model)
        case end(String)
        /// Tells Camera & Microphone which apps are in a call.
        case claims(CallClaims)
        case schedule(Date?)
    }

    private enum Session: Equatable {
        case pending(since: Date)
        case active(startedAt: Date?)
        case grace(until: Date, startedAt: Date?)
    }

    private struct Entry {
        var app: App
        var session: Session
    }

    private var sessions: [String: Entry] = [:]
    private var camera = false
    private var seedNext = true
    private var posted: [String: Model] = [:]
    private var claims = CallClaims()
    private var scheduled: Date?

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .micUsers(let apps):
            let seeding = seedNext
            seedNext = false
            let present = Set(apps.map(\.id))
            for app in apps {
                switch sessions[app.id]?.session {
                case nil:
                    sessions[app.id] = Entry(app: app, session: seeding ? .active(startedAt: nil) : .pending(since: now))
                case .grace(_, let startedAt)?:
                    sessions[app.id] = Entry(app: app, session: .active(startedAt: startedAt))
                default:
                    sessions[app.id]?.app = app
                }
            }
            for (id, entry) in sessions where !present.contains(id) {
                switch entry.session {
                case .pending:
                    sessions[id] = nil
                case .active(let startedAt):
                    // After wake there's no knowing how long it has been gone.
                    sessions[id] = seeding ? nil : Entry(app: entry.app, session: .grace(until: now.addingTimeInterval(Self.grace), startedAt: startedAt))
                case .grace:
                    if seeding { sessions[id] = nil }
                }
            }
        case .appQuit(let id):
            sessions[id] = nil
        case .camera(let on):
            camera = on
        case .tick:
            break
        case .wake:
            seedNext = true
            return []
        }
        settle(now: now)
        return effects()
    }

    /// Starts calls that have had a second of mic use, and ends those past their grace.
    private mutating func settle(now: Date) {
        for (id, entry) in sessions {
            switch entry.session {
            case .pending(let since) where now.timeIntervalSince(since) >= Self.startDelay - 0.001:
                sessions[id]?.session = .active(startedAt: since)
            case .grace(let until, _) where now.timeIntervalSince(until) >= -0.001:
                sessions[id] = nil
            default:
                break
            }
        }
    }

    private mutating func effects() -> [Effect] {
        var result: [Effect] = []
        var shown: [String: Model] = [:]
        for (id, entry) in sessions {
            switch entry.session {
            case .active(let startedAt), .grace(_, let startedAt):
                shown[id] = Model(app: entry.app, startedAt: startedAt, camera: camera)
            case .pending:
                break
            }
        }
        for id in shown.keys.sorted() where posted[id] != shown[id] {
            posted[id] = shown[id]
            result.append(.post(shown[id]!))
        }
        for id in posted.keys.sorted() where shown[id] == nil {
            posted[id] = nil
            result.append(.end(id))
        }
        let nextClaims = CallClaims(identities: Set(sessions.keys), isCallActive: !shown.isEmpty)
        if nextClaims != claims {
            claims = nextClaims
            result.append(.claims(nextClaims))
        }
        let next = sessions.values.compactMap { entry -> Date? in
            switch entry.session {
            case .pending(let since): since.addingTimeInterval(Self.startDelay)
            case .grace(let until, _): until
            case .active: nil
            }
        }.min()
        if next != scheduled {
            scheduled = next
            result.append(.schedule(next))
        }
        return result
    }
}
