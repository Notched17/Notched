# ADR-0029: Per-app volume with Core Audio process taps (#17)

- Status: **proposed: conditional go (3 Nov 2026), waiting for Charlie's approval.** Round 2 answered the two blocking questions. A crash gives the app's sound back. A refused permission silences the app, but the refusal can be detected within a second (§Round 2). Five build gates (§Decision) must pass before #17 ships, or it becomes no-go. Round 1 was undecided (2 Nov).
- Evidence: `docs/spikes/results/spike-audiotap.txt` (round 1) and `docs/spikes/results/round2/spike-audiotap.txt` (both rounds), notes in `docs/spikes/M6-spike-1.md` §1 (MacBook Air M4 15", macOS 27.2 build 26B123, Debug build).
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

## Round 1 decision (2 Nov)

None yet. If round 2 shows audio returning after `kill -9`, a refused permission leaving apps audible (or reliably detectable), and the tap path costing under about 1 % with a clean baseline, this becomes **go**: the Audio tab from the plan, tapping an app only while its slider is below 100 %. Any of those failing makes it **no-go**, and #17 is dropped from the roadmap with this evidence.

## Round 2 (3 Nov 2026)

MacBook Air M4 15", macOS 27.2, Debug build, Spotify tapped at gain 0.3, mostly on AirPods Max. The log is `spike-audiotap.txt` from 01:24Z on 3 Nov. Step 1.4 was run on 2 Nov, and Charlie's answer is quoted below.

| Step | Result |
|---|---|
| 1.1 CPU, no taps (`cpu.sh`, 60 s) | Notched 2.350 % + perl 0.017 % = **2.367 %**; footprint 97 MB. This is Notched's Debug idle with Now Playing running, not the tap's cost. |
| 1.2 CPU, one tap (`cpu.sh`, 60 s) | Notched 3.950 % + perl 0.000 % = **3.950 %**: **+1.6 points** for the tap, in Debug. The probe's own counter: IOProc busy 3.1–3.5 % of one core (wall-clock time inside the callback, Debug, including its counters). |
| 1.3 Recording indicator | **A purple dot in the menu bar while tapped.** It couldn't be clicked to read its text. |
| 1.4 `kill -9` while tapped (2 Nov) | **Pass.** "The Spotify volume went back to the normal volume." Charlie also saw that "when I opened Notched, it moved back to the specific volume setting Notched was on". The log shows the relaunched Notched made **no tap** (the next session has only a `report`, no `tap` line), so whatever lowered Spotify was not a Notched tap. Unexplained, but not a safety problem; the gate test below repeats it. |
| 1.5 Sleep (lid closed 30 s) | **Pass.** Still playing, still quieter, no stutter or crackle. |
| 1.6 Permission refused | Prompt: *"“Notched” would like access to record your system audio. Notched turns individual apps up or down when you move an app's volume slider. The audio stays on your Mac."* `AudioHardwareCreateProcessTap` **returned no error but blocked for 56 s** while the prompt was up. After **Don't Allow**, the tap ran but **delivered digital silence: 0 of 296 callbacks with sound in 3 s, 0 of 4,916 overall**, and **Spotify went silent.** `TCCAccessPreflight` said "unknown", not "denied". |
| 1.7 Untap | Spotify returned to normal at once. |
| Rebuild on output change | AirPods → speakers → AirPods: rebuilt in 66 and 46 ms. 0 overloads in about 14,000 callbacks. |

### What the numbers mean

**The refusal is detectable.** In every run where the permission was granted and Spotify was playing, sound reached the tap in about the first 15 callbacks (about 0.16 s). The runs had 283 of 298, 284 of 299 and 216 of 231 callbacks with sound in their first few seconds. Refused, it was 0 of 296. So a tap that has delivered only exact zeros for **0.75 s while Core Audio says the app is running output** (`kAudioProcessPropertyIsRunningOutput`) can be treated as refused and removed. That gives the app its sound back within a second, about 4–5 times the observed delay. A false alarm, an app that really is outputting silence, costs nothing audible: removing a tap from a silent app changes nothing. TCC can't be asked instead, because the preflight answered "unknown" both after the refusal and while a granted tap delivered sound.

**The CPU is mostly the Debug build.** The IOProc's copy loop, compiled on its own (scratch benchmark, a 512-frame stereo callback at 48 kHz), takes **133 µs unoptimised (1.25 % of a core) and 1.6 µs optimised (0.015 %)**. That accounts for about 1.25 of the 1.6-point Debug difference. The rest, about 0.35 points, is the HAL's own IO thread for the aggregate device, which optimisation doesn't change. The estimate for a Release build is about 0.4 % per tapped app, under the 0.5 % budget but close to it, so it is a gate, not a pass.

**Creating a tap can block for as long as the prompt is up** (56 s). The product must never create taps on the main thread.

## Decision

**Conditional go** (proposed). Against the round 1 criteria:

- **Audio returns after a crash:** pass.
- **No glitches:** pass.
- **Latency:** pass.
- **Recovers from an output change:** pass.
- **One understandable prompt:** pass. The wording is ours and clear, and it appears on the first slider move.
- **Refused permission:** fails as tested, because the app went silent, but it is detectable. The probation rule below turns "silent forever" into "silent for under a second, then explained".
- **CPU:** not yet measurable. The Release estimate is within budget.

### What gets built (Sonnet high)

- **The Audio tab** from the plan: a slider and mute per app playing, the output switcher, and room for the AirPods row. The module is **off by default**, because it needs the audio-capture permission, asked on the first slider move.
- **A pure `MixerReducer`**, unit-tested. It handles apps appearing and leaving, slider changes, output changes, and tap results. Taps are built only while an app's slider is below 100 % and the app is running output, and removed at 100 %, so the purple dot shows only while a volume is actually changed.
- **The probation rule.** A new tap is on probation until it delivers a non-zero sample. If it delivers only zeros for 0.75 s while the app is running output, the reducer removes it and marks the app "can't hear this app". It shows *"Notched couldn't hear Spotify. If audio access was turned off, allow it in System Settings."* with Open System Settings and Try Again. It **never retries by itself**, so a refusal costs at most one sub-second silence per deliberate try. Once any tap has delivered sound in this launch, the permission is proven and later taps skip probation, so silent passages between tracks can't trigger it.
- **`Services/Audio/ProcessTapEngine`** owns the taps and aggregates on a background queue. Tap creation is never on the main thread. The IOProc has no allocation, locks or logging, and the gain is passed atomically (the probe's pattern).
- **Disclosure:** the Audio tab and the module's settings say plainly that macOS shows a purple recording dot while an app's volume is changed, and that no audio leaves the Mac or is stored.

### Gates: each must pass before #17 ships, or it becomes no-go

1. **Release CPU:** `scripts/cpu.sh` on a Release build with one app tapped and playing shows ≤ 0.5 % more than untapped.
2. **The refusal test again, on the real engine:** deny the prompt. The app must come back at full volume within about 1 s, and the tab must show the explanation.
3. **`kill -9` while tapped, then relaunch:** the app's sound returns at once. On relaunch nothing is tapped until a slider is below 100 % again, and slider values are not reapplied silently at launch.
4. **No main-thread stall** while the prompt is up: the island keeps animating.
5. **Idle cost:** with the module on and every slider at 100 %, there are no taps, no aggregate devices and no IOProcs, and the tap path costs 0 % CPU.

### Risks accepted

- The purple dot is macOS's own indicator and can't be hidden. Some users will find it alarming, hence the disclosure and tapping only below 100 %.
- A permission revoked in System Settings while Notched runs would silence a tapped app until its slider goes back to 100 % or Notched restarts. This is rare, and the fix is one click. The tab's mute and slider still work.
- The step 1.4 relaunch oddity is unexplained. Gate 3 repeats that situation.
