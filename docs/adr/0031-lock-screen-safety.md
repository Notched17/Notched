# ADR-0031: Lock-screen widgets (#59) and lyrics (#13b): safety design

- Status: **accepted 2 Nov 2026** for the Stage 2 spike, with Charlie's changes (§6). **Stage 2 passed and the decision is go (3 Nov 2026, §9).** Stage 3 is built, experimental and off by default (§8).
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

## Evidence: the Space calls on macOS 27.2 (spike round 2, 2 Nov 2026)

From `docs/spikes/results/round2/spike-lockscreen.txt` and the `lockscreen-desktop-*.png` screenshots in the same folder.

1. **First lock test: nothing showed.** The reducer confirmed the lock and went to `shown`. Then the wrapper read `SLSShowSpaces` as failing (`-1342177280`) and tore everything down before any window existed. The safety path worked as designed: it destroyed everything, cleared the shown flag and turned the feature off with a reason.
2. **Why the call seemed to fail.** It didn't. Disassembly of SkyLight on 27.2 shows two paths for each Space call. In an AppKit app, SkyLight takes the bridged one, `SLSPerformAsynchronousBridgedWindowManagementOperation`. That path **returns no status**: `x0` is whatever an autorelease-pool pop left behind (`0xB0000000`, which is not a `CGError`). This applies to set level, show, hide, add windows and destroy. `SLSSpaceCreate` and `SLSCopySpacesForWindows` are synchronous and return real values.
3. **The wrapper now ignores those return values** (declared `Void`) and checks by observation instead.
4. **Desktop test (unlocked, no one at the keyboard needed).** A window at *desktop* level, which normally sits behind every app window, was shown for 5 s.
   - **Control, no Space:** hidden behind the app windows. SkyLight lists it on Space 1.
   - **In our level-400 Space, all four set-ups** (with and without `.canJoinAllSpaces`, added before or after ordering front): **shown in front of every app window.** SkyLight lists it on no Space at all. On 27.2 that query reports desktop Spaces only, so "no Spaces" is what a successful move looks like.
   - Gone from the window list 0.5 s after tear-down, every time.
5. **What this proves:** the Space mechanism works on macOS 27.2, and the order and join settings make no difference. **What it doesn't prove:** that level 400 is above the macOS 27 lock screen. The lock test (round 2 §3) answers that.
6. **Stage 3 consequence.** No call reports failure any more, so the controller can't rely on errors. It records each card's state 0.5 s after showing it. Stage 3 should turn a card still on a desktop Space into a `.failure`, once the lock test shows the reading is reliable while locked.

### The lock test after the fix (round 2, 2 Nov 2026)

`spike-lockscreen.txt` from 07:51 onwards. The photo is `docs/spikes/results/round2/lockscreen-label-cropped.jpg`, cropped so that the "if lost" phone number, face and name are left out. The full photo stays out of the repo.

| Stage 2 check | Result |
|---|---|
| 5.2: the label shows, and covers nothing | **Pass.** It shows under the clock within 0.5 s of the lock confirming. It is well clear of the user picture, the name, "Touch ID or Enter Password" and the "if lost" message, which start about 80 % of the way down the screen. |
| 5.3: unlock removes it at once | **Pass, 3 of 3.** Every `screenIsUnlocked` led straight to `destroy`. |
| 5.8: display sleep while locked | **Pass.** `screensSlept` led to destroy. On wake the lock was confirmed again and the card shown again. |
| Placement reading while locked | 0.5 s after each show the card is on screen and **out of the desktop Spaces**, the same as on the desktop. This confirms the reading, so Stage 3 can act on it. |
| 5.13: kill switch | **Pass** (run by Claude, unlocked). With `lockScreen.killSwitch` set, `arm` was refused. |
| 5.4 (20 cycles), 5.5 (60 s limit), 5.6 (wrong password), 5.7 (Touch ID), 5.9 (lid), 5.10 (click on the card), 5.11 (VoiceOver), **5.12 (kill -9 while locked)** | **Not run yet.** |

**Decision: provisional go for Stage 3.** Charlie asked for Stage 3 before the full test list. The mechanism works and the placement is safe, so Stage 3 is built **off by default, with every rule in §1–§4 and labelled untested**. #59 and #13b stay 🟨, and the setting carries an "experimental" note, until the rows above marked "not run" pass. Above all that means 5.12: if the lock screen ever fails to work after a crash, the decision is **no-go**, whatever has been built.

### 7. Placement (Charlie, 2 Nov 2026)

Charlie wants the card in the vertical middle by default, with a left, centre or right choice. This stays inside the safe band, which the photo checks:

