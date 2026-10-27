# Mac "Live Activity" event sources for a third-party notch app (macOS 26 Tahoe / 27, Oct 2026)

Research date: 2026-10-27. Scope: which iPhone-Dynamic-Island-style events a **non-sandboxed, notarised or locally signed** Mac app can actually detect and show in the notch, and how. I read source code from shallow clones of four repos, each at the commit noted:
- Ebullioscopic/Atoll @ `8be6bd9` (27 Oct 2026)
- jackson-storm/DynamicNotch @ `ec927e1` (25 Oct 2026)
- TheBoredTeam/boring.notch @ `23e7705` (18 Oct 2026)
- farouqaldori/vibe-notch @ `10f1d24` (20 Apr 2026)

Code links point at those commits or at the default branch. Where a statement comes from reading code and not from documentation, it says "(code read)".

Legend used in the catalogue: **PUBLIC** = documented Apple API. **PRIVATE** = undocumented symbol, private notification or private file format. **HEURISTIC** = inferred from processes, files or UI scraping. **NONE** = no known route.

---

## Q1. Navigation / turn-by-turn, and reading the iPhone Live Activities that Tahoe shows in the Mac menu bar

### Takeaway
There is no public or known private API that lets a third-party Mac app read the iPhone Live Activities macOS 26 shows in the menu bar. They are rendered by the system and only reach the Mac through the iPhone Mirroring/Continuity pipeline. Apple Maps on Mac does route planning and "send to iPhone", not live GPS turn-by-turn. So a notch app cannot honestly reproduce iPhone navigation. The realistic routes are scraping the menu-bar item through Accessibility (unproven) or an app-specific integration.

