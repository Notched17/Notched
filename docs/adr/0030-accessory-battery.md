# ADR-0030: AirPods and accessory battery (#28): spike result

- Status: **accepted: provisional go with route C, `system_profiler` (3 Nov 2026), approved by Charlie and built (the connect banner shows "NN%").** One check is still open: see "What would change this".
- Evidence: `docs/spikes/results/round2/spike-battery-accessory.txt` (personal device names removed), 12 runs on 3 Nov 2026, MacBook Air M4 15", macOS 27.2, Debug build. AirPods Pro 2 (product id 0x2024) ran the round 1 sheet: in the case, in the ears, one bud in the case, case charging, put away. AirPods Max 2 (0x202D) ran round 2 §2: on the head, on the desk, charging, reconnect.
- Plan and criteria: `docs/superpowers/specs/2026-11-02-m6-hard-parts-and-release-design.md` §3.

## What was tried

`AccessoryBatteryProbe` ran three routes, all original code (AirBattery was never read for code):

- **A, private IOBluetooth:** the `IOBluetoothDevice` battery properties (`batteryPercentLeft`, `Right`, `Case`, `Single`), read through KVC.
- **B, Bluetooth LE adverts:** Apple's proximity-pairing adverts (type 0x07) from a CoreBluetooth scan, decoded from the published layout.
- **C, `system_profiler`:** `system_profiler SPBluetoothDataType -json -detailLevel basic`, Apple's own report, run as a child process.

## Results

| | A. IOBluetooth | B. LE adverts | C. system_profiler |
|---|---|---|---|
| AirPods Pro 2 | L 100 / R 100 / case 52 % | L 100 / R 100 / case 50 % (10 % steps) | L 100 / R 100 / case 52 % |
| AirPods Max 2 | single 100 % | 100 % (model `2D20`, not in the table) | main 100 % |
| Time | 2–4 ms (3.9 s on the first call, the permission prompt) | **0.07–5.7 s** before Charlie's device was heard | 93–117 ms |
| Permission | **Bluetooth: prompts** (step 2.1 was this prompt) | Bluetooth | **None.** Verified on 3 Nov: Notched's Bluetooth grant reset, Notched relaunched, levels still returned and the permission stayed "not asked yet" |
| Charging | no | **yes**, per bud and case | no |
| Unknown values | written as **0 %** (the case read 0 while the buds were out of it) | 15 = unknown | field missing |
| When disconnected | keeps the last values, `connected=false` | silent | listed under `device_not_connected` with the last values |
| Other people's devices | no | **yes: 98 identifiers from strangers' AirPods in the library** (they rotate, so fewer actual devices). Ours could only be told apart by model and signal strength | no |

All three routes agree. A and C gave identical numbers in every run. B is a separate pipeline (the AirPods' own broadcast, not bluetoothd), and it agreed within its 10 % resolution. The case reading also moved: 52 % during the runs, then **70 %** half an hour later on C, after the case had been on the charger since step "case charging".

## Against the go criteria

| Criterion (written before the run) | Result |
|---|---|
| Left/right/case values match the Bluetooth menu within 5 % | **Not compared directly.** Charlie didn't record what Control Centre showed, because the probe has no on-screen display and was expected to have one. Indirectly it passes: C is Apple's own report from the same daemon as the menu, and three routes agree. |
| Within 3 s of connecting | **Pass for A and C** (0.1 s, and values were there straight after the reconnect in step 2.4). B missed it in 2 of 12 runs (3.1 s, 5.7 s). |
| On every test | **Pass for A and C**: every run with the AirPods connected returned values. |
| Prefer a route with no new permission | **C needs none**, which is now verified. A prompts for Bluetooth. |

The weakness is that almost every level was 100 %, so the readings never had to change while being watched. Only the case reading moved (52 → 70 %, which is also what a charging case should do).

## Decision

**Provisional go with route C only.** A and B are not used.

- **Why C:** no permission and no prompt. This keeps the M3a Bluetooth banner prompt-free (ADR-0013), which is the main complaint about rival apps. It is also a public, Apple-signed tool rather than a private API, so a macOS update is less likely to break it silently, and it costs about 0.1 s of one process per connect.
- **Why not A:** it needs the Bluetooth permission for numbers C already gives. It is a private API, and it writes "unknown" as 0 %. It stays as a known fallback if a future macOS removes the battery fields from `system_profiler`.
- **Why not B:** it needs the permission. It hears strangers' AirPods, so a bug could show someone else's battery. It is sometimes slower than 3 s and only reads in 10 % steps. Its one advantage, charging flags, isn't worth that.

## How it will be built

- **Event-driven, never polled.** The existing AirPods connect event (CoreAudio, ADR-0013) triggers one read off the main thread at +1 s. **Built (3 Nov 2026) without the retry:** every recorded run had the values straight away, even right after a reconnect, so a missing level just gives the plain banner. A retry is the first thing to add if real use shows gaps. The read times out after 3 s. No timer, so a disabled feature costs nothing.
- **A pure parser**, unit-tested on recorded JSON:
  - It reads only `device_connected` entries from Apple (vendor 0x004C), matched to the connected output by product id and name.
  - It takes only `device_batteryLevelLeft/Right/Case/Main` ("NN%" strings). A missing field means unknown.
  - It never reads, stores or logs `device_serialNumber*` or the address.
- **What shows (built: banner only):** the connect banner gets the iPhone-style layout, the device's glyph on the left and the level with a battery on the right (the name is dropped to fit the width; it stays in the VoiceOver label). The L/R/case row below is not built, because the Audio tab (#17) is undecided. The original plan was: name on the left and level on the right ("AirPods Max" | "100%"). For buds, it shows the lower of left and right, and the expanded audio tab or Bluetooth row shows L, R and case. No charging bolt, because C has no charging state.
- **Fails quietly:** if `system_profiler` is missing, fails, times out after 3 s, or its JSON changes, the battery value is simply left out and the failure is logged once.
- **The setting:** "Show AirPods battery" in the Bluetooth module, **on by default**, because it needs no permission and does nothing until AirPods connect (the module rule for defaults).

## What would change this

- **Open check:** the next time Charlie's AirPods are below 100 %, compare the banner with Control Centre. A difference over 5 % means stopping and revisiting: try A against the same reading.
- **Case readings may be stale.** C kept the case at 52 % while both buds were in the ears, so it is a last-known value. If Control Centre hides the case in that state, the banner should hide it too.
- If a future macOS drops the battery fields, the battery simply disappears (the feature hides itself). Route A becomes the fallback, behind an explicit Bluetooth-permission switch.
