# ADR-0027: Weather: where the place comes from, and how it refreshes

- Status: accepted for M4b Step 5 (#51); **written on Linux, not yet compiled or run**
- Date: 2026-10-31
- Spec: `docs/superpowers/specs/2026-10-31-m4b-productivity-design.md` §4.5, §8 (answer 3)

## Decisions

- **A chosen city is the default and asks macOS for nothing.** The pane searches Open-Meteo's geocoder and stores the pick. "My location (approximate)" is an opt-in in the pane.
- **Device location is taken at most once a day.** One `CLLocationManager.requestLocation()` at 3 km accuracy (`CoreLocationProvider`), never continuous updates, and only when Location is already allowed. The place is labelled "Current location": `CLGeocoder` is deprecated in macOS 26 and a name isn't worth another network call. A fix younger than 24 h is reused (`WeatherLocationPlan`, tested). Choosing "My location" asks for permission in that pane; denying it falls back to the city. The module descriptor declares **no** permissions, so turning Weather on never prompts.
- **Only rounded coordinates leave the Mac.** Latitude and longitude are rounded to 0.1° (about 11 km) before a request, which is also the key for "the same place". A typed city name is sent only to the geocoder, only when the user presses Search.
- **Refresh: 30 minutes while on, one request at a time.** Retries after 1, 5, 15, then every 30 minutes; coming back online skips the rest of the back-off. No polling timer of its own: one `OneShotTimer` the reducer sets, plus wake and clock-change nudges. It uses `NWPathMonitor` on a utility queue (event-driven).
- **The last forecast is cached** (`Application Support/Notched/Weather/cache.json`, 0600) and used straight away for the same place. Offline, it stays on screen marked "Updated … ago" with a `wifi.slash`; past 6 hours it is dimmed and the compact temperature goes away.
- **Compact temperature is `.passive`** and off by default, so it never takes the island from media or a live activity (ADR-0011).
- **Attribution:** Open-Meteo's data is CC BY 4.0; the pane carries "Weather data by Open-Meteo.com" with a link.
- Open-Meteo is called with `timeformat=unixtime`, so no time-zone parsing is needed; the hourly strip starts at the current hour.

## Open until checked on the Mac

- Whether `requestLocation()` returns promptly for an agent app, and what the place name looks like from `CLGeocoder`.
- The real Open-Meteo responses against `OpenMeteo.parseForecast` (the tests use a hand-written sample in the documented shape).
- How the weather strip fits above the Calendar and Reminders columns (two rows each) at the narrowest island width.
