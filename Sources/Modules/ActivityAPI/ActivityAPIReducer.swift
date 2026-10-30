// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Names one client's activity. Two clients can use the same id.
struct ActivityKey: Hashable, Sendable {
    let clientID: String
    let id: String
}

/// The rules for activities posted through the API: per-client caps, alert
/// rate limits and expiry. Pure; the module turns requests into events and
/// carries out the effects (ADR-0021).
struct ActivityAPIReducer: Sendable {
    static let maxActivitiesPerClient = 5
    static let alertInterval: TimeInterval = 30

    struct Entry: Equatable, Sendable {
        var spec: ActivitySpec
        var clientName: String
        var createdAt: Date
        var updatedAt: Date
        var expiresAt: Date
    }

    struct Rejection: Equatable, Sendable {
        var status: Int
        var code: String
        var message: String

        var response: HTTPResponse { .error(status, code, message) }
    }

    enum Event: Equatable, Sendable {
        case put(ActivityKey, ActivitySpec, clientName: String)
        case delete(ActivityKey)
        /// A client was revoked.
        case revoke(clientID: String)
        case tick
        /// The module stopped.
        case reset
    }

    enum Effect: Equatable, Sendable {
        case accepted(created: Bool)
        case rejected(Rejection)
        case post(ActivityKey, Entry, alert: Bool)
        case end(ActivityKey, immediate: Bool)
        /// Call `tick` at this date; nil cancels the wake.
        case wake(Date?)
    }

    private(set) var entries: [ActivityKey: Entry] = [:]
    private var lastAlert: [String: Date] = [:]

    func entries(of clientID: String) -> [ActivityKey] {
        entries.keys.filter { $0.clientID == clientID }.sorted { $0.id < $1.id }
    }

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        var effects: [Effect] = []
        switch event {
        case .put(let key, let spec, let name):
            let existing = entries[key]
            if existing == nil, entries(of: key.clientID).count >= Self.maxActivitiesPerClient {
                return [.rejected(Rejection(status: 409, code: "too_many_activities",
                                            message: "A client can have \(Self.maxActivitiesPerClient) activities at once. End one first."))]
            }
            var expiresAt = now.addingTimeInterval(spec.expiresAfter)
            if let endsAt = spec.endsAt { expiresAt = min(expiresAt, endsAt.addingTimeInterval(60)) }
            var alert = false
            if spec.alert {
                let last = lastAlert[key.clientID]
                if last == nil || now.timeIntervalSince(last!) >= Self.alertInterval {
                    alert = true
                    lastAlert[key.clientID] = now
                }
            }
            let entry = Entry(spec: spec, clientName: name, createdAt: existing?.createdAt ?? now, updatedAt: now, expiresAt: expiresAt)
            entries[key] = entry
            effects += [.accepted(created: existing == nil), .post(key, entry, alert: alert)]

        case .delete(let key):
            guard entries.removeValue(forKey: key) != nil else {
                return [.rejected(Rejection(status: 404, code: "not_found", message: "No such activity."))]
            }
            effects.append(.end(key, immediate: false))

        case .revoke(let clientID):
            for key in entries(of: clientID) {
                entries[key] = nil
                effects.append(.end(key, immediate: true))
            }
            lastAlert[clientID] = nil

        case .tick:
            for (key, entry) in entries where entry.expiresAt <= now {
                entries[key] = nil
                effects.append(.end(key, immediate: false))
            }

        case .reset:
            entries.removeAll()
            lastAlert.removeAll()
        }
        effects.append(.wake(entries.values.map(\.expiresAt).min()))
        return effects
    }
}