### Cited Findings
- In macOS 26, iPhone Live Activities appear in the Mac menu bar. The compact view shows the leading and trailing views together, like the Dynamic Island. Clicking shows the Lock Screen presentation, and clicking that opens the app via iPhone Mirroring. "Live Activities on macOS can be provided by iPhones running iOS 18 and later". Existing apps work with no developer changes. — [9to5Mac, 16 Jun 2025](https://9to5mac.com/2025/06/16/macos-26-live-activities-work-even-if-your-iphone-is-on-ios-18/)
- Requirements: iPhone Mirroring set up, the same Apple Account, Wi-Fi and Bluetooth on, and the Mac setting System Settings > Notifications > "Allow Live Activities from iPhone". Read-only until clicked, which opens the app in Mirroring. — [iGeeksBlog](https://www.igeeksblog.com/how-to-use-live-activities-on-ipad-mac/)
- The feature is described as an extension of iPhone Mirroring ("Live Activities that are running on your iPhone will automatically display in the Mac's menu bar"). The article does not mention ActivityKit on macOS. — [9to5Mac, 13 Jun 2025](https://9to5mac.com/2025/06/13/live-activities-are-coming-to-ipad-and-mac-heres-how-theyll-work/)
- MacStories review: the menu-bar Live Activity text is "far too small", and the "shrunken down menu bar-height UI needs to be reconsidered". Clicking expands it below the menu bar. — [MacStories Tahoe review p3](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3)
- The ActivityKit framework availability lists **only iOS 16.1+ and iPadOS 16.1+**, with no macOS entry, yet the overview says "On Mac, it appears in the Menu bar". So Mac display is a mirror of iPhone activities, not a Mac-side API. — [Apple ActivityKit docs (.md)](https://developer.apple.com/documentation/activitykit.md)
- WWDC26 session 223 "Live Activities essentials" says: "When your app runs a Live Activity on iPhone, it automatically appears on other Apple devices… In the macOS menu bar". It gives no API for Mac apps to observe other apps' activities. — [WWDC26 session 223](https://developer.apple.com/videos/play/wwdc2026/223/)
- Mac Maps: "Do the research on your Mac, get the turn-by-turn help on your iPhone". Directions are shared from Mac to iPhone. — [Tom's Guide](https://www.tomsguide.com/how-to/how-to-share-maps-directions-from-your-mac-with-your-iphone-and-why-youd-want-to). An older Macworld guide (2017) says Mac Maps gives "written turn-by-turn directions" that you can print, with live guidance on the iPhone. — [Macworld](https://www.macworld.com/article/670871/how-to-use-apple-maps-on-a-mac.html)

### Inferences
- **Navigation = NONE (practically).** Mac Maps has no live navigation session to observe, and iPhone Maps navigation reaches the Mac only as a system-drawn menu-bar Live Activity. None of the iPhone Live Activity sources I found mention Maps navigation specifically (iGeeksBlog explicitly did not), so whether Maps nav even mirrors is **unverified**.
- **Reading mirrored Live Activities = NONE public; HEURISTIC possible but unproven.** A notch app with Accessibility permission could try to enumerate the menu-bar extra via `AXUIElementCreateSystemWide` → `kAXMenuBarAttribute`/`AXExtrasMenuBar` and read its AX title or value. Atoll and DynamicNotch already do exactly this for the Clock timer menu extra (see Q3), so the technique is proven for Apple's own menu extras. Whether Live Activity menu items expose meaningful AX text is **untested**. Expect at most a short text string, not structured data. Risk: brittle and dependent on the macOS version.
- Alternatives: Google Maps in a browser has no turn-by-turn on desktop (general knowledge, **unverified** here). A "next calendar event + travel time" or "ETA" card built from EventKit plus MapKit `MKDirections` is the honest Mac-native approximation.

### Gaps
- No source names the process that draws mirrored Live Activities (likely a ControlCenter/SystemUIServer/Continuity agent; unverified), and none shows its AX tree.
- No source confirms whether Apple Maps turn-by-turn on iPhone appears as a Live Activity on the Mac menu bar.

---

## Q2. Phone / FaceTime / VoIP calls (incoming, ongoing, duration)

### Takeaway
CallKit's `CXCallObserver` is **not available for native macOS** (only iOS, iPadOS, Mac Catalyst, visionOS, watchOS). A native notch app therefore has no public call API. The practical approach is "mic in use + which process", via the public Core Audio process-object API on macOS 14+, combined with a list of known call app bundle IDs and the camera in-use flag. Incoming Continuity/FaceTime calls can only be heuristically detected (FaceTime launch or its notification window).

### Cited Findings
- `CXCallObserver` availability: "iOS 10.0, iPadOS 10.0, macCatalyst 10.0, visionOS 1.0, watchOS 9.0", with no macOS entry. "any app can create a new CXCallObserver object to be notified of any calls activity on the system" (on those platforms). — [Apple docs (.md)](https://developer.apple.com/documentation/callkit/cxcallobserver.md)
- macOS 26 Phone app: makes cellular calls through the iPhone's connection. Incoming calls show in a "pop-up section in the top right corner" with answer and hang-up. Adds Call Screening and Hold Assist. — [AppleInsider, 9 Jun 2025](https://appleinsider.com/articles/25/06/09/macos-26-tahoe-phone-app-greatly-improves-taking-calls-on-your-mac)
- Keyboard Maestro forum (Nov 2024 – Feb 2025): "There aren't any notification-received triggers". Suggested workarounds are a FaceTime app-launch trigger ("FaceTime launches when an inbound call arrives") plus checking the window for an Accept button, or image detection/OCR of the pop-up. — [KM forum](https://forum.keyboardmaestro.com/t/is-it-possible-to-trigger-on-an-incoming-phone-call/38457)
- Per-process mic use (macOS 14+): enumerate `kAudioHardwarePropertyProcessObjectList` on `kAudioObjectSystemObject`, check `kAudioProcessPropertyIsRunningInput`, and read `kAudioProcessPropertyPID` (added in the macOS 14.0 SDK). Before Sonoma, only device-level `kAudioDevicePropertyDeviceIsRunningSomewhere` is available. — [Apple Dev Forums 798884](https://developer.apple.com/forums/thread/798884)
- Atoll (code read): `MicrophoneMonitor.swift` uses `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device, which is device-level and does not say which app. `CameraMonitor.swift` uses a CoreMediaIO property listener on `kCMIODevicePropertyDeviceIsRunningSomewhere`. These feed "Privacy Access Indicators". — [Atoll managers/](https://github.com/Ebullioscopic/Atoll/tree/dev/DynamicIsland/managers); [CHANGELOG 2.3.0](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)
- Atoll's screen-recording manager keeps a known "screen sharing/meeting app" bundle-ID list: `com.apple.FaceTime`, `com.apple.ScreenSharing`, `com.cisco.webexmeetingsapp`, `com.hnc.Discord`, `com.microsoft.teams`, `com.microsoft.teams2`, `com.skype.skype`, `com.tinyspeck.slackmacgap`, `us.zoom.xos` (code read). — [ScreenRecordingManager.swift](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/ScreenRecordingManager.swift)
- Droppy advertises meeting live activities with controls for Zoom, Teams, Google Meet, WhatsApp and Telegram. It uses Automation (Apple Events) for "meeting apps for mute and camera", plus Microphone and Camera permissions. Its detection method is not documented. — [Droppy permissions docs](https://getdroppy.app/docs/permissions)

### Inferences
- Recommended "call in progress" detector: (1) Core Audio process list → PIDs with `IsRunningInput` → map to `NSRunningApplication` → match against a call-app list (FaceTime, Phone `com.apple.mobilephone`? — bundle ID **unverified**, Zoom, Teams, Meet in a browser, Discord, Slack, WhatsApp). (2) Start the duration timer when input starts. (3) Optionally add the camera flag as a "video call" hint. This is PUBLIC and reliable for "a call-like session is active". It cannot give caller name or incoming/ringing state.
- Incoming-call ringing = HEURISTIC only: watch `NSWorkspace.didLaunchApplicationNotification` for FaceTime/Phone, or the AX window list for a call banner. Fragile. Caller ID would need AX or OCR scraping (high risk, privacy-sensitive).
- Browser-based Meet calls show up as the browser process holding the mic, so there is no per-tab attribution.

### Gaps
- I didn't verify the Phone app's bundle ID on macOS 26, or whether `callservicesd` or TelephonyUtilities posts any observable distributed notification.
- No current source on reading call history (`CallHistory.storedata`) on Tahoe. It would need Full Disk Access and is not live anyway.

---

## Q3. Timers and alarms from the macOS Clock app

### Takeaway
There is no public API. Two notch apps (Atoll and DynamicNotch) mirror Clock timers by combining three private or heuristic channels: (a) reading the `com.apple.mobiletimerd` preferences domain (`MTTimers`), (b) streaming unified logs from subsystem `com.apple.mobiletimer.logging` via `/usr/bin/log`, and (c) Accessibility scraping of the Clock timer menu-bar extra (needed for pause/stop control). Alarms are not mirrored by any app I found.

### Cited Findings
- Atoll `SystemTimerBridge.swift` (code read):
  - preferences domain `com.apple.mobiletimerd` and path `~/Library/Preferences/com.apple.mobiletimerd.plist`, read via `CFPreferencesCopyAppValue("MTTimers", domain)`
  - a `/usr/bin/log` stream with predicate `subsystem == "com.apple.mobiletimer.logging"`
  - an AX search of the system-wide menu bar for the timer menu extra (`locateTimerMenuExtra`, matching AX identifier, title or value text)
  - gating on the Clock app running (`com.apple.clock`)
  - a comment that the "unthrottled firehose freezes the menu bar", so updates are coalesced to ≥0.25 s
  - — [SystemTimerBridge.swift](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/SystemTimerBridge.swift)
- DynamicNotch has its own `ClockTimerMonitor.swift` / `ClockTimerController.swift` using `AXUIElementCreateSystemWide` and `com.apple.clock` (code read). — [DynamicNotch Features/Timer](https://github.com/jackson-storm/DynamicNotch/tree/main/DynamicNotch/Features/Timer)
- Atoll's changelog lists a "bridge to the macOS system timer". An unreleased fix removed a floating timer window, and Pause/Stop now render inline. — [Atoll CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)

### Inferences
- Reliability: medium-low. All three channels are private or undocumented formats that Apple can change in any point release. The log-stream approach costs CPU if it is not throttled.
- Permissions: Accessibility (for the AX menu extra and control). Reading another app's preferences domain works for a non-sandboxed app (general knowledge).
- A simpler, robust option is the notch app's own timers (fully PUBLIC) plus an App Intents/Shortcuts action, so users start timers in the notch app.

### Gaps
- No source confirms alarm (`MTAlarms`?) mirroring. The key name is **unverified**.

---

## Q4. Screen recording active

### Takeaway
There is no public "someone is capturing the screen" API. Both Atoll and DynamicNotch use the private CGS/SkyLight symbols `CGSIsScreenWatcherPresent()` and `CGSRegisterNotifyProc` (event types 1502/1503), plus a `screencapture`/`screencaptureui` process check. Stopping the recording is done by sending the system stop shortcut or killing `screencapture`.

### Cited Findings
- Atoll `ScreenRecordingManager.swift` (code read):
  - `@_silgen_name("CGSIsScreenWatcherPresent")`, and `CGSRegisterNotifyProc(callback, 1502, ctx)` / `(…, 1503, …)` for connect/disconnect events. A comment notes "Private SkyLight/CGS symbols are intentionally isolated here".
  - It checks whether a process named `screencapture` is running.
  - Stop: sends the stop shortcut via System Events and CGEvent, then falls back to `killall -INT/-TERM screencapture` and `-TERM screencaptureui`.
  - It suppresses false positives while known screen-sharing apps (FaceTime, Zoom, Teams…) are active.
  - — [ScreenRecordingManager.swift](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/ScreenRecordingManager.swift)
- DynamicNotch `SystemScreenRecordingMonitor.swift` uses the same `CGSIsScreenWatcherPresent` and `CGSRegisterNotifyProc`, references `screencapture`/`screencaptureui`, and stops via `/usr/bin/pkill` (code read). — [DynamicNotch Features/ScreenRecording](https://github.com/jackson-storm/DynamicNotch/tree/main/DynamicNotch/Features/ScreenRecording)
- Atoll added "a recording live activity with optional native stop controls" (Unreleased). — [Atoll CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)

### Inferences
- `CGSIsScreenWatcherPresent` reports any screen watcher (ScreenCaptureKit clients, screen sharing, possibly the notch app's own capture). That explains the app allow-list. Reliability: good in practice. Risk: private symbol, not App Store-safe.
- PUBLIC partial alternative: detect `screencaptureui` or QuickTime processes via `NSWorkspace.runningApplications`. This covers Apple's Cmd-Shift-5 tool only.

### Gaps
- Meaning of event IDs 1502/1503 is only known from community code. No Apple documentation exists.

---

## Q5. AirDrop progress, browser downloads, Finder copy progress

### Takeaway
- **Downloads**: watch `~/Downloads` for in-progress extensions (`.crdownload`, `.download`, `.part`, `.opdownload`). Read progress from the `com.apple.progress.fractionCompleted` extended attribute (Safari/WebKit and others) or from file growth. This is HEURISTIC but works well.
- **AirDrop**: progress is only available for transfers the notch app itself starts via `NSSharingService(.sendViaAirDrop)`. Incoming AirDrop and transfers started by other apps were not observed by any app I found.
- **Finder copies**: `NSProgress.addSubscriber(forFileURL:withPublishingHandler:)` is a public macOS API (10.9+) for observing published file progress. I found no notch app using it, and no confirmation that Finder publishes progress observable this way.

### Cited Findings
- Atoll `DownloadManager.swift` (code read): in-progress extensions `["crdownload", "download", "opdownload", "part"]`. Notes: "Chromium writes `archive.zip.crdownload`, Safari an `archive.zip.download` bundle, Firefox `archive.zip.part`… Opera… `.opdownload`". It uses a `DispatchSourceFileSystemObject` on the Downloads directory, and speed comes from sampling bytes over time. — [DownloadManager.swift](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/DownloadManager.swift)
- Atoll changelog: download speed is "measured from how fast the files in your Downloads folder are growing". Completion vs cancellation is decided by "whether the destination holds data that was written *after* the temporary file appeared". — [Atoll CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)
- DynamicNotch `FolderFileDownloadMonitor.swift` reads xattr `com.apple.progress.fractionCompleted`, "that browsers (Safari/WebKit and others) write onto in-flight downloads… stored as a string whose decimal separator follows the current locale". It also has a `ChromiumDownloadMetadataReader.swift` that reads under `~/Library/Application Support` (code read). — [DynamicNotch Features/Download](https://github.com/jackson-storm/DynamicNotch/tree/main/DynamicNotch/Features/Download)
- DynamicNotch AirDrop: `AirDropController.swift` uses `NSSharingService(named: .sendViaAirDrop)` with an `NSSharingServiceDelegate` (`didShareItems` / `didFailToShareItems`). In code, `updateTransferProgress` is only called from a debug preview, so real AirDrop progress is not tracked (code read). — [AirDropController.swift](https://github.com/jackson-storm/DynamicNotch/blob/main/DynamicNotch/Features/DragAndDrop/Components/AirDropController.swift)
- `Progress.addSubscriber(forFileURL:withPublishingHandler:)`: macOS 10.9+. It fires "when a progress object calls publish() with a fileURLKey… that is the same as this method's URL, or that is an item that the URL directly contains". You get a proxy progress object, and the handler runs on main. — [Apple docs (.md)](https://developer.apple.com/documentation/foundation/progress/addsubscriber(forfileurl:withpublishinghandler:).md)
- A developer forum post (FB20929181) asks for "Finder-style copy with progress". It has no Apple reply. — [Dev Forums 806394](https://developer.apple.com/forums/thread/806394)

### Inferences
- Subscribing with `addSubscriber(forFileURL: ~/Downloads)` may catch Safari's published download progress (Safari historically showed progress on Dock/Finder icons, which uses this mechanism). This is **unverified on 26/27**, but it is a PUBLIC, cheap experiment worth trying before falling back to xattr polling.
- Incoming AirDrop: files land in `~/Downloads`, so the download watcher catches completion, but not live progress (**unverified**).
- Permissions: the Downloads folder TCC prompt for non-sandboxed apps (Atoll calls `requestDownloadsPermissionIfNeeded`). No Full Disk Access is needed.

### Gaps
- No test data on whether Finder copy operations publish NSProgress to subscribers on macOS 26/27.

---

## Q6. Now Playing, charging/battery, AirPods connect, Focus/DND, lock/unlock, Touch ID, Apple Pay

### Takeaway
- **Now Playing**: private MediaRemote via `mediaremote-adapter` (perl trick). Reported working on macOS 27.0.
- **Battery**: PUBLIC IOKit.
- **Bluetooth/AirPods connect**: PUBLIC IOBluetooth connect notifications. Per-bud battery is private.
- **Focus/DND**: private distributed notifications plus Full Disk Access for mode names.
- **Lock/unlock**: semi-private but stable distributed notifications.
- **Touch ID / Apple Pay**: no detection route found. DynamicNotch's "FaceID" feature is a camera-based gimmick, not system auth.

### Cited Findings
- MediaRemote: from macOS 15.4 it was "completely non-functional when being loaded directly from within an app". The adapter runs `/usr/bin/perl` (Apple-signed) to load a bundled framework. — [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter). Issue #41 (28 Sep 2026) reports reading works "at least" on macOS 27.0. Commands go to the "elected" now-playing app only. — [Issue #41](https://github.com/ungive/mediaremote-adapter/issues/41). Atoll bundles `MediaRemoteAdapter.framework` + `mediaremote-adapter.pl` (code read). — [Atoll repo](https://github.com/Ebullioscopic/Atoll/tree/dev/mediaremote-adapter)
- Focus/DND (Atoll `DoNotDisturbManager.swift`, code read):
  - observes `DistributedNotificationCenter` names `_NSDoNotDisturbEnabledNotification` / `_NSDoNotDisturbDisabledNotification`
  - polls `~/Library/DoNotDisturb/DB/Assertions.json`
  - reads mode names from `~/Library/DoNotDisturb/DB/ModeConfigurations.json` (both gated on `FullDiskAccessAuthorization.hasPermission()`)
  - has a `/usr/bin/log` fallback with predicate `process == "duetexpertd" AND eventMessage CONTAINS "semanticModeIdentifier"`
  - knows mode IDs such as `com.apple.donotdisturb.mode`, `com.apple.focus.work`, `.sleep`, `.driving`, `.gaming`, `.reduce-interruptions`
  - — [DoNotDisturbManager.swift](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/managers/DoNotDisturbManager.swift)
- DynamicNotch has the same design (`FocusAssertionsReader.swift`, `FocusLogStream.swift`, `FullDiskAccessAuthorization.swift`, `_NSDoNotDisturb*Notification`) (code read). — [DynamicNotch Features/Focus](https://github.com/jackson-storm/DynamicNotch/tree/main/DynamicNotch/Features/Focus)
- Bluetooth connect (Atoll `BluetoothAudioManager.swift`, code read): `import IOBluetooth`; `DistributedNotificationCenter` names `IOBluetoothDeviceConnectedNotification` / `IOBluetoothDeviceDisconnectedNotification`; `IOBluetoothDevice.pairedDevices()`. — [Atoll managers/](https://github.com/Ebullioscopic/Atoll/tree/dev/DynamicIsland/managers). AirPods per-bud battery comes from private IOBluetooth properties or BLE advertisements (AirBattery). — see sibling notes `Mac notch app features/building_notch_apps.md`; [AirBattery](https://github.com/lihaoyun6/AirBattery)
- Lock/unlock: both Atoll and DynamicNotch observe distributed notifications `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` (code read). Atoll draws above the lock screen via SkyLight. — [Atoll](https://github.com/Ebullioscopic/Atoll); [DynamicNotch](https://github.com/jackson-storm/DynamicNotch)
- DynamicNotch's `FaceID` feature uses `AVCaptureSession`/`AVCaptureDevice`, a `FaceAttentionEvaluator` and a `FaceIDKeychainService` (code read). This is a camera-based face-presence feature, not detection of system Touch ID prompts. — [DynamicNotch Features/FaceID](https://github.com/jackson-storm/DynamicNotch/tree/main/DynamicNotch/Features/FaceID)
- Battery: Atoll shows actual charging wattage (merged 26 Oct 2026); boring.notch has `BatteryStatusViewModel`. — [Atoll CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md); [boring.notch managers](https://github.com/TheBoredTeam/boring.notch/tree/main/boringNotch/managers)

### Inferences
- Focus without Full Disk Access: you get the on/off state from the private distributed notification, but no mode name. With Full Disk Access, the JSON files give the name. Both are undocumented formats. Medium reliability.
- Battery/charging: IOKit `IOPSCopyPowerSourcesInfo` + `IOPSNotificationCreateRunLoopSource` is PUBLIC and high reliability (general knowledge; Apple doc not fetched).
- Touch ID prompt: the iPhone shows Face ID in the island. On the Mac, the nearest heuristic is watching for the `coreautha`/`SecurityAgent` window via the CGWindowList (**unverified, speculative**). Not recommended.
- Apple Pay on Mac: NONE found.

### Gaps
- No source on detecting Touch ID or Apple Pay sheets.
- MediaRemote on macOS 27 is only confirmed by the adapter's own issue tracker.

---

## Q7. Notifications from other apps

### Takeaway
There is no public API. Since Sequoia, the Notification Center DB lives at `~/Library/Group Containers/group.com.apple.usernoted/db2/db` behind TCC. Tools that read it ask for Full Disk Access. Apple keeps tightening redaction (CVE-2026-20603, fixed in 26.3). Most notch apps therefore show only their own or extension notifications, or app-specific integrations (WhatsApp, Messages).

### Cited Findings
- Sequoia moved the DB from `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db` to `~/Library/Group Containers/group.com.apple.usernoted/db2/db`. "Group Containers are protected by TCC… prompts". — [9to5Mac, 1 Sep 2024](https://9to5mac.com/2024/09/01/security-bite-apple-addresses-privacy-concerns-around-notification-center-database-in-macos-sequoia/)
- A notification-reader agent skill (updated 9 Mar 2026) checks `~/Library/Group Containers/group.com.apple.usernoted/db2/db` and states "This skill requires Full Disk Access to read the macOS notification database". — [ClawKit skill page](https://getclawkit.com/skills/official-gift-is-coding-macos-notification-reader)
- CVE-2026-20603: in Notification Center, "An app with root privileges may be able to access private information due to insufficient redaction". Fixed in macOS Tahoe 26.3 (11 Feb 2026) by "improving the redaction of sensitive information in Notification Center". — [Wiz CVE page](https://www.wiz.io/vulnerability-database/cve/cve-2026-20603)
- SuperIsland docs: "macOS does not provide a public API for arbitrary apps to read every item from Notification Center". Sources are extensions, a WhatsApp integration and "apps that publish public distributed notifications". — [SuperIsland NOTIFICATIONS.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/NOTIFICATIONS.md). Earlier builds used "one-second notification log scans" (energy issue). — sibling notes `superisland.md`
- Alcove: "Notifications cover only Alcove's own alerts" (competitor blog). — [Droppy blog](https://getdroppy.app/blog/best-mac-notch-apps-2026)
- Droppy has a "Notifications" Droplet (banners in the notch) and uses Contacts for "names and photos on message notifications you can reply to". It lists Full Disk Access as "Needed by a few features that read outside the sandbox's reach" without naming notifications. — [Droppy permissions](https://getdroppy.app/docs/permissions)

### Inferences
- Route: Full Disk Access + `FSEvents` on the db/WAL file + SQLite read of the `record` table, whose `data` column is a binary plist (format per plaso parser; **unverified on 26/27**). Risk: private format, a big privacy ask, and Apple may redact further. Medium-low reliability.
- Lower-risk alternative: the AX observer on the `NotificationCenter` process banner windows (needs Accessibility) gives title and body text only while the banner is visible. **Unverified**.

### Gaps
- No source confirms that Full Disk Access alone still suffices to read the db on 26.3+ / 27, or how the CVE fix changed redaction in the DB.

---

## Q8. Sports scores, deliveries, rideshare

### Takeaway
There is no Mac-side system source. On iPhone these are ActivityKit activities from each app, and on Mac they appear only as mirrored menu-bar items (unreadable, see Q1). A notch app must call third-party web APIs itself.

### Cited Findings
- Mirrored examples include Uber/Lyft, DoorDash/Uber Eats, Flighty, ESPN/Apple Sports and Clock. — [iGeeksBlog](https://www.igeeksblog.com/how-to-use-live-activities-on-ipad-mac/)
- SuperIsland 1.0.10 added "live football scores" (web-sourced). — sibling notes `superisland.md` / [SuperIsland releases](https://github.com/shobhit99/SuperIsland/releases)
- Atoll weather uses Open-Meteo (a public web API). — [Atoll README](https://github.com/Ebullioscopic/Atoll)

### Inferences
- Sports: a free or cheap scores API polled every 30–60 s. Deliveries and rideshare: no consumer APIs (Uber/DoorDash rider APIs are restricted). Order-tracking emails or links are the only practical source. Effectively NONE for rideshare.

### Gaps
- I didn't evaluate specific sports APIs or their pricing and terms.

---

## Q9. Developer events: Xcode builds, Claude Code

### Takeaway
Claude Code exposes first-class hooks (command or HTTP) for 33 events. vibe-notch shows the pattern: install a hook script into `~/.claude/settings.json` that forwards the event JSON over a Unix socket (`/tmp/claude-island.sock`). For Xcode, there is no public build-progress API. Options are Xcode Behaviors "Run script" on build start/succeed/fail, or watching DerivedData/logs (heuristic).

### Cited Findings
- Claude Code hook events (33) include `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Notification`, `SubagentStart/Stop`, `TaskCreated/Completed`, `Stop`, `StopFailure`, `PreCompact`, `SessionEnd`, and more.
  - `Notification` `notification_type` values include `permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`.
  - Command hooks get JSON on stdin. HTTP hooks (`type: "http"`) POST the same JSON to a URL such as `http://localhost:8080/...`.
  - — [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- vibe-notch (code read):
  - `HookInstaller.swift` copies `claude-island-state.py` into `~/.claude/hooks/` and registers it in settings for `UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Notification, Stop, SubagentStop, SessionStart, SessionEnd, PreCompact`, with a timeout of 86400 for permission waits.
  - The Python script connects to `SOCKET_PATH = "/tmp/claude-island.sock"` (AF_UNIX), with `TIMEOUT_SECONDS = 300` "for permission decisions".
  - The app's `HookSocketServer.swift` listens on that socket.
  - — [vibe-notch HookInstaller.swift](https://github.com/farouqaldori/vibe-notch/blob/main/ClaudeIsland/Services/Hooks/HookInstaller.swift); [claude-island-state.py](https://github.com/farouqaldori/vibe-notch/blob/main/ClaudeIsland/Resources/claude-island-state.py)
- Atoll's "LLM usage" reads Claude Code credentials from the Keychain item `Claude Code-credentials-<hash>` and parses Codex session logs. This covers usage and quota, not live progress. — [Atoll CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)
- Droppy's "Agents" Droplet shows Claude/Codex/Cursor/Antigravity/OpenCode progress and limits. SuperIsland has a coding-agents status extension. — sibling notes `droppy.md`, `superisland.md`
- BuildWatch (Lickability) tracks Xcode build time, but the article does not disclose the mechanism. — [Lickability blog](https://lickability.com/blog/meet-buildwatch/)

### Inferences
- Claude Code = PUBLIC and highly reliable. The simplest modern option is an HTTP hook to a localhost listener in the notch app: no Python dependency, and the response can return approve/deny for `PermissionRequest`.
- Xcode: Behaviors → "Run" a script on Build Starts/Succeeds/Fails, posting to the notch app via URL scheme or socket. User setup is required; there is no progress percentage. `xcodebuild` CLI builds can be wrapped. (General knowledge, **unverified** for Xcode 26.)

### Gaps
- I didn't verify the Xcode 26 Behaviors UI or any build-progress distributed notification.

---

## Q10. How existing notch apps implement these, and IPC for third-party apps to push activities

### Takeaway
Atoll has the most complete public extension story: the AtollExtensionKit Swift SDK (LGPL-3) over an XPC Mach service `com.ebullioscopic.Atoll.xpc`, plus a WebSocket JSON-RPC 2.0 server on loopback `localhost:9020` with `atoll.*` methods. NotchNotification is just an in-process Swift package for showing your own notch toasts, not IPC. vibe-notch uses a Unix socket. SuperIsland uses JS extensions plus distributed notifications.

### Cited Findings
- AtollExtensionKit:
  - Swift SDK; "uses XPC… to securely communicate with the Atoll app" via a Mach service
  - `AtollClient.shared.requestAuthorization()` shows a user prompt, revocable in Settings → Extensions
  - `presentLiveActivity` / `updateLiveActivity` / `dismissLiveActivity(activityID:)`, plus lock-screen widgets
  - `AtollLiveActivityDescriptor` has `id`, `priority`, `title` (≤50 chars), `subtitle` (≤100), `leadingIcon`/`leadingContent` (symbol, app icon or Lottie), `trailingContent` (text, marquee, `countdownText(targetDate:)`, icon, animation) or `progressIndicator` (ring, bar, percentage, Lottie), `accentColor`, `allowsMusicCoexistence`, `sneakPeekConfig`
  - activities last ≤24 h; macOS 13+, Swift 6.2+; LGPL v3
  - — [AtollExtensionKit](https://github.com/Ebullioscopic/AtollExtensionKit)
- Atoll host side (code read): `ExtensionXPCServiceHost.swift` uses `NSXPCListener(machServiceName: "com.ebullioscopic.Atoll.xpc")`. `ExtensionRPCServer.swift` notes "Listens on localhost:9020 for JSON-RPC 2.0 requests over WebSocket" (Network.framework `NWListener`). RPC methods are `atoll.getVersion`, `requestAuthorization`, `checkAuthorization`, `presentLiveActivity`, `updateLiveActivity`, `dismissLiveActivity`, `present/update/dismissLockScreenWidget`, `present/update/dismissNotchExperience`, `getShelfItems`, `addFilesToShelf`, `subscribeShelfEvents`, and more. `AtollDistributedNotifications.swift` only broadcasts lifecycle (`com.ebullioscopic.Atoll.lifecycle.didBecomeActive/Idle`). — [services/Extensions/](https://github.com/Ebullioscopic/Atoll/tree/dev/DynamicIsland/services/Extensions)
- Security fix: the RPC port 9020 had been bound to the wildcard address. It now binds loopback only (2.3.3). — [Atoll CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)
- NotchNotification (MIT, macOS 12+): `NotchNotification.present(message:)`, `present(error:interval:)`, `present(bodyView:interval:)`. In-process only; "works even on devices without a notch"; refactored from NotchDrop. — [Lakr233/NotchNotification README](https://github.com/Lakr233/NotchNotification)
- SuperIsland: JavaScript extension SDK rendered natively, with APIs like `notifications.send`, `http.fetch`, `system.getNowPlaying`. Its notification sources include public distributed notifications. — [SuperIsland EXTENSIONS-API.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/EXTENSIONS-API.md)
- Droppy ships a DroppyKit SDK and an MCP server ("lets Claude, Cursor and Codex use Droppy"). — sibling notes `droppy.md`; [Droppy docs](https://getdroppy.app/docs)
- boring.notch has no extension or IPC surface for activities. Its only XPC is a privileged brightness helper (`XPCHelperClient`). It has no Focus, download or screen-recording detection in its tree (code read: no matches for `DoNotDisturb`, `crdownload` or `screencapture`). — [boring.notch](https://github.com/TheBoredTeam/boring.notch)

### Inferences
- Recommended IPC design for a new notch app, in layers:
  1. A **URL scheme** (`mynotch://activity?...`) for shell and Shortcuts one-shots.
  2. A **localhost HTTP/WebSocket JSON endpoint** bound to 127.0.0.1 with a per-client token. This makes the app compatible with Claude Code HTTP hooks and any language.
  3. An optional **XPC Mach service plus Swift SDK** for native apps.
  4. Listening to a documented **DistributedNotificationCenter** name for fire-and-forget events. Note that distributed notifications are unauthenticated and payloads must be plist-safe.
- Learn from Atoll's mistakes: bind loopback only, require user authorisation per client, and cap activity lifetime and string sizes.
- Licensing: Atoll and boring.notch are GPL-3. AtollExtensionKit is LGPL-3. NotchNotification and NotchDrop are MIT. Reimplement from these descriptions rather than copying GPL code into a closed app.

### Gaps
- I didn't read the AtollExtensionKit source to confirm whether it also uses the WebSocket path.
- I couldn't read Droppy's and NotchNook's private implementations (closed source).

---

## Catalogue: iPhone Dynamic Island activity → macOS route (summary)

| iPhone DI activity | Mac route | Method / API | Permissions | Reliability | Risk |
|---|---|---|---|---|---|
| Maps turn-by-turn | NONE (iPhone-only; mirrored menu-bar item unreadable) | Possible AX scrape of the menu extra (untested) | Accessibility | Very low | High |
| Other iPhone Live Activities (Uber, sports, flights) | NONE public | AX scrape (untested) or the app's own web APIs | Accessibility / network | Low | High |
| Phone/FaceTime call ongoing + duration | HEURISTIC on PUBLIC API | Core Audio `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput` + PID → bundle-ID list; CMIO camera flag | None for the read (verify mic TCC isn't triggered) | Good for "in call" | Low |
| Incoming call ringing / caller ID | HEURISTIC | FaceTime/Phone launch + AX/OCR of the banner | Accessibility (+ Screen Recording for OCR) | Low | High |
| Timer (Clock app) | PRIVATE | `com.apple.mobiletimerd` prefs `MTTimers` + `log stream` subsystem `com.apple.mobiletimer.logging` + AX of the menu extra (Atoll `SystemTimerBridge.swift`) | Accessibility | Medium-low | Medium |
| Own timers / stopwatch | PUBLIC | In-app | none | High | Low |
| Screen recording | PRIVATE | `CGSIsScreenWatcherPresent`, `CGSRegisterNotifyProc` 1502/1503, `screencapture` process | none (stop needs Accessibility/Automation) | Good | Medium |
| Camera / mic in use | PUBLIC | CMIO / Core Audio `DeviceIsRunningSomewhere` listeners | none | High (debounce) | Low |
| Downloads | HEURISTIC | `~/Downloads` watcher; `.crdownload/.download/.part/.opdownload`; xattr `com.apple.progress.fractionCompleted`; try `Progress.addSubscriber(forFileURL:)` | Downloads folder TCC | Good | Low |
| AirDrop (own sends) | PUBLIC | `NSSharingService(.sendViaAirDrop)` delegate (no granular progress) | none | Medium | Low |
| AirDrop incoming / Finder copy progress | Unknown | `Progress.addSubscriber` (untested) | — | Unknown | — |
| Now Playing | PRIVATE | MediaRemote via `mediaremote-adapter` (perl) | none (+ Apple Events for per-app control) | Good on 27.0 so far | Medium-high (Apple may close it) |
| Charging / battery | PUBLIC | IOKit power sources | none | High | Low |
| AirPods / BT connect | PUBLIC (+PRIVATE battery) | IOBluetooth connect notifications; private props or BLE for per-bud battery | Bluetooth | Good / medium | Low / medium |
| Focus / DND | PRIVATE | `_NSDoNotDisturbEnabled/DisabledNotification`; `Assertions.json` + `ModeConfigurations.json` | Full Disk Access for names | Medium | Medium |
| Lock / unlock | Semi-private | `com.apple.screenIsLocked/Unlocked` distributed notifications | none | High | Low |
| Face ID / Touch ID prompt | NONE found | — | — | — | — |
| Apple Pay | NONE found | — | — | — | — |
| Other apps' notifications | PRIVATE | `usernoted` db2 SQLite (Full Disk Access) or AX on banners | Full Disk Access / Accessibility | Medium-low | High (privacy, redaction changes) |
| Sports scores | Web API | Poll a scores API | network | Depends on API | Low |
| Delivery / rideshare | NONE practical | — | — | — | — |
| Claude Code | PUBLIC | Hooks: command → Unix socket (vibe-notch) or `type: "http"` → localhost | none | High | Low |
| Xcode build | HEURISTIC | Xcode Behaviors run script → URL scheme/socket | user setup | Medium | Low |
| Third-party push into the notch | Own design | XPC Mach service + SDK (AtollExtensionKit), localhost JSON-RPC (Atoll :9020), Unix socket, URL scheme, distributed notifications | per-client user authorisation | — | Low if loopback + auth |
