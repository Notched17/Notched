# ADR-0008: Now Playing backends (mediaremote-adapter first, Music/Spotify scripting as fallback)

- Status: accepted (M2)
- Date: 2026-10-28

## Context

Now Playing (#9, #10) must work for any app: Music, Spotify, Podcasts, and web video in Safari and Chrome. The only system-wide source is the private MediaRemote framework. Since macOS 15.4 it only answers Apple-signed processes, so loading it directly from Notched no longer works. ungive/mediaremote-adapter (BSD-3) works around this by running the Apple-signed `/usr/bin/perl` with a small framework that streams JSON. Apple could close this in any release, so there must be a fallback and a way to notice that the adapter has broken.

Checked on macOS 27.2 (26B118) on 28 Oct 2026:
- adapter v0.7.7's `test` exits 0
- `get` and `stream` read Spotify and Chrome/YouTube, artwork included
- `send` plays and pauses
- `--micros` gives microsecond timestamps; the plain `timestamp` key is ISO-8601 at 1 s precision, too coarse for a smooth scrubber
- the adapter only sees and controls the system's "elected" now-playing app (upstream issues #41–#43)

## Decision

- **`NowPlayingProvider` protocol, two backends,** chosen by the pure, tested `BackendSelector`:
  - **Adapter** (default). A single long-lived `stream --micros --debounce=100` child process. `AdapterStreamDecoder` (tested) merges its diffed JSON lines. Commands are one-shot `send`/`seek` runs. Nothing is polled.
  - **Scripting** (fallback). Music's `com.apple.Music.playerInfo` and Spotify's `com.spotify.client.PlaybackStateChanged` distributed notifications say when anything changes, and need no permission. `NSAppleScript`, on a serial queue with a 2 s timeout, fills in position, artwork and Music favourites. Every script is wrapped in `if application id … is running`, so it never launches a player.
- **Selection:** the preference is Automatic (default), Any App Only, or Music and Spotify Only. Automatic uses the adapter unless its health is `failed`, otherwise scripting. When neither is possible, no activity is shown and Settings ▸ Now Playing explains why and offers the fix.
- **Health:**
  - The first real payload means `healthy`.
  - A non-zero exit means `failed`. The adapter is not relaunched, as its README asks.
  - A death by signal is relaunched with 1/2/4 s backoff, three times at most.
  - The adapter's own `test` can briefly publish a fake now-playing entry, so it isn't run at every launch. It runs when Music or Spotify announces "Playing" while the adapter has reported nothing for 3 s (at most every 10 min), and from Settings ▸ Check Again.
- **Bundling:** see `Vendor/mediaremote-adapter/NOTCHED.md`. The source is vendored unmodified and built by XcodeGen targets, signed with the app's identity. The framework is embedded but not linked; the test client sits in `Contents/MacOS` and the script in `Resources`. The app gains `com.apple.security.automation.apple-events` for the fallback.
- **Commands are optimistic:** play/pause and seek update the shown state at once, and the backend's next report confirms it.

## Consequences

- Any app that shows in Control Center's Now Playing appears on the island, with no permission prompt.
- The Apple Events prompt appears only when the fallback actually runs, or when the user first taps the heart for a Music track.
- Two players at once: the island follows the elected one, like Control Center.
- If Apple blocks the Perl route, Automatic mode degrades to Music and Spotify with a clear status, instead of silently showing nothing.
- The perl helper is part of the performance budget (measured in M2's verification).
