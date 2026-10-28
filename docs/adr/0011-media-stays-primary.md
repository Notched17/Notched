# ADR-0011: Whatever is playing stays primary

- Status: accepted (M3a). Amends the kind order in ADR-0006.
- Date: 2026-10-28

## Context

ADR-0006 ranked activity kinds `system > live > media > passive`. A timer, keep-awake or charging indicator, all user-started or status, therefore took the attached island from Now Playing, and the music moved to a minimal bubble. M3a adds several such activities at once (timers, keep-awake, an opt-in charging activity), so with music playing the island would often show a coffee cup instead of the song.

Charlie's call (28 Oct 2026): "Music and whatever is currently playing should stay primary." It also fits the iPhone: the media activity is what people look at most, and the island stays on it while other Live Activities sit beside it.

## Decision

- `ActivityKind` is ordered `passive < live < media < system`.
  - **`system`** (a call, screen recording) still wins over everything.
  - **`media`** (Now Playing) keeps the attached island against everything else.
  - **`live`** (timers, keep-awake, downloads, an agent working) shows as a minimal bubble beside media, and is primary when nothing plays.
  - **`passive`** (charging, later weather) comes last.
- Nothing else changes. Relevance and start order still break ties within a kind. The user can still make a bubble primary (a click, or a two-finger swipe); the swap is sticky as before.
- Alerts are independent of rank. A finished timer or a Claude Code permission request still expands the island over the music, then returns to it.

## Consequences

- The ranking tests (`rankByClass`, `twoActivities`, `threeActivities`) now expect music primary.
- M3a modules use `.live` for timers and keep-awake, and `.passive` for the charging activity.
- User-adjustable priority (#8, M3b) starts from this order.
