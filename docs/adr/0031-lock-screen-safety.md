# ADR-0031: Lock-screen widgets (#59) and lyrics (#13b): safety design

- Status: **accepted 2 Nov 2026** for the Stage 2 spike, with Charlie's changes (§6). Stage 3 (the real widgets) waits for the spike's go/no-go.
- Date: 2026-11-02
- Rules it implements: CLAUDE.md "Safety rules for risky features: Lock-screen windows"; M6 prompt §6.3.
- Numbers reserved: ADR-0029 per-app volume, ADR-0030 accessory battery (both waiting for spike results).

## Context

The danger isn't a crash, it's a Mac that can't be unlocked. A window above the lock screen can hide the password field, take keyboard focus away from it, or stay on screen after unlock and float above every app. One developer locked himself out four times building this. Everything below exists to make those three failures impossible, or at worst harmless and short-lived.

**What Lakr233/SkyLightWindow (MIT) does.** It calls five private SkyLight functions: `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces` and `SLSSpaceAddWindowsAndRemoveFromSpaces`. It creates a Space at absolute level 400 (`NotificationCenterAtScreenLock`), which sits **above the lock screen UI at level 300**, shows that Space, and moves a window into it. That is the whole technique, and it's what we'll use. Its packaging is unsafe for us, though:

| SkyLightWindow as published | Why it's unsafe here |
|---|---|
| The window is **full-screen**, `canBecomeKey == true`, and opened with `makeKeyAndOrderFront` | It takes keyboard focus and sits over the password field |
| The level-400 Space is created once and **stays shown for the app's life** | After unlock, anything in it floats above every app |
| `unsafeBitCast(dlsym(…))` without checks | A missing symbol on a future macOS crashes the app instead of hiding the feature |

## Decision

**Adapt the technique, not the package.** A small wrapper, `Services/Private/SkyLightLockScreen.swift`, is written from scratch around the same five calls (attributed to SkyLightWindow, MIT, in the file header and `THIRD_PARTY_NOTICES.md`), plus `SLSHideSpaces` and `SLSSpaceDestroy` so the Space can be taken down. Every symbol is checked; any missing one makes the feature unavailable, logged once.

### 1. Off unless deliberately turned on, with several ways to turn it off

