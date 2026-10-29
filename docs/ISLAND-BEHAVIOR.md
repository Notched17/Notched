# Island behaviour spec: iPhone Dynamic Island parity

Goal: Notched should *behave* like the iPhone Dynamic Island, not just look like it. Several live things can run at once (music, a timer, Claude Code working, a call), the island shows the most important one, keeps the others visible as small bubbles, briefly expands for important updates, and returns to what it was showing.

Sources:
- `docs/research/ios-dynamic-island.md`: what iOS does, with Apple citations.
- `docs/research/mac-live-activity-sources.md`: which events a Mac app can actually detect.

Where Apple documents nothing (alert durations, cross-app ordering, spring values), this spec makes a decision and marks it **[decision]**. Tune these by eye.

---

## 1. Presentations

| Presentation | When | What it shows | iOS equivalent |
|---|---|---|---|
| **Idle** | No live activity | Nothing beyond the hardware notch (pure black, invisible). On non-notch displays, a small pill or nothing (setting). | The island at rest |
| **Compact** | Exactly one visible activity | **That activity's** leading view (left of the notch) and trailing view (right of the notch). They read as one piece of information. | Compact |
| **Compact + minimal** | Two or three visible activities | The **primary** activity stays attached, shown either as full compact or reduced-width compact (see §3). The others show as **minimal** bubbles: small black circles or ovals detached from the island by a small gap, each showing live data such as a countdown, never just a logo. | Minimal / reduced-width compact (iPhone 18 Pro) |
| **Expanded** | Hover, the Mac's "touch and hold" (existing hover delay). Hovering a minimal bubble expands **that** activity. | The activity's expanded layout (§4), wrapping tightly around the camera housing. | Expanded on long-press |
| **Alert expansion** | An activity update marked as an alert, or a new high-priority activity | The island expands to that activity's expanded view for a few seconds, then returns to the previous presentation. | Expanded on an alerting update |
| **Transient banner** | Short system events: charging, Caps Lock, Bluetooth connected, volume/brightness (M3b Part B) | A "wide compact" banner (icon leading, short text or value trailing). It pre-empts the current compact view for 1.5–2.5 s **[decision]**, then restores it. It doesn't take a minimal slot. A volume or brightness HUD is a banner too, but it never waits: it replaces whatever banner is up (which resumes after it), and it only takes the key while the island can show it (not expanded under the pointer, no alert showing, not paused or hidden), otherwise macOS keeps the key. | Charging, silent switch, AirPods connect, volume keys |
| **Home** | Hover with nothing live | The current expanded "home" view: date and time header, quick actions, and later calendar and weather. Mac-only addition (iOS has no idle expansion). | — |

**Never** split compact slots across activities: leading and trailing always come from the same activity. The current M1 coordinator does split them, and must change.

## 2. Activity model

```swift
struct LiveActivity {
  id, moduleID
  kind: .system | .media | .live | .passive   // ranking class, highest first
  relevance: Double                            // within class; higher wins, ties → started first
  isHideable: Bool                             // false for call, screen recording
  state: .active | .stale | .ended(dismissAt) | .hidden
  staleDate: Date?                             // past it, the activity renders an "outdated" look
  alert: AlertRequest?                         // one-shot: expand for N s (default 4 s [decision]); optional sound
  openAction: (() -> Void)?                    // click = "tap": open the source app or perform the default action
  presentation: ActivityPresentation           // see §4
  accessibilityLabel: String                   // updated with state
}
```

The same activity id updates in place, and keeps its position and slot. An alert on update triggers alert expansion.

### Ranking (attached vs minimal) [decision, Apple doesn't document cross-app order]

1. **Class:** `system` (call, screen recording, navigation-like) > `media` (whatever is playing) > `live` (timer, Claude Code working, keep-awake, download, camera/mic indicator) > `passive` (charging). Whatever is playing keeps the attached island; the user's own timers and tools show as bubbles beside it (ADR-0011, M3a). **The user can change this** (Settings ▸ Modules ▸ Priority, ADR-0016): `system` is always first, then modules the user pinned, then their own order of media, live and passive.
2. Within a class, higher `relevance` wins. On a tie, the activity started first wins: it's stable, and newer ones don't steal the island.
3. The user overrides: **swap** (clicking a minimal bubble makes it primary; a two-finger horizontal swipe on the compact island cycles), and **hide** (swipe up on an activity, or a context-menu "Hide"). Hiding an activity doesn't end it; it stays listed in the expanded view's activity list and can be restored. System activities that aren't hideable ignore hide. **An activity that isn't hideable is never left hidden** (one that becomes non-hideable, like the camera indicator when the camera turns on, comes back) **and always takes one of the three visible slots**, ahead of better-ranked hideable ones, so it can't end up only in the list (ADR-0016).
4. A user's swap is sticky until either activity ends or a new `system` activity arrives.

