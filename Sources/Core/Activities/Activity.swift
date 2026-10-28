// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The ranking class of a live activity, lowest first (ISLAND-BEHAVIOR.md §2).
/// A higher class wins the attached (primary) slot.
enum ActivityKind: Int, Comparable, CaseIterable, Sendable {
    /// Nice to know, e.g. a weather alert.
    case passive
    /// Now Playing.
    case media
    /// Something the user started: a timer, keep-awake, a download, an agent working.
    case live
    /// Something the system is doing that the user must not miss: a call, screen recording.
    case system

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where an activity is in its life. Hiding is a separate user choice, so a
/// hidden activity can still go stale or end.
enum ActivityState: Equatable, Sendable {
    case active
    /// Its stale date has passed: it renders an "outdated" look until updated.
    case stale
    /// Off the island; listed under Recent until `dismissAt`.
    case ended(dismissAt: Date)
}

/// How long an ended activity stays in the Recent list.
enum DismissalPolicy: Equatable, Sendable {
    /// The user's Recent retention setting (15 minutes by default).
    case `default`
    /// Gone at once, never listed under Recent.
    case immediate
    /// Until this date, at most four hours away.
    case after(Date)
}

/// Asks the island to expand for an important update, then return to what it
/// was showing (like an alerting Live Activity update on iPhone).
struct AlertRequest: Equatable, Sendable {
    /// How long the island stays expanded; nil uses the user's setting.
    var duration: Duration?
    /// A system sound name played once when the alert shows, e.g. "Glass".
    var sound: String?

    init(duration: Duration? = nil, sound: String? = nil) {
        self.duration = duration
        self.sound = sound
    }
}

/// What the expanded island says under a stale activity.
struct StaleNote: Equatable, Sendable {
    var text: String
    var symbol: String

    /// The default: the activity's data is out of date until its module updates it.
    static let updating = StaleNote(text: "Updating…", symbol: "arrow.triangle.2.circlepath")
}

/// Something live that a module shows on the island, like an iPhone Live
/// Activity. Posting the same id again updates it in place.
@MainActor
struct LiveActivity: Identifiable {
    let id: ActivityID
    let moduleID: ModuleID
    var kind: ActivityKind
    /// A short name for lists, e.g. "Timer" or a song's title.
    var title: String
    /// Orders activities within a class; higher wins. Ties go to the one started first.
    var relevance: Double
    /// False for activities the user must not lose sight of (a call, screen recording).
    var isHideable: Bool
    /// After this date the activity looks outdated until the module updates it.
    var staleDate: Date?
    /// Tints the subtle border drawn around minimal bubbles and the expanded island.
    var keylineTint: Color?
    /// Describes the whole activity (leading and trailing together) for VoiceOver.
    var accessibilityLabel: String
    /// What a click does, e.g. open the source app. Nil expands the activity instead.
    var openAction: (@MainActor () -> Void)?
    /// Shown under the expanded activity while it's stale; nil only dims it
    /// (e.g. paused media, whose data isn't out of date).
    var staleNote: StaleNote?
    /// Asks the island to stay visible over a fullscreen app while this is
    /// live, when the user allows it (#5, "Keep showing while media plays").
    var keepsIslandInFullscreen: Bool
    var presentation: ActivityPresentation

    init(
        id: ActivityID,
        moduleID: ModuleID,
        kind: ActivityKind,
        title: String,
        relevance: Double = 0,
        isHideable: Bool = true,
        staleDate: Date? = nil,
        keylineTint: Color? = nil,
        accessibilityLabel: String,
        openAction: (@MainActor () -> Void)? = nil,
        staleNote: StaleNote? = .updating,
        keepsIslandInFullscreen: Bool = false,
        presentation: ActivityPresentation
    ) {
        self.id = id
        self.moduleID = moduleID
        self.kind = kind
        self.title = title
        self.relevance = relevance
        self.isHideable = isHideable
        self.staleDate = staleDate
        self.keylineTint = keylineTint
        self.accessibilityLabel = accessibilityLabel
        self.openAction = openAction
        self.staleNote = staleNote
        self.keepsIslandInFullscreen = keepsIslandInFullscreen
        self.presentation = presentation
    }
}

/// What the coordinator knows about a posted activity.
@MainActor
struct ActivityRecord: Identifiable {
    let id: ActivityID
    var activity: LiveActivity
    /// Start order; the final ranking tiebreak.
    let sequence: Int
    var state: ActivityState
    var isHidden: Bool
    /// Increments with every update, so the island can animate content changes.
    var revision: Int

    init(activity: LiveActivity, sequence: Int, state: ActivityState = .active, isHidden: Bool = false, revision: Int = 0) {
        self.id = activity.id
        self.activity = activity
        self.sequence = sequence
        self.state = state
        self.isHidden = isHidden
        self.revision = revision
    }

    var isStale: Bool { state == .stale }
}
