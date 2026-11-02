# ADR-0025: One Today tab shared by Calendar, Reminders and Weather (amends ADR-0020)

- Status: accepted for M4b Steps 3–5 (#48, #50, #51); written after the fact in the review pass, from the code as built
- Date: 2026-11-02
- Spec: `docs/superpowers/specs/2026-10-31-m4b-productivity-design.md` §5 (ADR list), Charlie's answer on the Today tab layout

## Context

ADR-0020 gives each module at most its own expanded tab, and the bar holds four module tabs. Calendar, Reminders and Weather each have a little to show, and three tabs for them would leave one place for everything else.

## Decisions

- **One "Today" tab that modules add sections to.** `TodayHub` (in `Sources/Core/Island/Tabs/`) collects `TodaySection`s and publishes a single tab, id `today`, under the pseudo-module id `today`. The modules stay separate: each keeps its own toggle, permission, settings and lifecycle. Only the tab is shared.
- **Fixed slots, not free layout:** Weather is a strip across the top (`header`), Calendar the left column (`leading`), Reminders the right column (`trailing`). With one column it takes the full width. `TodayLayout.make` (pure, tested) decides the columns and the row limit: 2 rows under a header, otherwise 3.
- **The tab exists only while a section does.** Each module adds its section in `start()` and removes it in `stop()` (`remove(moduleID:)`). When the last section goes, the hub publishes no tabs, so nothing is left behind.
- **Amends ADR-0020:** a tab may belong to the hub rather than to a module. It still counts as one of the four places, and the layout editor (ADR-0028) lists it as "Today", from "Calendar, Reminders or Weather".

## Consequences

- A new day-glance module (for example a future Mail count) adds a section rather than a tab.
- The slots are hard-coded. A fourth section would need a new slot and a layout rule.
