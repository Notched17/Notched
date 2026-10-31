# ADR-0016: User priority (#8) and non-hideable activities

- Status: accepted (M3b A0 and A6)
- Date: 2026-10-28
- Amends: ADR-0011 (media stays primary), ADR-0006 (live activity model)

## Context

Two things were missing before the system activities of M3b could ship.

1. **The user could not change the order** (#8): ADR-0011 fixed it as system > media > live > passive. ROADMAP said the setting "feeds relevance".
2. **"Not hideable" only stopped the Hide command.** An activity that was hidden and *then* became non-hideable stayed hidden (a mic indicator hidden by the user, then the camera turns on). A non-hideable activity could also end up only listed, outside the island's three slots, behind a call, music and a timer. A privacy indicator that can be hidden or listed away isn't one.

## Decisions

### User priority

`RankingPolicy` (`Sources/Core/Activities/RankingPolicy.swift`, pure, saved as JSON under `activities.ranking`) sorts activities by:

1. **System** first, always. A call or recording can't be demoted. This also settles what "can't be demoted below live" means: it is not just "above live", it is first.
2. **Pinned modules**, in pin order.
3. The user's **class order** (default media, live, passive: ADR-0011 unchanged).
4. Relevance, then start order, as before.

- **Not through relevance.** A relevance number is set by each module and only orders within a class. It can't say "this timer beats music", so the policy changes the comparison itself, and `ActivityCoordinator.ranksHigher` reads `Configuration.ranking`.
- **Alerts and the swap rules stay keyed on kind**, never on rank: a new `.system` activity still alerts and clears the user's swap.
- **Saved by name.** `ActivityKind` is saved as "media", "live" and so on, never by number, and moved to a Foundation-only file. Bad, empty or future data loads as the default, and a stored order is repaired by `normalized()` (drops system and repeats, restores a missing class in its default slot).
- **Settings ▸ Modules ▸ Priority.** Move Up and Move Down buttons, not drag handles, because drag-to-reorder doesn't work reliably in a grouped macOS `Form` and buttons work with VoiceOver. "Pin Above Others" is also on each module's context menu. The Layout editor (#71, M4b) will reuse `RankingPolicy`.
- **A changed configuration re-ranks at once.** `ActivityCoordinator.configuration` refreshes on a real change only, since the app reassigns it on every settings change.

### Non-hideable activities

- `post()` **unhides** an activity that has become non-hideable.
- **A non-hideable activity always gets one of the three visible slots**, ahead of better-ranked hideable ones. The shown activities keep rank order, and an explicit swap target keeps its slot. With more than three non-hideable activities, the best three show and the rest are listed.
- `listedOnly` is now "visible but not shown", not "everything after the third".
- Nothing changes for the existing activities: only the Scenario Lab posts non-hideable ones, and ordering tests are unchanged.

## Consequences

- Camera & Microphone (#31) can mark itself non-hideable while the camera is on and rely on the island to keep showing it.
- A user can bury music under status items. That's their choice, and Reset to Default undoes it.
- `LiveActivity.alertsWhenStarted` (suppressing the auto-alert for a new system activity) was planned for Screen recording and isn't built: that module is deferred (ADR-0014).

## Known issue

On the Priority page the toolbar title reads "Modules", where the Timers options page shows its own name. The page is pushed the same way and sets its title the same way; three attempts (a title at the destination, a type-erased destination) didn't change it. Cosmetic, to look at later.
