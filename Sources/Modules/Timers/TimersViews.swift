// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The regions of timer and stopwatch activities (#37). Digits come from
/// `Text(timerInterval:)`, which the system ticks; the ring is Core
/// Animation (`TimerRing`). Nothing here runs a timer of its own.
@MainActor
enum TimersPresentation {
    /// Orange, like the Clock app's timers.
    static let tint = Color.orange

    static func timer(_ item: TimerItem, relevance: Double, model: TimersModel) -> LiveActivity {
        let isDone = if case .done = item.phase { true } else { false }
        return LiveActivity(
            id: TimersModule.activityID(item.id),
            moduleID: TimersModule.descriptor.id,
            kind: .live,
            title: isDone ? "\(item.label) Done" : item.label,
            relevance: relevance,
            keylineTint: tint,
            accessibilityLabel: accessibilityLabel(item),
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { TimerGlyph(item: item, size: 18, lineWidth: 2.5) },
                compactTrailing: IslandRegion { TimerTime(item: item, font: IslandFont.compact) },
                minimal: IslandRegion {
                    if isDone {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                    } else {
                        WidthCap(maxWidth: IslandMetrics.bubbleMaxWidth - 2 * IslandMetrics.bubblePadding) {
                            TimerTime(item: item, font: IslandFont.minimal)
                                .minimumScaleFactor(0.7)
                        }
                    }
                },
                expanded: ExpandedPresentation(
                    // Inset from the screen's top edge, like Now Playing's artwork.
                    leading: ExpandedRegion { TimerGlyph(item: item, size: 40, lineWidth: 4).padding(.top, 6) },
                    trailing: ExpandedRegion { TimerTime(item: item, font: IslandFont.hero) },
                    bottom: ExpandedRegion { TimerExpandedBottom(id: item.id, model: model) }
                )
            )
        )
    }

    static func stopwatch(_ stopwatch: Stopwatch, model: TimersModel) -> LiveActivity {
        LiveActivity(
            id: TimersModule.stopwatchID,
            moduleID: TimersModule.descriptor.id,
            kind: .live,
            title: "Stopwatch",
            relevance: TimersState.stopwatchRelevance,
            keylineTint: tint,
            accessibilityLabel: stopwatch.isRunning ? "Stopwatch running" : "Stopwatch paused at \(remainingText(stopwatch.elapsed(at: Date())))",
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                },
                compactTrailing: IslandRegion { StopwatchTime(stopwatch: stopwatch, font: IslandFont.compact) },
                minimal: IslandRegion {
                    WidthCap(maxWidth: IslandMetrics.bubbleMaxWidth - 2 * IslandMetrics.bubblePadding) {
                        StopwatchTime(stopwatch: stopwatch, font: IslandFont.minimal)
                            .minimumScaleFactor(0.7)
                    }
                },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile {
                            Image(systemName: "stopwatch.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                        .padding(.top, 6)
                    },
                    trailing: ExpandedRegion { StopwatchTime(stopwatch: stopwatch, font: IslandFont.hero) },
                    bottom: ExpandedRegion { StopwatchControls(model: model) }
                )
            )
        )
    }

    /// "4:59" or "1:04:59".
    static func remainingText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let pattern: Duration.TimeFormatStyle.Pattern = whole >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(whole).formatted(.time(pattern: pattern))
    }

    static func accessibilityLabel(_ item: TimerItem) -> String {
        switch item.phase {
        case .running(let endsAt): "\(item.label), ends at \(endsAt.formatted(date: .omitted, time: .shortened))"
        case .paused(let remaining): "\(item.label), paused with \(remainingText(remaining)) left"
        case .done: "\(item.label) done"
        }
    }
}

/// The ring, or a bell once done.
private struct TimerGlyph: View {
    let item: TimerItem
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        if case .done = item.phase {
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(TimersPresentation.tint)
                .symbolEffect(.bounce, options: .repeat(2))
                .frame(width: size, height: size)
        } else {
            TimerRing(item: item, lineWidth: lineWidth)
                .frame(width: size, height: size)
                .opacity(isPaused ? 0.6 : 1)
        }
    }

    private var isPaused: Bool {
        if case .paused = item.phase { true } else { false }
    }
}

/// The time left: ticking while running, still while paused, "Done" at the end.
private struct TimerTime: View {
    let item: TimerItem
    let font: Font

    var body: some View {
        Group {
            switch item.phase {
            case .running(let endsAt):
                Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true)
            case .paused(let remaining):
                Text(TimersPresentation.remainingText(remaining))
                    .opacity(0.6)
            case .done:
                Text("Done")
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(TimersPresentation.tint)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
    }
}

private struct StopwatchTime: View {
    let stopwatch: Stopwatch
    let font: Font

    var body: some View {
        Group {
            if let startedAt = stopwatch.startedAt {
                let origin = startedAt.addingTimeInterval(-stopwatch.accumulated)
                Text(timerInterval: origin...Date.distantFuture, countsDown: false)
            } else {
                Text(TimersPresentation.remainingText(stopwatch.accumulated))
                    .opacity(0.6)
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(TimersPresentation.tint)
        .lineLimit(1)
    }
}

/// Under an expanded timer: its label and controls, then a row to start another.
private struct TimerExpandedBottom: View {
    let id: UUID
    let model: TimersModel

    var body: some View {
        if let item = model.item(id) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(item.label).font(IslandFont.title).lineLimit(1)
                        Text(subtitle(item)).font(IslandFont.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Spacing.s)
                    TimerControls(item: item, model: model)
                }
                if case .done = item.phase {} else {
                    TimerComposer(model: model, closesPanel: false, offersStopwatch: false)
                }
            }
        }
    }

