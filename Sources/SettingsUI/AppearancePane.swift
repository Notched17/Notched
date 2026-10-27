// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AppearancePane: View {
    @Bindable var settings: SettingsStore
    let accessibility: AccessibilityOptions

    var body: some View {
        Form {
            Section {
                IslandPreview(settings: settings, accessibility: accessibility)
            } footer: {
                Text("Rest the pointer on the preview, or choose Replay, to try your settings.")
            }

            Section {
                Picker("Notched displays", selection: $settings.notchTheme) {
                    ForEach(IslandTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("Other displays", selection: $settings.pillTheme) {
                    ForEach(IslandTheme.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keyline in Dark Mode", isOn: $settings.keyline)
            } header: {
                Text("Theme")
            } footer: {
                Text("On a notched display the compact island always stays black, so it blends into the notch. The keyline is a subtle border that keeps bubbles and the open island distinct in Dark Mode. With Reduce Transparency, glass themes use a solid colour.")
            }

            Section("Motion") {
                Picker("Animation", selection: $settings.animationStyle) {
                    ForEach(AnimationStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledSlider(
                    title: "Hover delay", value: $settings.hoverDelay,
                    range: SettingsStore.hoverDelayRange, step: 0.05
                ) { String(format: "%.2f s", $0) }
            }

            Section("Size") {
                LabeledSlider(
                    title: "Compact width", value: $settings.widthOffset,
                    range: SettingsStore.widthOffsetRange, step: 2
                ) { $0 == 0 ? "Standard" : String(format: "%+.0f pt", $0) }
                LabeledSlider(
                    title: "Expanded size", value: $settings.expandedScale,
                    range: SettingsStore.expandedScaleRange, step: 0.05
                ) { String(format: "%.0f%%", $0 * 100) }
            }
        }
        .formStyle(.grouped)
    }
}

/// A slider row with its current value shown on the right.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.m) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 160)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
    }
}
