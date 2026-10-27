# iOS Dynamic Island behaviour (as of iOS 27 / macOS 26–27, October 2026)

Scope note: Primary sources are Apple's HIG "Live Activities" page (change log shows a revision on **October 13, 2026**) and the ActivityKit/WidgetKit docs, both read live in October 2026. Apple documents the *Live Activity* (third-party) model in detail. It does **not** publish a spec for first-party system alerts (Face ID, AirDrop, charging and so on), animation curves or alert durations. Those sections lean on secondary sources and are flagged.

---

## 1. Presentations: compact, minimal, expanded, alert expansion, and the API surface

### Takeaway
The island has four Live Activity presentations: compact (leading + trailing around the camera, used when one activity runs), minimal (used when several run), expanded (on touch-and-hold, or briefly on an alerting update) and Lock Screen. In the island the background is always opaque black and only the keyline tint can be customised. Expanded content is laid out in four regions (leading, trailing, center, bottom). iOS 27 adds a "limited width" mode (28pt circle) for landscape, "iPhone Duo" and iPhone 18 Pro multi-activity layouts.

### Cited Findings
**Presentation definitions (HIG, rev. Oct 13 2026)**
- "In the Dynamic Island, the system uses the compact presentation when only one Live Activity is active. The presentation consists of two separate elements: one on the leading side of the TrueDepth camera and one on the trailing side." — [Apple HIG: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- "When multiple Live Activities are active, the system uses the minimal presentation to display up to three of them in the Dynamic Island. One appears attached to the Dynamic Island, while a second (and third, when supported) appear detached on one or both sides. Depending on its content size, a detached minimal presentation appears circular or oval." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- "people tap the minimal presentation to open its app or touch and hold it to see the expanded presentation." / "When people touch and hold a Live Activity in compact or minimal presentation, the system displays the expanded presentation." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- The expanded presentation "appears when a person touches and holds a compact or minimal presentation, and it also appears briefly for Live Activity updates." — [ActivityKit: Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Compact design rules: design leading and trailing "to read as a single piece of information"; "Keep content as narrow as possible and ensure it's snug against the TrueDepth camera… don't add padding between content and the TrueDepth camera. Maintain a balanced layout with similarly sized views for both leading and trailing"; "Ensure both leading and trailing elements link to the same screen." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Expanded: "The expanded presentation is an enlarged version of the compact or minimal presentation. Ensure information and layouts expand predictably"; "Wrap content tightly around the TrueDepth camera." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Minimal: show live data rather than a logo where possible ("the Timer app's minimal… displays the remaining time instead of a static icon"). — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)

**Dimensions (points, HIG "Specifications", Oct 2026)**
| Screen (portrait) | Compact (each of leading and trailing) | Minimal (width range) | Expanded (height range) | Lock Screen | Limited width |
|---|---|---|---|---|---|
| 430×932 | 62.33×36.67 | 36.67–45 × 36.67 | 408 × 84–160 | 408 × 84–160 | 28×28 |
| 393×852 | 52.33×36.67 | 36.67–45 × 36.67 | 371 × 84–160 | 371 × 84–160 | 28×28 |
— [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities). "macOS dimensions: Use the provided iOS dimensions." (same source). "The system may truncate a Live Activity if its height exceeds 160 points." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Image assets larger than the presentation size may cause the activity to fail to start. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

**Expanded regions (WidgetKit `DynamicIslandExpandedRegionPosition`)**
- `.center` "places content below the TrueDepth camera"; `.leading`/`.trailing` place content "along the leading/trailing edge… next to the TrueDepth camera and wraps additional content below it"; `.bottom` "places content below the leading, trailing, and center content." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Layout algorithm: "the system first determines the width of the center content while taking into account the minimal width of the leading and trailing content. The system then places and sizes the leading and trailing content based on its vertical position. By default, leading and trailing positions receive an equal amount of horizontal space." A region `priority` makes "the highest-priority view [render] at the full width of the Dynamic Island". `.belowIfTooWide` drops leading content below the camera. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- `DynamicIsland` (iOS 16.1+) API: `init(expanded:compactLeading:compactTrailing:minimal:)`, `widgetURL(_:)`, `keylineTint(_:)` ("subtle tint color to the surrounding border"), `contentMargins(_:_:for: DynamicIslandMode)`. — [WidgetKit DynamicIsland](https://developer.apple.com/documentation/widgetkit/dynamicisland)
- `contentMargins`: example `.contentMargins(.trailing, 8, for: .expanded)`. "If you repeatedly use the contentMargins modifier, the system uses the innermost specified values for a mode." — [Creating custom views for Live Activities](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities)
- Colour: "Live Activities in the Dynamic Island use a black background color with white text… You can't change the background color of Live Activities in the Dynamic Island." Keyline: "When the background is dark — for example, in Dark Mode — a key line appears around the Dynamic Island to distinguish it from other content." — [Creating custom views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities); [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)

**Limited width (new in iOS 27)**
- `isDynamicIslandLimitedInWidth` has availability **iOS 27.0+, iPadOS 27.0+, Mac Catalyst 27.0+**: "In some devices and context, the system adapts the flexible width of compact and minimal Live Activities and renders them smaller; for example, on iPhone in landscape orientation or on iPhone Duo." — [SwiftUI docs](https://developer.apple.com/documentation/swiftui/environmentvalues/isdynamicislandlimitedinwidth)
- Fit compact and minimal "inside a 28pt-diameter circle". If both leading and trailing can't be made to work, ship a leading view only and the "system automatically hides the trailing view" (an empty trailing view gets hidden). — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities); [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- WWDC26 "Live Activities essentials" (session 223): "in iOS 27, Live Activities are visible in the Dynamic Island, when in portrait and landscape… In portrait, compact views are flexible in width but in landscape, they don't have room to grow in width." — [WWDC26 session 223](https://developer.apple.com/videos/play/wwdc2026/223/)

**Transient style**
- "Live Activities can appear temporarily in the extended presentation in the Dynamic Island to allow interactions and status updates while a person is actively performing a task. Locking the device, collapsing the extended presentation in the Dynamic Island, or tapping outside the Dynamic Island ends the Live Activity." Example given: Music shows an extended presentation offering an AirPlay hand-off to a HomePod when playback starts, and it "ends automatically when the person leaves the app." Started via `request(attributes:content:pushType:style:)` with `ActivityStyle.transient`. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- The symbol page lists `ActivityStyle.transient` as iOS 16.1+ but has no description. — [ActivityStyle.transient](https://developer.apple.com/documentation/activitykit/activitystyle/transient)

### Inferences
- For a Mac notch app, the state machine can be modelled as: `idle` → `compact(L,T)` (one activity) → `multi` (attached + detached minimal(s)) → `expanded` (long-press or alert, transient) → `transient` (an expanded-only session that dies on outside click or collapse).
- The expanded layout model (center sized first, leading and trailing sharing the rest equally, bottom full width, an optional priority row) maps cleanly onto a custom SwiftUI layout.
- Heights 84–160pt and widths 371/408pt are useful default bounds for an expanded Mac panel. Apple tells Mac to "use iOS dimensions".

### Gaps
- Apple publishes no corner radius, idle-pill size or keyline width for the island.
- The `ActivityStyle.transient` availability label (16.1) looks like a doc artifact. Which iOS version actually introduced transient activities is unverified.

---

## 2. Multiple activities: primary vs minimal, 3+, swapping, tap vs long-press

### Takeaway
On most Dynamic Island iPhones, two activities show as one minimal view attached to the island plus one detached circle or oval. On iPhone 18 Pro (iOS 27), two activities show as reduced-width compact views and up to three can show at once. Reports say the third slot is reserved for a system activity. Within one app, `relevanceScore` (highest wins; ties go to the first started) picks which activity reaches the island. Across apps, Apple documents no ordering rule. Tap opens the app, touch-and-hold expands, and swipe gestures hide or swap activities.

### Cited Findings
- "When Live Activities from several apps are active, the number of visible Live Activities depends on the device. For example, iPhone 18 Pro displays two simultaneous Live Activities in the Dynamic Island that use the compact leading and trailing presentations with reduced width. On other devices, both activities appear in the minimal presentation. One active Live Activity appears attached to the Dynamic Island, and the activity from another app appears detached from it." — [ActivityKit: Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- "When several Live Activities are active, the system chooses how to present them… the system renders each one to best fit — attached to or detached from the Dynamic Island, and in the compact presentation, the compact presentation with reduced width, or the minimal presentation." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Reduced width occurs "on iPhone in landscape orientation, on iPhone Duo, or on iPhone 18 Pro with two or more active Live Activities." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Relevance score, within one app: "If you don't provide a relevance score or if Live Activities have the same relevance score, the system shows the first Live Activity you started in the Dynamic Island. If you use different relevance scores, the system shows the Live Activity with the highest relevance score in the Dynamic Island." Scores are relative (example: 100 vs 50) and can change with each update. The push payload key is `relevance-score`. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities); [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- iPhone 18 Pro (announced Sept 2026): smaller island, "up to three simultaneous Live Activities" (previously a maximum of two). — [MacRumors, 9 Sep 2026](https://www.macrumors.com/2026/09/09/iphone-18-pro-features-smaller-dynamic-island/); Apple press release quoted as "the Dynamic Island is redesigned to create room for additional information" — [Android Headlines](https://www.androidheadlines.com/2026/09/iphone-18-pro-smaller-dynamic-island-live-activities-upgrade.html)
- Gruber: the Face ID sensor moved under the display, so the cutout is "noticeably smaller", while the island is effectively bigger because iOS can now draw to the left of the cutout. — [Daring Fireball, 18 Sep 2026](https://daringfireball.net/linked/2026/09/18/iphone-18-pro-dynamic-island)
- With two activities on iPhone 18 Pro, the second shows more detail. Example: a timer next to media playback now shows "the remaining time" where before it "only showed a timer icon". — [9to5Mac, 22 Sep 2026](https://9to5mac.com/2026/09/22/iphone-18-pros-best-dynamic-island-feature-is-one-apple-barely-mentioned/)
- **Unverified (code explorer, not Apple):** "the third Live Activity in iOS 27 is only ever a system activity" (Now Playing, navigation), and "it can't be another app." — [MacRumors, 5 Oct 2026](https://www.macrumors.com/2026/10/05/iphone-18-pro-three-live-activities-dynamic-island/); [Neoteo](https://www.neoteo.com/en/iphone-18-pro-may-show-three-live-activities-in-dynamic-island). iOS 27 code reportedly enables the 3-up mode only when the sensor region is "less than 100 layout points wide" (16.57 mm, vs 20.76 mm on 17 Pro). — [MacRumors leak article](https://macrumors.com/2026/09/09/leaked-video-shows-iphone-18-pro-dynamic-island/)
- Other iOS 27 devices still cap at two. — [iThinkDifferent](https://www.ithinkdiff.com/how-to-use-live-activities-and-the-dynamic-island-on-iphone-18-pro/) (secondary)
- Gestures (iOS 16/17 era guides): swipe inward from either side hides the activity, and swipe outward (left, right or down) brings it back. With two activities, swiping the primary onto the secondary hides the primary and promotes the secondary. Swiping in from the secondary hides it, and swiping in again hides all. "you will only be able to use gestures to switch between two activities". Navigation and screen recording can't be hidden. — [Nerdschalk](https://nerdschalk.com/how-to-use-gestures-in-dynamic-island-on-iphone-14-pro/); dismissing doesn't stop the activity (music keeps playing) — [AppleInsider](https://appleinsider.com/inside/ios-17/tips/how-to-manage-activity-on-the-dynamic-island-in-ios-17)
- On iPhone 18 Pro, "Swipe across the Dynamic Island to move between up to three active Live Activities." — [iThinkDifferent](https://www.ithinkdiff.com/how-to-use-live-activities-and-the-dynamic-island-on-iphone-18-pro/) (secondary, unverified)
- One secondary source claims that with more than two running, the island shows "two of the most recently used apps". — [ArcTouch](https://arctouch.com/blog/dynamic-island.md) (old, unverified; contradicts nothing official but is not confirmed by Apple)
- HIG on per-app multiplicity: "prefer a single Live Activity that uses a dynamic layout and rotates through events". WWDC23 also says "consider [cycling] between the display of them". — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities); [WWDC23 Design dynamic Live Activities](https://developer.apple.com/videos/play/wwdc2023/10194/)
- Device limits on concurrent activities are undocumented: "the exact number may depend on a variety of factors. Scheduled Live Activities count towards the limit." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

### Inferences
- Practical arbitration model for a Mac clone. Slot 1 (attached) goes to the highest-priority or most recent activity, using relevanceScore within an app. Slot 2 (detached) goes to the next one. A 3rd slot can be reserved for system-class activities (media, navigation, call). Let users swipe or click to rotate, and hide (not end) an activity on an inward swipe.
- System activities appear to outrank third-party ones (navigation and screen recording can't be hidden, and the third slot is reportedly system-only). Apple has not formally specified this.

### Gaps
- Apple publishes no cross-app ordering algorithm (recency vs priority vs system class). It is unverified which activity becomes "attached" when two apps each have one.
- No primary source covers the exact 3-up layout on iPhone 18 Pro (which side, circle vs reduced compact), and the iOS 27 swipe gesture changes are undocumented.
- The iOS 26/27 Apple Support user guide page ("View Live Activities in the Dynamic Island") could not be read (it is JS-rendered).

---

## 3. Alerts and transient system events

### Takeaway
An `AlertConfiguration` (or a push `alert` dict) lights up the screen, plays a sound and briefly shows the expanded presentation in the island. Apple does not document how long it stays. First-party system events (Face ID, Apple Pay, AirDrop, charging, silent mode, AirPods, Focus and so on) use the island as a transient overlay, and no Apple spec exists for their durations or pre-emption rules.

### Cited Findings
- "Live Activity alerts light up the screen and by default play the notification sound… Alerts also show the expanded presentation in the Dynamic Island or a banner on devices that don't support the Dynamic Island." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- "On Apple Watch, the system uses the title and body attributes for the alert. On iPhone and iPad, the system doesn't show a regular alert but instead shows the expanded Live Activity in the Dynamic Island or the Lock Screen presentation as a banner on devices without the Dynamic Island." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- `AlertConfiguration(title:body:sound:)` (iOS 16.1+). Title and body are described as "on Apple Watch", and the sound "plays when the Live Activity alert appears". — [AlertConfiguration](https://developer.apple.com/documentation/activitykit/alertconfiguration)
- On non-island devices, the banner shows only if "The device is unlocked and its app isn't in use" and an AlertConfiguration is passed. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Scheduled activities must pass an AlertConfiguration. Push-to-start payloads must include an `alert`. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities); [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- Apps can't hold the island expanded programmatically. A developer forum thread asking how has no answer from Apple. — [Apple Dev Forums 780678](https://developer.apple.com/forums/thread/780678)
- WWDC23: "rather than sending a push notification, when possible, expand the island to present that information." The island "floats on a layer above apps. Apps shouldn't draw UI that points to the island or interacts with it." — [WWDC23 10194](https://developer.apple.com/videos/play/wwdc2023/10194/)
- Apple newsroom (2022): the island is "adapting in real time to show important alerts, notifications, and activities", "fluidly expanding into different shapes… to clearly convey important activities like Face ID authentication." — [Apple Newsroom, iPhone 14 Pro](https://www.apple.com/newsroom/2022/09/apple-debuts-iphone-14-pro-and-iphone-14-pro-max/)
- System alerts that use the island (list only, no durations): AirDrop, AirPlay, Airplane mode, AirPods connect, Apple Pay, CarKey, Charging, eSIM alerts, Face ID, Find My, Focus changes, Incoming calls, Low battery, NFC interactions, Shortcuts, Silent switch on/off, Watch unlock, accessory connections. — [Macworld](https://www.macworld.com/article/1069195/iphone-14-pro-dynamic-island-features-apps.html); [9to5Mac](https://9to5mac.com/2022/09/14/dynamic-island-supported-apps/); [MacRumors guide](https://www.macrumors.com/guide/dynamic-island/)
- Apple Pay "morphs into a square to match the Face ID confirmation"; during a call it "expands into a large rectangle with phone controls." — [MacRumors guide](https://www.macrumors.com/guide/dynamic-island/)
- "Some cards auto-collapse after a few seconds" (no figure given). — [Digital Citizen](https://www.digitalcitizen.life/how-to-customize-dynamic-island/)

### Inferences
- In a clone, alert expansion should be a timed overlay (a few seconds, configurable) that pre-empts the current compact or minimal state, then returns to it. System HUD-style events (charging, silent, Bluetooth connect) behave the same way but are shorter and usually wider than tall (a "wide compact" banner). Face ID and Apple Pay use a near-square shape.

### Gaps
- **Exact alert-expansion duration, and how long each system transient stays, are undocumented by Apple. I found no reliable measurements.**
- No source gives queuing rules for alerts that arrive at the same moment (for example, an incoming call vs a Live Activity alert). Incoming calls are known to take over the island in an expanded form, but no primary source states the precedence.

---

## 4. Lifecycle: stale, dismissal, duration, update budgets

### Takeaway
A Live Activity can be active for at most 8 h. At that point the system ends it and removes it from the island immediately, and it can linger on the Lock Screen (and Mac menu bar, Watch Smart Stack) for up to 4 h more, 12 h in total. Ended activities leave the island and CarPlay immediately. Payloads are capped at 4 KB. Push updates have an hourly budget (priority 10 counts against it, priority 5 doesn't), and apps can opt into frequent updates.

### Cited Findings
- "A Live Activity can be active for up to eight hours… After the eight-hour limit, the system automatically ends the Live Activity, and immediately removes it from the Dynamic Island. However, the Live Activity remains on the Lock Screen… for up to four additional hours… a maximum of 12 hours." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- "When a Live Activity ends, the system immediately removes it from the Dynamic Island and in CarPlay. On the Lock Screen, in the Mac menu bar, and the watchOS Smart Stack, it remains for up to four hours… In most cases, 15 to 30 minutes is adequate." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Dismissal policies: `.default` (up to 4 h), `.immediate`, `.after(date)` (capped at 4 h). In push payloads, use `dismissal-date` (a past date dismisses immediately). — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities); [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- Stale: at `staleDate`, `activityState` becomes `.stale` and `context.isStale` becomes true. The app should then render an "outdated" indication. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- States: active, stale, ended, and dismissed ("When a person or the system removes a Live Activity, its ActivityState changes to dismissed"). — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- "Static and dynamic data… can't exceed a combined size of 4 KB." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Push budget: "The system allows for a certain budget of ActivityKit push notifications per hour". Priority 10 (the default) counts toward it, and priority 5 "doesn't count toward the budget". `NSSupportsLiveActivitiesFrequentUpdates` raises the budget, and users can turn it off (`frequentPushesEnabled`). — [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- An activity normally starts only from the foreground app. Exceptions are `LiveActivityIntent`, push-to-start (iOS 17.2+; "17.1 and earlier, you can't start Live Activities with… push") and scheduled start dates. Activities run sandboxed and "can't access the network or receive location updates". — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities); [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- Users can remove an activity from the Lock Screen, which ends it but "doesn't end or cancel the person's action that started it." — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

### Inferences
- A clone should track `active → stale → ended → dismissed`, remove ended items from the notch immediately, and keep them in a secondary "recent" list for a configurable window (≤4 h).

### Gaps
- The exact hourly push budget number is not published.

---

## 5. Catalogue of system and third-party activities

### Takeaway
Apple publishes no per-activity spec. Reputable outlets list the participating features. Per-feature compact, minimal and expanded content is mostly undocumented and has to be observed on a device.

### Cited Findings
- Apple Live Activities (persistent): Now Playing / Apple Music, camera indicator, Maps directions, microphone indicator, ongoing calls, Personal Hotspot, Screen Recording, SharePlay, Timer, Voice Memos. — [Macworld](https://www.macworld.com/article/1069195/iphone-14-pro-dynamic-island-features-apps.html)
- MacRumors guide: Maps "upcoming and turn-by-turn directions"; calls "incoming call and call duration"; Music "time remaining on the playing song"; sports "live scores"; plus SharePlay, Screen Recording, Voice Memos and Hotspot. — [MacRumors guide](https://www.macrumors.com/guide/dynamic-island/)
- Timer: "iPhone shows the progress in real time". Music, Timer and FaceTime expand into controls ("you can pause or stop [timers] directly from Dynamic Island"). — [9to5Mac](https://9to5mac.com/2022/09/14/dynamic-island-supported-apps/)
- Third-party at launch (before ActivityKit): Now Playing apps such as Spotify, Audible, Overcast, YouTube Music, Pandora and SoundCloud, and CallKit apps such as WhatsApp, Skype and Google Voice appear automatically. — [Macworld](https://www.macworld.com/article/1069195/iphone-14-pro-dynamic-island-features-apps.html)
- Third-party Live Activity use cases Apple cites: food delivery ETA, live soccer match, workout metrics with pause/cancel, rideshare (driver contact button), sports, coffee order tracker. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities); [WWDC25 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- Transient system alerts: see section 3 list. Apple Pay and Face ID use a square or tall shape, and calls use a large rectangle with controls. — [MacRumors guide](https://www.macrumors.com/guide/dynamic-island/)
- Interactivity: buttons and toggles via App Intents. HIG: "prefer limiting it to a single element". The system disables them in CarPlay. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)

### Inferences (common observed conventions, **not verified against a source in this session**)
- Timer: orange timer glyph leading, countdown trailing; minimal shows the countdown.
- Music: album art leading, animated waveform tinted to the artwork trailing; expanded shows art, title and artist, scrubber, and transport plus AirPlay.
- Phone: green handset leading, duration or waveform trailing; expanded shows the caller with end/mute buttons.
- Maps: turn arrow leading, distance trailing; expanded shows the instruction plus ETA.
- Screen recording: red dot or timer.
- Hotspot: chain-link icon plus connection count.
- Charging: the battery percentage and icon flank the camera in a brief "wide" pill.
- Silent mode: bell with a strike-through plus a "Silent" label.

These should be confirmed on a device before being cited.

### Gaps
- No primary source describes per-system-activity compact, minimal and expanded content. Voice Memos, Shazam, AirDrop progress, Find My and Wallet details were not found in fetched sources.

---

## 6. Animation and visual design

### Takeaway
Apple describes the island as a "living organism" with "deliberate elasticity". It is an opaque black shape that blends with the camera cutout and expands fluidly into different shapes. Live Activity content animations are system-timed (custom `withAnimation` is ignored), capped at 2 s, and switched off on reduced-luminance Always-On. No official spring parameters exist.

### Cited Findings
- "Inspired by biological form and motion, the Dynamic Island is designed to feel like a living organism, with a deliberate elasticity that serves as a playful contrast to the fixed nature of the hardware." Apps "swoop up into the Dynamic Island… feel like the app is going and physically inhabiting that space." — [WWDC23 Design dynamic Live Activities](https://developer.apple.com/videos/play/wwdc2023/10194/)
- Concentricity: "rounded shapes nest inside of each other with even margins all the way around". To check optical alignment, blur the object, then make it concentric. Separate content with an inset shape or separator line. "Avoid a 'forehead'… hug the sensor as tightly as possible." — [WWDC23 10194](https://developer.apple.com/videos/play/wwdc2023/10194/); use `ContainerRelativeShape` rather than hard-coded radii — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- "Live Activities use system and custom animations with a maximum duration of two seconds… the system doesn't perform animations on Always-On displays with reduced luminance." — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- "the system ignores any animation modifiers — for example, withAnimation and animation(_:value:) — and uses the system's animation timing instead… Text views animate content changes with blurred content transitions… If you add or remove views… views fade in and out." Supported transitions: `.opacity`, `.move(edge:)`, `.slide`, `.push(from:)`, `.numericText(countsDown:)`. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Layout changes: "preserve as much of the existing layout as possible by animating existing elements to their new positions rather than removing and animating them back in"; avoid overlap. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Expanded height should change dynamically with the content available. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- "The Dynamic Island blurs the line between hardware and software, fluidly expanding into different shapes". — [Apple Newsroom 2022](https://www.apple.com/newsroom/2022/09/apple-debuts-iphone-14-pro-and-iphone-14-pro-max/); Alan Dye: the animation "didn't have to be limited to the status bar area", "dynamic software like a fluid". — [AppleInsider interview](https://appleinsider.com/articles/22/10/02/craig-federighi-alan-dye-talk-about-dynamic-islands-creation)
- Typography and colour: "large, heavier-weight text — a medium weight or higher"; bold brand colours on black; logo mark without a container, not the whole app icon. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Don't add elements in-app that "draw attention to the Dynamic Island". — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)

### Inferences
- For macOS, use a black, continuously-cornered shape that is pixel-aligned to the notch, with a spring on the shape's frame and corner radius (morph) and content cross-fading or blur-replacing inside. Show a subtle keyline (tinted border) in dark contexts. Content swaps should use blur and numeric transitions of ≤2 s. Detached minimal circles should appear to "bud off" the main pill. Common third-party recreations use a gooey/metaball effect, but whether Apple uses one is unverified.
- Idle state: on iPhone the idle island is just the black pill matching the cutout. Nothing is drawn beyond the hardware (per general descriptions: "At rest… a small rounded black area" — [MacRumors guide](https://www.macrumors.com/guide/dynamic-island/)).

### Gaps
- No Apple-published spring response/damping, shadow or blur values exist. A Notion breakdown of Apple's springs could not be fetched. Whether the island casts a shadow is unverified (it appears flat and opaque).

---

## 7. Accessibility

### Takeaway
Apple's documented requirement is accessibility labels on every presentation, kept in sync with dynamic state. Motion is reduced via system settings and Always-On luminance. Reduced Motion specifics for the island are undocumented.

### Cited Findings
- Add `.accessibilityLabel` to compact leading, compact trailing and minimal views (example: "Health level at N percent"), and update labels when status images change. — [Adding accessible descriptions](https://developer.apple.com/documentation/activitykit/adding-accessible-descriptions-to-widgets-and-live-activities)
- Avoid sensitive content: redact, or show an innocuous summary, because the island and Lock Screen are visible to observers. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Use `isLuminanceReduced` to skip animations and adapt colours on Always-On. — [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- Reduce Motion "soften[s] animations" of the island. — [Digital Citizen](https://www.digitalcitizen.life/how-to-customize-dynamic-island/) (secondary)

### Inferences
- A Mac clone should expose each activity as an accessibility element combining the leading and trailing labels, honour `accessibilityReduceMotion` (cross-fade instead of morph) and `accessibilityReduceTransparency`, and keep text medium weight or heavier.

### Gaps
- No Apple source describes VoiceOver navigation order inside the island or how Reduce Motion changes the morph.

---

## 8. Changes iOS 18 → 27, and Live Activities on Mac

### Takeaway
iOS 18 brought push-to-start with channels and tokens. iOS 26 / macOS 26 Tahoe surfaced iPhone Live Activities in the Mac menu bar (iPhone running iOS 18+, no developer code changes, click to expand, open the app via iPhone Mirroring). iOS 27 added island Live Activities in landscape, the limited-width environment value, and iPhone 18 Pro's smaller island with up to three activities. No public API lets third-party Mac apps read those mirrored Live Activities.

### Cited Findings
- WWDC25 "What's new in widgets": "Live Activities from a paired iPhone will now appear in macOS Tahoe. Just like in the Dynamic Island on iPhone… presents the leading and trailing views together in the menu bar. When the Live Activity is selected, the lock screen presentation from iPhone will appear. Clicking on the lock screen presentation will launch the associated app using iPhone Mirroring… Live Activities on macOS can be provided by iPhones running iOS 18 and later. There are no code changes required." — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- **Conflict:** current docs (2026) say "Live Activities that appear in the Menu bar use unchanged compact, minimal, and expanded presentations" — [Creating custom views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities); the HIG says the Mac uses "compact, minimal, and expanded presentations. Clicking the Live Activity launches iPhone Mirroring" — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities). WWDC25 said clicking shows the *Lock Screen* presentation. The likely explanation is that the behaviour changed between macOS 26.0 and later versions. Unverified.
- Apple Support: you must first connect via iPhone Mirroring, after which "Your Mac then receives Live Activities from your iPhone even when you aren't using iPhone Mirroring". "Your iPhone must be turned on, but it doesn't need to be nearby". Depending on menu bar space, the Mac shows "either a small icon or a compact view". Clicking shows more detail, and double-clicking (iPhone nearby) opens iPhone Mirroring. A hover close button dismisses one activity. Settings > Notifications > "Allow Live Activities from iPhone" (macOS Tahoe 26+). iPhone selection lives in General > AirDrop & Continuity (26.4+). — [Apple Support 120684](https://support.apple.com/en-us/120684); [9to5Mac, Sep 2025](https://9to5mac.com/2025/09/23/iphone-mirroring-on-the-mac-gets-a-key-upgrade-in-macos-tahoe/)
- Ended activities stay in the Mac menu bar for up to 4 h (same as the Lock Screen). — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- ActivityKit availability is listed as **iOS 16.1+ / iPadOS 16.1+ only** (no macOS). The framework blurb says Live Activities appear "on Mac… in the Menu bar". — [ActivityKit](https://developer.apple.com/documentation/activitykit)
- A June 2026 developer forum question asks for "recommended patterns for creating a persistent, glanceable activity experience on macOS that maintains parity with Live Activities", noting developers "currently need to build separate UI surfaces such as menu bar extras, widgets, and custom overlays". No Apple answer was visible. — [Apple Dev Forums](https://developer.apple.com/forums/activities/1628080)
- iOS 18: push-to-start with `input-push-channel` or `input-push-token` and broadcast channels. — [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- iOS 26 era (HIG Dec 16 2025 revision): CarPlay Dashboard and Mac guidance added. `supplementalActivityFamilies([.small])` covers Watch and CarPlay, and `.medium` covers iPad/iPhone Lock Screen and StandBy. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities); [Creating custom views](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities)
- iOS 27: island Live Activities in landscape, `isDynamicIslandLimitedInWidth` (iOS 27.0+), and an "iPhone Duo" reference in the docs. — [WWDC26 223](https://developer.apple.com/videos/play/wwdc2026/223/); [SwiftUI docs](https://developer.apple.com/documentation/swiftui/environmentvalues/isdynamicislandlimitedinwidth)
- iPadOS: Live Activities appear on the Lock Screen and Home Screen. The island is iPhone-only. — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- Reports mention a pill-shaped Siri animation coming from the island in iOS 27, and a rumoured island on a touchscreen MacBook Pro (unconfirmed). — [MacRumors guide](https://www.macrumors.com/guide/dynamic-island/)

### Inferences
- A third-party Mac notch app **cannot** subscribe to the iPhone's mirrored Live Activities through any public API. The only realistic options are (a) the developer's own iOS app relaying state to the Mac app, (b) Mac-side sources (Now Playing via MediaRemote, which is private and restricted in recent macOS, calendar, timers and so on), or (c) reading the system menu bar items through Accessibility APIs (fragile, likely not App Store-safe). No source confirmed any of these, so they are inferences.

### Gaps
- No source confirmed whether macOS exposes mirrored Live Activities to other apps (for example via NSStatusItem/Accessibility). Treat it as "no public API" pending verification.
- No primary source explains how the Mac menu bar orders multiple Live Activities.
- Apple primary sources for iOS 18 and iOS 26 changes to first-party island visuals (charging, volume, Siri) were not found in this session.