    private func subtitle(_ item: TimerItem) -> String {
        switch item.phase {
        case .running(let endsAt): "Ends at \(endsAt.formatted(date: .omitted, time: .shortened))"
        case .paused: "Paused"
        case .done(let endedAt, _): "Ended at \(endedAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}

private struct TimerControls: View {
    let item: TimerItem
    let model: TimersModel

    var body: some View {
        GlassEffectContainer(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                switch item.phase {
                case .running, .paused:
                    Button("+1 min") { model.actions.addMinute(item.id) }
                        .buttonStyle(.island)
                        .accessibilityLabel("Add a minute")
                    if case .running = item.phase {
                        IslandIconButton(symbol: "pause.fill", label: "Pause", size: 28) { model.actions.pause(item.id) }
                    } else {
                        IslandIconButton(symbol: "play.fill", label: "Resume", size: 28) { model.actions.resume(item.id) }
                    }
                    IslandIconButton(symbol: "xmark", label: "Cancel timer", size: 28) { model.actions.cancel(item.id) }
                case .done:
                    Button("Repeat", systemImage: "arrow.counterclockwise") {
                        model.actions.cancel(item.id)
                        model.actions.start(item.duration, item.label)
                    }
                    .buttonStyle(.island)
                    Button("Stop", systemImage: "stop.fill") { model.actions.cancel(item.id) }
                        .buttonStyle(.island(prominent: TimersPresentation.tint))
                }
            }
            .labelStyle(.titleAndIcon)
        }
    }
}

private struct StopwatchControls: View {
    let model: TimersModel

    var body: some View {
        let isRunning = model.state.stopwatch?.isRunning ?? false
        HStack(spacing: Spacing.m) {
            Text("Stopwatch").font(IslandFont.title)
            Spacer(minLength: Spacing.s)
            GlassEffectContainer(spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Button("Reset", systemImage: "arrow.counterclockwise") { model.actions.stopwatchReset() }
                        .buttonStyle(.island)
                    if isRunning {
                        Button("Pause", systemImage: "pause.fill") { model.actions.stopwatchPause() }
                            .buttonStyle(.island(prominent: TimersPresentation.tint))
                    } else {
                        Button("Start", systemImage: "play.fill") { model.actions.stopwatchStart() }
                            .buttonStyle(.island(prominent: TimersPresentation.tint))
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

/// Starts a timer: preset minutes, or a − / minutes / + stepper for any
/// length (press and hold to repeat, or scroll over it), since the island
/// never takes keyboard focus.
struct TimerComposer: View {
    let model: TimersModel
    let closesPanel: Bool
    let offersStopwatch: Bool
    @State private var isCustom = false
    @Environment(\.closeHomePanel) private var closePanel

    static let customRange = 1...180

    var body: some View {
        IslandChipRow {
            if isCustom {
                Button("Less", systemImage: "minus") { step(-1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.island)
                    .buttonRepeatBehavior(.enabled)
                Text("\(model.customMinutes) min")
                    .font(IslandFont.compact)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.customMinutes)))
                    .frame(minWidth: 52)
                    .background(ScrollWheelReader { step($0) })
                    .accessibilityElement()
                    .accessibilityLabel("Minutes")
                    .accessibilityValue("\(model.customMinutes)")
                    .accessibilityAdjustableAction { direction in
                        step(direction == .increment ? 1 : -1)
                    }
                Button("More", systemImage: "plus") { step(1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.island)
                    .buttonRepeatBehavior(.enabled)
                Button("Start") { start(minutes: model.customMinutes) }
                    .buttonStyle(.island(prominent: TimersPresentation.tint))
                Button("Back", systemImage: "chevron.left") { withAnimation(Motion.content) { isCustom = false } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.island)
            } else {
                ForEach(TimersModule.presets, id: \.self) { minutes in
                    Button("\(minutes) min") { start(minutes: minutes) }
                        .buttonStyle(.island)
                        .accessibilityLabel("Start a \(minutes)-minute timer")
                }
                Button("Custom") { withAnimation(Motion.content) { isCustom = true } }
                    .buttonStyle(.island)
                    .accessibilityLabel("Custom length")
                if offersStopwatch {
                    Button("Stopwatch", systemImage: "stopwatch") {
                        model.actions.stopwatchStart()
                        if closesPanel { closePanel() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.island)
                    .accessibilityLabel("Start the stopwatch")
                }
            }
        }
    }

    private func step(_ delta: Int) {
        let range = Self.customRange
        model.customMinutes = min(max(model.customMinutes + delta, range.lowerBound), range.upperBound)
    }

    private func start(minutes: Int) {
        model.actions.start(TimeInterval(minutes * 60), nil)
        if closesPanel { closePanel() }
    }
}

/// Turns scrolling over its area into steps (one per notch of a wheel, or
/// per 12 pt of trackpad travel).
private struct ScrollWheelReader: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> ScrollWheelView { ScrollWheelView() }

    func updateNSView(_ view: ScrollWheelView, context: Context) {
        view.onStep = onStep
    }

    final class ScrollWheelView: NSView {
        var onStep: (Int) -> Void = { _ in }
        private var travel: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            guard event.scrollingDeltaY != 0 else { return }
            if !event.hasPreciseScrollingDeltas {
                onStep(event.scrollingDeltaY > 0 ? 1 : -1)
                return
            }
            travel += event.scrollingDeltaY
            while abs(travel) >= 12 {
                onStep(travel > 0 ? 1 : -1)
                travel -= travel > 0 ? 12 : -12
            }
            if event.phase == .ended || event.momentumPhase == .ended { travel = 0 }
        }
    }
}
