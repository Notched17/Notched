# ADR-0012: Banner pipeline: throttle in the module, queue in the coordinator

- Status: accepted (M3a)
- Date: 2026-10-28

## Context

M3a adds four sources of transient banners: charging, Bluetooth, Wi-Fi and Caps Lock. M5 will add volume and brightness. Real events are messy:
- Wi-Fi flaps on a weak signal.
- A loose MagSafe connector plugs and unplugs within a second.
- AirPods appear in CoreAudio, vanish and reappear while connecting.
- Several events arrive together, e.g. waking from sleep: charger, Wi-Fi and a keyboard at once.

ADR-0006 gave the coordinator one banner on screen and **one** waiting slot, where the newest waiting banner won. Two different events at once lost one. Nothing stopped a flapping source from showing a banner every two seconds.

## Decision

Two layers, both pure and tested.

**1. In the module: `BannerSource<Value>`** decides *whether* a state change is worth a banner. Each module's reducer embeds one, and returns its wakes as effects. Its policy has three knobs:
- **`settle`:** a change must last this long. A change that reverts in time says nothing.
- **`cooldown`:** the same value isn't announced again within this time.
- **`maxPerWindow`/`window`:** a rate limit. While it holds a change back, later changes replace it, so only the **latest** state is announced, never the steps in between.

The first value is the starting state and is never announced.

| Source | Settle | Cooldown | Rate limit |
|---|---|---|---|
| Network | 2 s | — | 3 per 60 s |
| Charger plugged/unplugged | 0 | 10 s | — |
| Bluetooth connect / disconnect | 1 s / 2 s | — | — |
| Caps Lock | 0 | — | — (same id restarts one banner) |

**2. In the coordinator: `BannerQueue`** decides *when* a banner shows.
- **`TransientBanner.priority`** is `.low` (disconnects), `.normal` or `.high` (low battery).
- **What waits:** banners queue while an alert expansion shows, while the user is on the island, and behind a banner that matters as much or more. A more important banner replaces the one on screen.
- **The queue:**
  - The same id replaces its queued copy. Ids are categories ("network", "battery.power", "bluetooth.<device>").
  - Up to 3 wait, ordered by priority, then arrival.
  - A banner that waited longer than 5 s (30 s for `.high`) is dropped as old news.
- **An alert cuts a banner short,** and the banner isn't shown again. On iPhone an expanding activity takes the whole island, and by the time it collapses the banner's moment has passed.
- **Banners never take a minimal slot** (unchanged).

## Consequences

- The flapping cases are pinned by tests:
  - `BannerSourceTests` (`revertWithinSettleIsSilent`, `rateLimitEmitsOnlyLatestWhenAllowed`, `cooldownSuppressesRepeat`)
  - `BannerQueueTests`
  - `ActivityCoordinatorTests` (`bannerWaitsForAlert`, `sameIdReplacesQueuedBanner`, `higherPriorityPreempts`, `alertCutsBannerShort`, `highPriorityWaitsThirtySeconds`)
- `bannerWaitsForAlert` changed meaning: two banners behind an alert now both show, in order, instead of only the newest.
- Modules keep using `ActivitySink.show(_:)`. The throttle lives in their reducers, which return `.wake(Date)` effects for the module's one `OneShotTimer`.
- One shared banner look (`BannerContent`: symbol + label leading, value trailing) is built with the first module's UI on the Mac.
