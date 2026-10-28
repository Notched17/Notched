# M2 Media: design

- Date: 2026-10-28
- Brief: `docs/prompts/M2-media.md`. Charlie asked for every open question to take the recommended option, with a list of those calls at the end (marked **[call]** here).
- Builds on: ADR-0006 (live activity model), `docs/ISLAND-BEHAVIOR.md`, the Scenario Lab Music demo.

## Intent

The first real module, and the template for every later one. It must feel like Apple's own Now Playing in the Dynamic Island: calm, exact, and invisible when idle. It must also cost nothing when off and next to nothing when on.

## What the platform allows (checked on macOS 27.2, 26B118)

| Question | Finding |
|---|---|
| mediaremote-adapter on 27.2 | **Works.** v0.7.7 (3 Sep 2026, BSD-3), built from source. `test` exits 0. `get` and `stream` read Spotify and Chrome (YouTube), including artwork. `send` plays and pauses. No prebuilt binaries are published. |
| Timestamps | Without `--micros`, `timestamp` is ISO-8601 at **1 s precision**. `--micros` gives `timestampEpochMicros`, `elapsedTimeMicros` and `durationMicros`. Infinite durations (live streams, issue #28) are dropped by the adapter with a stderr line, and the key is simply missing. **Use `stream --micros`.** |
| Track identity | `contentItemIdentifier` changes on every play and pause, so a track is identified by title + artist + album. |
| Elected player only | Reads and commands reach the system-elected now-playing app only (issues #41–#43). A safe per-app command route does not exist. |
| Music like | Music's dictionary has `favorited` on tracks. `loved` is gone. |
| Spotify like | `starred` is **read-only** in Spotify's dictionary. Liking needs the Web API (OAuth PKCE), which is deferred: **ask Charlie**. |
| Fallback events | Music posts `com.apple.Music.playerInfo` and Spotify posts `com.spotify.client.PlaybackStateChanged` (distributed notifications). Observing them needs no permission. Scripting is used only for position, artwork, commands and like. |

## Decisions

### Backends

- `NowPlayingProvider` protocol with two backends:
  - **`AdapterNowPlayingProvider`.** A long-lived `/usr/bin/perl mediaremote-adapter.pl <framework> <test-client> stream --micros --debounce=100` child process. JSON lines are merged by a pure decoder. Commands are one-shot `send` and `seek` invocations.
  - **`ScriptingNowPlayingProvider`.** Music and Spotify through distributed notifications plus `NSAppleScript` on a serial queue with a 2 s AppleScript timeout. It never sends an Apple Event to an app that isn't running, because that would launch it.
- **Bundling.** The adapter source is vendored at `Vendor/mediaremote-adapter/` (v0.7.7, commit e3ff502, with LICENSE). XcodeGen builds it as a `MediaRemoteAdapter` framework target (embedded in `Contents/Frameworks`, **not linked**) and a `MediaRemoteAdapterTestClient` tool (in `Contents/MacOS`). The `.pl` script ships in Resources. Everything is signed with the app's Apple Development identity, so there is no CMake. **[call]**
- **Health.** The adapter starts `unknown`. A non-empty payload makes it `healthy`. A non-zero exit makes it `failed`, and it is not relaunched (the README says so). A death by signal relaunches with backoff, up to 3 times. If Music or Spotify announce "Playing" while the adapter reports nothing for 3 s, the module runs the adapter's `test` command once, and a failure marks the adapter `failed`. Settings has a "Check Again" button that runs `test`. There's no `test` at every launch, because it can briefly fake a now-playing entry. **[call]**
- **Selection** (pure, tested), by preference:
  - **Auto** (the default): the adapter unless it has `failed`, otherwise scripting.
  - **Adapter only.**
  - **Music & Spotify only.**

  Scripting is unavailable when neither app is installed or both have denied Automation. When nothing is available, the module shows no activity and the Media pane explains why, with a button to fix it.

### Data model

- `NowPlayingSnapshot`: title, artist, album, `duration?` (nil for live), a `PlaybackTimeline` (elapsed at a timestamp, plus rate), `isPlaying`, `sourceBundleID` (the parent app when present), artwork data, `supportsSkip15` and `liked` (nil when unknown or unsupported).
- Elapsed time is interpolated: `elapsed(at:) = clamp(elapsed + (t − timestamp) × rate, 0, duration)`. It is never polled. The scrubber redraws once per second, and only while expanded.

### Presentation (one `.media` activity, id `media.nowPlaying`)

- **compactLeading:** artwork, 20 pt, continuous corners. Placeholder: a `music.note` glyph on a quiet fill.
- **compactTrailing:** visualiser bars tinted with the artwork accent. With the lyric ticker on and lyrics loaded, it shows the current line instead (one line, fade-truncated; it's capped by the island's 64 pt region). **[call]**
- **minimal:** bars while playing, a small artwork circle while paused, because still bars say nothing. **[call]**
- **Expanded:**
  - leading: artwork, 56 pt.
  - center: title (with small live bars after it), then artist · source-app icon.
  - trailing: output-device button with menu (#16).
  - bottom: scrubber with elapsed and remaining time, then controls (±15 s only when the source supports it, or when the duration is ≥ 20 min, plus previous, play/pause, next and heart), then an optional lyric line.
- **Visualiser.** Core Animation keyframe loops run in the render server. A SwiftUI `TimelineView` meter measured ~7% CPU in M1.5. Bar levels are a sum of phase-shifted sines plus value noise from a fixed seed (deterministic, tested). Amplitude eases in and out over 0.35 s. Every animation is removed when the view leaves its window, the window is occluded, or playback pauses. Reduce Motion shows still bars. This differs from the brief's "TimelineView or Canvas" because of the CPU budget: ADR-0010. **[call]**
- **Tint.** A deterministic accent from the artwork: downsample to 24×24 sRGB, keep saturated mid-tone pixels in 12 hue buckets weighted by saturation, take the heaviest bucket's mean, then lift it to a minimum brightness for legibility on black. A greyscale cover gives white.
- **Track change.** Artwork uses `.blurReplace` keyed by track. Text rolls with `numericText` through the island host. There's no alert unless "Briefly expand on track change" is on (off by default).
- **Lifecycle.** Paused → `stale` after 2 min → ended after 10 min. Both are settings. A player quitting or nothing playing ends the activity at once. Stale media shows dimmed with no "Updating…" note, which is misleading for a paused song: a new optional `staleNote` on `LiveActivity`.
- **`openAction`** opens the source app.
- **Fullscreen (#5).** A new generic `LiveActivity.keepsIslandInFullscreen`. Media sets it while playing **and the source isn't the frontmost app**, so a fullscreen YouTube video still hides the island. **[call]** The General setting "Keep showing while media plays" sits under "Hide in fullscreen apps" and is on by default.
- **Media swipe gestures (#9 row).** These are not built: horizontal swipes already cycle activities (ADR-0006), and a second meaning would be inconsistent. **[call]**

### Output devices (#16)

CoreAudio lists the output devices and the default output, and switches the default. It reacts through property listeners, and only while the module runs. Symbols (pure, tested):
- AirPods Pro / Max / other → `airpods.pro` / `airpods.max` / `airpods`
- Beats → `beats.headphones`
- other Bluetooth → `headphones`
- built-in → `laptopcomputer`, or `headphones` when the data source is headphones
- HDMI/DisplayPort → `tv`
- AirPlay → `airplayaudio`
- USB → `hifispeaker`
- anything else → `speaker.wave.2`

### Lyrics (#13)

- LRCLIB `GET /api/get?track_name&artist_name&album_name&duration`, with a `User-Agent: Notched/<version> (https://github.com/…)`.
- Disk cache in `~/Library/Caches/me.rkck.Notched/Lyrics/<sha256(key)>.json`. Not-found results are cached for 7 days.
- The key is normalised (trimmed, lowercased, whitespace collapsed) title|artist|album|rounded duration.
- **Privacy rule** (ADR-0009): the lyrics client is only constructed while lyrics are on. Turning them off releases it and cancels in-flight work. Tests prove that a disabled lyrics store never calls the fetcher.

### Settings (Media pane, under Modules)

- Source (Auto / Adapter only / Music & Spotify only)
- backend status with Check Again
- ignored apps
- lyrics on/off and compact ticker
- briefly expand on track change
- stale after (1 / 2 / 5 / 10 min) and end after (5 / 10 / 30 / 60 min)
- visualiser (Animated / Still / Off)
- media keys (disabled placeholder, "Arrives with HUD replacement")

### Scenario Lab

The Music demo stays as a DEBUG-only reference. It's useful for screenshots without real playback. **[call]**

## Non-goals

- Spotify like (needs Charlie).
- Lock-screen lyrics (M6).
- Animated artwork (#14).
- Per-app volume (#17).
- Real audio-reactive bars (needs System Audio Recording permission).
- Media keys (M5).
