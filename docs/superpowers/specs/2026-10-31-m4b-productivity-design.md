# M4b: productivity modules and layout editor (design, Step 0)

- Status: **draft. Charlie answered §7 on 31 Oct (see §8); the Today tab layout (§3.1) waits for his confirmation.** No code until then, and the code is built on the Mac (§8, Q1).
- Date: 2026-10-31
- Prompt: `docs/prompts/M4b-productivity.md`. ROADMAP rows #45, #48 (+#49), #50, #51, #55, #64, #71.
- Builds on: ADR-0006 (activity model), ADR-0011 (media stays primary), ADR-0012 (banners), ADR-0016 (priority), ADR-0020 (tabs).

## 0. Preconditions and two problems found while planning

**M4a is merged into `main`, but it hasn't been checked on a Mac.** It compiles and 868/869 tests pass. The fix for the last test (`0586e9a`) isn't merged, and none of `docs/M4A-MAC-CHECKLIST.md` has been run. The prompt only says to stop if M4a isn't merged, so this doesn't block M4b, but M4b builds on M4a's tab host and settings. Decision needed: **Q1**.

**This session can't build.** It runs on Linux with no Xcode, and this container doesn't have a Swift toolchain at the moment. M4a got 148 pure-logic tests running on a Linux Swift 6.0.3 toolchain. I can do the same again if the toolchain can be installed. AppKit, SwiftUI, EventKit, CoreLocation and SwiftTerm code can't be compiled here, and none of the required screenshots, `ps`, `top` or `scripts/cpu.sh` checks can run. Decision needed: **Q1**.

**The tab cap.** ADR-0020 allows at most **four module tabs**, because that is what fits the narrowest expanded island (371 pt) with labels. M4a's AI tab uses one. M4b as specified adds five: Clipboard, Calendar, Reminders, Weather and Terminal. That makes six, and the prompt says "the full tab bar with every tab enabled must still fit". §3 proposes a fix (**Q2**).

## 1. What every module gets

The rules from CLAUDE.md and the prompt, so they aren't repeated in each section below:

- **Folder layout.** One folder per module, `Sources/Modules/<Name>/`, holding `<Name>Module.swift`, the reducer, the views and `<Name>SettingsPane.swift`, plus a `ModuleDescriptor`. Registered in `App/AppEnvironment.swift`.
- **Permissions.** Declared in `ModuleDescriptor.permissions`. They are requested only when the module (or the sub-feature) is switched on, never at launch or during onboarding. When a permission is denied, the tab shows a short explanation and an **Open System Settings** button (`PermissionCenter.openSystemSettings(for:)`). The settings pane shows "Not Allowed", following the Downloads pattern.
- **Off by default.** Exception: the colour picker needs no permission and does nothing until clicked, so it qualifies as `isOnByDefault` under the module contract.
- **Zero cost when off.** No timers, observers, processes or file handles. Every shell gets a `ModuleShellTests` case: switch it on and off five times, and nothing is left behind.
- **A pure reducer.** Foundation only, with an injected `now`, wakes as effects and a silent first observation (`docs/templates/module-reducer.md`). Each reducer gets one `@Suite` in `Tests/`.
- **Tab content is built only while it's visible.** `IslandTab.onVisibilityChange` drives `RefreshScheduler.setUIVisible`.
- **Logging and privacy.** Each module logs to `os.Logger` under its own category. No user content is ever logged: clipboard text, event titles, reminder titles and locations stay out of the logs.

## 2. New shared pieces

