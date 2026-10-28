# ADR-0013: What M3a's assumptions turned out to be on macOS 27.2

- Status: accepted (M3a Part B)
- Date: 2026-10-28
- Mac: Mac16,13 (notched MacBook Air), macOS 27.2, Debug build signed with Apple Development, run from `~/Applications`.

## Context

M3a Part A was written on Linux with no Xcode. Its plan listed assumptions only a Mac can answer (`docs/superpowers/plans/2026-10-28-m3a-status.md`, handoff). Part B tested each by experiment. This records the answers and the decisions they led to.

## Findings

### 1. Caps Lock without Accessibility (#25)

**It works with no permission at all.** Tested with a probe app under a fresh bundle id (`me.rkck.Notched.CapsProbe`, ad-hoc signed, launched with `open`, so it is its own TCC client) that has neither Accessibility (`AXIsProcessTrusted() == false`) nor Input Monitoring (`IOHIDCheckAccess` not granted). Caps Lock was toggled in software with `IOHIDSetModifierLockState`. The control: Notched, which has both grants, showed "Caps Lock On" and "Off" banners for the same toggles.

- The probe's global `NSEvent` monitor received **every** `flagsChanged` event, with the right Caps Lock state.
- It received **no** `keyDown` for an F18 press posted at the same time, so TCC was filtering this untrusted app's key events. It just doesn't filter modifier-flag changes.
- `addGlobalMonitorForEvents` returns a monitor either way; it isn't a permission check.

Decision: the module declares no permission and asks for none; the pane says so. The Input Monitoring row in Settings ▸ Permissions no longer claims Caps Lock needs it. Caveat: a physical key press wasn't repeated with the probe, only the software toggle (Notched with its grants did get physical presses). The default stays **off** as agreed for this milestone; with no permission, CLAUDE.md's rule would make it on-by-default, which is Charlie's call.

### 2. Bluetooth accessories without a permission prompt (#27)

- **No prompt.** The Bluetooth module ran all session, with its accessory monitor on. Settings ▸ Permissions still showed Bluetooth as **Not Asked Yet** (`CBManager.authorization == .notDetermined`), and no system dialog appeared. The monitor only reads the I/O Registry (`IOServiceAddMatchingNotification` for `IOHIDDevice` with `Transport` = `Bluetooth` or `Bluetooth Low Energy`) and never opens a device, so it needs neither Bluetooth nor Input Monitoring.
- **AirPods' own HID interface reports `Transport = "BT-AACP"`**, not Bluetooth, so the accessory monitor ignores it. AirPods are announced from CoreAudio instead. Real connects and disconnects banner correctly, with "Charlie's" stripped from the name.
- **Keyboards and mice: not verified with a real device.** None of the paired ones (a Magic Keyboard, a Microsoft mouse) connected during either test round, and the accessory monitor logged no add or remove. It matches the documented transport values (`kIOHIDTransportBluetoothValue`, `kIOHIDTransportBluetoothLowEnergyValue`); DEBUG builds log every accessory it sees, so one real connection will confirm it.

Decision: keep the I/O Registry route. No Bluetooth permission is requested, and the IOBluetooth fallback isn't needed.

### 3. SF Symbol names

All exist on 27.2, including `magicmouse`, `rectangle.and.hand.point.up.left`, `cup.and.saucer(.fill)`, `personalhotspot`, `cable.connector`, `powerplug.fill` and `stopwatch.fill`. `SymbolNameTests` now scans `Sources/` and `App/` for every literal name, plus the names chosen at runtime, so a typo or a renamed symbol fails a test.

### 4. Charger timing (#26)

Measured against macOS's own log (`pmset -g log`):

| Event | macOS switched | Notched banner |
|---|---|---|
| Unplug | 15:02:33 "Using Batt (Charge: 91)" | 15:02:34.4 "On Battery 91%" |
| Plug in | 15:02:41 "Using AC (Charge: 91)" | 15:02:42.8 "Plugged In 91%" |

