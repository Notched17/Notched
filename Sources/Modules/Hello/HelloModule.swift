// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import SwiftUI

/// A DEBUG-only demo that proves activities flow from a module, through the
/// coordinator, into the compact and expanded island. Triggered from the
/// status menu's Debug submenu.
@MainActor
final class HelloModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "hello",
        name: "Hello",
        symbol: "hand.wave.fill",
        summary: "A demo alert and live session that show how modules use the island.",
        permissions: [],
        isDebugOnly: true
    )

    private let context: ModuleContext
    private var sessionStart: Date?

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {}

    func stop() {
        sessionStart = nil
        context.activities.removeAll()
    }

    /// A transient alert: it bounces in, then disappears after 4 seconds.
    func showAlert() {
        context.activities.post(Activity(
            id: "hello.alert",
            moduleID: Self.descriptor.id,
            priority: .alert,
            lifetime: .transient(.seconds(4)),
            compactLeading: ActivityContent(width: 20, accessibilityLabel: "Hello") {
                HelloWave(size: 15).islandMatchedGeometry(id: "hello.wave")
            },
            compactTrailing: ActivityContent(width: 40, accessibilityLabel: "Hello") {
                Text("Hello").font(.system(size: 13, weight: .semibold, design: .rounded))
            },
            expanded: ActivityContent(width: 0, accessibilityLabel: "Hello from DynamicNotch") {
                HelloAlertCard()
            }
        ))
    }

    var isLiveSessionRunning: Bool { sessionStart != nil }

    /// A live session with a ticking timer, until toggled off.
    func toggleLiveSession() {
        if sessionStart != nil {
            sessionStart = nil
            context.activities.remove("hello.session")
            return
        }
        let start = Date()
        sessionStart = start
        context.activities.post(Activity(
            id: "hello.session",
            moduleID: Self.descriptor.id,
            priority: .liveSession,
            lifetime: .untilRemoved,
            compactLeading: ActivityContent(width: 18, accessibilityLabel: "Demo session") {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .islandMatchedGeometry(id: "hello.timer")
            },
            compactTrailing: ActivityContent(width: 40, accessibilityLabel: "Elapsed time") {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            },
            expanded: ActivityContent(width: 0, accessibilityLabel: "Demo live session") {
                HelloSessionCard(start: start)
            }
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

private struct HelloAlertCard: View {
    var body: some View {
        HStack(spacing: Spacing.l) {
            HelloWave(size: 34)
                .islandMatchedGeometry(id: "hello.wave")
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Hello from DynamicNotch")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("This demo alert came from a module, through the activity coordinator, into the island.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct HelloSessionCard: View {
    let start: Date

    var body: some View {
        HStack(spacing: Spacing.l) {
            Image(systemName: "timer")
                .font(.system(size: 28, weight: .semibold))
                .islandMatchedGeometry(id: "hello.timer")
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Demo live session")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
    }
}
#endif
