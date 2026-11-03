# Privacy

Notched is built to be quiet about you. It has no account, no analytics, no crash reporting and no advertising, and it sends nothing anywhere unless a module you turned on needs the network to do its job. This page lists every case, and what stays on your Mac.

## What touches the network

| What | When | What is sent | To whom |
|---|---|---|---|
| **Synced lyrics** | Only while *Now Playing ▸ Show synced lyrics* is on and a track with an artist and length is playing | The track's title, artist, album and length | [LRCLIB](https://lrclib.net) (a free community lyrics database). No account, no cookies. See ADR-0009. |
| **Spotify cover art** | Only in Now Playing's AppleScript fallback for Spotify | A request for the cover image | Spotify's own image server |
| **Weather** | Only while Weather is on, about every 30 minutes | Your location rounded to about 11 km (0.1°), or the city you picked | [Open-Meteo](https://open-meteo.com) (free, no key). A city name you type is sent to Open-Meteo's search only when you press Search. See ADR-0027. |
| **Updates** | Not built yet. When added (you'll be asked first), it will contact the release server and nothing else | The app version | GitHub |

Nothing else leaves the Mac. In particular, none of these ever do: the clipboard history, calendar events, reminders, Claude Code usage, terminal contents, Bluetooth devices, Wi-Fi names, downloads or your media history.

Requests use private sessions (no cookies, no shared cache). With a firewall such as Little Snitch you should see no connection from Notched unless one of the rows above applies.

## What stays on your Mac, and where

| Data | Where | Notes |
|---|---|---|
| Settings | `~/Library/Preferences/me.rkck.Notched.plist` | Which modules are on, layout, shortcuts |
| Clipboard history | `~/Library/Application Support/Notched/Clipboard/` | Off by default. Text, links, file paths and image copies. Items marked private by password managers, and copies from excluded apps (a list you can edit), are never read. Never logged. *Clear on quit* is available. See ADR-0024. |
| Lyrics cache | `~/Library/Caches/me.rkck.Notched/Lyrics/` | Files named by a hash, so the folder doesn't list what you play |
| Weather cache | `~/Library/Application Support/Notched/Weather/` | The last forecast and place |
| Activity API clients | The login Keychain | Only a hash of each token. Tokens are shown once. |
| Claude Code usage | Nothing stored | Read from `~/.claude/projects` on this Mac; nothing is sent, and no login or token is read. The *Install Claude Code hooks* button edits `~/.claude/settings.json` after backing it up. |
| Logs | The system log (`os.Logger`) | Never contains clipboard text, event titles, reminder text or terminal output. Debug builds also write research reports to `~/Library/Logs/Notched/`; release builds don't. |

Delete `~/Library/Application Support/Notched` and `~/Library/Caches/me.rkck.Notched` to remove everything Notched keeps, apart from its settings and Keychain entries (*Settings ▸ Modules ▸ Activity API* revokes clients).

## The local Activity API

When you turn it on, Notched listens on `127.0.0.1` only, on a port you can see, and only for requests that carry a token you created. Web pages in your browser can't use it (ADR-0021). It is off, with no listening socket, otherwise.

## Permissions

Notched asks for a permission only when you turn on the module that needs it. The list, and why each is needed, is in the [README](../README.md#permissions).

## Questions or concerns

Notched is open source: every claim here can be checked in the code. Please open an issue if one of them doesn't hold.
