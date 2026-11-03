// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Where the card gets the things that aren't already on screen elsewhere:
/// the battery and the next event. Read when the card is drawn and then once
/// a minute while it exists; nothing runs while the Mac is unlocked.
@MainActor
final class LockScreenInfo {
    private var events: (any CalendarEventSource)?

    /// The internal battery right now; nil on a Mac without one.
    func battery() -> PowerSnapshot? {
        let snapshot = PowerSourceMonitor.read()
        return snapshot.hasBattery ? snapshot : nil
    }

    /// The next-event line. Reads the calendar only if access was already
    /// granted (to the Calendar module): the lock screen never asks.
    func nextEventLine(now: Date, showTitle: Bool) -> String? {
        let source = events ?? EventStoreService()
        events = source
        guard source.authorization == .granted else { return nil }
        let list = source.events(from: now.addingTimeInterval(-LockScreenCardText.nowGrace),
                                 to: now.addingTimeInterval(LockScreenCardText.horizon))
        return LockScreenCardText.nextEvent(list, now: now, showTitle: showTitle)
    }

    func release() { events = nil }
}

/// The lock-screen card (#59): Now Playing, a lyric line, the battery and the
/// next event, each only if its switch is on. Display only: no controls, no
/// text fields, hidden from VoiceOver by its window (ADR-0031 §3).
struct LockScreenCardView: View {
    let options: LockScreenCardOptions
    let nowPlaying: NowPlayingShelf
    let info: LockScreenInfo

    @Environment(\.colorSchemeContrast) private var contrast

    /// The card's outer radius, declared once as the container shape so the
    /// artwork inside is concentric with it (HIG: nested corners subtract the padding).
    private static let cardRadius: CGFloat = 22

    var body: some View {
        // The card is laid out once, at its base size, and scaled to the window it
        // is given (Small, Medium and Large are only different scales), so no size
        // can clip or reflow its content.
        GeometryReader { proxy in
            let base = LockScreenGeometry.baseSize
            let scale = min(proxy.size.width / base.width, proxy.size.height / base.height)
            // Read each minute: the footer's clock and battery follow it.
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .frame(width: base.width, height: base.height)
            .scaleEffect(scale.isFinite && scale > 0 ? scale : 1)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }


    @ViewBuilder
    private func content(now: Date) -> some View {
        let model = options.showTrack ? nowPlaying.model : nil
        let battery = options.showBattery ? info.battery() : nil
        let event = options.showEvent ? info.nextEventLine(now: now, showTitle: options.showEventTitle) : nil
        let hasTrack = model?.snapshot != nil
        if hasTrack || battery != nil || event != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let model, hasTrack {
                    TrackRow(model: model, showArtwork: options.showArtwork)
                    if options.showLyrics { LyricRow(model: model) }
                }
                // A hairline between the two groups, as Apple suggests for Live Activities
                // (a dividing line or containing shape rather than edge-to-edge graphics).
                if hasTrack, battery != nil || event != nil {
                    Rectangle()
                        .fill(Color.white.opacity(contrast == .increased ? 0.4 : 0.12))
                        .frame(height: 0.5)
                }
                if battery != nil || event != nil {
                    HStack(spacing: 12) {
                        if let battery { BatteryLabel(snapshot: battery) }
                        if let event {
                            Label(event, systemImage: "calendar")
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .dimmedText(0.85)
                }
            }
            .padding(14)   // Apple's uniform Live Activity inset
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(style: options.style, radius: Self.cardRadius))
            .containerShape(.rect(cornerRadius: Self.cardRadius))
            // Hugs its content and sits in the middle of the window, so a small card isn't a tall one.
            .frame(maxHeight: .infinity)
        }
    }
}

/// The card's surface. **Solid** (the default) is dark and nearly opaque, like
/// the island and an iPhone Live Activity: readable over any wallpaper, which
/// matters most on the lock screen. **Glass** is the real Liquid Glass material,
/// darkened with a tint so the white text keeps its contrast over a pale
/// wallpaper. Reduce Transparency always gets the solid surface, fully opaque.
/// Applied after the layout modifiers, as the glass rules ask.
private struct CardSurface: ViewModifier {
    let style: LockScreenCardStyle
    let radius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if style == .glass, !reduceTransparency {
            content
                .glassEffect(.regular.tint(Color.black.opacity(0.4)),
                             in: .rect(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(Color.black.opacity(reduceTransparency ? 1 : 0.88),
                            in: .rect(cornerRadius: radius, style: .continuous))
                .overlay {
                    // A visible edge under Increase Contrast, a faint one otherwise so it
                    // doesn't melt into a dark wallpaper.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(contrast == .increased ? 0.6 : 0.14), lineWidth: 0.5)
                }
        }
    }
}

private struct TrackRow: View {
    let model: MediaModel
    let showArtwork: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showArtwork {
                Group {
                    if let artwork = model.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note").dimmedText(0.6)
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(.rect(corners: .concentric(minimum: 8), isUniform: true))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.snapshot?.title ?? "")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let artist = model.snapshot?.artist {
                    Text(artist)
                        .font(.caption)
                        .dimmedText(0.7)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: model.isPlaying ? "waveform" : "pause.fill")
                .font(.caption)
                .dimmedText(0.7)
                .contentTransition(.symbolEffect(.replace))
        }
        .foregroundStyle(.white)
    }
}

/// The line being sung, redrawn only when it changes (the schedule has one
/// entry per lyric line), like the island's own lyric line.
private struct LyricRow: View {
    let model: MediaModel

    var body: some View {
        if let lyrics = model.lyrics, let timeline = model.snapshot?.timeline {
            TimelineView(LyricLineSchedule(lyrics: lyrics, timeline: timeline)) { context in
                let position = timeline.elapsed(at: context.date)
                let text = lyrics.lineIndex(at: position).map { lyrics.lines[$0].text } ?? ""
                Text(text.isEmpty ? " " : text)
                    .font(.footnote)
                    .dimmedText(0.9)
                    .lineLimit(1)
            }
        }
    }
}

private struct BatteryLabel: View {
    let snapshot: PowerSnapshot

    var body: some View {
        let charging = snapshot.power == .charging
        Label {
            Text(LockScreenCardText.batteryText(level: snapshot.level))
                .font(.system(.caption, design: .rounded).monospacedDigit())
        } icon: {
            Image(systemName: LockScreenCardText.batterySymbol(level: snapshot.level, charging: charging))
                .symbolRenderingMode(.hierarchical)
        }
    }
}