The banner follows the 1 s settle. This Mac holds at 91% on its 15 W charger: IOKit reports AC power, not charging and not charged, which is exactly `.notCharging`, so "Plugged In" (with a plug in the battery) is the right banner. A plug/unplug under a second never reached macOS as a power-source change at all, so the flap case is covered only by `BatteryReducerTests`.

### 5. ModuleHost crash protection (#70)

- **A module that crashes while starting** (DEBUG: `notched://debug/crash-at-start?on=1` makes Hello `fatalError` in `start()`): the first crash gives a strike, the second suspends it; the third launch starts every other module and Settings ▸ Modules shows Hello as off with "Turned off — Hello quit unexpectedly while starting, twice" and **Turn On**, which resumes it (strikes cleared).
- **Three quick crashes** (`kill -9` within 30 s of launch, three times): the next launch logs "Repeated crashes at launch: starting in safe mode, with no modules", starts none, and the status menu shows **Resume Modules**, which starts them and clears the streak.
- **Under a debugger** (`lldb`, the parent is `debugserver`), with eight quick crashes on record, every module started: no safe mode.
- **Found and fixed:** a session that ran under a debugger still counted as a quick crash at the *next* launch, so three Xcode Stops followed by a normal launch would enter safe mode. `LaunchRecord.sessionDebugged` now excludes such sessions from strikes and quick crashes (`LaunchGuardTests.debuggedSessionIsNoCrash`). Records saved before the field existed still decode.

## Other decisions made on the Mac

- **Banner layout fits the width budget.** A banner side can be at most 70 pt (the 90 pt budget less padding). The spec's "symbol + label leading, value trailing" doesn't fit labels like "Caps Lock", "Low Battery" or "Magic Keyboard" next to a glyph, so banners follow ISLAND-BEHAVIOR.md §1 instead: an icon *or* a short label leading, a short value trailing. Battery uses iPhone's charging layout ("Charging" | "82%" + battery); Caps Lock, Network and Bluetooth use iPhone's Silent/AirPods layout (glyph | "On", "Offline", "AirPods Pro"). `WidthCap` lets text scale to 85%, then truncate.
- **Home quick actions open panels, not menus.** Keep Awake and Timer on Home open a row of glass chips in place (presets, the custom-minutes stepper, Turn Off), since the island never takes keyboard focus and this gives the timer a "Custom" entry with no timer running.
- **The glass pill has a dark wash** (Charlie, 28 Oct). Plain `.glassEffect(.regular)` over a light window went pale grey, and the tints washed out under glass vibrancy. A 50% black fill inside the glass (`IslandTheme.glassDarkening`; `Glass.tint` isn't drawn in a borderless panel on 27.2) keeps white text and tints legible while the glass edge still shows. Glass bubbles get the same wash.
- **The Wi-Fi name is read without PermissionCenter's cached status.** That status is probed once at launch, before Location answers, and was stale (`notDetermined` while the live status was `authorizedAlways`), so names never appeared. CoreWLAN returns no name without Location access anyway.
- **A finished timer rings for a minute** (or until Stop), not just for the alert's 4 s. The branch review found that an alert which had to wait (the user on the island, or another alert showing) was dropped when the timer ended under it. iPhone's timer also keeps ringing until dismissed.
- **Links are rate-limited.** `notched://timer` starts at most one timer per 2 s and five a minute, each at least 5 s long, since any web page can open it.
- **Quiet around sleep.** Network and Bluetooth announce nothing while asleep and for 8 s after waking: reconnecting isn't news.
- **The test player runs as an app.** MediaRemote reports a script's track without a bundle identifier, and Notched (like Control Center) shows only apps, so `scripts/test-player` builds `build/TestPlayer.app`.

## Consequences

- No module asks for a new permission except Network's optional Wi-Fi name (Location).
- `PermissionCenter`'s launch-time probe can be stale for Location; anything that must act on a permission should check it live. (Its Settings rows refresh while visible, so they're right.)
