# M6 spike build 1: per-app volume (6.1), AirPods battery (6.2), Activity API check, lock-screen signals and test label (6.3)

About 70 minutes at the Mac; sections can be done on different days, in order. Every step is numbered; write what you hear or see in the **Notes** column (a word is enough), then send back the two results files and this sheet (see the end).

The probes only run in the Debug build and only when you start them with the commands below. Turning the island's modules on or off doesn't matter for this sheet.

## 0. Set up (5 min)

| # | Do | Notes |
|---|---|---|
| 0.1 | `cd` to the project, then `git fetch && git checkout claude/layout-editor-review-vs0usk && scripts/go.sh`. It builds, tests, installs and relaunches. If it stops with compile errors, paste me the error lines and stop here. | Done 2026-11-02: go.sh exit 0, 1151 tests in 119 suites passed, installed and launched Debug build (the CoreSimulator warnings in the log are harmless). |
| 0.2 | Optional, to watch live: in a second Terminal window, `log stream --level debug --predicate 'subsystem == "me.rkck.Notched.probe"'` | |
| 0.3 | Start fresh results files: `rm -f ~/Library/Logs/Notched/spike-*.txt` | Done; no old files existed (folder was created by the first probe). |

## 1. Per-app volume (6.1, about 20 min)

**If an app ever stays silent or stuck:** run `killall Notched` (every tap ends with the app). If it's *still* silent, run `sudo killall coreaudiod` (audio restarts in a second). Write down which step it happened at; that's a crucial result.

Have **Music** playing a song and **Safari** playing a YouTube video with someone talking, both audible, on the **built-in speakers**.

> **Deviations in this run (2026-11-02):** Spotify (com.spotify.client) was used instead of Music, and all audio was on AirPods Max, not the built-in speakers. Steps 1.9, 1.10, 1.12, 1.13, 1.14 and 1.15 were not done; sections 2 and 5 were not started.

