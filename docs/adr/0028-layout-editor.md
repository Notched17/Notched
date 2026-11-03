# ADR-0028: Layout editor: Show in Compact and the tab layout (#71)

- Status: accepted for M4b Step 7; **written on Linux, not yet compiled or run**
- Date: 2026-11-02
- Builds on: ADR-0016 (user priority, non-hideable slots), ADR-0020 (expanded tabs), ADR-0025 (Today tab)

## Decisions

- **One page, not two.** Settings ▸ Modules ▸ Layout replaces the Priority page. The class order and the pins stay in `RankingPolicy` exactly as before; the editor adds to it rather than creating a second priority store (the prompt's "reuse M3b's priority settings").
- **Show in Compact is a list on `RankingPolicy` (`listedOnly`).** A listed-only module's activities are left out when the coordinator picks the primary and the bubbles, but stay in `live`, so the expanded island still lists them. A non-hideable activity (a call, screen recording) ignores the list, so the user can't hide a call by accident. A listed-only activity can't be made primary by a swap. **It doesn't alert either (decided 2 Nov 2026):** a module turned off for compact queues no alert expansion and no bounce, and an alert already waiting for it is dropped. Turned off means off.
- **Old saved priorities still load:** `listedOnly` is decoded with `decodeIfPresent`.
- **The tab layout is its own small value (`TabLayout`, key `tabs.layout`)**: a preferred order and a hidden set, both by tab id. A tab not named in the order (one added later) follows the named ones in its own default order. Ids the editor knows but that aren't present now keep their place in the saved order.
- **A hidden tab is removed before the four-tab limit is applied.** That is how the user chooses which four tabs show (the Terminal problem: hiding a demo tab or moving Terminal up brings it back).
- **The editor's lists are pinned by tests:** `LayoutCatalogue` names the modules that can show in compact and the known tabs, and a test checks both against the real module ids and tab ids so they can't drift.
- **Every control works without dragging** (Move Up/Down buttons, switches). Drag to reorder is offered on the tab list where SwiftUI's `onMove` works in a grouped `Form`.
- **The preview uses sample activities and stand-in tabs** with the real module ids, in its own `ActivityCoordinator`, so it looks the same whatever is switched on and never touches the real island.