### Lifecycle

`active → stale` (stale date passed: dim the content and show an "updating…" hint) → `ended`. An ended activity disappears from the island **immediately**, matching iOS. It stays in a "Recent" section of the expanded list until its dismissal time (default 15 min, max 4 h) **[decision]**. Modules can request dismissal immediately or after a set time.

## 3. Multiple activities: layout on the Mac

- **One activity:** full compact. Leading and trailing hug the notch with no padding against the camera housing, and are similar in width (HIG).
- **Two activities:**
  - Primary in compact (reduced width if needed to respect the width budget).
  - Secondary as a minimal bubble on the **trailing** side, detached by a 6 pt gap **[decision]**. The bubble "buds off" the island when it appears: a spring scale from the island edge, optionally with a short metaball/goo bridge. Build the goo bridge only if it looks native and costs nothing when idle.
- **Three activities:** a second minimal bubble on the leading side **[decision]**. Never more than three visible; the rest are only listed in the expanded view.
- **Width budget:** total compact width (bubbles included) ≤ notch width + 2 × 90 pt **[decision]**, so app menus and status items beside the notch stay usable. Click-through outside the drawn shapes still applies.
- **Setting:** "Multiple activities: Bubbles (iPhone) / Side-by-side (iPhone 18 Pro style)". Side-by-side uses reduced-width compact views for both activities, with no detached bubbles.

## 4. Presentation template (replaces free-form `AnyView` content)

Modules supply views for named regions. The island owns layout, sizing and animation, so every activity looks consistent and fits the hardware:

| Region | Size (Mac points, from the iOS spec) | Rules |
|---|---|---|
| `compactLeading` / `compactTrailing` | ≤ 64 × notch height each | Medium weight or heavier, one glyph or a short value. Snug against the notch. If trailing is empty, it hides automatically. |
| `minimal` | 28–45 wide × notch height | Live data (countdown, progress ring), not just a logo. Must fit a 28 pt circle when limited. |
| `expanded.leading` / `.trailing` | Beside the camera housing, equal widths by default | Wraps below the housing if tall. |
| `expanded.center` | Below the housing | Sized first. |
| `expanded.bottom` | Full width below everything | Controls and progress bars. At most one primary interactive control (HIG). |
| Expanded overall | 371–408 wide × content up to ~160 tall (plus the header row) | Height follows content. Truncate past the maximum. |

Implement a custom SwiftUI `Layout` for the expanded regions that follows Apple's algorithm:
1. Size the center region first, keeping the minimum widths of leading and trailing.
2. Leading and trailing then share the rest equally.
3. A region `priority` makes that region full width.
4. A `.belowIfTooWide` option drops leading content below the camera housing.

**Keyline:** an optional subtle tinted border (`keylineTint`, per activity). Show it on expanded views and minimal bubbles when the background behind them is dark. Never draw it on the idle notch.

## 5. Motion (the island controls it; modules don't animate themselves)

- **Shape:** one continuous black shape that morphs, with springs from `DesignSystem/Motion` on frame and corner radii. Minimal bubbles bud off and merge back. Apple's own description: "a living organism, with a deliberate elasticity".
- **Content:** a module's `withAnimation` is ignored, as on iOS. The island applies:
  - `.blurReplace` for swaps
  - `.contentTransition(.numericText(countsDown:))` for numbers
  - `.symbolEffect` for SF Symbols
  - opacity, move or push for views that come and go

  Any content animation lasts at most 2 s. Elements that persist animate to their new positions instead of fading out and in.
- **Alert expansion:** expand spring → hold → collapse spring back to the previous presentation. The current single bounce stays for transient banners.
- **Concentric layout:** inner rounded shapes nest inside the island with even margins (use `ContainerRelativeShape`). No "forehead": content hugs the camera housing.
- **Accessibility:** Reduce Motion swaps morphs and budding for quick cross-fades, and Reduce Transparency means no glass. Each activity is one accessibility element whose label combines its leading and trailing content and updates when they change.

