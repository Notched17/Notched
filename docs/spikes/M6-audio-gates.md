# App Volume (#17): the five gates

ADR-0029 makes #17 a conditional go. Each gate below has to pass on the **Release** build (`scripts/go.sh --release`, already installed), or per-app volume is dropped. About 15 minutes. Spotify playing, AirPods or speakers, either.

Setup: Settings ▸ Modules ▸ turn on **App Volume**. Open the island's expanded view: there is a **Volume** tab. The first slider move asks for the audio permission.

If an app ever stays silent: menu bar ▸ **Reset App Volumes**, or `killall Notched`, and if still silent `sudo killall coreaudiod`.

| # | Do | Pass if | Notes |
|---|---|---|---|
| 5 | **Idle cost.** With the module on and every slider at 100 %: `scripts/cpu.sh 60 "mixer on, no taps"`. Look at the menu bar for the purple dot. | No purple dot. Total close to the number with the module off (Release idle). | CPU: |
| 1 | **CPU.** Move Spotify's slider to about 30 % (allow the permission if asked). Play for a minute: `scripts/cpu.sh 60 "mixer, 1 tap"`. | Total is at most **0.5 points above** gate 5's number. | CPU: |
| 4 | **Prompt doesn't freeze the island.** Reset the permission first: `tccutil reset AudioCapture me.rkck.Notched`, relaunch Notched. Move a slider and **leave the prompt open for 20 s**, hovering the island meanwhile. | The island still opens and animates while the prompt is up. | |
| 2 | **Refusal.** Same prompt: press **Don't Allow**. | Spotify is silent for **about a second at most**, then back at full volume. The row shows "Notched couldn't hear Spotify…" with Settings and Try Again. No purple dot afterwards. | How long was it silent? |
| 2b | Allow it in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then press **Try Again**. | Spotify goes quieter, the message goes away. | |
| 3 | **Crash.** Spotify at 30 %: `killall -9 Notched`. Then `open ~/Applications/Notched.app`. | Spotify is at full volume straight after the kill. After relaunch it **stays** at full volume, and the Volume tab shows 100 % (nothing re-applied). | Did Spotify go quiet again by itself? |
| 6 | **Everyday use.** Change two apps (Spotify, a YouTube video in Safari), switch the output between speakers and AirPods, mute and unmute, close the lid for 30 s. | No crackle; levels follow the sliders; after the output switch both stay turned down. | |
| 7 | Set every slider back to 100 %. | The purple dot goes away. | |

Send back: the numbers in the notes column and anything that looked wrong.
