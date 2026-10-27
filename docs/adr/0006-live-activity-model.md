# ADR-0006: Live activity model (iPhone parity)

- Status: accepted (M1.5). Supersedes ADR-0004.
- Date: 2026-10-27

## Context

ADR-0004 let the compact island take its leading item from one activity and its trailing item from another. Media artwork could sit beside a timer's countdown. That's not how the iPhone Dynamic Island works, and it doesn't scale to several live things at once (music, a timer, a call, Claude Code working). `docs/ISLAND-BEHAVIOR.md` specifies iPhone parity, and `docs/research/ios-dynamic-island.md` records Apple's documented behaviour. M2 (media) builds on this model, so it has to be right first.

## Decision

Modules post **`LiveActivity`** values through their scoped `ActivitySink`. An activity has:

- a **kind**: `system > live > media > passive`
- a **relevance** (higher wins within its kind)
- **`isHideable`**
- an optional **stale date**, **keyline tint** and **`openAction`**
- a short **title** for lists ("Timer", a song's name), and a fuller accessibility label for VoiceOver
- an **`ActivityPresentation`**: named regions (`compactLeading`, `compactTrailing?`, `minimal`, and `expanded` leading / trailing / center / bottom) instead of free-form views.

`ActivityCoordinator` stays pure and clock-injected. Its rules are pinned by scenario tests (`ActivityCoordinatorTests`):

1. **Ranking:** kind, then relevance, then start order. An update in place keeps its start order, so a newcomer never steals the island from an equal.
2. **One primary activity owns both compact sides.** Leading and trailing never come from different activities.
3. **Minimal bubbles:** the next two visible activities, trailing first, then leading. Never more than three on the island; the rest are listed only.
4. **Swap** (`makePrimary`, `cyclePrimary`) is sticky until either swapped activity ends or a new `system` activity arrives.
5. **Hide** keeps the activity running and listed. Non-hideable activities (a call, screen recording) ignore it. Hidden is a user flag, separate from the lifecycle, so a hidden activity can still go stale or end.
6. **Lifecycle:** `active → stale` at the stale date. `ended` leaves the island immediately and stays under **Recent** until its dismissal date: the user's retention (15 min by default), `.immediate`, or `.after(date)`, capped at 4 h. Disabling a module ends its activities with no Recent entries.
7. **Alert expansion:** an `AlertRequest` on `post` (a parameter, not a stored field, because it's one-shot) expands that activity for its duration (4 s by default), then the island returns. A new `system` activity alerts by default. Alerts queue one at a time, wait while the user is on the island (`isInteracting`), and start their clock when shown. A pointer arriving during an alert turns it into a normal hover. An alert on a hidden activity still expands but leaves it hidden. With alert expansion off, the island bounces instead.
8. **Transient banners** (`TransientBanner`) are a separate path for short system events: a wide compact view for 2 s by default. They pre-empt the compact island (the bubbles merge in for the duration), never take a minimal slot, wait while the island is expanded, and are dropped once they've waited more than 5 s. Showing the same id again restarts it without another bounce.
9. **Deadlines:** stale dates, alert and banner ends and Recent dismissals all go through one `nextDeadline` and a one-shot wake. There is no polling.

**The island owns layout and animation.** Each region renders inside `IslandRegionHost`, which drops a module's own animations and applies the island's short content animation. That means numeric-text rolls, symbol effects and blur-replace swaps, all ≤ 2 s. Stale content dims. Expanded regions are placed by `ExpandedRegionsLayout` with Apple's algorithm (`ExpandedRegionsGeometry`, tested). The expanded island is the notch + 2 × 140 pt wide (408 pt on the pill), and its height follows the content (notch row + 46…160 pt).

**The pill has no camera to work around.** Idle, it keeps its standard 190 pt. With an activity live, its leading and trailing regions sit together, like a Live Activity in the macOS menu bar, rather than keeping an empty middle that only exists on iPhone because of the camera. Side by side, a 17 pt gap with a hairline divider separates the two activities.

**Interaction (ISLAND-BEHAVIOR.md §6):**

- **Hover** expands the hovered activity: the island → the primary, a bubble → that activity.
- **Click** opens it (`openAction`, or expands if it has none); clicking a bubble makes it primary. "Click to expand" is a setting.
- **Two-finger swipe:** sideways cycles the primary, up hides.
- **Right-click** offers Hide.
- **Expanded view:** pages between the activities and Home, with a page indicator. Home lists Live, Hidden and Recent.
- **Esc** collapses once a click has given the island keyboard focus.

## Consequences

- Modules can't break the island's layout or animation. They choose regions and content, not frames or springs.
- The model is `@MainActor`, because presentations hold SwiftUI views. The rules stay testable because the tests post plain text presentations.
- Measured widths drive compact sizing (`CompactLayout`, tested), so there are no magic width constants in modules. A region's width can change by a pixel when its text changes, so ticking values should use `.monospacedDigit()`.
- M3's remaining #8 work is user-adjustable priority only.
