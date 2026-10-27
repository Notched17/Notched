# ADR-0002: Click-through with a fixed island panel and a sensor window

- Status: accepted (M1)
- Date: 2026-10-27

## Context

The island panel sits above the menu bar. A window takes clicks across its whole frame, transparent parts included, so a panel larger than the visible island would block the menu-bar items beside the notch (#7). The island must still detect hover, and expand/collapse must be one smooth spring with no jank.

The plan's first approach resized the panel to follow the island: grow to fit both states before the spring, shrink back after a collapse. A burst of screenshots during expansion showed that this glitches. In the first frame after the window grows, the compact island is drawn about 170 pt left of centre, because the window server applies the new window frame one frame before SwiftUI re-lays out its content.

## Decision

- **The island panel has a fixed size** (big enough for the expanded island and the widest compact island, plus 20 pt for the shadow). It only resizes when the geometry or size settings change, never during interaction. The island is drawn top-centre in it, so the morph is purely a SwiftUI animation.
- **While compact, the island panel ignores the mouse entirely** (`ignoresMouseEvents = true`). Every click outside the visible island, including on menu-bar items beside the notch, goes to whatever is underneath.
- **An invisible sensor panel** (`IslandSensorPanel`), exactly the size of the compact island and one window level below the island panel, detects hover (an `NSTrackingArea`) and clicks while compact. Resizing an invisible window has no visual cost.
- **While expanded, the island panel takes the mouse** and its own tracking area (the expanded island rect) reports the pointer leaving. Events from each window are only honoured in the states where that window is responsible.
- No global mouse monitors are used, so idle hover detection costs nothing.

## Consequences

- Zero dead zone beside the island while compact. While expanded, the 20 pt shadow margin around the island takes clicks (it's next to the island the pointer is on).
- Two windows per display instead of one.
- Verified by `scripts/window-bounds.swift` (sensor = notch rect) and a screenshot burst showing every frame centred.