## 6. Interaction map (iPhone → Mac)

| iPhone | Mac |
|---|---|
| Tap compact or minimal → open the app | **Click** compact → `openAction` (open the source app, e.g. Music; for timers, a sensible default). Click a minimal bubble → make it primary. |
| Touch and hold → expanded | **Hover** (existing delay) → expanded for the hovered activity |
| Swipe inward → hide | Two-finger swipe up on the compact island, or right-click → Hide |
| Swipe primary onto secondary → swap | Two-finger horizontal swipe on the compact island cycles the primary activity |
| — | In the expanded view, a horizontal swipe or a page indicator moves between all live activities, plus Home |
| Tap outside → collapse | Pointer leaves → collapse (existing). Esc collapses. |

## 7. What the Mac can and can't show (from the research)

| iPhone island item | On Mac | Plan |
|---|---|---|
| Now Playing | Yes (private MediaRemote via mediaremote-adapter) | M2 |
| Timer | Our own timers: yes, public. The Clock app's timers: private routes only (Atoll's `SystemTimerBridge`, GPL, adaptable). | Recommend adding #37 timers to M3. Clock-app mirroring is experimental and later. |
| Calls (FaceTime, Zoom, Teams, Phone via iPhone) | "In a call" + duration via Core Audio per-process mic use + known call apps (public, heuristic). Caller name and ringing: no reliable route. No Mute/End (no public route). The call owns its mic and camera, shown as dots on it. | M3b: built, simulated-tested (ADR-0017) |
| Screen recording | Detection yes: private SkyLight notify types 1502/1503, no permission (ADR-0014). Stop: only for `screencapture -v`; ⌘⇧5 ignores SIGINT. | Deferred |
| Camera / mic in use | Yes (public); names only apps it can prove | M3b: built (#31), `.live`, not hideable while the camera is on |
| Downloads | Yes (FSEvents on `~/Downloads`, partial-file names, progress xattr); needs Files & Folders | M3b: built (ADR-0018) |
| Charging, AirPods connect, Caps Lock | Yes | M3a, as transient banners |
| Focus | Only through an App Intents Focus Filter the user adds to each Focus. The DND notifications and `INFocusStatusCenter` don't work on 27.2 (ADR-0015). | Dropped from M3b |
| Lock / unlock | Yes (distributed notifications) | Used by M6 lock-screen features |
| **Maps turn-by-turn** | **No.** Mac Maps has no live navigation. Tahoe shows the iPhone's Live Activities in the menu bar, but no API lets another app read them (only an untested Accessibility scrape). | Not possible. Don't build it; at most a later experiment. |
| Other apps' Live Activities (Uber, sports, flights) | No public route | Sports scores via a web API could be a later module |
| Face ID, Apple Pay | No detection route on Mac | — |
| Claude Code | Yes (hooks → local socket or HTTP) | M4 (#62/#63) |
| Third-party pushes | Our own API: URL scheme + localhost-only endpoint with per-client tokens (+ optional XPC) | M4: "Activity API". Claude Code hooks use it too. |

## 8. Gap analysis of the M1 code (reviewed 27 Oct 2026)

**Already right:**
- The idle island is invisible black.
- One continuous morph.
- Hover expansion with a delay.
- Transient activities expire and restore the previous state without polling.
- Bounce on new alerts.
- Activities are scoped per module.
- Reduce Motion, Reduce Transparency and Increase Contrast are handled.
- The header reserves the camera-housing gap.

**Must change for iPhone parity:**
1. `ActivityCoordinator` fills leading and trailing from *different* activities. Change it to one primary activity owning compact, with others as minimal (§1, §2).
2. There's no minimal presentation or detached bubbles (§3).
3. Alerts only take the compact slots and bounce. Add alert expansion (§1), and a separate transient-banner path for short system events.
4. The expanded view only shows the top-ranked activity. Hovering should expand the hovered activity, with swipe or paging between all activities and Home (§6).
5. Clicking the surface currently expands. Make a click perform the activity's `openAction`, and keep hover for expanding (setting: "Click to expand" for people without hover habits).
6. There's no hide, swap, relevance, stale, ended or Recent lifecycle (§2).
7. Expanded content is a free-form `AnyView`. Move to the region template (§4) so modules can't break the layout, and so the island owns animation (§5).
8. `ActivityPriority` needs a `system` class and a `relevance` tiebreak; transient banners leave the priority ladder entirely.
