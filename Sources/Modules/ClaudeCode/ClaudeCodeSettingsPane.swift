// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Settings ▸ Modules ▸ Claude Code: the two switches, and installing or
/// removing the hooks with a preview of exactly what changes.
struct ClaudeCodeSettingsPane: View {
    @Bindable var settings: ClaudeCodeSettings
    @Bindable var api: LocalAPISettings
    let registry: ModuleRegistry
    @State private var status = ClaudeSettingsMerger.Status.notInstalled
    @State private var plan: HookInstaller.Plan?
    @State private var message: String?

    private let installer = HookInstaller.standard()

    private var module: ClaudeCodeModule? { registry.module(ClaudeCodeModule.descriptor.id) as? ClaudeCodeModule }

    var body: some View {
        Form {
            Section {
                Toggle("Status and approvals", isOn: $settings.statusEnabled)
                    .onChange(of: settings.statusEnabled) { module?.applySettings() }
                LabeledContent("Hooks") { Text(statusText).foregroundStyle(statusColor) }
                HStack {
                    Button(status == .notInstalled ? "Install Hooks…" : "Update Hooks…") { preview(.install) }
                    Button("Remove Hooks…") { preview(.remove) }.disabled(status == .notInstalled)
                }
                Stepper("Wait for your answer: \(api.approvalWait) s", value: $api.approvalWait, in: LocalAPISettings.approvalWaitRange, step: 15)
                if let message { Text(verbatim: message).font(.callout).foregroundStyle(.red) }
            } footer: {
                Text("Hooks make Claude Code tell Notched what it's doing, and ask it first when it needs permission. If Notched is closed or you don't answer in time, Claude Code asks in the terminal as usual. Notched edits ~/.claude/settings.json only after showing you the change, and keeps a backup.")
            }

            Section {
                Toggle("AI tab with token usage", isOn: $settings.usageEnabled)
                    .onChange(of: settings.usageEnabled) { module?.applySettings() }
            } footer: {
                Text("Reads Claude Code's session logs on this Mac (~/.claude/projects). Nothing is sent anywhere and no login is needed. Costs are estimates at API prices; a subscription isn't billed per token. Prices are in claude-pricing.json, which you can override in ~/Library/Application Support/Notched.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Claude Code")
        .onAppear(perform: refreshStatus)
        .sheet(item: Binding(get: { plan.map(PlanBox.init) }, set: { if $0 == nil { plan = nil } })) { box in
            DiffSheet(plan: box.plan, apply: { apply(box.plan) }, cancel: { plan = nil })
        }
    }

    private var statusText: String {
        switch status {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .partial: "Partly installed"
        case .outdated: "Installed, needs updating"
        }
    }

    private var statusColor: Color { status == .installed ? .green : .secondary }

    private func refreshStatus() {
        status = installer.status(approvalWait: api.approvalWait)
    }

    private func preview(_ kind: HookInstaller.Plan.Kind) {
        message = nil
        let result = kind == .install ? installer.planInstall(approvalWait: api.approvalWait) : installer.planRemove(record: settings.installRecord)
        switch result {
        case .failure(let error): message = error.text
        case .success(let found):
            if found.isNoOp && kind == .install && installer.cliIsInstalled { message = "Already installed; nothing to change."; return }
            plan = found
        }
    }

    private func apply(_ plan: HookInstaller.Plan) {
        switch installer.apply(plan, previous: settings.installRecord) {
        case .failure(let error):
            message = error.text
        case .success(let record):
            settings.installRecord = record
            message = nil
        }
        self.plan = nil
        refreshStatus()
    }
}

private struct PlanBox: Identifiable {
    let plan: HookInstaller.Plan
    var id: String { plan.baseHash ?? "none" }
}

extension PlanBox: Equatable {
    static func == (lhs: PlanBox, rhs: PlanBox) -> Bool { lhs.id == rhs.id }
}

private struct DiffSheet: View {
    let plan: HookInstaller.Plan
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plan.kind == .install ? "Install Claude Code hooks" : (plan.isRestore ? "Restore the original settings" : "Remove Claude Code hooks"))
                .font(.headline)
            Text("This is exactly what changes in ~/.claude/settings.json.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(plan.diff) { line in
                        Text(verbatim: prefix(line) + line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(background(line))
                    }
                    if plan.diff.isEmpty { Text("No changes to settings.json.").foregroundStyle(.secondary).padding(6) }
                }
            }
            .frame(height: 260)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if plan.kind == .install {
                Text("Also copies the notched-hook helper to ~/.local/bin. A backup of settings.json is saved next to it first.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(plan.kind == .install ? "Install" : "Remove", action: apply).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private func prefix(_ line: LineDiff.Line) -> String {
        switch line.kind {
        case .added: "+ "
        case .removed: "- "
        case .same: "  "
        case .gap: "  "
        }
    }

    private func background(_ line: LineDiff.Line) -> Color {
        switch line.kind {
        case .added: .green.opacity(0.18)
        case .removed: .red.opacity(0.18)
        default: .clear
        }
    }
}
