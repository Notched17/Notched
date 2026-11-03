# ADR-0032: The lyrics tab is a separate panel that never takes focus

- Status: **accepted 3 Nov 2026**
- Rules it follows: ADR-0026 (keyboard policy), CLAUDE.md "never take keyboard focus" for windows that sit over other apps.
- Replaces: the lyric ticker beside the notch (removed).

## Context

Charlie wanted to read the lyrics while working. The first idea, a one-line ticker in the compact island, failed: each side of the notch has a 64 pt region (about ten characters), so a line was cut off after a word. A scrolling line (tried and dropped) was too quick to read. The expanded island is too short-lived: it collapses when the pointer leaves, and it takes the keyboard when it is clicked.

## Decision

The lyrics tab is its own panel, a black card hanging under the island, with several lines scrolling and the sung line bright in the middle. It stays until the user presses its close button (or the Now Playing module stops).

- **Not part of the island panel.** The island panel is sized for the island and collapses on hover-out. A second `NSPanel` (`LyricsPanel`) is exactly the card's size, so every click outside it reaches the app underneath.
- **Never key, never main.** `canBecomeKey` and `canBecomeMain` are false, and the panel is `.nonactivatingPanel`. Pressing the close button (the hosting view accepts the first mouse) doesn't activate Notched, so a text field the user was typing in keeps the keyboard. Checked on a Debug build: the frontmost app is the same before and after opening and closing it by real mouse clicks.
- **Level** is one below the island (`mainMenu + 2`), so the expanded island opens over the card, not under it.
- **Cost.** Nothing exists while it is closed: no panel, no observer. Open, it redraws only when the sung line changes (`LyricLineSchedule`, as the Now Playing page does), and watches for display changes (to stay under the island), removed on close.
- **Opened from** a lyrics button beside the output icon on the Now Playing page, shown when lyrics were found for the track. It stays visible while the tab is open, so the tab can be closed from there as well.
- **Placement.** Centred under the notch (a notch is centred on its screen), a gap below it; on a display without a notch, under the floating pill. Pure and tested (`LyricsPanelController.frame`).

## Consequences

- With lyrics off, or no synced lyrics for a song, the button isn't shown; an open tab says "No synced lyrics for this song" and stays.
- The tab isn't draggable and isn't remembered across launches. Both are easy to add if wanted.
- Not for the lock screen (ADR-0031 covers lock-screen windows).
