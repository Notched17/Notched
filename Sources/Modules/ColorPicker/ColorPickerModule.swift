// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Colour Picker (#55): an eyedropper in Home's tools row. A thin shell around
/// `ColorPickerReducer`; `NSColorSampler` is public and needs no Screen
/// Recording permission. Does nothing until the user picks a colour.
@MainActor
final class ColorPickerModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "colorpicker",
        name: "Colour Picker",
        symbol: "eyedropper",
        summary: "Pick any colour on your screen and copy it as HEX, RGB or HSL. It does nothing until you use it.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(ColorPickerSettingsPane(settings: context.settings.colorPicker, registry: context.registry))
    }

    let model = ColorPickerModel()
    private let context: ModuleContext
    private let sampler: any ColorSampling
    private let copiedReset = OneShotTimer()
    private var reducer = ColorPickerReducer()
    private var isRunning = false
    private var isSampling = false
    private let log = Log.module("colorpicker")

    convenience init(context: ModuleContext) {
        self.init(context: context, sampler: SystemColorSampler())
    }

    init(context: ModuleContext, sampler: any ColorSampling) {
        self.context = context
        self.sampler = sampler
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = ColorPickerActions(
            pick: { [weak self] in self?.pick() },
            select: { [weak self] color in self?.send(.selected(color)) },
            copy: { [weak self] format in self?.copy(format) }
        )
        copiedReset.action = { [weak self] in self?.model.copied = nil }
        send(.loaded(context.settings.colorPicker.recents))
        publishHomeAction()
    }

    func stop() {
        isRunning = false
        copiedReset.schedule(at: nil)
        model.actions = ColorPickerActions()
        model.copied = nil
        reducer = ColorPickerReducer()
        model.sync(from: reducer.state)
        context.activities.endAll()
    }

    // MARK: Picking

    /// Starts the system eyedropper. One at a time; Esc cancels and changes nothing.
    func pick() {
        guard isRunning, !isSampling else { return }
        isSampling = true
        sampler.sample { [weak self] sample in
            guard let self else { return }
            self.isSampling = false
            guard self.isRunning, let sample else { return }
            self.send(.picked(sample.color, outsideGamut: sample.outsideGamut))
        }
    }

    /// Empties the recent row (the settings pane's button).
    func clearRecents() { send(.clearRecents) }

    func copy(_ format: ColorFormat) {
        guard isRunning, let color = reducer.state.current else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(format.text(for: color), forType: .string)
        model.copied = format
        copiedReset.schedule(at: Date().addingTimeInterval(1.5))
    }

    private func send(_ event: ColorPickerReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .persist(let colors): context.settings.colorPicker.recents = colors
            }
        }
        model.sync(from: reducer.state)
    }

    private func publishHomeAction() {
        guard isRunning else { return }
        let model = model
        context.activities.setHomeActions([HomeAction(
            id: "colorpicker",
            moduleID: Self.descriptor.id,
            title: "Colour",
            symbol: "eyedropper",
            accessibilityValue: nil,
            panel: IslandRegion { ColorPickerPanel(model: model) }
        )])
    }

    // MARK: Status menu

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Pick Colour…") { [weak self] in self?.pick() }]
    }
}

// MARK: Sampling

/// What the eyedropper found: the colour in sRGB, and whether it had to be clamped.
struct ColorSample: Equatable, Sendable {
    var color: ColorValue
    var outsideGamut: Bool
}

/// Lets tests stand in for the system eyedropper.
@MainActor
protocol ColorSampling: AnyObject {
    /// Calls back once, on the main actor: nil if the user cancelled.
    func sample(_ completion: @escaping @MainActor @Sendable (ColorSample?) -> Void)
}

/// `NSColorSampler`: the loupe the system draws over the screen. No permission.
@MainActor
final class SystemColorSampler: ColorSampling {
    private let sampler = NSColorSampler()

