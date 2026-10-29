# M3b Part B, B0: HUD event-tap safety design

**Status:** draft for Charlie's approval, 29 Oct 2026. Covers the key interception behind #20 (volume) and #21 (brightness); #23 styles only where they touch safety. Builds on CLAUDE.md's safety rules for event taps, ADR-0012 (banners) and `LaunchGuard` (crash protection). Calls marked *(my call)* are mine to make and open to change.

## The promise

The volume and brightness keys always work. The worst Notched can do is leave a key to macOS, which then shows its own HUD. It swallows a press only once the change has taken effect, or, at the very top or bottom, once it has confirmed the output works and there was nothing left to change. It never delays typing, and it can always be switched off from the menu bar.

## 1. What the tap sees

- One active **session** tap (`kCGSessionEventTap`, head insert, `.defaultTap`) whose mask is `1 << NX_SYSDEFINED` and nothing else. Typing, shortcuts and the mouse never pass through it. It's a session tap, not a HID tap, so another user's session (fast user switching) is never touched. If B1 finds that only a HID tap suppresses the system HUD, I stop and ask.
- Inside the callback, only subtype 8 (aux control buttons) with keys `SOUND_UP` (0), `SOUND_DOWN` (1) and `MUTE` (7) is handled, plus `BRIGHTNESS_UP` (2) and `BRIGHTNESS_DOWN` (3) once B2 is armed. Every other system-defined event (play/pause, keyboard backlight, the aux-mouse-button events that clicks produce) goes straight back after the subtype check.
- The mask is never widened to key-down events. If this Mac's brightness keys arrive as ordinary key presses (B1 experiment 5), #21 is dropped and macOS keeps its brightness HUD *(Charlie, 29 Oct)*.

## 2. Where it runs

- On a dedicated thread with its own run loop, in `Services/Input/MediaKeyTap.swift`, the only file that touches `CGEventTap`. The main thread never runs the callback, so a busy UI can't delay a key, and a stuck tap thread can't freeze the UI or the status menu.
- The callback is synchronous and never waits on the main actor. The state shared with main (armed, can-be-seen, breaker, pairing) lives in one `Mutex` from Synchronization. The HUD reading is handed to the main actor with a fire-and-forget hop *after* the decision.
- The callback context is retained by the tap and released only after `CFMachPortInvalidate` and the thread's run loop has stopped.

## 3. The decision rule

For each key-down, including auto-repeats, in order:

1. **Pass it to macOS** if any of these hold:
   - Not armed: the module is off, paused or latched, or there's no permission.
   - Our HUD can't be seen right now: Pause Island is on, the screen is locked or asleep, the session is inactive, or the island is hidden over a fullscreen app *(my call for B1; B3 may let the HUD show over fullscreen, which then counts as "can be seen")*.
   - That key's class is tripped (§4).
   - A modifier we don't own is held. Shift (inverts the volume feedback sound, as on macOS) and Shift+Option (quarter steps, 1/64, no sound) are ours. Option alone (macOS opens Sound or Displays settings), Control and Command pass. Fn, Caps Lock and the keypad flag are ignored.
2. **Apply it synchronously** on the tap thread: take the default output device, check the property is settable, read the value, compute the 1/16 (or 1/64) target, set it, then read it back. Mute toggles `kAudioDevicePropertyMute`; raising the volume from mute unmutes, and reaching 0 mutes, as on macOS. Brightness follows the same pattern on the built-in display, after `DisplayServicesCanChangeBrightness`.
3. **Swallow it only if the change is confirmed**: the read-back reached the target, or mute flipped. If the property isn't settable or the set call fails, **pass**, so macOS does it and shows its own HUD (its crossed-out speaker for HDMI and similar outputs).
   - **The ambiguous case:** the set call succeeded but the read-back hasn't moved yet (likely on Bluetooth). Passing would double the step, so it's swallowed and checked again 150 ms later *(my call, all of this case)*:
     - Targets are absolute, so the next step (an auto-repeat, say) builds on the **pending target**, not the stale read-back, and re-applying a target can never double a step.
     - If the check still shows no change, the pending target is set once more. If that doesn't take either, the press counts as **unconfirmed**. Unconfirmed is counted per press, not per auto-repeat.
     - Two unconfirmed presses on one device switch that device to pass-through until the output changes. This is the promise's one bounded exception: at most a press or two, on a device that accepts a change and then doesn't apply it.
   - **At the limits** (up at 100%, down at 0%): the key is swallowed, and our HUD shows full or empty with a small nudge, but only if the read succeeded and the property is settable. Otherwise it passes, as above. Holding a key past the limit never switches HUDs halfway through. Down at 0% also makes sure the output is muted, as on macOS *(Charlie, 29 Oct)*.
4. **A key-up follows its press.** It's swallowed only if every key-down of that press was swallowed; if macOS saw any of them, it gets the key-up too. A key-up from a press we never saw passes.
5. The HUD reading reaches the main actor after the callback has returned: a late HUD is fine, a late key isn't.

## 4. Tap health and the breaker

