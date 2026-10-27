# ADR-0007: Minimal bubbles: one drawing panel, one sensor per region

- Status: accepted (M1.5)
- Date: 2026-10-27

## Context

With two or three live activities, the extra ones show as minimal bubbles: small black circles or ovals detached from the island by a gap, which "bud off" it and merge back (ISLAND-BEHAVIOR.md §3). ADR-0002 constrains the design: the island panel never resizes during interaction, and while compact it ignores the mouse so everything beside the notch stays clickable. A single invisible sensor window detects hover and clicks. Bubbles need their own hover (expand that activity), click (make it primary), right-click (Hide) and swipes. The 6 pt gaps between them must stay click-through.

The options were:

1. **Extra drawing panels**, one per bubble. Each bubble gets its own window. A bubble can't morph out of the island across window boundaries, though, and the windows would be repositioned as the island resizes, which is the frame-lag glitch ADR-0002 found.
2. **One sensor over the whole compact area**, bubbles included. That's simple, but it swallows clicks in the gaps and can't tell regions apart without hit-testing inside an invisible window, which still blocks clicks.
3. **Draw everything in the island panel, sense each region separately.**

## Decision

Option 3.

- **Drawing:** bubbles are separate shapes in the island's own SwiftUI tree (`MinimalBubblesView`), placed from `CompactLayout` frames in screen coordinates. The panel is already larger than notch + 2 × 90 pt, so it just unions the bubble rects.
- **Z-order:** bubbles are drawn *under* the island. They bud out from beneath its edge (scale 0.55 → 1 with an elastic spring, `Motion.budOff`) and slip back under it to merge when the island expands or a banner shows. With Reduce Motion they fade. Beside a glass pill they are glass too, and never glass on glass.
- **Gap:** 6 pt, measured from the island's *body*. On a notch that's inside the concave shoulders, so the gap from the rect edge is 0 pt.
- **Sensing:** `IslandController` keeps one `IslandSensorPanel` per hit region: the island, then each bubble. Each is exactly its region (a bubble's sensor reaches up to the screen's top edge, so a thrown pointer counts). Extra sensors are ordered out. Each sensor reports enter, exit, click, right-click and scroll, tagged with its region. Moving from the island onto a bubble isn't treated as leaving.
- **Keyline:** a 1 px border in the activity's tint at 28% opacity, on bubbles and the expanded island, only in Dark Mode and only if the setting is on. Never on the island attached to the notch, where it would outline the hardware.

**Not built: the goo (metaball) bridge.** The spec allowed one only if it looks native and costs nothing at rest. A metaball needs the island and its bubbles rendered together through a blur and alpha threshold, which would also soften the island's crisp edge against the hardware notch. Black on black, it would only show against the menu bar. The bud from under the edge already reads as one living shape in a frame burst (see `docs/screenshots/m1.5`), so I didn't spike it. It can be revisited with a `Canvas` that's only drawn during the transition.

## Consequences

- One drawing panel and up to three tiny sensor windows per display. Sensors are invisible and cost nothing while the pointer is elsewhere.
- Everything around and between the island and its bubbles stays click-through.
- Bubble positions come from tested pure maths (`CompactLayoutTests`), including the width budget.