- **Off by default.** It can only be turned on in Settings ▸ Modules ▸ Lock Screen, behind a confirmation that explains the risk in plain words and what to do if the lock screen ever looks wrong. It is not part of onboarding.
- **Kill switches**, each checked before anything is created:
  1. The Settings toggle.
  2. A status-menu item, **Disable Lock Screen Widgets**, beside "Pause island" (CLAUDE.md's escape-hatch pattern).
  3. The launch argument **`--no-lock-screen`** (`open -a Notched --args --no-lock-screen`), which turns the setting off before any module starts.
  4. A defaults key that works from another Mac over SSH: `defaults write me.rkck.Notched lockScreen.killSwitch -bool true`. It's read at launch and on every lock.
- **Crash rules**, from `LaunchGuard` and our own flag:
  - If the previous session didn't quit cleanly (`previousSessionCrashed`), the feature turns itself **off** at launch. Settings then says why, and the user has to turn it on again.
  - A persisted flag `lockScreen.windowsShown` is set just before windows are shown and cleared after they're destroyed. If it's still set at launch, the app died while windows were showing: the feature turns itself off and the Settings note says so.
  - In safe mode the module doesn't start at all, like every other module.
- **Zero cost when off:** no observers, no timers, no Space.

### 2. Windows exist only while the screen is confirmed locked

A pure, unit-tested `LockScreenReducer` (Foundation only, per the module contract) owns the lifecycle. The module turns system signals into events and carries out the effects.

- **States:** `disabled` → `armed` (enabled, unlocked, nothing exists) → `pending` (lock seen, waiting to confirm) → `shown` (Space and windows exist).
- **Showing needs two signals agreeing (fail closed):** the `com.apple.screenIsLocked` distributed notification, **and** then, 0.5 s later, `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"] == true`. If the key is missing, or the session isn't on console, or anything is unknown, **nothing is shown**.
- **Destroy at once on any of these:**
  - `com.apple.screenIsUnlocked`;
  - `NSWorkspace.sessionDidResignActive` (fast user switching) and `sessionDidBecomeActive`;
  - screens sleeping;
  - a display change;
  - the setting or a kill switch going off;
  - any private call returning an error;
  - the watchdog;
  - the app quitting.
  Destroying is the first thing the handler does, before any other work.
- **Destroy order:** hide the Space first (`SLSHideSpaces`), so nothing is visible from that moment. Then order out and close the windows, then `SLSSpaceDestroy`. Even if a later step fails, the first one already took everything off screen.
- **The Space exists only while locked.** It is created on show and destroyed on hide, never kept shown while unlocked (the main change from SkyLightWindow).
- **Watchdog for a missed unlock:** while shown, every 2 s (its own timer, since `RefreshScheduler` pauses while locked), and on every `NSWorkspace.didActivateApplication`, it re-reads `CGSSessionScreenIsLocked`. If that's not `true`, everything is destroyed. A missed unlock therefore leaves a widget on screen for at most about 2 s.
- **Screens wake while still locked:** the lock is confirmed again (two signals), then the windows are shown again.

### 3. Never in the way of unlocking

- **No keyboard focus, ever:**
  - A borderless `NSPanel` with `.nonactivatingPanel`, `canBecomeKey == false` and `canBecomeMain == false`.
  - It is never made key, the app is never activated, and there are no text fields.
  - Typing on the lock screen always goes to the password field.
- **Never covers the password field or the user picker.** The window is a **small card, not full-screen**: at most 360 × 120 pt and at most 40 % of the screen width, centred horizontally, with its top at 30 % of the screen height (under the clock). It must never reach into the **bottom 45 % of the screen**, where the avatar, password field, user list and Touch ID prompt live. The geometry is a pure function, and a test checks that last rule for every screen size, including small and scaled ones.
- **The primary display by default** (the one with the login UI). A switch, **Also on other displays**, off by default, adds the same card, with the same safe-zone rule, on each secondary display.
- **Clicks:**
  - The card ignores the mouse (`ignoresMouseEvents = true`), so clicks pass straight through.
  - Media buttons (play/pause, next) are a separate sub-switch, off until the Stage 2 spike shows that clicking one never moves focus away from the password field.
  - If they're allowed, only the buttons take clicks.
- **VoiceOver:** the card is hidden from accessibility, so it never takes VoiceOver's focus from the password field (VoiceOver sits at level 600, above us).
- **If anything fails, the lock screen is untouched.** Errors destroy everything and turn the feature off; nothing retries in a loop.

### 4. Nothing sensitive unless chosen

Each item has its own switch, under the master switch:

| Item | Default |
|---|---|
| Now Playing: track title and artist | on (it's what a lock-screen player is for) |
| Now Playing: artwork | on |
| Battery percentage | on |
| Next event: the time only ("Event in 12 min") | on |
| Next event: its title | **off** |
| Lyrics line (#13b) | **off** |
| Media buttons | **off**, and only offered once the Stage 2 spike passes |

The card is built from the existing services' current values (Now Playing, Power, Calendar, the #13 lyric schedule), which are already running for their modules. Nothing is fetched because the screen locked.

### 5. Proving it: Stage 2 spike, then Stage 3 build

**Stage 2 (after this is approved):** a debug-only probe that shows **only a plain grey label** in the safe zone, using the wrapper, the reducer and every rule above. It also **destroys itself 60 s after appearing, whatever happens**. Charlie's physical test sheet:
1. Lock and unlock 20 times, quickly.
2. A wrong password.
3. Touch ID.
4. Display sleep and wake while locked.
5. Lid closed and opened.
6. An external display.
7. Fast user switching, if a second account exists.
8. Click on the label and then type the password: does typing still go to the field?
9. VoiceOver on, on the lock screen.
10. **`kill -9` while locked**, from a timer started before locking: the lock screen must still unlock normally.
11. A photo of the lock screen with the label, to check the safe zone.

**Go/no-go criteria for the spike:**
- The password field is always usable, and never covered or unfocused.
- The label is gone within 0.5 s of unlocking, in every test.
- The label never appears outside the lock screen.
- A crash while locked leaves the lock screen working, and on the next launch the feature is off.
- Nothing appears for another user.

Any failure is a no-go: #59 and #13b are dropped (✖) with the evidence.

**Stage 3 (if go):** the real card (Now Playing, battery, next event, then the lyric line), the Settings pane with its warning, the status-menu item, and the full physical test list again.

## Consequences

- The feature depends on five private SkyLight calls and an undocumented `CGSession` key. A macOS update can break it at any time. When that happens it hides itself; it never half-works.
- Being so strict costs some convenience: up to 0.5 s before the card appears after locking, nothing on external displays, and media buttons only after proof.
- Tests:
  - the reducer's invariants: windows exist only in `shown`, every destroy event from every state leads to no windows, the crash and kill-switch rules, and fail-closed behaviour on unknown lock state;
  - the safe-zone geometry for every screen size;
  - the wrapper's handling of missing symbols.

### 6. Charlie's decisions (2 Nov 2026)

1. **Adapt the technique into our own wrapper** rather than use the package: approved.
2. **The defaults in §4** are fine for the test version; revisit before Stage 3 ships.
3. **Secondary displays:** a switch, *Also on other displays*, off by default.
4. **Other user accounts:** a switch, *Show when this Mac has other user accounts*, off by default. When another login account exists (a local account with a login shell, UID ≥ 501, not the current user), nothing is shown unless that switch is on. Fast user switching still always destroys everything (§2), whatever the switch says.

Also noted while building: macOS Space ids are 64-bit (`uint64_t`, as in yabai's MIT headers); SkyLightWindow declares them `Int32`, which only works because of the arm64 calling convention. The wrapper uses `UInt64`.

## Evidence: lock signals on macOS 27.2 (spike round 1, 2 Nov 2026)

From `docs/spikes/results/spike-lockevents.txt` (MacBook Air M4 15", one 1920 × 1243 display, no other accounts). The probe created no windows.

| What the design relies on | Observed |
|---|---|
| `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` arrive | **Yes, every time:** five password locks, a wrong password, Touch ID, display sleep, lid close. A wrong password or Touch ID adds no events of its own. |
| `CGSSessionScreenIsLocked` confirms the lock | **Yes.** It is `1` from the lock notification onwards (already at the notification, and at +0.5 s and +2 s), and **absent** (not `0`) when unlocked, with `onConsole = 1`. `LockStateReader` treats exactly that as unlocked; showing needs the key present and true. |
| Unlock is seen promptly | `screenIsUnlocked` arrives with the key already absent; `didActivateApplication` follows within 50 ms. Either one tears the card down; the watchdog is only a backstop. |
| Display sleep while locked | `screensDidSleep` then `screensDidWake`, with the key `1` throughout, then unlock. Matches §2 (destroy on sleep, confirm again on wake). |
| Lid close | **`willSleep` and `screensDidSleep` come about 0.2 s *before* `screenIsLocked`.** On wake: `screensDidWake`, `didWake`, still locked, then unlock. |

**Change made from this:** a lock notification that arrives while the screens are asleep is ignored, and so is a lock read that lands while they are asleep. The wake event confirms the lock again and shows the card then. Without this, a check left pending across a lid close would show the card on wake a moment before the wake signal rebuilt it (a flicker, not a safety problem). Tests: `lidCloseOrder`, `noShowWhileAsleep`. The safe-zone test now includes Charlie's 1920 × 1243 screen.

`didActivateApplication` also fires about 0.15 s *before* every lock (the login window becoming active). It is harmless here: the reducer only reacts to it while a card is shown.

Not covered by round 1, and still needed before the Stage 2 go/no-go: everything in the Stage 2 test list (§5), plus fast user switching and an external display if Charlie ever uses them.