| # | Do | Listen for / Notes |
|---|---|---|
| 1.1 | `open -g "notched://debug/probe?name=audiotap&action=list"` | (nothing to hear; it lists what's playing) Ran. Playing: com.spotify.client (pid 1414) and Safari via com.apple.WebKit.GPU. **Music was not playing: this run used Spotify instead of Music** (bundle com.spotify.client). Output device was AirPods Max, not built-in speakers. |
| 1.2 | `open -g "notched://debug/probe?name=audiotap&action=tap&app=com.apple.Music&gain=0.3"` **Write down the exact wording of any permission prompt**, which button you pressed (press **Allow**), and whether it sent you to System Settings. | Prompt text: Ran with app=com.spotify.client gain=0.3; tap running in 1974.6 ms on AirPods Max, est. extra delay 181.3 ms. Prompt (user's words, approximate): a System Settings prompt asking to allow Notched to control/record system audio. Exact wording and button not captured. |
| 1.3 | Does Music get quieter (about a third)? Is the YouTube audio **completely unaffected**, with no click, gap or crackle? | User: Spotify became quieter; YouTube unaffected. After 3 s: 298 IO callbacks, 283 with sound, 0 overloads. |
| 1.4 | `scripts/cpu.sh 60 "1 app tapped"` (leave both playing for the minute). Paste the total line. | CPU: CPU: Total 10.200 % (Notched 10.183 %, perl 0.017 %), footprint 45 MB, resident 121.6 MB. Over the 0.5 % budget; no no-tap baseline measured. |
| 1.5 | `open -g "notched://debug/probe?name=audiotap&action=gain&app=com.apple.Music&gain=1"`, then the same with `gain=0`, then `gain=0.5`. Smooth, with no clicks? | Ran gain 1, 0, 0.5 on Spotify about 6 s apart. User: all smooth, no clicks. |
| 1.6 | `open -g "notched://debug/probe?name=audiotap&action=tap&app=com.apple.Safari&gain=0.5"`: now both apps are tapped. Watch the YouTube video: do lips still match the voice? | Lip-sync: fine / slightly late / clearly late Ran (Safari 0.5, tap built in 42.8 ms, 0 overloads). Lip-sync: fine (user: nothing seemed to change). Output was AirPods Max. |
| 1.7 | `scripts/cpu.sh 60 "2 apps tapped"`. Paste the total line. | CPU: CPU: Total 8.050 % (Notched 8.000 %, perl 0.050 %), footprint 46 MB, resident 119.6 MB. Not higher than with 1 app. |
| 1.8 | `open -g "notched://debug/probe?name=audiotap&action=report"` | Ran. Spotify healthy (2363 of 2397 callbacks with sound, 0 overloads). Safari 0 with sound because the user had muted the video (the SILENT flag is expected). During the run the user took the AirPods off: taps rebuilt to MacBook Air Speakers in 52-67 ms, then back to AirPods Max (47 ms Spotify, 315 ms Safari). Audio quality during that switch not observed. |
| 1.9 | Connect your **AirPods** while both are tapped. Does sound move to the AirPods within about a second, with nothing left playing from the speakers? Is lip-sync still OK on AirPods? | NOT DONE (user in a library). Only the accidental AirPods off/on described in 1.8 was observed. |
| 1.10 | `open -g "notched://debug/probe?name=audiotap&action=report"`, then switch back to the speakers (Control Centre ▸ Sound). OK? | NOT DONE as written. A report was run at 05:35:26Z while on AirPods Max: Spotify 17259 of 17293 callbacks with sound, 0 overloads. |
| 1.11 | **Quit Music** while it's tapped. Then open it again and play. Does it play at **normal** volume (it should, since the tap ended)? | Used Spotify instead of Music. User quit and reopened it: plays at normal volume. Log: audio processes gone, torn down (app gone), 0 overloads. Report afterwards lists 1 tapped app (Safari). |
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
| 3.1 | Settings ▸ Modules ▸ **Activity API**: turn it on, press **New Client…**, name it "test", tick every scope, copy the token. Note the port. | User turned on Activity API and created client test (port 59191). Token not recorded here: ****. |
| 3.2 | In Terminal: `export NOTCHED_PORT=<port>` and `export NOTCHED_TOKEN=<token>`, then: `curl -X POST "http://127.0.0.1:$NOTCHED_PORT/v1/banners" -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" -d '{"title":"Hello","subtitle":"from curl","symbol":"checkmark.circle.fill","tint":"green"}'`. Did a banner show, and did curl print `{"queued":true}`? | Ran. Response {"queued":true}, HTTP 202. User saw the banner on the second send: smooth, green checkmark, Hello / from curl, stayed about 2-3 s. |
| 3.3 | `curl -X PUT "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build" -H "Authorization: Bearer $NOTCHED_TOKEN" -H "Content-Type: application/json" -d '{"template":"progress","title":"Build","subtitle":"Compiling","progress":0.4,"symbol":"hammer.fill","tint":"orange"}'`. Does a progress activity appear beside the notch? Then remove it: `curl -X DELETE "http://127.0.0.1:$NOTCHED_PORT/v1/activities/build" -H "Authorization: Bearer $NOTCHED_TOKEN"` | PUT returned {"id":"build","state":"active"}, HTTP 201. User saw only an orange ring at about 40 percent (no hammer, title or subtitle); layout looked right. DELETE returned HTTP 204 and the ring disappeared. |
| 3.4 | If you use the Claude Code hooks: does the island show "Claude is working…", and does an approval show **Allow / Deny**? | Partly tested (hooks are installed in ~/.claude/settings.json). Claude is working... shows with the Claude symbol. A free-text prompt showed a clipped label (Wai...) with no way to answer on the island. Allow / Deny card NOT tested. No stale working state after closing the terminal tab. |
| 3.5 | You can revoke the "test" client in the pane afterwards. | User revoked the test client. Verified: the old token now gets HTTP 401 invalid_token (****). |

## 4. Lock-screen signals (6.3 research, about 5 min)

This probe **puts nothing on the lock screen**. It only writes down which signals macOS sends when you lock, unlock, sleep and switch users, so the lock-screen design (ADR-0031) can rely on the right ones. Lock with **⌃⌘Q** (Control-Command-Q).

| # | Do | Notes |
|---|---|---|
| 4.1 | `open -g "notched://debug/probe?name=lockevents&action=start"` | Ran; log shows locked=key absent onConsole=1 loginDone=1, one screen 1920x1243. |
| 4.2 | Lock (⌃⌘Q), wait 10 s, unlock with your password. | Done. Lock: screenIsLocked then locked=1; unlock: screenIsUnlocked, locked key absent. Nothing odd. |
| 4.3 | Lock, type a **wrong** password once, then the right one. | Done; looks the same in the log as a normal lock cycle (no separate wrong-password event). Nothing odd. |
| 4.4 | Lock, unlock with **Touch ID**. | Done; looks the same in the log as a normal lock cycle (no Touch ID event). Nothing odd. |
| 4.5 | Lock, leave it until the screen goes dark (about a minute), then press a key and unlock. | Done. screensDidSleep and screensDidWake arrive with locked=1, then screenIsUnlocked. Nothing odd. |
| 4.6 | Close the lid for 30 s, open it, unlock. | Done. Order: willSleep, screensDidSleep, screenIsLocked (about 0.2 s later), then on wake screensDidWake, didWake with locked=1, then screenIsUnlocked. Nothing odd. |
| 4.7 | Only if this Mac has a **second user account**: Control Centre ▸ your name ▸ *Login Window…*, then log back in. | Second account? yes / no Second account? no (skipped). |
| 4.8 | If you use an external display, plug it in and do step 4.2 once more. | External display? yes / no Not done (no external display mentioned). |
| 4.9 | `open -g "notched://debug/probe?name=lockevents&action=stop"` | Ran; log ends with stopped. |
| 4.10 | Optional but useful: a phone photo of the lock screen as it normally looks (clock, your picture, password field). Save it as `docs/spikes/results/lockscreen.jpg`. | |

## 5. Lock-screen test label (6.3 Stage 2, about 25 min)

This is the first time anything goes on the lock screen: a **plain grey label** under the clock, which **removes itself 60 s after it appears**, whatever happens. Do section 4 first.

> **If you ever can't unlock, or the label won't go away:**
> 1. Wait. The label removes itself within 60 s.
> 2. Type your password or use Touch ID anyway. The label never takes the keyboard, so typing always goes to the password field.
> 3. From another device: `ssh` into the Mac and run `killall -9 Notched`.
> 4. Last resort: hold the power button to restart. The test label is never armed at launch, so nothing comes back after a restart.
>
> Write down what happened and at which step.

| # | Do | Notes |
|---|---|---|
| 5.1 | `open -g "notched://debug/probe?name=lockscreen&action=status"`. Then `open -g "notched://debug/probe?name=lockscreen&action=arm"` | |
| 5.2 | Lock (⌃⌘Q). Within about a second, a grey label should appear under the clock. **Does it cover anything?** Is the password field / your picture fully visible? | |
| 5.3 | Type your password straight away. Does it unlock normally, and is the label gone the instant the desktop appears? | |
| 5.4 | Lock and unlock **20 times**, some quickly, some slowly. Did the label ever stay after unlocking, or ever show on the desktop? Did the password field ever misbehave? | |
| 5.5 | Lock and wait **70 s**. The label should disappear by itself at about 60 s. Then unlock. | |
| 5.6 | Lock, type a **wrong** password once, then the right one. | |
| 5.7 | Lock, unlock with **Touch ID**. | |
| 5.8 | Lock, wait until the screen goes dark, press a key, unlock. | |
| 5.9 | Close the lid for 30 s, open, unlock. | |
| 5.10 | Lock, **click on the label**, then type your password. Does the typing still go into the password field? | |
| 5.11 | Lock, turn on **VoiceOver** (⌘F5). Does VoiceOver read the label? (It shouldn't.) Can you still get to the password field and unlock? Turn VoiceOver off (⌘F5). | |
| 5.12 | **Crash test.** Run `(sleep 40; killall -9 Notched) &` in Terminal, then lock at once. The label appears, then vanishes when Notched is killed. **Unlock: does it work normally?** Then relaunch Notched (`open ~/Applications/Notched.app`) and run the *arm* command from 5.1. The results file should say **TURNED OFF: crashedWhileShowing**. Run *arm* once more, which should work again. | **Most important answer:** |
| 5.13 | **Kill switch.** `defaults write me.rkck.Notched lockScreen.killSwitch -bool true`, then the *arm* command: it should be refused. Then `defaults delete me.rkck.Notched lockScreen.killSwitch`. | |
| 5.14 | Only with an **external display**: `open -g "notched://debug/probe?name=lockscreen&action=arm&secondary=1"`, then lock. A label on both displays? Unlock. | |
| 5.15 | Only with a **second account**: *arm* (plain) and lock: **nothing** should show. Then `open -g "notched://debug/probe?name=lockscreen&action=arm&others=1"` and lock: the label shows. Then switch to the other account (Control Centre ▸ *Login Window…*): nothing on their screen, ever. | |
| 5.16 | A phone photo of the lock screen **with the label**, saved as `docs/spikes/results/lockscreen-label.jpg`. | |
| 5.17 | `open -g "notched://debug/probe?name=lockscreen&action=disarm"` | |

## 6. Send back

1. Copy the results files into the repo, commit and push:
   `mkdir -p docs/spikes/results && cp ~/Library/Logs/Notched/spike-*.txt docs/spikes/results/`
   (They contain process and device names and battery levels, but no Bluetooth addresses and no audio.)
2. Fill in the Notes columns of this file, then `git add docs/spikes && git commit -m "spike 1 results" && git push`.
3. Or paste both files and your notes into the chat instead.
