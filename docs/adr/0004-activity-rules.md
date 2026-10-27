# ADR-0004: Activity ranking and compact-slot rules

- Status: superseded by ADR-0006 (M1.5)
- Date: 2026-10-27

## Context

Several modules can have something live at once: an alert (battery low), a live session (timer, keep-awake) and media. The compact island has room for one leading and one trailing item (#8). Competitors get this wrong in both directions: noisy islands where events fight, or one slot where the newest event always wins.

## Decision

`ActivityCoordinator` is a pure, clock-injected `@Observable` model with these rules, each covered by a unit test:

1. **Ranking:** priority first (alert 300 > live session 200 > media 100 > idle 0), then the newest first.
2. **Alerts take over:** if the top activity is an alert, it owns both compact slots, even one it leaves empty, until it expires.
3. **Otherwise slots are shared:** leading comes from the highest-ranked activity with a leading item, and trailing from the highest-ranked activity with a trailing item. Media can keep its artwork on the left while a timer shows on the right.
4. **Transient expiry:** a transient activity disappears at `postedAt + duration`, and the island returns to what it showed before. The coordinator reports its next expiry; the app wakes once at that time (`OneShotTimer`). There is no polling.
5. **Updates in place:** re-posting an id updates it without changing its rank. A transient re-post resets its expiry, so repeated volume presses keep one alert alive.
6. **Bounce:** `alertSerial` increments only for *new* alerts; the island bounces once per serial (not with Reduce Motion).
7. **Scoping:** a module posts through an `ActivitySink` bound to its own id, so it can't post or remove another module's activities. Disabling a module stops it and removes its activities.

The compact island widens symmetrically by the wider slot plus 20 pt of padding on each side, so it stays centred on the notch. The expanded island shows the top-ranked activity's expanded view. M3 adds a list of every live activity.

## Consequences

The rules are cheap to change and are pinned by tests (`ActivityCoordinatorTests`, `ModuleRegistryTests`). Modules provide SwiftUI views through `ActivityContent`, which keeps the model `@MainActor` rather than `Sendable`.
