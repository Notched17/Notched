# ADR-0029: Per-app volume with Core Audio process taps (#17): spike round 1

- Status: **undecided after round 1 (2 Nov 2026).** The technique works, but two of the six go criteria were not tested and the CPU reading fails the budget. Round 2 (`docs/spikes/M6-spike-2.md` §1) decides it.
- Evidence: `docs/spikes/results/spike-audiotap.txt`, notes in `docs/spikes/M6-spike-1.md` §1 (MacBook Air M4 15", macOS 27.2 build 26B123, Debug build).
- Plan and criteria: `docs/superpowers/specs/2026-11-02-m6-hard-parts-and-release-design.md` §2.

## What was tried

`AudioTapProbe`: a `CATapDescription` stereo mix-down of one app's audio processes with `muteBehavior = .mutedWhenTapped`, inside a private aggregate device whose main sub-device is the default output, and an IOProc copying the tap to the output at a gain. Run with Spotify and a YouTube video in Safari (Safari's audio comes from `com.apple.WebKit.GPU`, mapped to Safari through `ResponsibleProcess`), mostly on AirPods Max.

## Results against the go criteria

| Criterion (written before the run) | Result |
|---|---|
| Audio comes back by itself if Notched is killed while tapping | **Not tested** (step 1.13 skipped). Blocking: no go without it. |
| No audible glitch in untapped apps | **Pass.** YouTube unaffected while Spotify was turned down; gain 1 → 0 → 0.5 smooth, no clicks; **0 processor overloads in about 40,000 IO callbacks**. |
| Added latency ≤ ~30 ms on built-in speakers; lip-sync fine on AirPods | **Pass.** Built-in speakers: estimated extra delay **22.5 ms** (input latency 21 + safety 36 frames + two 512-frame buffers at 48 kHz). AirPods Max: lip-sync "fine, nothing changed". The 181 ms estimate on Bluetooth is an over-count: the aggregate reports the AirPods' own 7,680-frame latency on its input side as well, and that latency is paid by every app anyway. |
| CPU ≤ 0.5 % per tapped app while playing; 0 % with no taps | **Fails as measured: 10.2 % with one app tapped, 8.05 % with two** (footprint 45 MB). Not explained: two taps cost *less* than one, so it doesn't scale with taps, and **no baseline without taps was measured**. Round 2 measures the baseline, the time spent inside the IOProc, and Notched's own CPU between reports. If the tap path really costs more than about 1 %, #17 is a no-go. |
| Recovers from an output change or the app quitting within ~1 s | **Pass** for what was seen. The output changed AirPods → speakers → AirPods (the AirPods came off): every tap was rebuilt on the new device in **47–315 ms**. Spotify quit: the tap was torn down, and Spotify reopened at normal volume. Audio quality during the switch wasn't listened to. |
| One understandable permission prompt, asked only when a slider is first moved | **Partly.** A prompt appeared on the first tap (first build took 1,975 ms, the prompt's wait); later builds took 40–70 ms. Exact wording not captured. **What happens when the permission is refused is untested**, and that is blocking (see failure modes). |

Not tested in round 1: sleep/wake with a tap (1.12), connecting AirPods deliberately (1.9), the built-in speakers as the main output (only briefly), and two apps on speakers.

## Things learned

- **`TCCAccessPreflight("kTCCServiceAudioCapture")` answers "unknown" even after access was granted** (it said "unknown" while taps delivered sound). There is no way to ask about this permission before using it. The product would have to infer a refusal from the tap delivering only silence, and that is ambiguous: a muted or paused app also delivers silence (Safari's video was muted in this run and looked exactly like a refusal).
- Rebuild on device change is fast and glitch-free in the counters. A real engine needs no polling: the default-output and process-list listeners were enough.
- Helper processes work: Safari's WebKit GPU process was found and tapped.

## Failure modes still open

1. **Crash while tapping:** does `mutedWhenTapped` end with our process (the tap is owned by our connection) so the app's sound returns at once? Expected, not proven.
2. **Permission refused:** if `mutedWhenTapped` silences the app while the tap delivers zeros, a refused permission would *silence* the app. That would be unacceptable unless the engine detects it reliably and removes the tap, and per the point above, detection is ambiguous.
3. **CPU** (above).
4. **System indicator:** macOS may show its "recording system audio" indicator while any tap runs. Round 2 checks the menu bar; if it does, the Audio tab must say so plainly.

## Decision

None yet. If round 2 shows audio returning after `kill -9`, a refused permission leaving apps audible (or reliably detectable), and the tap path costing under about 1 % with a clean baseline, this becomes **go**: the Audio tab from the plan, tapping an app only while its slider is below 100 %. Any of those failing makes it **no-go**, and #17 is dropped from the roadmap with this evidence.
