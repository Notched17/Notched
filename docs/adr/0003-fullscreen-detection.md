# ADR-0003: Fullscreen detection with SkyLight plus a public fallback

- Status: accepted (M1)
- Date: 2026-10-27

## Context

The island must hide on a display that is showing a fullscreen app (#5), such as Safari video or a game. There is no public API that says "the current Space on display X is a fullscreen Space".

## Decision

- **Primary:** read SkyLight's `CGSCopyManagedDisplaySpaces` (via `dlopen`/`dlsym` in `Services/Private/SkyLightSpaces.swift`, following CLAUDE.md's private-API rule). A display is fullscreen when its current Space has a `TileLayoutManager` or `type == 4`. A `"Main"` identifier (displays share Spaces) maps to the primary display. This is the technique used by TheBoredTeam/MacroVisionKit (MIT), reimplemented as a graceful wrapper. The parsing is pure and unit-tested with fixtures.
- **Always also:** the public window-list heuristic (`CGWindowListCopyWindowInfo`, bounds only, no Screen Recording permission). A normal-layer window from another app that covers a whole screen, menu bar included, marks it fullscreen. This catches borderless fullscreen games that don't use a fullscreen Space, and it is the only signal if the SkyLight symbols ever disappear.
- **Event-driven:** re-check on `activeSpaceDidChange`, `didActivateApplication` and screen changes, plus a single one-shot re-check 0.4 s later to catch the end of the transition animation. No polling.

## Consequences

- Verified by hand on macOS 27.2: fullscreening Safari and a second app hid the island on that display, and leaving fullscreen brought it back.
- If Apple changes the SkyLight dictionary, the fallback still covers fullscreen windows. The failure is logged once.
- "Keep showing during fullscreen media" needs Now Playing and moves to M2.
