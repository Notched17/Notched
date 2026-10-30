// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Lets other tools post live activities, banners and approval requests to
/// the island over a localhost-only HTTP API with per-client tokens
/// (docs/ACTIVITY-API.md, ADR-0021). A thin shell: `ActivityPayload`
/// validates, `ActivityAPIReducer` holds the rules, `APIGateway` does the
/// authentication. With the module off there is no socket.
@MainActor
final class ActivityAPIModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "activityapi",
        name: "Activity API",
        symbol: "point.3.connected.trianglepath.dotted",
        summary: "Lets scripts and apps you trust show activities, banners and approval requests in the island, through a local-only API with tokens you create.",
        permissions: [],
        isDebugOnly: false
    )

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        guard let api = context.api else { return nil }
        return AnyView(ActivityAPISettingsPane(api: api, registry: context.registry))
    }

    private let context: ModuleContext
    private var reducer = ActivityAPIReducer()
    private let wake = OneShotTimer()
    private var approvals: [String: ApprovalWaiter] = [:]
    private var bannerLimits: [String: RateLimit] = [:]
    private var approvalLimits: [String: RateLimit] = [:]
    private var isRunning = false

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let api = context.services.api
        let id = Self.descriptor.id
        wake.action = { [weak self] in self?.apply(.tick) }
        api.register(owner: id, prefix: "/v1/activities", scope: .activity) { [weak self] request in
            await self?.handleActivities(request) ?? .error(503, "disabled", "The Activity API is off.")
        }
        api.register(owner: id, prefix: "/v1/banners", scope: .banner) { [weak self] request in
            self?.handleBanner(request) ?? .error(503, "disabled", "The Activity API is off.")
        }
        api.register(owner: id, prefix: "/v1/approvals", scope: .approval) { [weak self] request in
            await self?.handleApproval(request) ?? .error(503, "disabled", "The Activity API is off.")
        }
        api.onRevoke(owner: id) { [weak self] clientID in
            self?.apply(.revoke(clientID: clientID))
            self?.approvals[clientID]?.resolve("dismissed")
        }
    }

    func stop() {
        isRunning = false
        wake.schedule(at: nil)
        for waiter in approvals.values { waiter.resolve("dismissed") }
        approvals.removeAll()
        bannerLimits.removeAll()
        approvalLimits.removeAll()
        context.services.api.unregister(owner: Self.descriptor.id)
        _ = reducer.reduce(.reset, now: Date())
        reducer = ActivityAPIReducer()
        context.activities.endAll()
    }

    // MARK: Activities

    @discardableResult
    private func apply(_ event: ActivityAPIReducer.Event, now: Date = Date()) -> [ActivityAPIReducer.Effect] {
        let effects = reducer.reduce(event, now: now)
        for effect in effects {
            switch effect {
            case .post(let key, let entry, let alert):
                let activity = ActivityAPIPresentation.activity(key: key, entry: entry, moduleID: Self.descriptor.id)
                context.activities.post(activity, alert: alert ? AlertRequest() : nil)
            case .end(let key, let immediate):
                context.activities.end(ActivityAPIPresentation.activityID(key), dismissal: immediate ? .immediate : .default)
            case .wake(let date):
                wake.schedule(at: date)
            case .accepted, .rejected:
                break
            }
        }
        return effects
    }

    private func handleActivities(_ api: APIContext) async -> HTTPResponse {
        guard isRunning else { return .error(503, "disabled", "The Activity API is off.") }
        let parts = api.request.path.split(separator: "/").map(String.init)
        if parts.count == 2 {
            guard api.request.method == "GET" else { return .error(405, "method_not_allowed", "Use GET to list activities.") }
            let items = reducer.entries(of: api.client.id).map { ["id": $0.id, "state": "active"] }
            return .json(200, ["activities": items])
        }
        guard parts.count == 3, ActivityPayload.isValidID(parts[2]) else {
            return .error(404, "not_found", "Activity ids are 1–64 characters of letters, digits, dot, dash and underscore.")
        }
        let id = parts[2]
        let key = ActivityKey(clientID: api.client.id, id: id)
        switch api.request.method {
        case "PUT":
            switch ActivityPayload.parse(api.request.body, now: api.now) {
            case .failure(let error):
                return error.response
            case .success(let spec):
                let effects = apply(.put(key, spec, clientName: api.client.name), now: api.now)
                for effect in effects {
                    if case .rejected(let rejection) = effect { return rejection.response }
                    if case .accepted(let created) = effect {
                        return .json(created ? 201 : 200, ["id": id, "state": "active"])
                    }
                }
                return .error(500, "internal", "The activity wasn't posted.")
            }
        case "DELETE":
            let effects = apply(.delete(key), now: api.now)
            if case .rejected(let rejection)? = effects.first { return rejection.response }
            if api.request.query["dismiss"] == "immediate" {
                context.activities.end(ActivityAPIPresentation.activityID(key), dismissal: .immediate)
            }
            return .noContent
        default:
            return .error(405, "method_not_allowed", "Use PUT to post or update and DELETE to end.")
        }
    }

    // MARK: Banners

    private func handleBanner(_ api: APIContext) -> HTTPResponse {
        guard isRunning else { return .error(503, "disabled", "The Activity API is off.") }
        guard api.request.method == "POST", api.request.path == "/v1/banners" else {
            return .error(405, "method_not_allowed", "POST a banner to /v1/banners.")
        }
        switch ActivityPayload.parseBanner(api.request.body) {
        case .failure(let error):
            return error.response
        case .success(let spec):
            var limit = bannerLimits[api.client.id] ?? RateLimit(minimumInterval: 1, maxPerWindow: 10, window: 60)
            let allowed = limit.allow(at: api.now)
            bannerLimits[api.client.id] = limit
            guard allowed else { return .error(429, "rate_limited", "Too many banners.", headers: ["Retry-After": "10"]) }
            showBanner(spec, clientID: api.client.id, source: api.client.name)
            return .json(202, ["queued": true])
        }
    }

    /// Shows a banner from a client, or from a `notched://banner` link.
    func showBanner(_ spec: ActivityPayload.BannerSpec, clientID: String, source: String) {
        let tint = spec.tint.color
        let symbol = spec.symbol.map { ActivityAPIPresentation.symbolName($0, template: .status) }
        let content = BannerContent(symbol: symbol, symbolTint: tint, label: spec.title, value: spec.subtitle)
        context.activities.show(.standard(
            id: "activityapi.banner.\(clientID)",
            moduleID: Self.descriptor.id,
            content: content,
            accessibilityLabel: [spec.title, spec.subtitle, "from \(source)"].compactMap { $0 }.joined(separator: ", ")
        ))
    }

    // MARK: Approvals

    private func handleApproval(_ api: APIContext) async -> HTTPResponse {
        guard isRunning else { return .error(503, "disabled", "The Activity API is off.") }
        guard api.request.method == "POST", api.request.path == "/v1/approvals" else {
            return .error(405, "method_not_allowed", "POST an approval request to /v1/approvals.")
        }
        guard approvals[api.client.id] == nil else {
            return .error(409, "approval_pending", "This client already has an approval request open.")
        }
        // Each request expands the island, so a client can't ask again straight away.
        var limit = approvalLimits[api.client.id] ?? RateLimit(minimumInterval: 5, maxPerWindow: 6, window: 60)
        let allowed = limit.allow(at: api.now)
        approvalLimits[api.client.id] = limit
        guard allowed else { return .error(429, "rate_limited", "Too many approval requests.", headers: ["Retry-After": "10"]) }
        guard let object = try? JSONSerialization.jsonObject(with: api.request.body), let json = object as? [String: Any],
              let rawTitle = json["title"] as? String else {
            return .error(400, "invalid_payload", "title is required.", field: "title")
        }
        let title = ActivityPayload.sanitize(rawTitle, limit: ActivityPayload.titleLimit)
        guard !title.isEmpty else { return .error(400, "invalid_payload", "title can't be empty.", field: "title") }
        let detail = ActivityPayload.sanitize((json["detail"] as? String) ?? "", limit: 160)
        let requested = (json["options"] as? [String]) ?? ["allow", "deny"]
        let wantsAllow = requested.contains("allow"), wantsDeny = requested.contains("deny")
        guard wantsAllow || wantsDeny else { return .error(400, "invalid_payload", "options must include allow or deny.", field: "options") }
        let timeout = min(max((json["timeout"] as? NSNumber)?.doubleValue ?? 60, 5), 120)
        let symbol = (json["symbol"] as? String).flatMap { ActivityPayload.isValidSymbolName($0) ? $0 : nil }

        let waiter = ApprovalWaiter()
        approvals[api.client.id] = waiter
        let activityID = ActivityID("activityapi.approval.\(api.client.id)")
        var choices: [ApprovalChoice] = []
        if wantsDeny { choices.append(ApprovalChoice(id: "deny", title: "Deny")) }
        if wantsAllow { choices.append(ApprovalChoice(id: "allow", title: "Allow", role: .primary)) }
        let model = ApprovalCardModel(symbol: ActivityAPIPresentation.symbolName(symbol, template: .status),
                                      title: title, context: "from \(api.client.name)", detail: detail, primary: choices)
        let moduleID = Self.descriptor.id
        context.activities.post(
            LiveActivity(
                id: activityID, moduleID: moduleID, kind: .live, title: title, relevance: 1.0,
                accessibilityLabel: "\(title), approval requested by \(api.client.name)", staleNote: nil,
                presentation: Self.approvalPresentation(model, choose: { waiter.resolve($0) })
            ),
            alert: AlertRequest(duration: .seconds(min(timeout, 20)))
        )
        let decision = await waiter.wait(timeout: timeout)
        approvals[api.client.id] = nil
        context.activities.end(activityID, dismissal: .immediate)
        return .json(200, ["decision": decision])
    }

    static func approvalPresentation(_ model: ApprovalCardModel, choose: @escaping @MainActor (String) -> Void) -> ActivityPresentation {
        ActivityPresentation(
            compactLeading: IslandRegion {
                Image(systemName: model.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
            },
            compactTrailing: IslandRegion {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
            },
            minimal: IslandRegion {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.orange)
            },
            expanded: ApprovalCard.expanded(model, tint: .orange, choose: choose)
        )
    }
}
