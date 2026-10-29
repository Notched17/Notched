// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// What the island shows first when several things are happening (#8).
/// A call always stays on top; the user orders the rest and can pin modules
/// above everything but a call.
struct PriorityPane: View {
    @Bindable var settings: SettingsStore
    let modules: [ModuleDescriptor]

    /// Modules whose activities are always system class, where pinning means nothing.
    private static let systemOnlyModules: Set<ModuleID> = ["calls"]

    private var policy: RankingPolicy { settings.activityRanking.normalized() }

    private var pinnedModules: [ModuleDescriptor] {
        policy.pinned.compactMap { id in modules.first { $0.id == id } }
    }

    private var pinnableModules: [ModuleDescriptor] {
        modules.filter { !policy.pinned.contains($0.id) && !Self.systemOnlyModules.contains($0.id) && !$0.isDebugOnly }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text("Always first").foregroundStyle(.secondary)
                } label: {
                    Label("Calls & screen recording", systemImage: "phone.fill")
                }
                ForEach(policy.order, id: \.self) { kind in
                    LabeledContent {
                        MoveButtons(
                            name: Self.name(of: kind),
                            canMoveUp: kind != policy.order.first,
                            canMoveDown: kind != policy.order.last,
                            move: { settings.activityRanking = policy.moving(kind, by: $0) }
                        )
                    } label: {
                        Label(Self.name(of: kind), systemImage: Self.symbol(of: kind))
                    }
                }
            } header: {
                Text("Order")
            } footer: {
                Text("When several things are happening, the island shows the highest one beside the notch and the next two as small bubbles. A call always stays on top.")
            }

            Section {
                ForEach(pinnedModules) { module in
                    LabeledContent {
                        HStack(spacing: Spacing.s) {
                            MoveButtons(
                                name: module.name,
                                canMoveUp: module.id != policy.pinned.first,
                                canMoveDown: module.id != policy.pinned.last,
                                move: { settings.activityRanking = policy.movingPin(module.id, by: $0) }
                            )
                            Button {
                                settings.activityRanking = policy.unpinning(module.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Unpin \(module.name)")
                            .accessibilityLabel("Unpin \(module.name)")
                        }
                    } label: {
                        Label(module.name, systemImage: module.symbol)
                    }
                }
                Menu("Pin a Module…") {
                    ForEach(pinnableModules) { module in
                        Button(module.name, systemImage: module.symbol) {
                            settings.activityRanking = policy.pinning(module.id)
                        }
                    }
                }
                .disabled(pinnableModules.isEmpty)
            } header: {
                Text("Pinned")
            } footer: {
                Text("A pinned module goes above everything except a call, in the order shown here.")
            }

            Section {
                Button("Reset to Default") { settings.activityRanking = .default }
                    .disabled(policy == .default)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Priority")
    }

    static func name(of kind: ActivityKind) -> String {
        switch kind {
        case .media: "Now Playing"
        case .live: "Timers, downloads & tools"
        case .passive: "Status"
        case .system: "Calls & screen recording"
        }
    }

    static func symbol(of kind: ActivityKind) -> String {
        switch kind {
        case .media: "music.note"
        case .live: "timer"
        case .passive: "info.circle"
        case .system: "phone.fill"
        }
    }
}

/// Move up / move down for a row in a priority list.
private struct MoveButtons: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .help("Move \(name) up")
                .accessibilityLabel("Move \(name) up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .help("Move \(name) down")
                .accessibilityLabel("Move \(name) down")
        }
        .buttonStyle(.borderless)
    }
}
