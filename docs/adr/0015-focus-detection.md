# ADR-0015: Focus (#30) is dropped from M3b

- Status: accepted (M3b spike S3)
- Date: 2026-10-28
- Mac: Mac16,13, macOS 27.2, Debug build signed with Apple Development, run from `~/Applications`.

## Context

ROADMAP #30 asks for the current Focus on the island. There is no public "which Focus is on" API. Charlie ruled out Full Disk Access, so reading `~/Library/DoNotDisturb/DB/*.json` (the Atoll and DynamicNotch route) is off the table. The M3b plan (`docs/superpowers/specs/2026-10-28-m3b-system-design.md`, S3) required at least one on/off signal that needs no permission before building anything.

## What we tried

A DEBUG probe ran inside the signed, installed app. Charlie switched Do Not Disturb and a second Focus on and off by hand.

| Route | Result on 27.2 |
|---|---|
| Distributed notifications `_NSDoNotDisturbEnabledNotification` / `_NSDoNotDisturbDisabledNotification` (community code) | **Never delivered.** Do Not Disturb and another Focus were each switched on and off, and nothing arrived. A catch-all observer (nil name, filtered for "disturb/focus/dnd/mode/assertion") also saw nothing. |
| `INFocusStatusCenter` (Intents) | The authorization prompt appeared and was allowed (`authorizationStatus == .authorized`). **`focusStatus.isFocused` still reported false while a Focus was on.** It needs Communication Notifications plumbing that a menu-bar agent doesn't have, so it's unusable. |
| App Intents `SetFocusFilterIntent` in the main app (no extension) | **Works**, but only for Focuses where the user has added the filter. "Show in Notched" appears under System Settings ▸ Focus ▸ *Focus* ▸ Focus Filters. `perform()` runs (off the main thread) with the user's parameters when that Focus turns on, and with nil when it turns off. `static var current` returns the same values at any time, so state can be seeded at launch. The filter never receives the Focus's own name; the user has to type it. |

## Decision

**Charlie dropped Focus from M3b.** The only working route needs a one-time setup in every Focus the user wants shown, and it can't detect a Focus that hasn't been set up. That falls short of "show the current Focus".

- The probe and `NSFocusStatusUsageDescription` are removed. Nothing ships.
- ROADMAP #30 goes back to "Later". If it returns, it should start from the Focus Filter route: it is public, needs no permission and no polling, and is event-driven, with a name and symbol picker in the filter.
- ISLAND-BEHAVIOR §7's "Focus names need Full Disk Access" is corrected: on 27.2, even on/off needs either the filter or Full Disk Access.
