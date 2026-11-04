# ADR-0033: A Weather tab, and the UV index from the same forecast

- Status: **accepted 4 Nov 2026**
- Amends: ADR-0025 (Weather was only the Today strip) and ADR-0027 (the forecast request).
- Rules it follows: ADR-0027 (one request, rounded coordinates, nothing new asked of macOS), CLAUDE.md (glass only for controls; contrast; Reduce Motion).

## Context

Charlie asked for the UV index: a full visual and a small one in Today, with a colour that moves from light sky blue to a deep sunburn red. Weather had no tab of its own, only a strip across the top of Today, and Today's layout has no room for another row without taking one from Calendar and Reminders.

## Decision

- **A Weather tab** (`weather`, right after Today) holds the conditions and the UV card. It can be hidden or moved in the layout editor like any tab. The Today strip stays as it was.
- **The small UV reading is a chip inside the Today strip**, after the high and low, not a new `TodaySection`. It drops out when there is no room, and the strip's height does not change, so Calendar and Reminders keep their rows.
- **No extra request.** `uv_index` is added to the existing `current` and `hourly` parameters and `uv_index_max` to `daily`. Checked against the live API on 4 Nov 2026.
- **UV is read from the whole day,** not the next 12 hours the snapshot keeps. The peak, its hour and the hours worth protecting (UV 3 or more) are worked out in the parser, so in the afternoon the morning's peak is still known. They are stored as `WeatherSnapshot.uv` (optional); each `HourlyWeather` gains an optional `uvIndex`. A cache saved before this change decodes with `uv == nil` (tested).
- **Missing means hidden.** No UV in the response, or "Show UV index" off, removes the card and the chip. A made-up zero is never shown. At night a real 0 shows as "0, Low" in light blue.
- **The band follows the number shown.** The reading is rounded first, then banded by the WHO ranges (0–2 low, 3–5 moderate, 6–7 high, 8–10 very high, 11+ extreme), so 2.6 reads "3, Moderate" and the word and number never disagree.
- **Colour.** `UVScale` blends linearly between eight stops (`#9AD6FF` at 0, `#6EC3FF` at 2, `#FFD84A` at 3, `#FFB03A` at 5, `#FF8C2E` at 6.5, `#FF5B33` at 8, `#FF3B30` at 10, `#EC2A3C` at 11). Above 11 the colour stays at the last stop and the real number is still shown. Every colour is at least 4.5:1 against black (the lowest, at 11, is about 5:1), checked by a test, so the top end is a luminous red rather than a dark one. The category word is always shown, so colour is never the only signal.
- **Settings.** "Show UV index" and "Show UV in Today", both on by default. The second needs the first.
- **DEBUG only.** `notched://debug/weather?fake=1&uv=8` (or `none`, `default`) makes up a forecast or a UV for screenshots; the reducer, the cache and the network never see it.

## Consequences

- One more tab slot is in use when Weather is on (the user can hide it).
- The parser reads the whole day's hourly values, which are already in the response.
- If Open-Meteo ever refuses the new variables, the whole forecast would fail; the live check and the parser tests are the guard.
