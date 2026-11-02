# M6 spike round 2: what round 1 couldn't decide

About 45 minutes; the sections are independent. Round 1's results stay in `docs/spikes/results/`; this round goes into `docs/spikes/results/round2/`.

## 0. Set up

| # | Do | Notes |
|---|---|---|
| 0.1 | `git pull && scripts/go.sh` (tests, install, relaunch). Paste any error lines and stop. | |
| 0.2 | Fresh results files: `rm -f ~/Library/Logs/Notched/spike-*.txt` | |

## 1. Per-app volume: the three open questions (ADR-0029, about 20 min)

Spotify and a YouTube video in Safari, **both audible (video not muted)**. AirPods are fine. If an app ever stays silent: `killall Notched`, and if still silent, `sudo killall coreaudiod`.

| # | Do | Notes |
|---|---|---|
| 1.1 | **Baseline, nothing tapped.** `open -g "notched://debug/probe?name=audiotap&action=report"`, then `scripts/cpu.sh 60 "no taps"`, then the *report* command again. Paste the cpu.sh total. | CPU no taps: |
| 1.2 | **One tap.** `open -g "notched://debug/probe?name=audiotap&action=tap&app=com.spotify.client&gain=0.3"`, then `scripts/cpu.sh 60 "1 tap"`, then *report*. Paste the cpu.sh total. (The report adds "IOProc busy" and "Notched process CPU" lines.) | CPU 1 tap: |
| 1.3 | While it's tapped: is there a **recording indicator** in the menu bar (an orange or purple dot, or a symbol in Control Centre)? If so, click it: what does it say? | |
| 1.4 | **The crash test.** With Spotify still tapped at 0.3: `killall -9 Notched`. Within 2 s, is Spotify back at **full volume** by itself? Then relaunch: `open ~/Applications/Notched.app` | **Most important answer:** |
| 1.5 | **Sleep.** Tap Spotify at 0.3 again (1.2's command), close the lid for 30 s, open and unlock. Is Spotify still playing, still quieter, no crackle? Then *report*. | |
| 1.6 | **Permission refused.** Run `tccutil reset AudioCapture me.rkck.Notched` (if it says "No such service", turn Notched off in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording instead). Relaunch Notched, then tap Spotify (1.2's command). **Write down the prompt's exact words and buttons.** Press **Don't Allow** (or the deny option). Is Spotify then **quieter, normal, or silent**? Wait 5 s, then *report*. | Prompt: · Spotify: |
| 1.7 | `open -g "notched://debug/probe?name=audiotap&action=untap"`. Does Spotify return to normal? Then allow Notched again in System Settings (the same pane), and relaunch Notched. | |

## 2. AirPods Max battery (6.2, about 10 min)

AirPods Max report one battery (no left/right/case), so this is shorter than round 1's sheet. Write what **Control Centre ▸ Bluetooth** (or the Battery widget) shows each time.

| # | Do | Notes: what macOS shows |
|---|---|---|
| 2.1 | AirPods Max on your head, connected. `open -g "notched://debug/probe?name=battery-accessory&action=run"`. **Write down any permission prompt** (press Allow). Wait 15 s. | Battery __ % · Prompt: |
| 2.2 | Take them off and leave them on the desk (not in the case) for a minute; run the same command. | Battery __ % |
| 2.3 | Plug in the charging cable; run it again. | Battery __ % charging? |
| 2.4 | Turn Bluetooth off and on (or disconnect and reconnect them). **Straight after** they reconnect, run it again. | |

## 3. Lock-screen test label (6.3 Stage 2, about 25 min)

Do **`docs/spikes/M6-spike-1.md` §5** as written: steps 5.1 to 5.13, then 5.16 and 5.17 (skip 5.14 and 5.15: no external display or second account). Read its emergency box first. The label removes itself within 60 s, and typing always goes to the password field.

## 4. Leftovers from round 1 (5 min)

| # | Do | Notes |
|---|---|---|
| 4.1 | **#62 cost:** open the island's AI tab. Does it show a dollar estimate? What does the small line under the numbers say ("estimated at API prices", "price table not found", or "some models unpriced")? | |
| 4.2 | **API progress with music paused:** pause Spotify, turn on the Activity API with a new test client, run round 1's §3.3 PUT command. Beside the notch: is there a hammer on the left and the ring on the right? (With music playing it's a small bubble with only the ring, which is correct.) DELETE it, revoke the client. | |
| 4.3 | **#63 Allow / Deny:** in Claude Code, ask for something that needs your permission (for example "run `ls ~` in the shell" with permissions on ask). Does the island open with **Allow / Deny**? Press Allow: does Claude carry on? | |

## 5. Send back

```bash
mkdir -p docs/spikes/results/round2 && cp ~/Library/Logs/Notched/spike-*.txt docs/spikes/results/round2/
git add docs/spikes && git commit -m "spike(m6): round 2 results" && git push
```

No token or password goes in these files (round 1 was clean).
