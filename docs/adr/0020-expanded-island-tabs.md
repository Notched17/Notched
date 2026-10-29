# ADR-0020: Expanded island tabs

- Status: accepted (M4a Step 1)
- Date: 2026-10-29
- Amends: ADR-0006 (live activity model: "the expanded view pages between the activities and Home")

## Context

The expanded island paged between activities and Home. M4a adds an "AI" view (Claude Code usage) and M4b adds more (Terminal, Calendar). A module needs a way to put a whole view in the expanded island that isn't an activity, and it must cost nothing when the module is off.

## Decisions

- **The existing pages become the first tab, "Island".** Activity pages and Home page exactly as before (hover, swipe, ← →). Module tabs follow it.
- **Modules set tabs through their sink, like Home actions.** `ActivitySink.setTabs(_:)` → `ActivityCoordinator.moduleTabs`. A module that stops loses its tabs because `ModuleHost.stopModule` already calls `endAll(from:)`. A disabled module is never instantiated, so it holds nothing. The plan had an `expandedTabs()` requirement on `IslandModule` collected by `ModuleHost`; the sink is the same pattern as `setHomeActions` and needs no new wiring between the host and the view model.
- **Ordering is a pure function** (`ExpandedTabs.arrange`): by `order`, then the module catalogue, then id; a repeated id keeps the first; the reserved id `island` is dropped; at most **four** module tabs (five segments is what fits the narrowest expanded island with one label).
- **The bar sits under the content, not in the header row.** The plan put it in the camera-housing row. Only Home has that row (activity pages put their regions beside the housing), so a header bar would be missing on most pages. A bottom row is the same on every tab and on the pill. It costs about 30 pt of height, inside the 160 pt maximum, and shares the row with the page dots.
- **No bar without tabs.** With no module tab nothing changes for the user.
- **An alert overrides the tab.** An alerting activity always shows on the Island tab and hides the bar; the user's pick returns afterwards.
- **Tab content is built only while selected.** `IslandTab.onVisibilityChange` tells the module when it appears and goes, so refreshes can use `RefreshScheduler.setUIVisible`.
- **Keyboard, after a click gives the panel focus** (the island never takes focus on hover): ⌘1–⌘5 pick a tab, ⌃Tab and ⌃⇧Tab cycle, ← and → page within Island. They come in as `performKeyEquivalent`/`keyDown` and map through the pure `ExpandedTabs.command`.
- **VoiceOver.** The bar is a container labelled "Tabs"; each segment is a button, with the selected trait, labelled "AI, tab 2 of 3".
- **Reduce Motion.** Tab changes use `Motion.reduced` instead of the content spring.

## Consequences

- `ExpandedTabsTests` and `IslandTabHostTests` pin ordering, the cap, selection fallback, key mapping, and the alert override.
- The pager still has no `accessibilityAdjustableAction`; the page dots are a plain label, as before. Not a regression, and not fixed here.
