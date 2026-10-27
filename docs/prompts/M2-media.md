We're continuing Notched, my macOS notch app. M1 (shell) and M1.5 (iPhone-style live-activity model) are done ✅. This session builds **M2: Media**, the first real module. It sets the standard every later module copies, so it must feel like Apple's own Now Playing in the Dynamic Island.

## Read first
1. `CLAUDE.md` (binding).
2. `docs/ROADMAP.md`: the **M2** section, feature rows #9, #10, #11, #12, #13, #15 and #16, plus the #5 fullscreen-media item moved from M1.
3. `docs/ISLAND-BEHAVIOR.md`: build media as a `LiveActivity` of class `.media` using the region template. Don't bypass the coordinator.
4. ADR-0006 and the M1.5 Scenario Lab "Music" demo. The real module should match or improve on that look.
5. `docs/research/notch-app-research.md`, section B (Media), and `docs/research/mac-live-activity-sources.md` ("Now Playing").

## Tools
- **superpowers:** brainstorm, then plan, then TDD, then systematically debug, then verify.
- **liquid-glass + hig-\* skills** for all UI. Apple's Music app and the iPhone Dynamic Island are the reference.
- **Xcode MCP** (with `xcodebuild` as fallback) and `screencapture`. After each UI step, screenshot it with real music playing and critique the result.
- **Read before integrating:** the mediaremote-adapter README and recent issues on GitHub (`ungive/mediaremote-adapter`, BSD-3). Check what works on macOS 27.2 before designing around it.

## Step 0: Plan (plan mode)
Propose a plan and wait for my approval. The plan must cover:
- **The `NowPlayingProvider` protocol** and its backends:
  - **mediaremote-adapter** (primary, any app). How you'll bundle and sign it (framework + `/usr/bin/perl` script), and how you'll detect at runtime that it has stopped working.
  - **AppleScript / ScriptingBridge for Music and Spotify** (fallback). This needs the Apple Events entitlement and usage string.
  - The rules for picking a backend, and what happens when both fail. The module then hides itself and explains why in Settings.
- **The data model:** track, artist, album, artwork, duration, elapsed + timestamp + rate (interpolated locally, never polled), playing state, source app bundle ID, and whether the track can be liked.
- **The presentation per region:**
  - **compactLeading:** artwork in a small continuous-corner square.
  - **compactTrailing:** animated bars tinted with the artwork's colour.
  - **minimal:** bars, or a small artwork circle when another activity is primary.
  - **Expanded layout:**
    - leading: artwork
    - center: title, artist and source-app glyph
    - trailing: AirPlay/output button (#16)
    - bottom: scrubber with elapsed/remaining time (#11), then a controls row (±15 s for podcasts and long-form content, previous / play-pause / next, heart #15), then an optional lyric line (#13)
- **`openAction`:** opens the source app.
- **Unit tests** for:
  - elapsed-time interpolation
  - backend selection and fallback
  - the LRC parser and current-line lookup
  - artwork colour extraction (deterministic)
  - lyric-cache keying
- **Questions for me.**

## Build (build, test, install, screenshot and commit after each step)
1. **#9 + #10: Now Playing**, with both backends.
   - Test with: Apple Music, Spotify, Safari playing YouTube, Chrome, Podcasts, and a paused or idle state.
   - When playback stops, the activity goes `stale` after 2 min of pause and `ended` after 10 min **[decision, tune]**. Make both timings settings.
   - Track changes animate artwork with blur-replace and text with `numericText` and `blurReplace`. No alert expansion on track change by default; add a setting "Briefly expand on track change" (off).
2. **#11: Seek bar and ±15 s.**
   - A glass-free, Apple-Music-style scrubber with drag and live preview, and a `.monospacedDigit()` timecode.
   - Show the ±15 s buttons only when the source supports seeking, or for podcasts and long content.
3. **#12: Animated visualiser.**
   - 4–5 rounded bars that look alive, not random: per-bar phase-shifted motion with noise, and amplitude easing in and out on play and pause.
   - Tinted with the artwork's accent colour.
   - Uses `TimelineView(.animation)` or Canvas and **stops completely when off-screen, hidden or paused**.
   - Measure its CPU cost.
4. **#16: Output device switcher.**
   - Show the current output with the right SF Symbol (AirPods, speaker, display, headphones) and a menu to switch, through CoreAudio.
   - React to device changes with property listeners.
5. **#15: Like / favourite.**
   - Apple Music through AppleScript; check whether `favorited` or `loved` works on macOS 27.2.
   - **Spotify needs the Web API (OAuth PKCE, my own developer app). Stop and ask me before building it.**
6. **#13: Synced lyrics (in the notch).**
   - LRCLIB lookup keyed by track, artist, album and duration, with a disk cache.
   - **No network calls unless lyrics are enabled.**
   - The current line sits under the controls in expanded view, and there's an optional compact ticker setting.
   - Leave the lock-screen lyrics part for M6.
7. **#5 follow-up: fullscreen media.** Add the setting "Keep showing during fullscreen media" to the fullscreen auto-hide logic.
8. **Settings pane for Media:**
   - preferred backend (Auto / Adapter / Music & Spotify only)
   - excluded apps
   - lyrics on/off
   - expand on track change
   - stale and ended timings
   - visualiser style
   - media-key behaviour placeholder for M5
9. **Delete** the Scenario Lab "Music" fake module, or keep it DEBUG-only as a reference.

## Verify
- Screenshots in `docs/screenshots/m2/` showing:
  - compact (Music, Spotify, Safari)
  - media as a minimal bubble beside the Lab "Timer"
  - expanded with lyrics
  - output menu
  - paused / stale
  - a non-notch pill
- Critique every screenshot against iPhone Now Playing and fix anything that isn't Apple-quality.
- Performance:
  - idle with nothing playing: CPU < 0.5%
  - playing with the island compact: < 1.5%
  - expanded with the visualiser: < 3%
  - the adapter's helper process included in all of the above
  - memory < 150 MB
  - Report the numbers.
- Robustness:
  - quit the music app while it's playing
  - switch between two players
  - sleep and wake
  - unplug AirPods
  - deny the Apple Events permission
  - force the adapter to fail and check that the fallback takes over
- Update `docs/ROADMAP.md` (M2 rows ✅ with notes), write ADRs for the media backend choice and the lyrics privacy rule, and update `THIRD_PARTY_NOTICES.md` for mediaremote-adapter.
- Finish with a short report:
  - what was built
  - screenshots
  - performance numbers
  - what works on macOS 27.2 and what doesn't
  - questions for me
  - suggestions for M3
