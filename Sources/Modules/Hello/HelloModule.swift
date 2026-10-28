// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import SwiftUI

/// A DEBUG-only demo that proves activities flow from a module, through the
/// coordinator, into the island: a transient banner and a live session.
/// Triggered from the status menu's Debug submenu.
@MainActor
final class HelloModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "hello",
        name: "Hello",
        symbol: "hand.wave.fill",
        summary: "A demo banner and live session that show how modules use the island.",
        permissions: [],
        isDebugOnly: true
    )

    private static let sessionID: ActivityID = "hello.session"
    private let context: ModuleContext
    private var sessionStart: Date?

    init(context: ModuleContext) {
        self.context = context
    }

    /// DEBUG: crash while starting, to check ModuleHost's crash-loop protection.
    static let crashAtStartKey = "debug.hello.crashAtStart"

    func start() {
        if UserDefaults.standard.bool(forKey: Self.crashAtStartKey) {
            fatalError("Hello: simulated crash while starting (debug)")
        }
    }

    func stop() {
        sessionStart = nil
        context.activities.endAll()
    }

    /// A transient banner: it bounces in, then the island returns after a moment.
    func showAlert() {
        context.activities.show(TransientBanner(
            id: "hello.banner",
            moduleID: Self.descriptor.id,
            leading: IslandRegion { HelloWave(size: 15) },
            trailing: IslandRegion {
                Text("Hello").font(.system(size: 13, weight: .semibold, design: .rounded))
            },
            accessibilityLabel: "Hello from Notched"
        ))
    }

    var isLiveSessionRunning: Bool { sessionStart != nil }

    /// A live session with a ticking timer, until toggled off.
    func toggleLiveSession() {
        if sessionStart != nil {
            sessionStart = nil
            context.activities.end(Self.sessionID)
            return
        }
        let start = Date()
        sessionStart = start
        context.activities.post(LiveActivity(
            id: Self.sessionID,
            moduleID: Self.descriptor.id,
            kind: .live,
            title: "Demo session",
            accessibilityLabel: "Demo session",
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: "timer").font(.system(size: 13, weight: .semibold))
                },
                compactTrailing: IslandRegion { HelloElapsed(start: start, size: 13) },
                minimal: IslandRegion { HelloElapsed(start: start, size: 11) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        Image(systemName: "timer").font(.system(size: 22, weight: .semibold))
                    },
                    trailing: ExpandedRegion { HelloElapsed(start: start, size: 22) },
                    center: ExpandedRegion {
                        Text("Demo live session").font(.system(.headline, design: .rounded))
                    }
                )
            )
        ))
    }
}

/// A waving hand that bounces once when it appears.
private struct HelloWave: View {
    let size: CGFloat
    @State private var waves = 0

    var body: some View {
        Image(systemName: "hand.wave.fill")
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.bounce, value: waves)
            .onAppear { waves += 1 }
    }
}

private struct HelloElapsed: View {
    let start: Date
    let size: CGFloat

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}
#endif
