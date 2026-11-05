Add a **UV index** to Notched's Weather module: a full visual in the Weather tab, and a small one in the Today tab. The colours should change with the UV value: low UV is a light sky blue, high UV gets warmer and finally a deep sunburn red.

## Model guide (for me, not for you)
Plan mode: Opus, high effort. Build: Sonnet, medium effort. Builds, tests and searches: Haiku via `build-runner` and `Explore`.

## Setup
- Check `git status`. If there are uncommitted changes, stop and show me. Create a branch `uv-index` from `main`.
- Follow `CLAUDE.md` (module contract, reducer convention, Liquid Glass rules, accessibility rules, privacy rules, Token economy).

## Read first
1. `Sources/Modules/Weather/`: `OpenMeteo.swift` (the request and parser), `WeatherModels.swift` (`WeatherSnapshot`, `HourlyWeather`), `WeatherReducer.swift`, `WeatherViews.swift`, `WeatherSettings.swift`, `WeatherModule.swift`.
2. `Sources/Core/Island/Tabs/TodayHub.swift`: how modules publish a `TodaySection` into a slot, and how `TodayLayout` fits sections. Look at how Weather and Calendar publish theirs.
3. `Tests/`: the existing Weather tests, the parser tests, and the accessibility contrast lint (`AccessibilityLintTests`).
4. `docs/adr/` for the weather ADRs, `docs/ROADMAP.md` row #51.

## Step 0: Plan (plan mode)
Propose a plan and wait for my approval. Cover the data changes, the colour scale (with the exact stops), the two layouts, the settings, the tests, and any questions for me.

## Data
- Open-Meteo already returns UV. Add `uv_index` to the `current` and `hourly` parameters and `uv_index_max` to `daily`, in the **same single request**. No extra network calls, polling or new permissions.
- Extend `WeatherSnapshot` and `HourlyWeather` with optional UV fields: current UV, today's peak UV, and the hour of the peak (derive it from the hourly data).
- **Old cached snapshots must still decode.** The new fields are optional, and a test loads a cached snapshot saved before this change.
- A missing UV value (older cache, API omits it) hides the UV visuals. Never show a made-up zero.

## UV colour scale (dynamic, continuous)
- Interpolate smoothly between stops instead of hard steps, so 5.4 and 5.6 look different. Suggested stops (tune by eye): 0–2 light sky blue, 3–5 warm yellow-orange, 6–7 orange, 8–10 red, 11+ deep sunburn red. Values above 11 clamp the colour at the deepest red but still show the real number.
- Put the scale in one small pure type (`UVScale`) with tested functions: value → colour, value → category (Low, Moderate, High, Very high, Extreme, following the WHO bands 0–2, 3–5, 6–7, 8–10, 11+), and value → advice text.
- **Contrast:** the island is black, and a very dark red on black is hard to read. Keep every number at or above 4.5:1 against black, using a luminous, saturated red for the top end. If you want the darker feel, use a tinted capsule or gauge track behind the number. Add the new colours to the existing contrast lint.
- **Never rely on colour alone.** Always show the category word, and give VoiceOver the value, category and advice, for example "UV index 8, very high. Sun protection recommended."
- At night or when UV is 0, show a calm "0, Low" state in light blue. Don't hide the tab section just because the sun is down.

## Weather tab (full visual)
- A UV card in the expanded Weather tab: a large UV number in the scale colour, the category label, and a gauge (an arc or a horizontal bar) with a marker at the current value, drawn in the Liquid Glass style used elsewhere.
- Peak today (value and time), and a short advice line ("Sun protection recommended from UV 3", with the actual threshold wording).
- A small hourly UV strip for the next hours of daylight, with each bar tinted by the same scale. The strip must fit the tab's existing width and height budget. Drop it before the layout gets cramped.
- Values animate with `contentTransition(.numericText)` and a short spring on the gauge marker (≤ 2 s). Reduce Motion means plain cross-fades.

## Today tab (small visual)
- A compact UV element in the Today tab, published as a `TodaySection` the way Weather publishes its section: a small sun glyph, the UV number in the scale colour, and the category as one short word.
- It must work inside `TodayLayout`'s slots without breaking the existing layout. Check what happens when the Calendar and Reminders sections are also full.
- It disappears when the Weather module is off, when UV is unavailable, or when the new setting is off.

## Settings
- In the Weather settings pane: **Show UV index** (on by default), and **Show UV in Today** (on by default). The Layout editor's catalogue must know about the new Today section, and its ids must stay in step with the real sections (there is a test for that).

## Tests (write them first)
- `UVScale`: colour at the stops and between them, category boundaries (2.9, 3.0, 5.9, 6.0, 10.9, 11.0), clamping at and above 11, negative or NaN input.
- Parser: a fixture response with UV, one without UV, one with null UV entries; peak-hour derivation.
- Cache: a pre-change snapshot still decodes.
- Contrast: every scale colour is at least 4.5:1 against black.
- Layout catalogue: the new section id matches the real one.

## Verify
- Add a DEBUG-only override (for example in the Scenario Lab) that sets the UV to any value, so I can see UV 0, 3, 6, 8, 11 and 14 without waiting for the weather.
- Screenshots in `docs/screenshots/uv/`: the Weather tab and the Today tab at UV 1, 4, 7, 9 and 12, on a notch screen and on the pill; the "UV unavailable" state; the setting off.
- Critique each screenshot against Apple's Weather app UV card: hierarchy, legibility, and whether the colour change feels natural.
- Performance: no extra CPU or network. Confirm that only one request is made per refresh.
- Update `docs/ROADMAP.md` (note the UV addition under #51) and the Weather ADR if the decision changes anything there.
- Finish with a short report: what was built, screenshots, test results, decisions, and anything for me to try. Don't merge or push without asking.

If something turns out impossible or wrong in practice, stop and tell me rather than quietly doing something different.
