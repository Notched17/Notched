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
    /// The app asking, beside the camera housing ("Claude"). Nil: just the glyph.
    var brand: String?
    /// A small count beside the context ("+1": more requests waiting).
    var badge: String?
    /// How `detail` is drawn: a shell command shows a prompt mark.
    var detailStyle: DetailStyle = .text
    /// The changed lines of an edit. When there are some, they are shown in
    /// place of `detail`, which then names the file.
    var changes: [LineDiff.Line] = []

    enum DetailStyle: Sendable { case text, command }
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

/// The expanded island's approval card: the asking app and its project beside
/// the camera housing, then the title, what is being approved in a well (a
/// command, or the changed lines of an edit), and the answers along the
/// bottom. It takes no focus by itself; once the panel has focus, Return
/// allows and ⌘⌫ denies.
@MainActor
enum ApprovalCard {
    static func expanded(_ model: ApprovalCardModel, tint: Color, choose: @escaping @MainActor (String) -> Void) -> ExpandedPresentation {
        ExpandedPresentation(
            leading: ExpandedRegion {
                HStack(spacing: 6) {
                    BrandTile(symbol: model.symbol, tint: tint, filled: true)
                    if let brand = model.brand {
                        Text(verbatim: brand).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                }
            },
            trailing: ExpandedRegion {
                HStack(spacing: 6) {
                    if let context = model.context {
                        Text(verbatim: context).font(.system(size: 12)).dimmedText(0.7).lineLimit(1)
                    }
                    if let badge = model.badge {
                        Text(verbatim: badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .background(Color.orange, in: .capsule)
                            .accessibilityLabel("\(badge) more waiting")
                    }
                }
            },
            center: ExpandedRegion {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: model.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        if !model.changes.isEmpty {
                            Text(verbatim: model.detail)
                                .font(.system(size: 11, design: .monospaced))
                                .dimmedText(0.7)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                    ApprovalWell(model: model, tint: tint)
                }
            },
            bottom: ExpandedRegion { ApprovalButtons(model: model, choose: choose) }
        )
    }
}

/// The app's small rounded tile: a filled one when it needs you, a faint one
/// while it quietly works.
struct BrandTile: View {
    let symbol: String
    let tint: Color
    var filled: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(filled ? Color.black.opacity(0.85) : tint)
            .frame(width: 22, height: 22)
            .background(filled ? tint : tint.opacity(0.22), in: .rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What is being approved, in a dark well: a command, a path, or the changed lines.
private struct ApprovalWell: View {
    let model: ApprovalCardModel
    let tint: Color

    /// A command starts with a tinted shell prompt; anything else is plain text.
    private var detailText: Text {
        guard model.detailStyle == .command else { return Text(verbatim: model.detail) }
        var prompt = AttributedString("$ ")
        prompt.foregroundColor = tint
        return Text(prompt + AttributedString(model.detail))
    }

    var body: some View {
        Group {
            if model.changes.isEmpty {
                detailText
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.changes) { line in
                        DiffRow(line: line)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
        }
        .foregroundStyle(Color.white.opacity(0.95))
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.changes.isEmpty ? model.detail : "Changes to \(model.detail)")
    }
}

/// One line of a diff. Added and removed lines differ by their mark as well as their colour.
private struct DiffRow: View {
    let line: LineDiff.Line

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: mark).frame(width: 8)
            Text(verbatim: line.text).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(textColor)
        .padding(.horizontal, 8)
        .background(fill, in: .rect(cornerRadius: 4, style: .continuous))
        .accessibilityLabel("\(spoken) \(line.text)")
    }

    private var mark: String {
        switch line.kind {
        case .added: "+"
        case .removed: "\u{2212}"
        case .gap: "\u{22EF}"
        case .same: " "
        }
    }

    private var spoken: String {
        switch line.kind {
        case .added: "Added"
        case .removed: "Removed"
        case .gap: "Skipped"
        case .same: "Unchanged"
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added: Color(red: 0.49, green: 0.90, blue: 0.60)
        case .removed: Color(red: 1.0, green: 0.60, blue: 0.56)
        case .gap, .same: Color.white.opacity(0.6)
        }
    }

    private var fill: Color {
        switch line.kind {
        case .added: Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.16)
        case .removed: Color(red: 1.0, green: 0.37, blue: 0.34).opacity(0.16)
        case .gap, .same: .clear
        }
    }
}

/// Deny and the ⋯ menu are glass; Allow is a plain white capsule with black
/// text, so the one answer that does something stands out and stays calm.
private struct AllowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 1), in: .capsule)
            .contentShape(.capsule)
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
                            .buttonStyle(AllowButtonStyle())
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(role: choice.role == .destructive ? .destructive : nil) { choose(choice.id) } label: {
                            Text(choice.title).frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .keyboardShortcut(choice.role == .destructive ? KeyboardShortcut(.delete, modifiers: .command) : nil)
                    }
                }
                if !model.more.isEmpty {
                    Menu {
                        ForEach(model.more) { choice in
                            Button(choice.title, role: choice.role == .destructive ? .destructive : nil) { choose(choice.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 34, height: 34)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .menuIndicator(.hidden)
                    .accessibilityLabel("More answers")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
