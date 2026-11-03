// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The lyrics tab (#13): a black card that hangs under the island and stays
/// until its close button is pressed, with the lyrics scrolling past and the
/// line being sung bright in the middle.
///
/// It is a separate non-activating panel, and it never takes keyboard focus
/// (`canBecomeKey` is false), so whatever app the user is in, and whatever
/// text field they were typing in, keeps working. The panel is exactly the
/// size of the card, so every click outside it goes to the app underneath.
@MainActor
final class LyricsPanelController {
    nonisolated static let size = CGSize(width: 400, height: 220)
    /// Between the island's bottom edge and the card.
    nonisolated static let gap: CGFloat = 8
    /// The notchless pill's height and its distance below the menu bar (`NotchGeometry`'s defaults).
    nonisolated static let pillHeight: CGFloat = 32
    nonisolated static let pillGap: CGFloat = 4

    private let model: MediaModel
    private var panel: LyricsPanel?
    private var displayID: DisplayID?
    private var screenObserver: NSObjectProtocol?

    init(model: MediaModel) {
        self.model = model
    }

    var isOpen: Bool { panel != nil }

    func toggle() {
        if isOpen { close(animated: true) } else { open() }
    }

    func open() {
        guard panel == nil, let screen = Self.targetScreen() else { return }
        displayID = screen.displayID
        let panel = LyricsPanel(contentRect: Self.frame(on: screen))
        let host = LyricsHostingView(rootView: LyricsPanelView(model: model) { [weak self] in
            self?.close(animated: true)
        })
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
        self.panel = panel
        model.isLyricsPanelOpen = true

        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animated ? 0 : 1
        panel.orderFrontRegardless()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
        // Only while the card is open: nothing is observed otherwise.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    func close(animated: Bool) {
        guard let panel else { return }
        self.panel = nil
        model.isLyricsPanelOpen = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                // AppKit calls this on the main thread.
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    panel.contentView = nil
                }
            })
        } else {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// A display was added, removed or rearranged: stay under the island on the same screen, or
    /// the first one when that screen is gone.
    private func reposition() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? Self.targetScreen()
        guard let screen else { close(animated: false); return }
        displayID = screen.displayID
        panel.setFrame(Self.frame(on: screen), display: true)
    }

    // MARK: Placement

    /// The screen the pointer is on (where the island was clicked), else the main one.
    private static func targetScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func frame(on screen: NSScreen) -> CGRect {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return frame(screenFrame: screen.frame, topInset: topInset(safeAreaTop: screen.safeAreaInsets.top, menuBarHeight: menuBar), size: size)
    }

    /// How far below the screen's top edge the card starts: under the notch on a notched display,
    /// under the floating pill on one without.
    nonisolated static func topInset(safeAreaTop: CGFloat, menuBarHeight: CGFloat) -> CGFloat {
        (safeAreaTop > 0 ? safeAreaTop : menuBarHeight + pillGap + pillHeight) + gap
    }

    /// Centred on the screen (a notch is centred), kept inside it.
    nonisolated static func frame(screenFrame: CGRect, topInset: CGFloat, size: CGSize) -> CGRect {
        let width = min(size.width, screenFrame.width)
        let x = min(max(screenFrame.midX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: x.rounded(), y: (screenFrame.maxY - topInset - size.height).rounded(), width: width, height: size.height)
    }
}

/// Borderless, transparent and non-activating, like the island's panel, but it
/// can never become key or main: the user's own text field keeps the keyboard.
final class LyricsPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Under the island (which is three above the menu bar), so the expanded island opens over it.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The first click on the close button works even though the app isn't active.
private final class LyricsHostingView: NSHostingView<LyricsPanelView> {
    required init(rootView: LyricsPanelView) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: View

struct LyricsPanelView: View {
    let model: MediaModel
    let close: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            LyricsBody(model: model)
        }
        .frame(width: LyricsPanelController.size.width, height: LyricsPanelController.size.height)
        .background {
            ZStack {
                Color.black
                // The cover's colour, as on the Now Playing page, only a soft wash from the top.
                if model.artwork != nil, model.showsGlow {
                    Ellipse()
                        .fill(model.tint.opacity(0.28))
                        .frame(width: 460, height: 150)
                        .blur(radius: 50)
                        .offset(y: -90)
                }
            }
        }
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lyrics")
    }

    private var header: some View {
        HStack(spacing: 10) {
            MediaArtworkView(model: model, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.snapshot?.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.snapshot?.artist ?? model.sourceName ?? "")
                    .font(.system(size: 11))
                    .dimmedText(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close lyrics")
            .accessibilityLabel("Close lyrics")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .foregroundStyle(Color.white)
    }
}

/// The lyrics, one line per row, with the sung line bright in the middle.
/// While playing it redraws only when the line changes (`LyricLineSchedule`).
private struct LyricsBody: View {
    let model: MediaModel

    var body: some View {
        if let snapshot = model.snapshot, let lyrics = model.lyrics {
            if snapshot.isPlaying {
                TimelineView(LyricLineSchedule(lyrics: lyrics, timeline: snapshot.timeline)) { context in
                    LyricsScroller(lyrics: lyrics, current: lyrics.lineIndex(at: snapshot.timeline.elapsed(at: context.date)))
                }
                .id(model.trackKey)
            } else {
                LyricsScroller(lyrics: lyrics, current: lyrics.lineIndex(at: snapshot.timeline.elapsed(at: .now)))
                    .id(model.trackKey)
            }
        } else {
            Text("No synced lyrics for this song")
                .font(.system(size: 14, weight: .medium))
                .dimmedText(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LyricsScroller: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lyrics: SyncedLyrics
    let current: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        row(line.text, isCurrent: index == current)
                            .id(index)
                    }
                }
                // Room above the first line and below the last, so each can reach the middle.
                .padding(.vertical, 70)
            }
            .scrollDisabled(true)
            .mask {
                // Lines fade out toward the top and bottom edges.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: current) { scroll(proxy, animated: !reduceMotion) }
        }
    }

    @ViewBuilder
    private func row(_ text: String, isCurrent: Bool) -> some View {
        let shown = Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .scaleEffect(isCurrent ? 1 : 0.93)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: isCurrent)
        if isCurrent {
            shown.foregroundStyle(Color.white)
                .accessibilityAddTraits(.isSelected)
        } else {
            // Not under 3:1 on black (large text), and lifted by Increase Contrast.
            shown.dimmedText(0.45)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current else { return }
        if animated {
            withAnimation(.smooth(duration: 0.55)) { proxy.scrollTo(current, anchor: .center) }
        } else {
            proxy.scrollTo(current, anchor: .center)
        }
    }
}