    func sample(_ completion: @escaping @MainActor @Sendable (ColorSample?) -> Void) {
        sampler.show { color in
            // Read the numbers here so no NSColor crosses to the main actor.
            let sample = color.flatMap { Self.sample(from: $0) }
            Task { @MainActor in completion(sample) }
        }
    }

    private nonisolated static func sample(from color: NSColor) -> ColorSample? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let (value, outside) = ColorValue.fromUnit(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
        return ColorSample(color: value, outsideGamut: outside)
    }
}

// MARK: Model and views

/// What the colour picker's views can do.
@MainActor
struct ColorPickerActions {
    var pick: () -> Void = {}
    var select: (ColorValue) -> Void = { _ in }
    var copy: (ColorFormat) -> Void = { _ in }
}

@MainActor
@Observable
final class ColorPickerModel {
    var current: ColorValue?
    var outsideGamut = false
    var recents: [ColorValue] = []
    /// The format just copied, shown as a tick for a moment.
    var copied: ColorFormat?
    @ObservationIgnored var actions = ColorPickerActions()

    func sync(from state: ColorPickerReducer.State) {
        current = state.current
        outsideGamut = state.outsideGamut
        recents = state.recents
    }
}

extension ColorValue {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

/// Home's colour panel: the eyedropper button, then the picked colour with
/// copy buttons, then the recent row.
struct ColorPickerPanel: View {
    let model: ColorPickerModel
    @Environment(\.closeHomePanel) private var closePanel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Button("Pick Colour", systemImage: "eyedropper") {
                    // Leave the island's panel first so the loupe isn't fighting it.
                    closePanel()
                    model.actions.pick()
                }
                .buttonStyle(.island(prominent: .accentColor))
                .accessibilityHint("Shows a magnifier to pick any colour on the screen")

                if let color = model.current {
                    Swatch(color: color)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(ColorFormat.allCases, id: \.self) { format in
                            CopyRow(format: format, text: format.text(for: color), isCopied: model.copied == format) {
                                model.actions.copy(format)
                            }
                        }
                    }
                }
            }
            if model.current != nil, model.outsideGamut {
                Text("Outside sRGB: clamped to the closest colour.")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
            }
            if !model.recents.isEmpty {
                RecentRow(model: model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Swatch: View {
    let color: ColorValue

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.swiftUIColor)
            .frame(width: 52, height: 52)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("Picked colour \(color.hex)")
    }
}

private struct CopyRow: View {
    let format: ColorFormat
    let text: String
    let isCopied: Bool
    let copy: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(format.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Spacing.xs)
            Button(isCopied ? "Copied" : "Copy \(format.rawValue)", systemImage: isCopied ? "checkmark" : "doc.on.doc", action: copy)
                .labelStyle(.iconOnly)
                .buttonStyle(.island)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityLabel("Copy \(format.rawValue) value")
        }
    }
}

private struct RecentRow: View {
    let model: ColorPickerModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(model.recents, id: \.self) { color in
                Button { model.actions.select(color) } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(model.current == color ? 0.9 : 0.25), lineWidth: model.current == color ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent colour \(color.hex)")
            }
        }
    }
}

// MARK: Settings

struct ColorPickerSettingsPane: View {
    let settings: ColorPickerSettings
    let registry: ModuleRegistry

    private var module: ColorPickerModule? { registry.module(ColorPickerModule.descriptor.id) as? ColorPickerModule }

    var body: some View {
        Form {
            Section {
                LabeledContent("Use it from", value: "Home ▸ Colour, or the menu bar")
                LabeledContent("Permission", value: "None needed")
                LabeledContent("Recent colours", value: "\(settings.recents.count) of \(ColorPickerReducer.recentLimit)")
                Button("Clear Recent Colours", role: .destructive) {
                    if let module { module.clearRecents() } else { settings.recents = [] }
                }
                .disabled(settings.recents.isEmpty)
            } footer: {
                Text("The magnifier is macOS's own eyedropper, so Notched never sees your screen and doesn't need Screen Recording. Colours are shown in sRGB.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Colour Picker")
    }
}
