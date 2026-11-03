// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// How Claude Code looks on the island: the working activity, the approval
/// card, and the banners.
@MainActor
enum ClaudePresentation {
    /// Claude's terracotta.
    static let tint = Color(red: 0.85, green: 0.47, blue: 0.34)
    typealias Phase = ClaudeSessionsReducer.Phase

    static func activityID(_ sessionID: String) -> ActivityID { ActivityID("claude.\(sessionID)") }

    static func headline(_ phase: Phase) -> String {
        switch phase {
        case .working: "Claude is working…"
        case .waitingForApproval: "Needs your approval"
        case .waitingForInput: "Waiting for you"
        case .finished: "Claude finished"
        case .idle: "Claude Code"
        }
    }

    /// The title on the expanded card, shorter than the activity's headline.
    static func expandedTitle(_ phase: Phase) -> String {
        switch phase {
        case .working: "Working…"
        case .waitingForInput: "Waiting for you"
        case .finished: "Finished"
        case .waitingForApproval: "Needs your approval"
        case .idle: "Claude Code"
        }
    }

    static func activity(_ snapshot: ClaudeSessionsReducer.Snapshot,
                         answer: @escaping @MainActor (_ approvalID: String, ClaudeSessionsReducer.Answer) -> Void) -> LiveActivity {
        let phase = snapshot.phase
        let isApproval = snapshot.approval != nil
        let label = isApproval
            ? "Claude Code in \(snapshot.displayName) needs your approval for \(snapshot.approval?.toolName ?? "a tool")"
            : "\(headline(phase)) \(snapshot.displayName)"
        let expanded: ExpandedPresentation
        if let approval = snapshot.approval {
            expanded = ApprovalCard.expanded(cardModel(snapshot, approval), tint: tint) { choice in
                answer(approval.id, answerFor(choice))
            }
        } else {
            expanded = ExpandedPresentation(
                leading: ExpandedRegion {
                    HStack(spacing: 6) {
                        BrandTile(symbol: phase == .waitingForInput ? "ellipsis.bubble.fill" : "sparkle", tint: tint, filled: phase == .waitingForInput)
                        Text(verbatim: "Claude").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                },
                trailing: ExpandedRegion {
                    Text(verbatim: snapshot.displayName).font(.system(size: 12)).dimmedText(0.7).lineLimit(1)
                },
                center: ExpandedRegion {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: expandedTitle(phase)).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 8)
                            if phase == .working, let since = snapshot.since {
                                Text(since, style: .timer).font(.system(size: 12)).monospacedDigit().dimmedText(0.7)
                            }
                        }
                        if let title = snapshot.title {
                            Text(verbatim: title).font(IslandFont.subtitle).dimmedText(0.7).lineLimit(1)
                        }
                        if phase == .waitingForInput {
                            Text(verbatim: "Answer in the terminal").font(IslandFont.subtitle).dimmedText(0.7).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
        }
        return LiveActivity(
            id: activityID(snapshot.sessionID),
            moduleID: ClaudeCodeModule.descriptor.id,
            kind: .live,
            title: snapshot.displayName,
            relevance: isApproval ? 1.0 : 0.5,
            staleDate: phase == .working || phase == .waitingForInput ? snapshot.lastEvent.addingTimeInterval(ClaudeSessionsReducer.staleAfter) : nil,
            keylineTint: isApproval ? .orange : tint,
            accessibilityLabel: label,
            staleNote: StaleNote(text: "No word from Claude Code", symbol: "questionmark.circle"),
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { ClaudeGlyph(phase: isApproval ? .waitingForApproval : phase, size: 14) },
                compactTrailing: IslandRegion {
                    WidthCap(maxWidth: IslandMetrics.compactRegionMaxWidth) {
                        Text(verbatim: compactText(snapshot))
                            .font(IslandFont.compact)
                            .foregroundStyle(isApproval ? Color.orange : Color.white)
                            .lineLimit(1)
                    }
                },
                minimal: IslandRegion { ClaudeGlyph(phase: isApproval ? .waitingForApproval : phase, size: 12) },
                expanded: expanded
            )
        )
    }

    private static func compactText(_ snapshot: ClaudeSessionsReducer.Snapshot) -> String {
        switch snapshot.phase {
        case .waitingForApproval: "Allow?"
        case .waitingForInput: "Reply"
        case .finished: "Done"
        default: snapshot.displayName
        }
    }

    static func cardModel(_ snapshot: ClaudeSessionsReducer.Snapshot, _ approval: ClaudeSessionsReducer.Approval) -> ApprovalCardModel {
        var more: [ApprovalChoice] = []
        if let suggestion = approval.suggestion {
            more.append(ApprovalChoice(id: "alwaysAllow", title: "Always Allow \(suggestion.label)"))
        }
        more.append(ApprovalChoice(id: "denyAndStop", title: "Deny and Stop Claude", role: .destructive))
        more.append(ApprovalChoice(id: "terminal", title: "Answer in Terminal"))
        return ApprovalCardModel(
            symbol: "sparkle",
            title: "Allow \(approval.toolName)?",
            context: snapshot.displayName,
            detail: approval.detail,
            primary: [ApprovalChoice(id: "deny", title: "Deny"), ApprovalChoice(id: "allow", title: "Allow", role: .primary)],
            more: more,
            brand: "Claude",
            badge: snapshot.moreApprovals > 0 ? "+\(snapshot.moreApprovals)" : nil,
            detailStyle: approval.toolName == "Bash" ? .command : .text,
            changes: approval.changes
        )
    }

    static func answerFor(_ choiceID: String) -> ClaudeSessionsReducer.Answer {
        switch choiceID {
        case "allow": .allow
        case "alwaysAllow": .alwaysAllow
        case "denyAndStop": .denyAndStop
        case "terminal": .terminal
        default: .deny
        }
    }

    static func banner(_ banner: ClaudeSessionsReducer.Banner, sessionID: String) -> TransientBanner {
        switch banner {
        case .finished(let project):
            return .standard(
                id: "claude.banner.\(sessionID)", moduleID: ClaudeCodeModule.descriptor.id,
                content: BannerContent(symbol: "checkmark.circle.fill", symbolTint: .green, label: "Claude finished", value: project),
                accessibilityLabel: "Claude Code finished in \(project)"
            )
        case .failed(let project, let error):
            let reason = readable(error)
            return .standard(
                id: "claude.banner.\(sessionID)", moduleID: ClaudeCodeModule.descriptor.id,
                content: BannerContent(symbol: "exclamationmark.triangle.fill", symbolTint: .orange, label: "Claude stopped", value: reason),
                priority: .high,
                accessibilityLabel: "Claude Code stopped in \(project): \(reason)"
            )
        }
    }

    private static func readable(_ error: String) -> String {
        switch error {
        case "rate_limit": "Rate limit"
        case "overloaded": "Overloaded"
        case "authentication_failed": "Sign-in"
        default: "Error"
        }
    }
}

/// The glyph for a phase: a pulsing sparkle while working.
struct ClaudeGlyph: View {
    let phase: ClaudePresentation.Phase
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .symbolEffect(.pulse, isActive: phase == .working && !reduceMotion)
            .contentTransition(.symbolEffect(.replace))
    }

    private var symbol: String {
        switch phase {
        case .working, .idle: "sparkle"
        case .waitingForApproval: "hand.raised.fill"
        case .waitingForInput: "ellipsis.bubble.fill"
        case .finished: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch phase {
        case .waitingForApproval: .orange
        case .finished: .green
        default: ClaudePresentation.tint
        }
    }
}
