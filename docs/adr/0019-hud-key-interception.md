# ADR-0019: Intercepting the volume keys for the HUD (#20)

- Status: draft (M3b B1, Task 1). Experiments 1 and 2 done; 3 and 4 follow with the module.
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

## Still to do (later in B1)

3. Revoking Accessibility while armed leaves the keys working.
4. How long a Bluetooth output's read-back lags a set.
