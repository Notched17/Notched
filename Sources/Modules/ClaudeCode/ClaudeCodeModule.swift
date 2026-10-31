// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Claude Code on the island (#62, #63): what it is working on, its permission
/// requests with Allow / Deny, a banner when it finishes, and an AI tab with
/// token usage. A thin shell: `ClaudeSessionsReducer` holds the rules,
/// `notched-hook` (run by Claude Code's hooks) sends events through the local
/// API, and `ClaudeUsageService` reads the logs. If Notched is closed or slow,
/// the helper prints nothing and Claude Code asks in its own terminal prompt
/// (ADR-0022).
@MainActor
final class ClaudeCodeModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "claudecode",
        name: "Claude Code",
        symbol: "sparkles",
        summary: "Shows when Claude Code is working, lets you Allow or Deny its permission requests from the island, and adds an AI tab with your token usage.",
        permissions: [],
        isDebugOnly: false
    )

    static let clientName = "Claude Code hooks"
    static let tabID = "ai"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(ClaudeCodeSettingsPane(settings: context.settings.claudeCode, api: context.settings.api, registry: context.registry))
    }

    let model = ClaudeAIModel()
    private let context: ModuleContext
    private let settings: ClaudeCodeSettings
    private var reducer = ClaudeSessionsReducer()
    private let wake = OneShotTimer()
    private var waiters: [String: ApprovalWaiter] = [:]
    private var replies: [String: ClaudeHookReply?] = [:]
    private var isRunning = false
    private var usage: ClaudeUsageService?
    private var watcher: DirectoryWatcher?
    private var tabVisible = false
    private var logsChangedSinceRefresh = true
    private var refreshTask: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
        settings = context.settings.claudeCode
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        wake.action = { [weak self] in self?.apply(.tick) }
        applySettings()
    }

    func stop() {
        isRunning = false
        wake.schedule(at: nil)
        refreshTask?.cancel()
        refreshTask = nil
        // Every waiting hook gets "no decision", so Claude Code asks in its own prompt.
        for waiter in waiters.values { waiter.resolve("dismissed") }
        waiters.removeAll()
        replies.removeAll()
        context.services.api.unregister(owner: Self.descriptor.id)
        stopUsage()
        _ = reducer.reduce(.reset, now: Date())
        reducer = ClaudeSessionsReducer()
        model.sessions = []
        model.usage = nil
        context.activities.setTabs([])
        context.activities.endAll()
    }

    /// Follows the two switches in Settings while the module runs.
    func applySettings() {
        guard isRunning else { return }
        if settings.statusEnabled {
            ensureHookClient()
            context.services.api.register(owner: Self.descriptor.id, prefix: "/v1/claude", scope: .claude) { [weak self] request in
                await self?.handleHook(request) ?? .noContent
            }
        } else {
            context.services.api.unregister(owner: Self.descriptor.id)
            for waiter in waiters.values { waiter.resolve("dismissed") }
            _ = reducer.reduce(.reset, now: Date())
            reducer = ClaudeSessionsReducer()
            model.sessions = []
            context.activities.endAll()
            context.activities.setTabs(tabs())
        }
        if settings.usageEnabled { startUsage() } else { stopUsage() }
    }

    // MARK: Hook client

    /// Makes sure `notched-hook` has a token: one internal API client, its
    /// token in a private file. A missing file or client is recreated.
    private func ensureHookClient() {
        let api = context.services.api
        let fileManager = FileManager.default
        if api.internalClient(named: Self.clientName) != nil, fileManager.fileExists(atPath: settings.tokenFileURL.path) { return }
        if let old = api.internalClient(named: Self.clientName) { api.revoke(clientID: old.id) }
        guard let created = api.createClient(name: Self.clientName, scopes: [.claude], isInternal: true) else {
            Log.module("claudecode").error("Couldn't create the hook client")
            return
        }
        let directory = settings.tokenFileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            // Created private from the start, never world-readable even for an instant.
            fileManager.createFile(atPath: settings.tokenFileURL.path, contents: Data(created.token.utf8), attributes: [.posixPermissions: 0o600])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.tokenFileURL.path)
        } catch {
            Log.module("claudecode").error("Couldn't write the hook token file")
        }
    }

    // MARK: Hooks

    private func handleHook(_ api: APIContext) async -> HTTPResponse {
        guard isRunning, settings.statusEnabled else { return .noContent }
        guard api.request.method == "POST", api.request.path == "/v1/claude/hook" else {
            return .error(404, "not_found", "No such endpoint.")
        }
        guard let event = ClaudeHookEvent.parse(api.request.body) else {
            return .error(400, "invalid_payload", "That isn't a Claude Code hook payload.")
        }
        guard event.kind == .permissionRequest else {
            apply(.hook(event, approvalID: nil), now: api.now)
            return .noContent
        }

        // Don't leave Claude Code waiting behind a card nobody can see.
        if let presence = context.services.presence, presence.isPaused || presence.isSuspended || !presence.anyIslandShown {
            apply(.hook(event, approvalID: nil), now: api.now)
            return .noContent
        }

        let approvalID = UUID().uuidString
        let waiter = ApprovalWaiter()
        waiters[approvalID] = waiter
        apply(.hook(event, approvalID: approvalID), now: api.now)
        let outcome = await waiter.wait(timeout: TimeInterval(context.settings.api.approvalWait))
        waiters[approvalID] = nil

        if outcome == "answered", let stored = replies.removeValue(forKey: approvalID), let reply = stored {
            return HTTPResponse(status: 200, body: reply.body)
        }
        replies[approvalID] = nil
        if outcome != "answered" { apply(.approvalClosed(approvalID: approvalID)) }
        return .noContent
    }

    func choose(approvalID: String, _ answer: ClaudeSessionsReducer.Answer) {
        apply(.answered(approvalID: approvalID, answer))
    }

    private func apply(_ event: ClaudeSessionsReducer.Event, now: Date = Date()) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: now) {
            switch effect {
            case .post(let snapshot, let alert):
                let activity = ClaudePresentation.activity(snapshot) { [weak self] id, answer in self?.choose(approvalID: id, answer) }
                context.activities.post(activity, alert: alert ? AlertRequest(duration: .seconds(20), sound: "Glass") : nil)
            case .end(let sessionID, let immediate):
                context.activities.end(ClaudePresentation.activityID(sessionID), dismissal: immediate ? .immediate : .default)
            case .banner(let banner, let sessionID):
                context.activities.show(ClaudePresentation.banner(banner, sessionID: sessionID))
            case .reply(let approvalID, let reply):
                replies[approvalID] = .some(reply)
                waiters[approvalID]?.resolve("answered")
            case .wake(let date):
                wake.schedule(at: date)
            }
        }
        model.sessions = reducer.sessions.keys.compactMap { reducer.snapshot(of: $0) }
            .filter { $0.phase != .idle }
            .sorted { $0.lastEvent > $1.lastEvent }
    }

    // MARK: Usage tab

    private func tabs() -> [IslandTab] {
        guard settings.usageEnabled else { return [] }
        let model = model
        return [IslandTab(
            id: Self.tabID, moduleID: Self.descriptor.id, title: "AI", symbol: "sparkles",
            accessibilityLabel: "Claude Code usage", order: 10,
            onVisibilityChange: { [weak self] visible in self?.tabVisibilityChanged(visible) }
        ) { ClaudeAITabView(model: model) }]
    }

    private func startUsage() {
        context.activities.setTabs(tabs())
        guard watcher == nil else { return }
        usage = ClaudeUsageService()
        // If Claude Code hasn't run yet there's no projects folder; watch ~/.claude so it is noticed when it appears.
        var paths = ClaudeUsageService.defaultRoots().map(\.path)
        let claudeHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        if paths.isEmpty, FileManager.default.fileExists(atPath: claudeHome) { paths = [claudeHome] }
        if !paths.isEmpty {
            watcher = DirectoryWatcher(paths: paths) { [weak self] in
                Task { @MainActor in self?.logsChanged() }
            }
        }
    }

    private func stopUsage() {
        watcher?.stop()
        watcher = nil
        usage = nil
        refreshTask?.cancel()
        tabVisible = false
        model.usage = nil
        context.activities.setTabs([])
    }

    private func tabVisibilityChanged(_ visible: Bool) {
        tabVisible = visible
        if visible, logsChangedSinceRefresh || model.usage == nil { scheduleRefresh(after: .zero) }
    }

    /// FSEvents only says something changed; nothing is read until the tab is on screen.
    private func logsChanged() {
        logsChangedSinceRefresh = true
        if tabVisible { scheduleRefresh(after: .seconds(1)) }
    }

    private func scheduleRefresh(after delay: Duration) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let service = self.usage else { return }
            self.logsChangedSinceRefresh = false
            let snapshot = await service.refresh()
            guard !Task.isCancelled else { return }
            self.model.usage = snapshot
        }
    }
}
