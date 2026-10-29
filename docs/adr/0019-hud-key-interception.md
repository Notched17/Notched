# ADR-0019: Intercepting the volume keys for the HUD (#20)

- Status: accepted, partly verified (M3b B1). Experiments 1 and 2 are done; 3 and 4, and every check with a real key press, are on Charlie's list.
- Date: 2026-10-29
- Mac: Mac16,13, macOS 27.2.

## Context

The HUD replacement (#20) needs the system volume HUD, which lives in Control Center on macOS 26+, to stay away when Notched shows its own. The design (`docs/superpowers/specs/2026-10-29-m3b-hud-tap-safety-design.md`) puts an active session tap on system-defined events only, and swallows a key only after the change has taken effect. Before any HUD UI, B1 asked two questions.

## Experiment 1: does swallowing the key suppress the Control Center HUD?

**Yes.** A throwaway probe (`HUDTapProbe`) installed an active `kCGSessionEventTap` (mask `1 << NX_SYSDEFINED`, head insert) on its own thread and posted three Volume Up presses at `.cghidEventTap`, each tagged in `eventSourceUserData` so the probe touched nothing else. It removed itself after 30 s and restored the volume.

| Mode | What the tap did | Volume | Screen |
|---|---|---|---|
| Pass (control) | returned every event | system raised it | the Control Center HUD appeared top right, and the menu bar showed its Sound item (`docs/screenshots/m3b-hud/b1-spike-pass-through-system-hud.png`) |
| Swallow | set 1/16 up through CoreAudio, returned nil | 0.375 → 0.4375 → 0.5 → 0.5625, each set within 8 ms of the event | **no system HUD, no Sound item** (`b1-spike-swallowed-no-hud.png`) |

So "Show alongside the system HUD" isn't needed, and a **session** tap is enough: no HID tap, which the design said was Charlie's call.

Caveat: the events were synthetic (an `NSEvent` of subtype 8 posted at the HID tap), not a physical key press. They travel the same path (HID → session tap), but a real press is on the end-of-part list.

## Experiment 2: which permission does the tap need?

On this Mac both Accessibility and Input Monitoring were already granted to Notched (`AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` both true, and `CGPreflightPostEventAccess()` true), and `tapCreate` succeeded. **So this run can't tell whether Accessibility alone is enough.** Apple's model is that active taps need Accessibility and listen-only taps need Input Monitoring, so the module asks for Accessibility only. If `tapCreate` returns nil while Accessibility is trusted, the module logs it, reports Not Allowed, and the pane points at Input Monitoring (design §5).

Not yet verified: revoking only Input Monitoring for Notched and checking the tap still installs. On Charlie's list.

## Found while probing

- Tagged events (`eventSourceUserData`) survive the HID → session path, so a probe can mark its own events and leave real keys alone.
- A tap callback gets `NSEvent(cgEvent:)` with `subtype`, `data1` (key in the high 16 bits, state `0xA` down / `0xB` up in bits 8–15) exactly as volumeHUD (MIT) documents. No code was copied from it; the layout is the public `NX_SYSDEFINED` convention.
- The callback returns `Unmanaged.passUnretained(event)` to pass an event on, which is correct for a tap. (volumeHUD's `passRetained` leaks one reference per event.)

## What was built, and measured

`MediaKeyTap` (the only file that touches `CGEventTap`) runs the session tap on its own thread; `HUDKeyEngine` puts the pure `HUDKeyReducer` behind a lock and carries out the volume change on the tap thread, outside the lock; `HUDModule` is the shell (permission, off switches, latch, banner). Checked on this Mac with synthetic key events (`notched://debug/hud-key`), the tap armed:

| Check | Result |
|---|---|
| One Volume Up | volume 38 → 44 (one 1/16 step), no system HUD, our banner |
| Hold Down, 13 presses | 7 steps to 0 (muted, as macOS does), then 6 presses swallowed at the limit with the HUD still shown |
| Up from 0 | unmutes, 1/16 |
| Shift+Option | a 1/64 step (0.078) |
| Mute key | toggles both ways |
| Key posted during a 2.5 s main-thread hang | handled 7 ms later; the main thread was back 2 s after that |
| Arm and disarm ×10 | file descriptors 39 → 39, threads 5 → 5 |
| Each step of a press | set and read back within about 8 ms (log timestamps) |

Screenshots: `docs/screenshots/m3b-hud/b1-notch-*.png` and `b1-pill-volume.png`.

## Decisions

1. **A session tap on `NX_SYSDEFINED` only**, never widened (Charlie, 29 Oct): typing never passes through it.
2. **Accessibility only.** The tap is created only if `AXIsProcessTrusted()`; a refused `tapCreate` reports Not Allowed. Whether Input Monitoring is also needed is untested (above).
3. **The callback decides on the tap thread.** CoreAudio reads and writes are thread-safe, so the key is only swallowed once the change has taken effect, and a stalled main thread can't delay it.
4. **A key goes to macOS** whenever the island can't show the HUD (paused, locked, fullscreen-hidden, expanded under the pointer, an alert showing), whenever Option alone, Control or Command is held, and whenever the output can't be set.
5. **The feedback click** is the system's own `volume.aiff` (present on 27.2), only when System Settings' "Play feedback" is on, flipped by Shift, silent for the fine step, at a limit and for the mute key.
6. **volumeHUD (MIT)** was read for the pattern (an active tap, re-enable on timeout, fall back to the system when a change doesn't take). No code was copied; this is a fresh implementation around the safety design.

## Not yet verified

- **Experiment 3:** revoking Accessibility while armed. It needs the grant removed from System Settings, so it's on Charlie's list. The unit tests cover the rule (the tap is removed within 2 s and the keys pass), not what macOS does to a live tap.
- **Experiment 4:** how long a Bluetooth output's read-back lags a set (AirPods or similar). The unconfirmed-change path (swallow, check 150 ms later, two unconfirmed presses put the output in pass-through) is unit-tested only.
- **Real key presses** (tap, hold, mute, the modifiers), an external display, switching outputs mid-press, a fullscreen app.
- Whether Accessibility alone is enough, with Input Monitoring revoked (experiment 2).
