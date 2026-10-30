// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// What a route handler is given after the request passed every check.
struct APIContext: Sendable {
    let request: HTTPRequest
    let client: APIClient
    let now: Date
}

typealias APIHandler = @MainActor (APIContext) async -> HTTPResponse

/// The local API's settings (Settings ▸ Modules ▸ Activity API).
@MainActor
@Observable
final class LocalAPISettings {
    enum Key {
        static let port = "api.port"
        static let clients = "api.clients"
        static let linkBanners = "api.linkBanners"
        static let approvalWait = "api.approvalWait"
    }

    static let approvalWaitRange = 15...300
    @ObservationIgnored private let defaults: UserDefaults

    /// 0 until the server first runs, then a stable random port.
    var port: Int { didSet { defaults.set(port, forKey: Key.port) } }
    /// Whether `notched://banner` links may show a banner (off by default).
    var allowLinkBanners: Bool { didSet { defaults.set(allowLinkBanners, forKey: Key.linkBanners) } }
    /// How long an approval waits on the island before Claude Code falls back to its own prompt.
    var approvalWait: Int {
        didSet {
            let clamped = min(max(approvalWait, Self.approvalWaitRange.lowerBound), Self.approvalWaitRange.upperBound)
            if clamped != approvalWait { approvalWait = clamped; return }
            defaults.set(approvalWait, forKey: Key.approvalWait)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        port = defaults.integer(forKey: Key.port)
        allowLinkBanners = defaults.bool(forKey: Key.linkBanners)
        let wait = defaults.integer(forKey: Key.approvalWait)
        approvalWait = wait == 0 ? 90 : min(max(wait, Self.approvalWaitRange.lowerBound), Self.approvalWaitRange.upperBound)
    }

    var savedClients: [APIClient] {
        defaults.data(forKey: Key.clients).flatMap { try? JSONDecoder().decode([APIClient].self, from: $0) } ?? []
    }

    func save(clients: [APIClient]) {
        if let data = try? JSONEncoder().encode(clients) { defaults.set(data, forKey: Key.clients) }
    }
}

/// The one door into the app for local clients (ADR-0021). Modules register
/// routes; the gateway runs the checks in a fixed order: browser/host guard,
/// token, per-client rate limit, scope. The server socket exists only while
/// at least one route is registered.
@MainActor
@Observable
final class APIGateway {
    struct Route {
        let owner: ModuleID
        let prefix: String
        let scope: APIScope
        let handler: APIHandler
    }

    static let maxClients = 20
    let settings: LocalAPISettings
    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private var routes: [Route] = []
    @ObservationIgnored private var buckets: [String: TokenBucket] = [:]
    @ObservationIgnored private var failures = FailureLimiter(maxFailures: 20, window: 60)
    @ObservationIgnored private var directory = ClientDirectory()
    @ObservationIgnored private var revokeListeners: [ModuleID: (String) -> Void] = [:]
    @ObservationIgnored private let server = LocalAPIServer()
    /// False in tests, which call `handle` directly and must not open a socket.
    @ObservationIgnored var startsServer = true

    /// The clients the user manages in Settings (internal ones are hidden).
    private(set) var clients: [APIClient] = []
    var serverStatus: LocalAPIServer.Status { server.status }

    init(settings: LocalAPISettings = LocalAPISettings(defaults: UserDefaults(suiteName: "me.rkck.Notched.api.\(UUID().uuidString)") ?? .standard),
         secrets: SecretStore = InMemorySecretStore()) {
        self.settings = settings
        self.secrets = secrets
        for client in settings.savedClients {
            guard let hash = secrets.load(account: client.id) else { continue }
            directory.add(client, tokenHash: hash)
        }
        refreshClients()
        server.handler = { [weak self] request, port in
            guard let self else { return .error(503, "disabled", "Notched is shutting down.") }
            return await self.handle(request, port: port, now: Date())
        }
    }

    // MARK: Routes

    func register(owner: ModuleID, prefix: String, scope: APIScope, handler: @escaping APIHandler) {
        routes.removeAll { $0.owner == owner && $0.prefix == prefix }
        routes.append(Route(owner: owner, prefix: prefix, scope: scope, handler: handler))
        startServerIfNeeded()
    }

