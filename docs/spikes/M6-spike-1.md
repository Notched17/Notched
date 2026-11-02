# M6 spike build 1: per-app volume (6.1), AirPods battery (6.2), Activity API check

About 40 minutes at the Mac. Every step is numbered; write what you hear or see in the **Notes** column (a word is enough), then send back the two results files and this sheet (see the end).

The probes only run in the Debug build and only when you start them with the commands below. Turning the island's modules on or off doesn't matter for this sheet.

## 0. Set up (5 min)

| # | Do | Notes |
|---|---|---|
| 0.1 | `cd` to the project, then `git fetch && git checkout claude/layout-editor-review-vs0usk && scripts/go.sh`. It builds, tests, installs and relaunches. If it stops with compile errors, paste me the error lines and stop here. | |
| 0.2 | Optional, to watch live: in a second Terminal window, `log stream --level debug --predicate 'subsystem == "me.rkck.Notched.probe"'` | |
| 0.3 | Start fresh results files: `rm -f ~/Library/Logs/Notched/spike-*.txt` | |

## 1. Per-app volume (6.1, about 20 min)

**If an app ever stays silent or stuck:** run `killall Notched` (every tap ends with the app). If it's *still* silent, run `sudo killall coreaudiod` (audio restarts in a second). Write down which step it happened at; that's a crucial result.

Have **Music** playing a song and **Safari** playing a YouTube video with someone talking, both audible, on the **built-in speakers**.

| # | Do | Listen for / Notes |
|---|---|---|
| 1.1 | `open -g "notched://debug/probe?name=audiotap&action=list"` | (nothing to hear; it lists what's playing) |
| 1.2 | `open -g "notched://debug/probe?name=audiotap&action=tap&app=com.apple.Music&gain=0.3"` **Write down the exact wording of any permission prompt**, which button you pressed (press **Allow**), and whether it sent you to System Settings. | Prompt text: |
| 1.3 | Does Music get quieter (about a third)? Is the YouTube audio **completely unaffected**, with no click, gap or crackle? | |
| 1.4 | `scripts/cpu.sh 60 "1 app tapped"` (leave both playing for the minute). Paste the total line. | CPU: |
| 1.5 | `open -g "notched://debug/probe?name=audiotap&action=gain&app=com.apple.Music&gain=1"`, then the same with `gain=0`, then `gain=0.5`. Smooth, with no clicks? | |
| 1.6 | `open -g "notched://debug/probe?name=audiotap&action=tap&app=com.apple.Safari&gain=0.5"`: now both apps are tapped. Watch the YouTube video: do lips still match the voice? | Lip-sync: fine / slightly late / clearly late |
| 1.7 | `scripts/cpu.sh 60 "2 apps tapped"`. Paste the total line. | CPU: |
| 1.8 | `open -g "notched://debug/probe?name=audiotap&action=report"` | |
| 1.9 | Connect your **AirPods** while both are tapped. Does sound move to the AirPods within about a second, with nothing left playing from the speakers? Is lip-sync still OK on AirPods? | |
| 1.10 | `open -g "notched://debug/probe?name=audiotap&action=report"`, then switch back to the speakers (Control Centre ▸ Sound). OK? | |
| 1.11 | **Quit Music** while it's tapped. Then open it again and play. Does it play at **normal** volume (it should, since the tap ended)? | |
| 1.12 | Sleep the Mac (close the lid) for 30 s with Safari tapped at 0.5, then open it and play the video. Sound OK? | |
| 1.13 | **The crash test.** Tap Music again at 0.3 (step 1.2's command). Then run `killall -9 Notched`. Within 2 s, is Music back at **full** volume by itself? (Then relaunch Notched from ~/Applications.) | **Most important answer:** |
| 1.14 | Relaunch, then `open -g "notched://debug/probe?name=audiotap&action=untap"`. | |
| 1.15 | Optional: in **System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording** (or wherever step 1.2 sent you), turn Notched's audio access **off**, relaunch Notched, and repeat step 1.2. What happens to Music: quieter, normal, or **silent**? Then turn the access back on. | |

## 2. AirPods battery (6.2, about 10 min)

Which AirPods model do you have? ______

| # | Do | Notes: what macOS shows (Bluetooth menu or Control Centre) |
|---|---|---|
| 2.1 | AirPods **in your ears**, connected. Note left/right/case % from the Bluetooth menu. Then `open -g "notched://debug/probe?name=battery-accessory&action=run"`. **Write down any permission prompt** (press **Allow**). Wait 15 s. | L __ R __ Case __ · Prompt: |
| 2.2 | Put **one bud** in the case, lid open. Same command. Wait 15 s. | L __ R __ Case __ |
| 2.3 | Both buds in the case, **lid open**, case charging if you can. Same command. | L __ R __ Case __ |
| 2.4 | Disconnect, then reconnect (take them out). **Straight after** the connect sound, run the command again. | |

## 3. Activity API check (#63 and the API, 5 min)

| # | Do | Notes |
|---|---|---|
| 3.1 | Settings ▸ Modules ▸ **Activity API**: turn it on, press **New Client…**, name it "test", tick every scope, copy the token. Note the port. | |
| 3.2 | In Terminal: `export NOTCHED_PORT=<port>` and `export NOTCHED_TOKEN=<token>`, then: `curl -X POST "http://127.0.0.1:$NOTCHED_PORT/v1/banners" -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" -d '{"title":"Hello","subtitle":"from curl","symbol":"checkmark.circle.fill","tint":"green"}'`. Did a banner show, and did curl print `{"queued":true}`? | |
| 3.3 | `curl -X PUT "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build" -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" -d '{"template":"progress","title":"Build","subtitle":"Compiling","progress":0.4,"symbol":"hammer.fill","tint":"orange"}'`. Does a progress activity appear beside the notch? Then remove it: `curl -X DELETE "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build" -H "Authorization: Bearer $NOTCHED_TOKEN"` | |
| 3.4 | If you use the Claude Code hooks: does the island show "Claude is working…", and does an approval show **Allow / Deny**? | |
| 3.5 | You can revoke the "test" client in the pane afterwards. | |

## 4. Send back

1. Copy the results files into the repo, commit and push:
   `mkdir -p docs/spikes/results && cp ~/Library/Logs/Notched/spike-*.txt docs/spikes/results/`
   (They contain process and device names and battery levels, but no Bluetooth addresses and no audio.)
2. Fill in the Notes columns of this file, then `git add docs/spikes && git commit -m "spike 1 results" && git push`.
3. Or paste both files and your notes into the chat instead.