- On `tapDisabledByTimeout` or `tapDisabledByUserInput`: check Accessibility and the armed flag again, and re-enable only if both hold.
- **Breaker:** a second timeout within 10 minutes, or three callbacks slower than 50 ms within 60 s, removes the tap for the rest of the session and latches (§7) *(thresholds are my call; B1's measurements tune them)*.
- **Per key class:** three failed applies in a row (CoreAudio or DisplayServices errors) stop intercepting that class until the output device or the display set changes. The keys pass in the meantime, and nothing latches.

## 5. Permission

- Accessibility only, asked when the user turns the HUD on. `PermissionCenter` already prompts for it and probes `AXIsProcessTrusted()`. No tap is created unless `AXIsProcessTrusted()` is true at that moment, and a nil from `tapCreate` counts as no permission.
- **Revoked while running.** macOS can leave an active tap stuck when its app loses trust. Three things watch for this:
  - the `com.apple.accessibility.api` distributed notification;
  - the existing check on app activation;
  - a 2 s check through `RefreshScheduler`, only while the tap exists.

  When trust is revoked, the HUD disarms, disables the tap and invalidates it at once, and the pane shows Not Allowed.
- B1's ADR records whether 27.2 also wants Input Monitoring for this tap (active taps have historically needed only Accessibility). If it does, both are asked for in one walkthrough when the HUD is turned on, and the 2 s check watches both (`IOHIDCheckAccess`, already in `PermissionCenter`) *(my call)*.

## 6. Off switches (none needs the tap to cooperate)

| Switch | Effect |
|---|---|
| Settings ▸ the HUD module's toggle (the kill switch) | `stop()`: disarm, invalidate, and the thread exits. When it's off, it costs nothing. |
| Status menu ▸ **Pause HUD Replacement**: shown while the module is on, and persisted like Pause Island *(my call)* | It flips the armed flag first, so the callback passes everything from that instant, even if teardown is slow. Then `CGEvent.tapEnable(false)` runs from main, then teardown. Unpausing also clears a latch. |
| Pause Island; screen lock or sleep; an inactive session | The tap is disabled (not removed) and re-enabled on return. macOS's HUD shows in the meantime. |
| Quit | Always works: the menu is on main and the tap is on its own thread, and the tap dies with the process. |

## 7. Crashes and the latch

- A crash anywhere removes the tap along with the process, so the keys go straight back to macOS. The tap is created inside the module's `start()`, so `LaunchGuard`'s two-strike suspension already covers a crash while arming.
- `hud.armedSession` is set while armed and cleared on disarm and on a clean quit. If two sessions in a row end uncleanly with it set, the HUD starts **latched** *(my call, in the spirit of keep-awake's after-crash rule)*.
- **Latched** means: the reason and date are persisted; no tap is installed at launch; the HUD pane shows "Turned off after a problem: ‹reason›" with **Turn Back On**; one banner appears if it trips mid-session ("HUD replacement paused"); and it's logged once.

## 8. What the user sees when something fails

| Failure | What they see |
|---|---|
| No Accessibility, or it's revoked | The macOS HUD. The pane says Not Allowed, with Open System Settings. |
| Output can't be adjusted, or CoreAudio fails | The macOS HUD (its "can't change" one). |
| Island hidden (fullscreen, paused, lock screen) | The macOS HUD. |
| Tap timed out twice or kept running slow | The macOS HUD, one "paused" banner, and the latch in Settings. |
| DisplayServices symbols missing, no built-in display, or the lid closed | The brightness option is hidden; macOS handles brightness. |

## 9. Tests (fake event source)

- **`MediaKeyEvent` parser** (pure): (type, subtype, `data1`, flags) → key, down/up, repeat, modifiers. Tested with hand-built `data1` values.
- **`HUDKeyReducer`** (pure, Foundation-only, per `docs/templates/module-reducer.md`). The callback runs it twice per key: `.keyDown` → `[.apply(step)]`, then `.applied(result)` → `[.swallow, .showHUD(reading)]` or `[.pass]`.
  - Other events: `.keyUp`, `.tapDisabled`, `.slowCallback`, `.permissionChanged`, `.visibility`, `.outputChanged`, `.verify`.
  - Other effects: `.reEnableTap`, `.removeTap(reason)`, `.latch(reason)`, `.wake(Date)`.
- **`VolumeControl` and `BrightnessControl`** protocols, with fakes that script errors, not-settable properties, stale read-backs and slow calls.
- **`FakeTapHost`** feeds synthetic key events and disable notices into the real engine (everything except the `CGEventTap` itself) and records pass or swallow for each.
- Tests for every rule above, plus starting and stopping 10× without leaving a thread, port or run-loop source behind (like `ModuleShellTests`).
- **On the Mac (B1):** a DEBUG `notched://debug/hud-key?key=up` posts a real system-defined key event with `CGEventPost` (as Hammerspoon's `newSystemKeyEvent` does). That exercises tap → CoreAudio → HUD, and the Control Center check, without anyone pressing keys. Checks with real keys go on Charlie's list.

## 10. B1 experiments, before any HUD UI

1. Does swallowing at a session tap suppress the Control Center volume HUD on 27.2? This goes in an ADR. If it doesn't, offer "Show alongside the system HUD", which needs no tap at all, only CoreAudio volume listeners.
2. Which TCC permission does the active tap need on 27.2?
3. With the tap armed, does revoking Accessibility leave the keys working (via the auto-disarm)?
4. With AirPods or other Bluetooth outputs, how long does the read-back take to follow a set?
5. What do this Mac's brightness keys send? Log it listen-only while Charlie presses F1 and F2.

## Decisions

- **At the limits:** swallow the key and show our HUD full or empty (Charlie, 29 Oct; §3).
- **Brightness keys that aren't media-key events:** drop #21 rather than widen the tap (Charlie, 29 Oct; §1).
- Everything marked *(my call)* above is open to change on review.