    func unregister(owner: ModuleID) {
        routes.removeAll { $0.owner == owner }
        revokeListeners[owner] = nil
        if routes.isEmpty, startsServer { server.stop() }
    }

    /// Called with the client's id when it's revoked, so a module can end what it posted.
    func onRevoke(owner: ModuleID, _ listener: @escaping (String) -> Void) {
        revokeListeners[owner] = listener
    }

    private func startServerIfNeeded() {
        guard startsServer else { return }
        if settings.port == 0 { settings.port = Int.random(in: 49152...65535) }
        guard let port = UInt16(exactly: settings.port) else { return }
        server.start(port: port)
    }

    /// Applies a changed port (Settings) to a running server.
    func restartServer() {
        guard !routes.isEmpty else { return }
        server.stop()
        startServerIfNeeded()
    }

    // MARK: Clients

    /// Creates a client. The token is returned once; only its hash is kept.
    func createClient(name: String, scopes: Set<APIScope>, isInternal: Bool = false, now: Date = Date()) -> (client: APIClient, token: String)? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !trimmed.isEmpty, !scopes.isEmpty else { return nil }
        guard isInternal || clients.count < Self.maxClients else { return nil }
        let token = APIToken.generate()
        let client = APIClient(id: UUID().uuidString, name: trimmed, scopes: scopes, createdAt: now, lastSeen: nil, isInternal: isInternal)
        let hash = APIToken.hash(token)
        guard secrets.save(hash, account: client.id) else { return nil }
        directory.add(client, tokenHash: hash)
        persist()
        return (client, token)
    }

    func revoke(clientID: String) {
        guard directory.client(id: clientID) != nil else { return }
        secrets.delete(account: clientID)
        directory.remove(id: clientID)
        buckets[clientID] = nil
        persist()
        for listener in revokeListeners.values { listener(clientID) }
    }

    /// The internal client with this name, if any.
    func internalClient(named name: String) -> APIClient? {
        directory.clients.first { $0.isInternal && $0.name == name }
    }

    private func persist() {
        settings.save(clients: directory.clients)
        refreshClients()
    }

    private func refreshClients() {
        clients = directory.clients.filter { !$0.isInternal }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Requests

    func handle(_ request: HTTPRequest, port: UInt16, now: Date) async -> HTTPResponse {
        if case .reject(let response) = LocalAPIGuard(port: port).check(request) { return response }

        let client: APIClient
        switch directory.authenticate(header: request.header("authorization")) {
        case .ok(let found):
            client = found
        case .missing, .invalid:
            if failures.isBlocked(at: now) {
                return .error(429, "rate_limited", "Too many failed attempts. Try again in a minute.", headers: ["Retry-After": "60"])
            }
            failures.recordFailure(at: now)
            let hasToken = request.header("authorization") != nil
            return .error(401, hasToken ? "invalid_token" : "missing_token",
                          hasToken ? "The token isn't valid. Create a new one in Settings ▸ Modules ▸ Activity API."
                                   : "Send Authorization: Bearer <token>.",
                          headers: ["WWW-Authenticate": "Bearer"])
        }

        var bucket = buckets[client.id] ?? TokenBucket(burst: 20, perSecond: 10)
        let wait = bucket.take(at: now)
        buckets[client.id] = bucket
        if let wait {
            return .error(429, "rate_limited", "Too many requests.", headers: ["Retry-After": String(Int(wait.rounded(.up)))])
        }

        guard let route = routes.filter({ request.path == $0.prefix || request.path.hasPrefix($0.prefix + "/") })
            .max(by: { $0.prefix.count < $1.prefix.count }) else {
            return .error(404, "not_found", "No such endpoint.")
        }
        guard client.scopes.contains(route.scope) else {
            return .error(403, "missing_scope", "This client doesn't have the \"\(route.scope.rawValue)\" scope.")
        }
        directory.touch(id: client.id, at: now)
        if !client.isInternal { refreshClients() }
        return await route.handler(APIContext(request: request, client: client, now: now))
    }
}
