# ADR-0009: Lyrics only touch the network while they're on

- Status: accepted (M2)
- Date: 2026-10-28

## Context

Synced lyrics (#13) come from LRCLIB (`lrclib.net/api/get`), a free community database. A lookup sends the title, artist, album and length of what's playing to a third-party server. Atoll once sent this to LRCLIB with lyrics turned off (`docs/research/notch-app-research.md`, row 13). Notched promises the opposite: a feature that's off does nothing.

## Decision

- **No store, no requests.** `MediaModule` creates a `LyricsStore` only while Settings ▸ Now Playing ▸ "Show synced lyrics" is on. Turning it off cancels any lookup in flight and releases the store. With the module off, nothing exists at all.
- **Belt and braces.** `LyricsStore.isEnabled` gates every lookup, and it is checked again after the network answers, so a result that arrives after lyrics were turned off is discarded and not cached. `LyricsStoreTests.disabledNeverFetches` proves a disabled store never calls its fetcher.
- **Cache on this Mac only.** Results are saved in `~/Library/Caches/me.rkck.Notched/Lyrics/`. Each file is named with the SHA-256 of the normalised track key (lowercased, trimmed, whitespace collapsed, duration rounded to whole seconds), so the folder doesn't list what you listen to. "Not found" is cached for 7 days, and network errors aren't cached.
- **Minimal request.** The request carries only the four LRCLIB lookup fields and an identifying `User-Agent`, as LRCLIB asks. It uses an ephemeral `URLSession`, so there are no cookies and no shared cache.
- **Plain lyrics are ignored.** Only time-synced lyrics are shown. Without timing, a single line under the controls would be meaningless.

## Consequences

- The Settings footer says exactly what is sent and when.
- `nettop` or Little Snitch shows no connection to lrclib.net unless lyrics are on and something with an artist and a duration is playing.
- The cache can be deleted at any time; it rebuilds as songs play.
