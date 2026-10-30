// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@MainActor
@Suite("APIGateway")
struct APIGatewayTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 500_000)
    let port: UInt16 = 51234

    private func makeGateway() -> APIGateway {
        let defaults = UserDefaults(suiteName: "APIGatewayTests.\(UUID().uuidString)")!
        let gateway = APIGateway(settings: LocalAPISettings(defaults: defaults), secrets: InMemorySecretStore())
        gateway.startsServer = false
        gateway.register(owner: "test", prefix: "/v1/things", scope: .activity) { context in
            .json(200, ["client": context.client.name, "path": context.request.path])
        }
        gateway.register(owner: "test", prefix: "/v1/banners", scope: .banner) { _ in .json(202, ["queued": true]) }
        return gateway
    }

    private func request(_ path: String = "/v1/things", method: String = "GET", token: String? = nil, headers: [String: String] = [:]) -> HTTPRequest {
        var all = ["host": "127.0.0.1:\(port)"]
        if let token { all["authorization"] = "Bearer " + token }
        for (key, value) in headers { all[key.lowercased()] = value }
        return HTTPRequest(method: method, path: path, query: [:], headers: all, body: Data())
    }

    private func errorCode(_ response: HTTPResponse) -> String? {
        ((try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }.flatMap { $0["code"] as? String }
    }

    @Test("A valid token reaches the route and is told who it is")
    func happyPath() async throws {
        let gateway = makeGateway()
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        let response = await gateway.handle(request(token: created.token), port: port, now: t0)
        #expect(response.status == 200)
        let body = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(body["client"] as? String == "CI")
        #expect(gateway.clients.first?.lastSeen == t0)
    }

    @Test("No token is 401 missing_token; a wrong or malformed one is 401 invalid_token")
    func authFailures() async throws {
        let gateway = makeGateway()
        _ = gateway.createClient(name: "CI", scopes: [.activity], now: t0)
        let none = await gateway.handle(request(), port: port, now: t0)
        #expect(none.status == 401)
        #expect(errorCode(none) == "missing_token")
        #expect(none.extraHeaders["WWW-Authenticate"] == "Bearer")
        let wrong = await gateway.handle(request(token: APIToken.generate()), port: port, now: t0 + 1)
        #expect(wrong.status == 401)
        #expect(errorCode(wrong) == "invalid_token")
        let junk = await gateway.handle(request(token: "hello"), port: port, now: t0 + 2)
        #expect(errorCode(junk) == "invalid_token")
        // The same message whether the token never existed or was revoked: nothing reveals which clients exist.
        #expect(wrong.body == junk.body)
    }

    @Test("Browser and rebinding checks run before the token is even looked at")
    func guardsFirst() async throws {
        let gateway = makeGateway()
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        let page = await gateway.handle(request(token: created.token, headers: ["Origin": "https://evil.example"]), port: port, now: t0)
        #expect(page.status == 403)
        #expect(errorCode(page) == "browser_forbidden")
        let rebind = await gateway.handle(request(token: created.token, headers: ["Host": "evil.example:\(port)"]), port: port, now: t0)
        #expect(rebind.status == 421)
        // A refused page request doesn't count as a failed login either.
        for _ in 0..<30 { _ = await gateway.handle(request(headers: ["Origin": "x"]), port: port, now: t0) }
        let still = await gateway.handle(request(), port: port, now: t0 + 1)
        #expect(errorCode(still) == "missing_token")
    }

    @Test("Too many bad tokens block bad tokens, but a valid token keeps working")
    func failureLimit() async throws {
        let gateway = makeGateway()
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        for index in 0..<20 { _ = await gateway.handle(request(token: APIToken.generate()), port: port, now: t0 + Double(index) * 0.1) }
        let blocked = await gateway.handle(request(token: APIToken.generate()), port: port, now: t0 + 3)
        #expect(blocked.status == 429)
        #expect(blocked.extraHeaders["Retry-After"] == "60")
        let good = await gateway.handle(request(token: created.token), port: port, now: t0 + 4)
        #expect(good.status == 200)
        let later = await gateway.handle(request(token: APIToken.generate()), port: port, now: t0 + 70)
        #expect(later.status == 401)
    }

    @Test("A client is limited to a burst of 20, then waits")
    func rateLimit() async throws {
        let gateway = makeGateway()
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        var statuses: [Int] = []
        for _ in 0..<25 { statuses.append(await gateway.handle(request(token: created.token), port: port, now: t0).status) }
        #expect(statuses.prefix(20).allSatisfy { $0 == 200 })
        #expect(statuses.suffix(5).allSatisfy { $0 == 429 })
        let limited = await gateway.handle(request(token: created.token), port: port, now: t0)
        #expect(limited.extraHeaders["Retry-After"] != nil)
        let recovered = await gateway.handle(request(token: created.token), port: port, now: t0 + 1)
        #expect(recovered.status == 200)
        // Another client has its own bucket.
        let other = try #require(gateway.createClient(name: "Other", scopes: [.activity], now: t0))
        #expect(await gateway.handle(request(token: other.token), port: port, now: t0).status == 200)
    }

    @Test("A route needs its scope")
    func scopes() async throws {
        let gateway = makeGateway()
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        let denied = await gateway.handle(request("/v1/banners", method: "POST", token: created.token, headers: ["Content-Type": "application/json"]), port: port, now: t0)
        #expect(denied.status == 403)
        #expect(errorCode(denied) == "missing_scope")
        let missing = await gateway.handle(request("/v1/nothing", token: created.token), port: port, now: t0)
        #expect(missing.status == 404)
    }

    @Test("The longest matching prefix wins, and a prefix must end at a path boundary")
    func routing() async throws {
        let gateway = makeGateway()
        gateway.register(owner: "test", prefix: "/v1/things/special", scope: .activity) { _ in .json(200, ["special": true]) }
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        let special = await gateway.handle(request("/v1/things/special/x", token: created.token), port: port, now: t0)
        #expect(String(decoding: special.body, as: UTF8.self).contains("special"))
        let lookalike = await gateway.handle(request("/v1/thingsX", token: created.token), port: port, now: t0)
        #expect(lookalike.status == 404)
    }

    @Test("Revoking stops the token at once and tells the modules")
    func revoke() async throws {
        let gateway = makeGateway()
        var told: [String] = []
        gateway.onRevoke(owner: "test") { told.append($0) }
        let created = try #require(gateway.createClient(name: "CI", scopes: [.activity], now: t0))
        #expect(await gateway.handle(request(token: created.token), port: port, now: t0).status == 200)
        gateway.revoke(clientID: created.client.id)
        #expect(await gateway.handle(request(token: created.token), port: port, now: t0 + 1).status == 401)
        #expect(told == [created.client.id])
        #expect(gateway.clients.isEmpty)
    }

    @Test("Clients survive a restart, tokens still work, and the hash (not the token) is what's stored")
    func persistence() async throws {
        let suite = "APIGatewayTests.\(UUID().uuidString)"
        let secrets = InMemorySecretStore()
        let first = APIGateway(settings: LocalAPISettings(defaults: UserDefaults(suiteName: suite)!), secrets: secrets)
        first.startsServer = false
        let created = try #require(first.createClient(name: "CI", scopes: [.activity, .banner], now: t0))
        #expect(secrets.load(account: created.client.id) == APIToken.hash(created.token))
        #expect(secrets.load(account: created.client.id) != Data(created.token.utf8))

        let second = APIGateway(settings: LocalAPISettings(defaults: UserDefaults(suiteName: suite)!), secrets: secrets)
        second.startsServer = false
        second.register(owner: "test", prefix: "/v1/things", scope: .activity) { _ in .json(200, [:]) }
        #expect(second.clients.map(\.name) == ["CI"])
        #expect(await second.handle(request(token: created.token), port: port, now: t0).status == 200)
        // A client whose secret is gone can't be used.
        secrets.delete(account: created.client.id)
        let third = APIGateway(settings: LocalAPISettings(defaults: UserDefaults(suiteName: suite)!), secrets: secrets)
        #expect(third.clients.isEmpty)
    }

    @Test("Client names and scopes are validated; internal clients are hidden from the list")
    func creation() throws {
        let gateway = makeGateway()
        #expect(gateway.createClient(name: "   ", scopes: [.activity]) == nil)
        #expect(gateway.createClient(name: "x", scopes: []) == nil)
        let long = try #require(gateway.createClient(name: String(repeating: "n", count: 100), scopes: [.activity]))
        #expect(long.client.name.count == 40)
        let hidden = try #require(gateway.createClient(name: "Claude Code hooks", scopes: [.claude], isInternal: true))
        #expect(gateway.internalClient(named: "Claude Code hooks")?.id == hidden.client.id)
        #expect(gateway.clients.map(\.name) == [long.client.name])
        for index in 0..<30 { _ = gateway.createClient(name: "c\(index)", scopes: [.activity]) }
        #expect(gateway.clients.count == APIGateway.maxClients)
    }

    @Test("Settings: the approval wait is clamped and the port persists")
    func settings() {
        let defaults = UserDefaults(suiteName: "APIGatewayTests.\(UUID().uuidString)")!
        let settings = LocalAPISettings(defaults: defaults)
        #expect(settings.approvalWait == 90)
        settings.approvalWait = 5
        #expect(settings.approvalWait == 15)
        settings.approvalWait = 9999
        #expect(settings.approvalWait == 300)
        settings.port = 50111
        #expect(LocalAPISettings(defaults: defaults).port == 50111)
        #expect(LocalAPISettings(defaults: defaults).approvalWait == 300)
        #expect(!LocalAPISettings(defaults: defaults).allowLinkBanners)
    }
}