- **The band:** the card's top is never above 30 % from the top of the screen (under the clock), and its bottom is never below 55 % from the top, the existing `forbiddenBottomFraction` of 0.45 of the height measured from the bottom. On Charlie's screen the unlock controls start at about 80 %, so the band leaves a margin of a quarter of the screen. **The band is a hard rule in `LockScreenGeometry`, unit-tested. The settings choose positions inside it and never move its edges.**
- **Vertical:** *Middle* (default) puts the card's centre at 50 % of the height, clamped into the band. *Under the clock* puts its top at 30 %, as in the Stage 2 label.
- **Horizontal:** *Centre* (default), *Left* or *Right*. Left and right keep a margin of 6 % of the screen width from the edge. The card is never wider than 40 % of the screen.
- No placement may return a frame outside the band or off the screen. `cardFrame` returns nil instead, and the card isn't shown.

### 8. Stage 3 built (Charlie, 2 Nov 2026): experimental, untested on the real lock screen beyond Stage 2

Charlie chose to build the card before finishing the Stage 2 checklist (items 5.4–5.7 and 5.9–5.12, above all the `kill -9`-while-locked test 5.12, are still open), so everything below ships **flagged experimental, off by default**. If 5.12 fails, the decision is no-go and the module is removed.

- **A normal module.** `LockScreenModule` ("Lock Screen", `isOnByDefault: false`, no permission) wraps `LockScreenController` and the pure `LockScreenReducer`. Turning it on in Settings ▸ Modules asks for confirmation first. The menu bar offers "Disable Lock Screen Widgets" while it runs. When the reducer turns the feature off, the module is switched off and Settings says why (`lockScreen.lastOffReason`).
- **Settings are re-read on every lock.** The controller asks the module for its configuration each time `com.apple.screenIsLocked` arrives, so `defaults write me.rkck.Notched lockScreen.killSwitch -bool true` from another Mac works at the next lock without a restart. The crash rule is applied once per launch, so turning the module back on deliberately does not trip it again.
- **Content, all toggleable, display only.** Now Playing (track, artist, artwork), a lyric line, battery, and next event. No controls, no text fields, hidden from VoiceOver, ignores the mouse. Event titles and lyrics are off by default ("Event in 12 min"). The card reads the calendar only when the Calendar module already has access, so the lock screen never prompts. `NowPlayingShelf` (in `ModuleServices`) lets the card read the Media module's model without owning a second Now Playing service.
- **No polling.** The scheduler pauses while locked, so the card uses SwiftUI `TimelineView`: once a minute for the footer, one entry per lyric line for lyrics. Nothing is animated while locked.
- **Placement (§7) and size.** Height (under the clock or middle), side (left, centre, right) and size (Small 0.8×, Medium 1×, Large 1.3× of the tested 360 × 120) only choose a position inside the band: top no higher than 30 % from the top, bottom never in the bottom 45 %, at most 40 % of the screen's width. `cardFrame` ends with a check that returns nil for any frame outside the band, whatever the choices. Large in the middle is lifted to the band's lower edge, never lowered. Tests cover every size and placement on eleven screen shapes. Medium is the only size run on the real lock screen so far.
- **Look.** The card is a content-layer element, so by default it is a **solid** dark surface (88 % black, fully opaque under Reduce Transparency), like the island and a Live Activity, which stays readable over any wallpaper. The user may choose **Liquid Glass** instead (`.glassEffect(.regular.tint(black 40 %))`, applied after layout; solid again under Reduce Transparency). The glass was checked only over a dark desktop, not over a pale wallpaper on the real lock screen. One 360 × 120 layout is scaled to every size, so no size can clip.
- **Debug.** In Debug builds, `notched://debug/probe?name=lockscreen&action=card&style=glass&size=large` previews the card on the desktop with no SkyLight, unlocked only.

### 9. Stage 2 completed (Charlie, 3 Nov 2026)

Charlie ran the rows left open in the table above.

| Stage 2 check | Result |
|---|---|
| 5.4: 20 lock/unlock cycles | **Pass** ("looks good"). |
| 5.5: the 60 s limit | **Pass.** The label removed itself. |
| 5.6: wrong password, 5.7: Touch ID, 5.9: lid closed while locked | **Pass.** Unlocking worked as normal each time. |
| 5.10: click on the card | **Pass.** Typing still went into the password field. |
| 5.11: VoiceOver | **Pass.** VoiceOver doesn't read the card, and the password could still be typed and the Mac unlocked. |
| **5.12: `kill -9` while locked** | **Pass.** The lock screen kept working. On relaunch, the crash rule turned the feature off: `lockScreen.lastOffReason` = "Notched stopped while the lock-screen card was showing, so lock-screen widgets turned themselves off…", and `lockScreen.windowsShown` was back to false. The spike log has no line for it because a killed process can't write one. The evidence is the product's own setting (read by Claude on 3 Nov). |

**Decision: go.** Every Stage 2 check has passed, so the card stays: still off by default, still behind the confirmation, the kill switch and the crash rule. Not yet seen on the real lock screen: the Liquid Glass look over a pale wallpaper, and the Large size. Charlie's saved settings were on Glass and Large on 3 Nov, so they may already have been tried; that needs confirming. Not run at all: 5.14 (external display) and 5.15 (second account), because neither is available. Other displays and other accounts stay off by default until they are tested.
