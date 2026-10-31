// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The layout editor (#71; it replaces the Priority page): what the island
/// shows first and beside the notch (#8), and which tabs open in the expanded
/// island and in what order. A live preview shows the result.
///
/// Every control is a button or a toggle, so none of it needs a drag; the tab
/// list can also be dragged to reorder where macOS allows it.
struct LayoutPane: View {
    @Bindable var settings: SettingsStore
    let modules: [ModuleDescriptor]
    let registry: ModuleRegistry
    let accessibility: AccessibilityOptions

    @State private var previewActivities = LayoutPreviewSamples.makeCoordinator()

    private var policy: RankingPolicy { settings.activityRanking.normalized() }
    private var layout: TabLayout { settings.tabLayout.normalized() }

    private var pinnedModules: [ModuleDescriptor] {
        policy.pinned.compactMap { id in modules.first { $0.id == id } }
    }

    private var pinnableModules: [ModuleDescriptor] {
        modules.filter { !policy.pinned.contains($0.id) && !LayoutCatalogue.fixedFirst.contains($0.id) && !$0.isDebugOnly }
    }

    private var compactModules: [ModuleDescriptor] {
        LayoutCatalogue.compactModules.compactMap { id in modules.first { $0.id == id } }.filter { !LayoutCatalogue.fixedFirst.contains($0.id) }
    }

    private var editorTabs: [LayoutCatalogue.TabInfo] {
        LayoutCatalogue.editorTabs(live: registry.liveTabs, layout: layout)
    }

    private var isDefault: Bool { policy == .default && layout == .default }

    var body: some View {
        Form {
            Section {
                IslandPreview(settings: settings, accessibility: accessibility, activities: previewActivities)
            } header: {
                Text("Preview")
            } footer: {
                Text("Hover the island above to open it. It shows sample activities and every tab, so you can see your changes.")
            }

            compactSection
            pinnedSection
            showInCompactSection
            tabsSection

            Section {
                Button("Reset to Default") {
                    settings.activityRanking = .default
                    settings.tabLayout = .default
                }
                .disabled(isDefault)
            } footer: {
                Text("Puts the order, the pins, the compact choices and the tabs back the way they were.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
        .onAppear(perform: syncPreview)
        .onChange(of: settings.activityRanking) { syncPreview() }
        .onChange(of: settings.tabLayout) { syncPreview() }
        .onChange(of: registry.liveTabs) { syncPreview() }
    }

    // MARK: Sections

    private var compactSection: some View {
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
            Text("Compact Island")
        } footer: {
            Text("When several things are happening, the island shows the highest one beside the notch and the next two as small bubbles. A call always stays on top.")
        }
    }

    private var pinnedSection: some View {
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
    }

    private var showInCompactSection: some View {
        Section {
            ForEach(compactModules) { module in
                Toggle(isOn: Binding(
                    get: { !policy.isListedOnly(module.id) },
                    set: { settings.activityRanking = policy.showingInCompact(module.id, $0) }
                )) {
                    Label(module.name, systemImage: module.symbol)
                }
            }
        } header: {
            Text("Show in Compact")
        } footer: {
            Text("Turn a module off to keep it out of the notch's sides and the bubbles. Its activities still show when you open the island. Calls always show.")
        }
    }

    private var tabsSection: some View {
        Section {
            let tabs = editorTabs
            ForEach(tabs) { tab in
                LabeledContent {
                    HStack(spacing: Spacing.s) {
                        MoveButtons(
                            name: tab.title,
                            canMoveUp: tab.id != tabs.first?.id,
                            canMoveDown: tab.id != tabs.last?.id,
                            move: { settings.tabLayout = layout.moving(tab.id, by: $0, among: tabs.map(\.id)) }
                        )
                        Toggle("Show \(tab.title)", isOn: Binding(
                            get: { !layout.isHidden(tab.id) },
                            set: { settings.tabLayout = layout.setting(tab.id, visible: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                } label: {
                    Label {
                        Text(tab.title)
                        Text("From \(tab.moduleName)")
                    } icon: {
                        Image(systemName: tab.symbol)
                    }
                }
            }
            .onMove { source, destination in
                settings.tabLayout = layout.moving(fromOffsets: source, toOffset: destination, among: tabs.map(\.id))
            }
        } header: {
            Text("Expanded Tabs")
        } footer: {
            Text("The island shows up to four tabs besides Island. A tab you turn off doesn't use one of the four, so you can choose which four you want. A tab only appears while the module that adds it is on.")
        }
    }

    // MARK: Preview

    /// Keeps the sample island's ranking, tab layout and tabs in step with the settings.
    private func syncPreview() {
        var configuration = previewActivities.configuration
        configuration.ranking = settings.activityRanking
        configuration.tabLayout = settings.tabLayout
        previewActivities.configuration = configuration
        LayoutPreviewSamples.setTabs(on: previewActivities, tabs: LayoutCatalogue.editorTabs(live: registry.liveTabs, layout: .default))
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

/// Move up / move down for a row in a list.
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
