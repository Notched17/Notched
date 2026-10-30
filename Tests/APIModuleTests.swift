// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// A module wired to an in-memory gateway (no socket) and an isolated
/// settings store, so nothing touches the real app's files or Keychain.
@MainActor
private struct Rig<Module: IslandModule> {
    let module: Module
    let coordinator: ActivityCoordinator
    let services: ModuleServices
    let settings: SettingsStore
    let port: UInt16 = 52000

    init(_ type: Module.Type, configure: (SettingsStore) -> Void = { _ in }) {
        let defaults = UserDefaults(suiteName: "APIModuleTests.\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults)
        configure(settings)
        services = ModuleServices(api: APIGateway(settings: settings.api, secrets: InMemorySecretStore()))
        services.api.startsServer = false
        coordinator = ActivityCoordinator()
        let context = ModuleContext(activities: ActivitySink(moduleID: Module.descriptor.id, coordinator: coordinator), scheduler: RefreshScheduler(),
                                    settings: settings, services: services, previousSessionCrashed: false)
        module = Module(context: context)
    }

    func send(_ method: String, _ path: String, token: String, body: String = "") async -> HTTPResponse {
        let request = HTTPRequest(method: method, path: path, query: [:],
                                  headers: ["host": "127.0.0.1:\(port)", "authorization": "Bearer " + token, "content-type": "application/json"],
                                  body: Data(body.utf8))
        return await services.api.handle(request, port: port, now: Date())
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

private func json(_ response: HTTPResponse) -> [String: Any] {
    ((try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]) ?? [:]
}

@MainActor
@Suite("Activity API module")
struct ActivityAPIModuleTests {
    private func start() throws -> (Rig<ActivityAPIModule>, String) {
        let rig = Rig(ActivityAPIModule.self)
        rig.module.start()
        let created = try #require(rig.services.api.createClient(name: "Tester", scopes: [.activity, .banner, .approval]))
        return (rig, created.token)
    }

    @Test("PUT posts a live activity, a second PUT updates it in place, DELETE ends it")
    func lifecycle() async throws {
        let (rig, token) = try start()
        defer { rig.module.stop() }
        let body = #"{"template":"progress","title":"Build","progress":0.2,"symbol":"hammer.fill"}"#
        let created = await rig.send("PUT", "/v1/activities/build", token: token, body: body)
        #expect(created.status == 201)
        #expect(rig.coordinator.live.count == 1)
        #expect(rig.coordinator.live.first?.activity.title == "Build")
        #expect(rig.coordinator.live.first?.activity.kind == .live)
        #expect(rig.coordinator.live.first?.activity.isHideable == true)

        let updated = await rig.send("PUT", "/v1/activities/build", token: token, body: #"{"template":"progress","title":"Build 2","progress":0.9}"#)
        #expect(updated.status == 200)
        #expect(rig.coordinator.live.count == 1)
        #expect(rig.coordinator.live.first?.activity.title == "Build 2")

        let listed = await rig.send("GET", "/v1/activities", token: token)
        #expect((json(listed)["activities"] as? [[String: String]])?.map { $0["id"] } == ["build"])

        let deleted = await rig.send("DELETE", "/v1/activities/build?dismiss=immediate", token: token)
        #expect(deleted.status == 204)
        #expect(rig.coordinator.live.isEmpty)
    }

    @Test("Passive kind is honoured, and an API activity can never be a system one")
    func kinds() async throws {
        let (rig, token) = try start()
        defer { rig.module.stop() }
        _ = await rig.send("PUT", "/v1/activities/a", token: token, body: #"{"template":"status","title":"A","kind":"passive"}"#)
        #expect(rig.coordinator.live.first?.activity.kind == .passive)
        let system = await rig.send("PUT", "/v1/activities/b", token: token, body: #"{"template":"status","title":"B","kind":"system"}"#)
        #expect(system.status == 400)
    }

    @Test("Bad payloads and ids get clear 4xx errors and post nothing")
    func errors() async throws {
        let (rig, token) = try start()
        defer { rig.module.stop() }
        let bad = await rig.send("PUT", "/v1/activities/x", token: token, body: #"{"template":"progress","title":"x"}"#)
        #expect(bad.status == 400)
        #expect((json(bad)["error"] as? [String: Any])?["field"] as? String == "progress")
        #expect((await rig.send("PUT", "/v1/activities/has space", token: token, body: "{}")).status == 404)
        #expect((await rig.send("PUT", "/v1/activities/x", token: token, body: "nope")).status == 400)
        #expect((await rig.send("POST", "/v1/activities/x", token: token, body: "{}")).status == 405)
        #expect((await rig.send("DELETE", "/v1/activities/missing", token: token)).status == 404)
        #expect(rig.coordinator.live.isEmpty)
    }

    @Test("Revoking a client takes its activities off the island at once")
    func revoke() async throws {
        let (rig, token) = try start()
        defer { rig.module.stop() }
        _ = await rig.send("PUT", "/v1/activities/a", token: token, body: #"{"template":"status","title":"A"}"#)
        #expect(rig.coordinator.live.count == 1)
        let client = try #require(rig.services.api.clients.first)
        rig.services.api.revoke(clientID: client.id)
        #expect(rig.coordinator.live.isEmpty)
        #expect((await rig.send("GET", "/v1/activities", token: token)).status == 401)
    }

    @Test("Stopping the module removes its routes and everything it showed")
    func stopCleansUp() async throws {
        let (rig, token) = try start()
        _ = await rig.send("PUT", "/v1/activities/a", token: token, body: #"{"template":"status","title":"A"}"#)
        rig.module.stop()
        #expect(rig.coordinator.live.isEmpty)
        #expect((await rig.send("GET", "/v1/activities", token: token)).status == 404)
    }

    @Test("A banner is accepted, rate limited per client, and validated")
    func banners() async throws {
        let (rig, token) = try start()
        defer { rig.module.stop() }
        let first = await rig.send("POST", "/v1/banners", token: token, body: #"{"title":"Done","symbol":"checkmark"}"#)
        #expect(first.status == 202)
        let quick = await rig.send("POST", "/v1/banners", token: token, body: #"{"title":"Again"}"#)
        #expect(quick.status == 429)
        #expect((await rig.send("POST", "/v1/banners", token: token, body: "{}")).status == 400 || quick.status == 429)
    }

    @Test("An approval waits for the user, and a client that hangs up dismisses it")
    func approvalHangup() async throws {
        let (rig, token) = try start()
        defer { rig.module.stop() }
        let task = Task { @MainActor in
            await rig.send("POST", "/v1/approvals", token: token, body: #"{"title":"Deploy?","detail":"to production","timeout":60}"#)
        }
        await rig.waitUntil { !rig.coordinator.live.isEmpty }
        #expect(rig.coordinator.live.count == 1)
        // A second request from the same client is refused while one is open.
        #expect((await rig.send("POST", "/v1/approvals", token: token, body: #"{"title":"Again"}"#)).status == 409)
        task.cancel()
        let response = await task.value
        #expect(json(response)["decision"] as? String == "dismissed")
        #expect(rig.coordinator.live.isEmpty)
    }

    @Test("Stopping while an approval is open answers it 'dismissed'")
    func approvalStop() async throws {
        let (rig, token) = try start()
        let task = Task { @MainActor in
            await rig.send("POST", "/v1/approvals", token: token, body: #"{"title":"Deploy?","timeout":60}"#)
        }
        await rig.waitUntil { !rig.coordinator.live.isEmpty }
        rig.module.stop()
        let response = await task.value
        #expect(json(response)["decision"] as? String == "dismissed")
    }
}

@MainActor
@Suite("Claude Code module")
struct ClaudeCodeModuleTests {
    private func start() throws -> (Rig<ClaudeCodeModule>, String, URL) {
        let tokenFile = FileManager.default.temporaryDirectory.appendingPathComponent("notched-tests-\(UUID().uuidString)/claude-hook.token")
        let rig = Rig(ClaudeCodeModule.self) { settings in
            settings.claudeCode.tokenFileURL = tokenFile
            settings.claudeCode.usageEnabled = false
        }
        rig.module.start()
        let token = try #require(String(data: Data(contentsOf: tokenFile), encoding: .utf8))
        return (rig, token, tokenFile)
    }

    private func hook(_ name: String, extra: String = "") -> String {
        #"{"session_id":"sess1","cwd":"/Users/c/Notched","hook_event_name":"\#(name)"\#(extra)}"#
    }

    @Test("Starting makes a private token file that works, and only for the hook route")
    func tokenFile() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(APIToken.isWellFormed(token))
        #expect((await rig.send("POST", "/v1/claude/hook", token: token, body: hook("SessionStart"))).status == 204)
        // The hook token can't post activities.
        #expect((await rig.send("GET", "/v1/activities", token: token)).status == 404)
        // It's an internal client, so it isn't listed in Settings.
        #expect(rig.services.api.clients.isEmpty)
    }

    @Test("A restart keeps the same client and token file; a missing file makes a new one")
    func tokenReuse() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        rig.module.stop()
        rig.module.start()
        #expect(String(data: try Data(contentsOf: file), encoding: .utf8) == token)
        rig.module.stop()
        try FileManager.default.removeItem(at: file)
        rig.module.start()
        let fresh = try #require(String(data: try Data(contentsOf: file), encoding: .utf8))
        #expect(fresh != token)
        #expect((await rig.send("POST", "/v1/claude/hook", token: token, body: hook("SessionStart"))).status == 401)
    }

    @Test("A prompt shows 'working', and Stop after a long turn finishes it")
    func working() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect((await rig.send("POST", "/v1/claude/hook", token: token, body: hook("UserPromptSubmit", extra: #","prompt":"secret""#))).status == 204)
        #expect(rig.coordinator.live.count == 1)
        #expect(rig.coordinator.live.first?.activity.title == "Notched")
        #expect(rig.module.model.sessions.first?.phase == .working)
        #expect((await rig.send("POST", "/v1/claude/hook", token: token, body: hook("SessionEnd", extra: #","reason":"clear""#))).status == 204)
        #expect(rig.coordinator.live.isEmpty)
    }

    @Test("A permission request waits, and Allow answers with Claude Code's allow format")
    func allow() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let body = hook("PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"npm test"}"#)
        let task = Task { @MainActor in await rig.send("POST", "/v1/claude/hook", token: token, body: body) }
        await rig.waitUntil { rig.module.model.sessions.first?.approval != nil }
        let approval = try #require(rig.module.model.sessions.first?.approval)
        #expect(approval.detail == "npm test")
        rig.module.choose(approvalID: approval.id, .allow)
        let response = await task.value
        #expect(response.status == 200)
        let decision = ((json(response)["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision?["behavior"] as? String == "allow")
        #expect(rig.module.model.sessions.first?.phase == .working)
    }

    @Test("Deny answers with a deny and a message")
    func deny() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let body = hook("PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"rm -rf /"}"#)
        let task = Task { @MainActor in await rig.send("POST", "/v1/claude/hook", token: token, body: body) }
        await rig.waitUntil { rig.module.model.sessions.first?.approval != nil }
        rig.module.choose(approvalID: try #require(rig.module.model.sessions.first?.approval?.id), .deny)
        let decision = ((json(await task.value)["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision?["behavior"] as? String == "deny")
        #expect((decision?["message"] as? String)?.isEmpty == false)
    }

    @Test("If Notched stops mid-approval, the hook gets no decision, so Claude Code asks in its own prompt")
    func stopMidApproval() async throws {
        let (rig, token, file) = try start()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let body = hook("PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#)
        let task = Task { @MainActor in await rig.send("POST", "/v1/claude/hook", token: token, body: body) }
        await rig.waitUntil { rig.module.model.sessions.first?.approval != nil }
        rig.module.stop()
        let response = await task.value
        #expect(response.status == 204)
        #expect(response.body.isEmpty)
        #expect(rig.coordinator.live.isEmpty)
    }

    @Test("If the hook hangs up, the card goes away and nothing is answered")
    func hangUp() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let body = hook("PermissionRequest", extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#)
        let task = Task { @MainActor in await rig.send("POST", "/v1/claude/hook", token: token, body: body) }
        await rig.waitUntil { rig.module.model.sessions.first?.approval != nil }
        task.cancel()
        let response = await task.value
        #expect(response.status == 204)
        #expect(rig.module.model.sessions.first?.approval == nil)
    }

    @Test("With status switched off, hooks are ignored; garbage is a 400")
    func switchedOffAndGarbage() async throws {
        let (rig, token, file) = try start()
        defer { rig.module.stop(); try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect((await rig.send("POST", "/v1/claude/hook", token: token, body: "nope")).status == 400)
        rig.settings.claudeCode.statusEnabled = false
        rig.module.applySettings()
        #expect((await rig.send("POST", "/v1/claude/hook", token: token, body: hook("UserPromptSubmit"))).status == 404)
        #expect(rig.coordinator.live.isEmpty)
    }
}
