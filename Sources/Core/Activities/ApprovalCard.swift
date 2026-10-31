// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// One answer to an approval request.
struct ApprovalChoice: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case primary, normal, destructive }

    let id: String
    var title: String
    var role: Role = .normal
}

/// What an approval asks, for the card the island shows (Claude Code
/// permission requests, `POST /v1/approvals`).
struct ApprovalCardModel: Equatable, Sendable {
    var symbol: String
    var title: String
    /// The context line, such as the project.
    var context: String?
    /// The thing being approved: a command or a path, already redacted and truncated.
    var detail: String
    /// The two main buttons, deny first.
    var primary: [ApprovalChoice]
    /// Less common answers, in a menu.
    var more: [ApprovalChoice] = []
}

/// Waits for one answer, from the user, a timeout or a hung-up client.
/// Resolves once; later calls are ignored.
@MainActor
final class ApprovalWaiter {
    private var continuation: CheckedContinuation<String, Never>?
    private var result: String?

    func wait() async -> String {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: String) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }

    var isResolved: Bool { result != nil }

    /// Waits up to `timeout` seconds, and resolves "dismissed" if the
    /// surrounding task is cancelled (the client hung up).
    func wait(timeout: TimeInterval) async -> String {
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.resolve("timeout")
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await wait()
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve("dismissed") }
        }
    }
}

/// The expanded island's approval card: glyph and title beside the housing,
/// the request in the middle, buttons along the bottom. It takes no focus
/// by itself; once the panel has focus, Return allows and ⌘⌫ denies.
@MainActor
enum ApprovalCard {
    static func expanded(_ model: ApprovalCardModel, tint: Color, choose: @escaping @MainActor (String) -> Void) -> ExpandedPresentation {
        ExpandedPresentation(
            leading: ExpandedRegion {
                IslandTile {
                    Image(systemName: model.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .padding(.top, 6)
            },
            trailing: ExpandedRegion {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: model.title).font(IslandFont.title).lineLimit(1)
                    if let context = model.context {
                        Text(verbatim: context).font(IslandFont.subtitle).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
            },
            center: ExpandedRegion {
                Text(verbatim: model.detail)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            bottom: ExpandedRegion { ApprovalButtons(model: model, choose: choose) }
        )
    }
}

private struct ApprovalButtons: View {
    let model: ApprovalCardModel
    let choose: @MainActor (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(model.primary) { choice in
                    if choice.role == .primary {
                        Button(choice.title) { choose(choice.id) }
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(choice.title, role: choice.role == .destructive ? .destructive : nil) { choose(choice.id) }
                            .buttonStyle(.glass)
                            .keyboardShortcut(choice.role == .destructive ? KeyboardShortcut(.delete, modifiers: .command) : nil)
                    }
                }
                if !model.more.isEmpty {
                    Menu {
                        ForEach(model.more) { choice in
                            Button(choice.title, role: choice.role == .destructive ? .destructive : nil) { choose(choice.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("More answers")
                }
            }
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