| Piece | Where | Why |
|---|---|---|
| `EventStoreService` | `Sources/Services/EventKit/` | Calendar and Reminders share one `EKEventStore`, because Apple recommends one store per app. It is `@MainActor` and reference-counted: the first module to start creates the store and observes `EKEventStoreChanged`, and the last to stop drops it. It converts `EKEvent`/`EKReminder` into plain `Sendable` snapshots (`CalendarEventSnapshot`, `ReminderSnapshot`) so the reducers never see EventKit types. |
| `LocationService` | `Sources/Services/Location/` | Asks once for an approximate location (`CLLocationManager.requestLocation()` with `desiredAccuracy = kCLLocationAccuracyReduced`), then stops. No continuous updates. Weather is the only consumer for now. |
| `GlobalHotkey` | `Sources/Services/Input/` | The clipboard hotkey. Recommendation: **sindresorhus/KeyboardShortcuts** (MIT, already on the allowed list). It uses Carbon `RegisterEventHotKey`, which is public, needs no permission and doesn't use an event tap, and it comes with a recorder control for Settings. (**Q6**) |
| SPM packages | `project.yml` | The first `packages:` entries: SwiftTerm (#64) and KeyboardShortcuts (#45). Both pinned to an exact version and recorded in `THIRD_PARTY_NOTICES.md`. |
| Entitlement | `App/*.entitlements` | Add `com.apple.security.personal-information.calendars`. Hardened Runtime needs it for EventKit, and it covers reminders too. The Info.plist usage strings for calendars, reminders and location are already there. |

## 3. Tabs: fitting under the cap (Q2)

**Recommendation: four module tabs, merging the date-related modules into one "Today" tab.**

| Tab | Modules that fill it | Notes |
|---|---|---|
| Island | (existing) | Activities and Home. The colour picker lives in Home's tools row, so it needs no tab. |
| AI | ClaudeCode (M4a) | unchanged |
| Clipboard | Clipboard | |
| Today | Weather (header strip), Calendar (agenda), Reminders (list) | Like the Today view on Apple's platforms. Each section appears only if its module is on; if none are on, there is no tab. |
| Terminal | Terminal | |

The modules stay separate: each has its own toggle, permission, settings pane and zero-cost-when-off behaviour. Only the tab is shared. That needs a small addition to the tab framework: a **shared tab with sections**. Each module calls `setTabSection(_:in: "today", order:)` through its sink, and the coordinator builds the "Today" tab from the sections it has. Ordering and dedupe stay in the pure `ExpandedTabs.arrange`, extended and unit-tested. ADR-0020 gets an amendment (ADR-0024).

### 3.1 What the Today tab shows

The expanded island is about 400 × 160 pt, so the tab has to be laid out for that space, like the "Up Next" and Reminders widgets rather than the full apps:

```
┌──────────────────────────────────────────────────┐
│ ☀︎ 14°  Sunny · H 17° L 8° · Bristol    11 12 13 14 │  weather strip, ~36 pt
│                                          ☀︎  ⛅︎ ⛅︎ 🌧 │  (the next 4–6 hours)
├────────────────────────┬─────────────────────────┤
│ CALENDAR               │ REMINDERS               │
│ ▍10:00 Stand-up [Join] │ ○ Call Sam   overdue    │  two columns,
│ ▍13:30 Lunch with Ana  │ ○ Submit essay  17:00   │  ~3 rows each
│ ▍Tomorrow 09:00 Lab    │ ○ Buy milk              │
│   2 more               │   4 more                │
└────────────────────────┴─────────────────────────┘
```

- **Weather strip** on top: the condition symbol, temperature, condition, high/low and place, then the next 4–6 hours as small symbol + temperature cells.
- **Calendar column**: the next events for today, then tomorrow under a "Tomorrow" label. Each row has the calendar's colour bar, the time, the title and a **Join** button when there's a meeting link. "2 more" opens Calendar.
- **Reminders column**: overdue first (red time), then today, each with a checkbox (8 s undo). "4 more" opens Reminders.
- **What adapts:**
  - With only one of Calendar and Reminders on, that column takes the full width and gains a location/notes line.
  - With Weather off, the columns get the strip's height (one more row each).
  - With only Weather on, the tab shows the full hourly row (12 hours) and the high/low.
  - Empty states are one quiet line: "No more events today", "Nothing due today".

Alternatives:
- **B. One tab per module, and the layout editor picks which four appear.** No framework change, but "every tab enabled" doesn't fit, and some module tabs are silently hidden.
- **C. Raise the cap to seven with icon-only segments.** Seven glyphs at about 48 pt each fit 371 pt, but the bar loses its labels, which the HIG prefers for tab bars, and it's a crowded bottom row on a 160 pt-tall island.

## 4. Modules

### 4.1 #55 Colour picker (`colorpicker`)

- **Data source.** `NSColorSampler().show { color in … }`. Public, and needs no Screen Recording permission.
- **Permission.** None. **On by default** (it does nothing until clicked).
- **Presence.** A `HomeAction` ("Pick Colour", `eyedropper`) in Home's tools row. Clicking it collapses the island first, so the loupe isn't covered, then starts the sampler. The result opens the action's Home panel:
  - a large swatch
  - three rows, HEX / RGB / HSL, each with a glass copy button (a `.symbolEffect(.bounce)` checkmark on copy)
  - a "Recent" row of up to **12** swatches; clicking one re-selects it
- **No activity and no compact presence.** A short banner "Copied #3A7BFF" on copy is optional: off by default, because the checkmark already confirms it.
- **Colour space.** The sampler returns the screen's colour space, usually Display P3. Convert to **sRGB** for HEX/RGB/HSL, because that's what the web and design tools expect. An out-of-gamut colour is clamped, with a small "outside sRGB" note.
- **Reducer.** `ColorPickerReducer` handles recents (add to the front, dedupe on the 8-bit sRGB value, cap at 12, clear). `ColorFormat` converts HEX/RGB/HSL: round-trips, rounding, clamping and hue at 0/360. Both are pure and tested.
- **Persistence.** Recents in `SettingsStore` (`colorPicker.recents`, JSON, capped). Bad data falls back to empty.
- **States.** Cancelled sampler (Esc): nothing changes.

### 4.2 #45 Clipboard history (`clipboard`)

- **Data source.** Poll `NSPasteboard.general.changeCount` through `RefreshScheduler` every 0.5 s with `when: .always` and `scalesWithPower: true` (so 1 s on battery and 2 s in Low Power Mode). The work is one integer compare when nothing changed. The pasteboard is read only when the count changes.
- **Skip rules**, checked on the item's types before any content is read:
  - `org.nspasteboard.ConcealedType`, `TransientType` and `AutoGeneratedType`
  - `com.agilebits.onepassword` and the other markers password managers use
  - the user's **excluded apps** (by bundle ID). The source app is `NSWorkspace.frontmostApplication` at the moment of the change; that's a heuristic, and the pane says so.
  - our own copy-backs (we remember the `changeCount` we wrote)
- **Item kinds**, with their type icons:

  | Kind | Symbol | Stored |
  |---|---|---|
  | text | `text.alignleft` | up to 1 MB |
  | URL | `link` | the URL |
  | file | `doc` | file URLs as references, never the files |
  | image | `photo` | PNG, longest edge capped at 2048 px, ≤ 5 MB, plus a 128 px thumbnail |

- **Storage.** `~/Library/Application Support/me.rkck.Notched/Clipboard/`, folder mode 0700 and files 0600. Recommendation: **a JSON index plus image files**, written atomically and debounced. A few hundred items need no database, the store has no dependencies, and it can be tested with plain `swift test`. The ROADMAP suggests SwiftData or SQLite, so this deviates. (**Q4**)
- **Retention.** History length 50 / 100 / 200 / 500 (default **200**); pinned items don't count and are never evicted. "Clear on quit" is off by default. Also a "Clear History" button. (**Q4**)
- **The tab.**
  - A search field at the top that filters as you type, case- and diacritic-insensitive.
  - Pinned items first, then newest first.
  - Each row shows the type icon, a one-line preview (or a thumbnail), the source app's icon, and a relative time.
  - **Click** copies the item back and collapses the island. **Right-click** offers Pin/Unpin and Delete.
  - Arrow keys and Return work once the panel has focus.
- **Hotkey.** Default ⌘⇧V, recordable. It opens the island expanded on the Clipboard tab with focus in the search field. **⌘⇧V is "Paste and Match Style" in many apps**, so the default may be a bad idea. (**Q6**)
- **No auto-paste.** Copy back only. Pasting needs `CGEvent.post` and Accessibility, so it isn't built (it would be an opt-in for M6 if wanted).
- **Compact presence.** None. A copy is not an activity.
- **Pasteboard privacy (macOS 26+).** macOS can ask the user before an app reads the pasteboard. Reading `changeCount` never prompts, but reading contents may. **This has to be checked on 27.2 before building**: whether a background agent gets one prompt or one per read, and which `NSPasteboard` access-behaviour API reports it. The first build step is a spike. Onboarding and the pane explain the prompt; if access is denied, the tab says "macOS isn't letting Notched read the clipboard" and links to the setting.
- **Reducer.** `ClipboardReducer` takes events `observed(change: Int, item: ClipboardCandidate?, source: String?)`, `copyBack(id)`, `pin`, `delete`, `clear`, `quit` and `settingsChanged`. It covers dedupe (the same content moves to the top rather than duplicating), the skip rules, the own-write echo, eviction around pins, the length change, clear on quit, and that the first observation at start is silent (the clipboard at launch isn't a new copy). There is a **fuzz test** for the invariants: count ≤ limit + pins, no duplicate content hashes, pins never evicted. `ClipboardSearch` is pure and tested, which also covers the "clipboard dedupe" test CLAUDE.md asks for.
- **Never log contents.** Only kinds, sizes and counts.

### 4.3 #48 + #49 Calendar and Join (`calendar`)

- **Data source.** `EventStoreService` with `predicateForEvents` from now to the end of tomorrow, refetched on `EKEventStoreChanged`, on wake, and at local midnight (a wake effect). No polling.
- **Permission.** `.calendars`, full access, requested when the module is turned on. The module waits for an answer before fetching.
- **Filters.** Declined events (the user's own participant status) and cancelled events are hidden. All-day events show in the agenda but never start a countdown. There's an optional per-calendar exclusion list in the pane.
- **Compact presence.**
  - **Countdown.** When the next timed event starts within **15 min** (5 / 10 / 15 / 30 in Settings), post a `.live` activity:
    - leading: a calendar glyph tinted with the calendar's colour
    - trailing: "in 12m", then "now"; whole minutes only, redrawn once a minute (the `CallClock` lesson from M3b)
    - minimal: the minutes number
  - **Alert.** An alert expansion **1 min before start**: the title, the time, and the **Join** button when the event has a link.
  - **During the event.** The activity says "now" for the first 5 minutes of the event, then ends. It is hideable.
- **Join (#49).** `MeetingLinkDetector` is pure and tested. It finds the first meeting URL in the event's URL, then location, then notes, matching:
  - Zoom: `zoom.us/j/`, `zoom.us/my/`, `*.zoom.us/…` and `zoommtg://`
  - Google Meet: `meet.google.com/xxx-xxxx-xxx`
  - Teams: `teams.microsoft.com/l/meetup-join/`, `teams.live.com/meet/`
  - Webex: `*.webex.com/…/j.php`, `*.webex.com/meet/`

  It ignores Google's "Join with Google Meet" boilerplate lines that aren't links, and links in quoted reply text. Clicking Join opens the URL with `NSWorkspace`, so the right app (or the browser) handles it.
- **The "Today" section.** The agenda for today and tomorrow. Each row shows the calendar-colour bar, time (or "All day"), title, and a location line, with a glass **Join** button on rows that have a link. Past events today are dimmed. Click opens the event in Calendar (`ical://` with the event identifier). If the list is empty: "No more events today".
- **Reducer.** `CalendarReducer` decides the next eligible event, when the countdown starts, the alert at T−1 min, the end rule, the midnight roll-over, the event moving or being deleted mid-countdown, wake after sleep past the start, and edits that change a calendar's colour. Wakes are effects (one `OneShotTimer`).

### 4.4 #50 Reminders (`reminders`)

- **Data source.** `EventStoreService.fetchReminders(matching: predicateForIncompleteReminders(…ending: end of today))`, which is async. Refetched on `EKEventStoreChanged`, on wake and at midnight.
- **Permission.** `.reminders`, full access, requested when the module is turned on.
- **The "Today" section.** Overdue reminders (red due time), then today's, sorted by due date and then priority. Each row shows a round checkbox, the title, the due time and the list's colour dot. Click on the title opens Reminders (`x-apple-reminderkit://`). Long lists collapse to "6 more".
- **Completing with undo.** The checkbox fills at once and the row shows **Undo** for 5 s. The write to EventKit (`isCompleted = true`, `save(_:commit:)`) happens **when the 5 s run out**, so an undo never has to reverse a change that has already synced to iCloud. Quitting during the 5 s commits it. (**Q7**)
- **Due-soon banner.** Optional, off by default: "Due in 15 min: Call Sam", through a `BannerSource` (once per reminder, cooldown so a batch doesn't spam). Banners only, no activity.
- **Reducer.** `RemindersReducer` handles the list, the overdue/today split across midnight, pending completions (the 5 s deadline, undo, store changes arriving while a completion is pending, quit), and that the due-soon banner fires once per reminder. A fuzz test checks that a pending completion is either committed or undone exactly once.

### 4.5 #51 Weather (`weather`)

- **Data source.** **Open-Meteo**, with no key and HTTPS through `URLSession`:
  - forecast: `api.open-meteo.com/v1/forecast` with `current=temperature_2m,weather_code,is_day`, `hourly=temperature_2m,weather_code,precipitation_probability` for the next 12 h, and `daily=temperature_2m_max,temperature_2m_min`, `timezone=auto`
  - manual city: geocoding at `geocoding-api.open-meteo.com/v1/search`
  - The request sends only the latitude/longitude, rounded to 0.1° (about 11 km): enough for weather, and less precise data sent away.
- **Location.** (**Q3**) Recommendation: on first enable, the pane offers **"Use My Location (Approximate)"** and **"Choose a City"**, neither pre-selected. If Location is denied or unavailable, it falls back to the manual city and says so. With manual mode, Location is never asked.
- **Refresh.** Every 30 min through `RefreshScheduler` (power-scaled), plus on wake if the data is older than 30 min, and when the network comes back. No refresh while the screen is locked or asleep. The last result is cached to disk (`weather.cache`, JSON) so the island isn't empty after a relaunch.
- **Units.** From the system: `Locale.current.measurementSystem` and the temperature unit preference (`UnitTemperature(forLocale:)`), with an override in the pane.
- **Compact presence.** Optional, off by default: a `.passive` activity with the condition symbol and "14°". It's passive, so it never takes the island from media or a live activity (ADR-0011, `RankingPolicy`), and it shows only when nothing else is primary.
- **The "Today" section.** A header strip:
  - large condition symbol (multicolour SF Symbol, day/night variant from `is_day`) and temperature
  - condition text and H/L
  - a horizontally scrolling row of 12 hourly cells: time, symbol, temperature, and precipitation % when ≥ 20%
- **Offline and stale.** With no network, the cached values show with "Updated 2 h ago" and a `wifi.slash` glyph. Older than 6 h, the temperature is dimmed and the compact activity ends (its `staleDate`). The first fetch failing with nothing cached shows "Weather isn't available right now".
- **Pure parts, tested.**
  - `WeatherCode`: WMO code to SF Symbol and localisable text, with day/night variants
  - `OpenMeteoParser`: fixtures saved from real responses, malformed JSON, missing fields
  - `WeatherReducer`: the refresh schedule, backoff after errors (1, 5, 15, then 30 min), staleness, location changes, offline/online, and that the cache is used at start
- **Attribution.** Open-Meteo's data is CC BY 4.0, so the pane and the About pane carry "Weather data by Open-Meteo.com" with a link.

### 4.6 #64 Terminal (`terminal`)

- **Data source.** **SwiftTerm** (MIT) `LocalProcessTerminalView`, wrapped in `NSViewRepresentable`. The shell is `$SHELL` (falling back to `/bin/zsh`), started as a login shell (`-l`) with `TERM=xterm-256color` and the user's login environment. The working directory is `~`.
- **Permission.** None. Off by default.
- **Lifetime.** (**Q5**) Recommendation:
  - The shell starts the first time the Terminal tab is shown, not when the module turns on. Turning the module on costs nothing until it's used.
  - The shell **stays alive while the island collapses** (like a drop-down terminal), so `vim` survives a collapse.
  - It ends when the module turns off, on quit, with an "End Session" item in the tab's menu, or when the shell exits; showing the tab again then starts a new one.
  - Cleanup sends `SIGHUP` to the process group, then `SIGKILL` after 2 s, and `waitpid`s, so no orphans. Verified with `ps` (and `applicationWillTerminate` is the backstop).
- **Key focus.** This is the risky part; ADR-0025 records it.
  - The panel may become key **only while the island is expanded and the Terminal tab is selected**, and only after a click in the terminal. It never takes focus on hover, which matches `takeKeyFocus()`. On collapse, on a tab change and on Esc, it calls the existing `giveBackKeyFocus()`, which re-activates the user's previous app.
  - **Esc collapses.** That means Esc never reaches the shell, which breaks `vim`. Recommendation: plain Esc goes to the terminal while it has focus, and **⌘Esc** (or ⌘W) collapses, with the shortcut shown in the tab's empty corner. This contradicts the ROADMAP/prompt ("Esc collapses"), so it's a question. (**Q5**)
  - Ctrl+C, Ctrl+D, Tab and ⌘V (paste) go to the shell. ⌘1–⌘5 and ⌃Tab still switch tabs (ADR-0020's key map); ⌘C copies the selection.
  - **Hover.** While the terminal has key focus, or within 3 s of the last keystroke, pointer exit doesn't collapse the island. A **Pin Open** toggle in the tab keeps it open until it's unpinned or Esc/⌘Esc is pressed. Both feed the `HoverStateMachine` as a new `holdOpen` input (pure and tested).
  - The terminal never steals focus from another app while collapsed: the audit list goes in ADR-0025, with a test on the focus reducer.
- **Size.** The expanded island is at most about 408 × 160 pt, which is small for a terminal (about 60 × 9 cells at 11 pt SF Mono). Recommendation: the Terminal tab asks for a **taller expanded size** (about 408 × 300), and the font size can be set in Settings. Resizing the island resizes the PTY (`SIGWINCH` through SwiftTerm). This needs the tab host to allow a per-tab height override. (**Q5**)
- **Reducer.** `TerminalFocusReducer` handles: may the panel be key; hold-open; pin; which key collapses; and process lifecycle intents (start, end, ended unexpectedly). The process handling itself isn't a reducer; it's covered by an integration test that starts `/bin/sh -c 'sleep 30'` and checks it's gone after stop.
- **Attribution.** SwiftTerm goes in `THIRD_PARTY_NOTICES.md` (MIT) through SPM, not vendored.

### 4.7 #71 Layout editor (Settings ▸ Layout)

The prompt says to reuse M3b's priority settings rather than duplicate them. So this pane **replaces the Priority pane** and keeps its data, adding tab order.

- **Compact.** A drag-and-drop list of the modules that can show compact activities, top to bottom. It is `RankingPolicy.pinned` plus `order` presented as one list:
  - "Always first: Calls" is fixed at the top.
  - Then the modules the user has dragged into "Pinned".
  - Then the class order (Now Playing / Timers & tools / Status).

  Each module row has a **Show in Compact** toggle. Off means that module's activities are listed in the expanded view only, never compact or minimal, except non-hideable system ones (ADR-0016's rule stays). Stored as `RankingPolicy.listedOnly: [ModuleID]`, a new field with a migration from saved JSON (missing = empty).
- **Expanded tabs.** A drag-and-drop list of the available tabs (AI, Clipboard, Today, Terminal) with a visibility toggle each. Stored as `SettingsStore.tabOrder` (`tabs.order`, `[TabID]`), which `ExpandedTabs.arrange` uses ahead of each tab's own `order`. Unknown IDs are ignored, and new tabs go at the end.
- **Live preview.** A scaled `IslandRootView` fed by a fake coordinator with sample activities (music + timer + a calendar countdown), showing compact on top and the expanded tab bar below. It reacts to changes immediately. It's built from the existing preview fixtures, so no live data is involved.
- **Reset to Default.** Restores `RankingPolicy.default`, the default tab order and all compact toggles, after a confirmation.
- **Reducer.** The pane's logic is the pure `LayoutModel` (move, toggle, reset, normalise against the available modules and tabs), with tests, including round-tripping old Priority JSON.

## 5. Build order and steps

Unchanged from the prompt, with Today's framework work folded into Calendar's step:

| Step | What | Model / effort |
|---|---|---|
| 1 | #55 Colour picker | Sonnet, medium |
| 2 | #45 Clipboard (spike the privacy prompt first) | Sonnet, medium |
| 3 | Shared "Today" tab + EventStoreService + #48/#49 Calendar | Sonnet, medium |
| 4 | #50 Reminders | Sonnet, medium |
| 5 | LocationService + #51 Weather | Sonnet, medium |
| 6 | #64 Terminal | Sonnet, **high** |
| 7 | #71 Layout editor | Sonnet, medium |
| 8 | Settings panes, docs, ROADMAP, ADRs 0024–0026 | Sonnet, low |
| 9 | Fresh-reviewer pass | Opus, high |

After each step: build, test, install, screenshot, critique and commit (`feat(#55): …`). ADRs:
- 0024: clipboard storage and privacy (written with Step 2)
- 0025: shared tabs with sections, amending 0020
- 0026: terminal key handling
- 0027: weather location method

## 6. Verification

As in the prompt's Verify section, which all needs a Mac:
- screenshots to `docs/screenshots/m4b/`
- real use, including a password-manager copy that must be skipped and `vim`/`top` with resizing
- each permission denied
- offline weather
- sleep/wake
- switching every module on and off repeatedly
- `ps` for orphan shells
- `scripts/cpu.sh` per module

**Budget mismatch:** the prompt says memory < 150 MB, while CLAUDE.md says < 120 MB. I'll measure against **120 MB** (the stricter, binding one) unless Charlie says otherwise.

## 7. Questions for Charlie

1. **Where M4b gets built.** (a) Wait for the M4a Mac checklist and do M4b on the Mac (recommended, because M4b leans on M4a's untested tab host, and step 2 starts with a pasteboard spike that only a Mac can run), or (b) write M4b here on Linux, with only the pure logic tested, and run one combined M4a+M4b checklist later.
2. **The tab cap.** Shared "Today" tab (recommended), layout-editor-chooses-four, or seven icon-only tabs?
3. **Weather location.** Offer both choices on first enable (recommended), or default to manual city only?
4. **Clipboard.** JSON index + image files (recommended) or SQLite/SwiftData? Default history 200, pins exempt, clear-on-quit off: OK?
5. **Terminal.**
   - Should the shell persist across collapses? (Recommended yes.)
   - Should plain Esc go to the shell, with ⌘Esc collapsing? (Recommended, because otherwise `vim` is unusable; this contradicts the spec.)
   - May the Terminal tab make the island taller (about 300 pt)?
6. **Hotkey.** Is KeyboardShortcuts (SPM, MIT) OK? Keep ⌘⇧V as the default despite the "Paste and Match Style" clash, or pick another?
7. **Reminders undo.** Commit after the 5 s undo window (recommended) or at once and revert on undo?
8. **Layout editor.** Should it replace the Priority pane (recommended, so there's one place for it), or sit beside it?

## 8. Charlie's answers (31 Oct 2026)

These override the sections above where they differ.

1. **Build M4b on the Mac**, after the M4a checklist. Nothing more is written in the Linux session.
2. **Today tab:** asked what it shows. §3.1 was added in reply, and it waits for his confirmation.
3. **Weather location: "Choose a City" is the default on first enable.** "Use My Location (Approximate)" is an opt-in in the pane. When it's on, it's a single `requestLocation()` with reduced accuracy, **at most once a day** (on the first refresh of the day, or on wake if the last fix is over 24 h old), and Location stays idle the rest of the time. If it's denied, the module goes back to the city. The 30-minute forecast refresh is one small HTTPS request and doesn't touch Location.
4. **Clipboard: least computing power.** Decided:
   - **Storage:** a JSON index plus image files. No database engine and no background work. The index is written only after a change, debounced 2 s, and atomically.
   - **Reads:** the `changeCount` poll is one integer compare per tick, and the pasteboard is read only when the count changes.
   - **Images and search:** thumbnails are made once, when an image is copied. Search filters the in-memory list only while the tab is showing.
   - **Defaults:** 200 items, pins exempt, clear on quit off.
5. **Terminal: yes to all three.**
   - The shell persists across collapses.
   - Plain Esc goes to the shell, and ⌘Esc collapses.
   - The Terminal tab may make the island about 300 pt tall.
6. **Hotkey:** KeyboardShortcuts, default ⌘⇧V.
   - It's changeable (a recorder in the Clipboard pane) and can be turned off.
   - The history is always reachable without it: through the Clipboard tab, and through a **Clipboard History** item in the status menu that opens the island on that tab.
7. **Reminders undo: 8 s.** The completion is written when the 8 s run out, and quitting during the window writes it.
8. **The layout editor replaces the Priority pane.** It must be intuitive:
   - two clearly titled sections, "Compact Island" and "Expanded Tabs"
   - plain-language row labels and a footer sentence under each
   - drag handles plus Move Up/Down in the context menu, so drag isn't the only way
   - the live preview above both sections
   - Reset at the bottom
