# Picking notch-app features from six rivals

The six apps fall into two camps, and the split helps you decide what to build. **MediaMate** (HUDs plus Now Playing) and **Alcove** (media, HUDs, status alerts, calendar, lock screen) are deliberately narrow and win praise for polish. **Droppy** (about 40 opt-in "Droplets"), **Atoll** (open-source, GPL-3.0) and **Notchy** (74 advertised features) try to do everything, and reviewers credit them for breadth while complaining about CPU use, permission prompts, learning curves and regressions. **SuperIsland** sits in between, with about nine built-in modules and a JavaScript extension SDK. All six share a common core: a notch or pill overlay, Now Playing with art and controls, and a volume HUD. Most also offer a non-notch pill, battery alerts and a calendar. That core is buildable with mostly public APIs. The hard, fragile features are the ones built on private frameworks: any-app Now Playing (MediaRemote, broken for third-party apps since macOS 15.4 and worked around with `mediaremote-adapter`), brightness and keyboard-backlight HUDs (DisplayServices/CoreBrightness), lock-screen widgets (SkyLight) and AirPods battery levels (private IOBluetooth). Prices as of October 2026 are Droppy $9.99, Alcove about $14.99, MediaMate about €6.99 and Notchy $24.99 (it switched from free in the last week). **Atoll and SuperIsland are already free**, so if the only goal is avoiding payment, those two cover it. If the goal is to learn by building, the master checklist below numbers 77 features with build difficulty and API risk, so you can reply with the numbers you want.

## Six apps span a focused-to-kitchen-sink spectrum

| App | Maker | Price / licence (Oct 2026) | Min macOS | Notch vs non-notch | Personality |
|---|---|---|---|---|---|
| **Droppy** | Jordy Spruit (`iordv`) | $9.99 one-time, 2 Macs, 3-day trial; began MIT, then GPL-3.0 + Commons Clause, now paid (source status unclear) | 14 Sonoma; Apple silicon + Intel | Notch island; Dynamic Island-style pill + menu bar on notchless Macs and external displays | Kitchen-sink "utility suite", tamed by off-by-default Droplets |
| **SuperIsland** | Shobhit (`shobhit99`) | Free; source on GitHub but **no LICENSE file**; Aptabase analytics | 14 Sonoma; separate arm64/Intel DMGs | "Works on any Mac"; monitor picker | Mid-size, developer-flavoured, hackable via JS extensions |
| **Atoll** | Hariharan Mudaliar (Ebullioscopic) | Free, **GPL-3.0**, donationware | 14.6 (README says 14.0); Universal | Notch-first; simulated notch on non-notch/external since v2.0 | Maximal kitchen-sink, almost everything toggleable |
| **MediaMate** | Wouter Hennen | ~€6.99 one-time on Gumroad, 30-min demo; closed source | 13 Ventura; Universal | All Macs; separate styles for notch and non-notch displays | Ultra-focused HUD + Now Playing; maintenance mode |
| **Alcove** | Henrik Ruscon | ~$14.99 one-time, 3 Macs, 72-h trial; closed source | 15 Sequoia | "Simulated notch" pill on non-notch Macs | Focused, polish-first, "Apple-like" |
| **Notchy** | Vishva Variya | $24.99 one-time per Mac, 7-day trial (was free until ~26 Oct 2026); closed source | 13 Ventura; Universal since v1.0.98 | Virtual pill on any Mac; per-display choice | Extreme kitchen-sink, 74 features |

**Droppy** started in January 2026 as a "completely free and open source (MIT license)" notch file shelf ([hunted.space](https://www.hunted.space/product/droppy-3)) and grew into a paid suite. It now costs **$9.99 one-time for two Macs**, with lower prices in 126 countries and a 3-day full trial ([getdroppy.app](https://getdroppy.app/)). It needs **macOS 14 Sonoma** and supports notchless Macs and external displays through a Dynamic Island-style pill ([getdroppy.app](https://getdroppy.app/)). Its signature idea is a floating "basket" shelf that appears when you shake the mouse while dragging, which the maker built specifically for Macs without a notch ([Product Hunt](https://www.producthunt.com/products/droppy-4)).

**SuperIsland** is a free Swift/SwiftUI app whose README and docs describe a three-state island (188×34 compact, 360×80 expanded, 400×200 full) hosted in a non-activating `NSPanel` ([EXTENSIONS-API.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/EXTENSIONS-API.md)). It requires macOS 14 and ships separate Apple silicon and Intel builds ([README](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/README.md)). The website calls it "Free and open source" ([dynamicisland.app](https://dynamicisland.app)), but no LICENSE file exists in the repo ([raw LICENSE 404](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/LICENSE)). Its last tagged release is 1.0.10 (12 June 2026) ([Releases](https://github.com/shobhit99/SuperIsland/releases)).

**Atoll** is the most feature-dense open-source option. It is **GPL-3.0** and derived from boring.notch's codebase ([NOTICE](https://github.com/Ebullioscopic/Atoll/blob/dev/NOTICE)), and it is funded by donations ([Softpedia](https://mac.softpedia.com/get/Utilities/Atoll.shtml)). Its Sparkle appcast requires **macOS 14.6** ([appcast.xml](https://github.com/Ebullioscopic/Atoll/blob/dev/Updates/appcast.xml)), and v2.0 added "Dynamic Island support for external screens and non-notched Macs" ([Release v2.0.0](https://github.com/Ebullioscopic/Atoll/releases?page=3)).

**MediaMate** does "HUD replacement plus Now Playing" and nothing else. It requires **macOS 13**, and its site says "All macs are supported" ([official site](https://wouter01.github.io/MediaMate/)). It sells on Gumroad for **€6.99** ([Gumroad](https://wouter01.gumroad.com/l/mediamate)). The latest version, 3.8.4 (August 2026), is a compatibility release, and no new features have shipped since September 2025 ([GitHub releases](https://github.com/Wouter01/MediaMate-Releases/releases)).

**Alcove** is the polish benchmark. It costs **$14.99 one-time for up to three Macs, with a 72-hour trial and 14-day refunds** ([apps.deals](https://blog.apps.deals/best-notch-apps-mac)). It requires **macOS 15** ([Homebrew](https://formulae.brew.sh/cask/alcove)) and appears as a pill on Macs without a notch ([Softpedia](https://mac.softpedia.com/get/System-Utilities/Alcove.shtml)).

**Notchy** advertises 74 features on its homepage ([notchy.dev](https://notchy.dev)). It requires **macOS 13** and ships one universal build ([notchy.dev/download](https://notchy.dev/download)). Its pricing page now says **$24.99 one-time per Mac with a 7-day trial** ([notchy.dev/pricing](https://notchy.dev/pricing)), even though the maker said at launch that it would "never be monetized" ([Product Hunt](https://www.producthunt.com/products/notchy)).

## What each app actually ships

The lists below come from developer sites, docs, changelogs and source code where they were available. Notchy's list in particular is entirely self-reported.

### Droppy: a file shelf that became a suite

**Shell:** a notch island on notched Macs and a Dynamic Island-style pill elsewhere, with settings for open size, auto-expand and collapse, animation speed, gestures, "hide physical notch", per-display visibility, hide in Mission Control, hide from screenshots, hide on fullscreen, haptics and "hold to reveal" ([docs/settings](https://getdroppy.app/docs/settings)).

**Files:** a notch File Tray plus a shake-summoned floating "Basket". The basket supports multiple trays, shake sensitivity, auto-hide and retention, and a "protect originals" copy-not-move setting ([docs/settings](https://getdroppy.app/docs/settings); [docs/troubleshooting](https://getdroppy.app/docs/troubleshooting)). Quick Action tiles send dropped files to Mail, the cloud or AirDrop. Built-in Transform tools compress, convert, trim, make GIFs and merge PDFs on-device using FFmpeg and Ghostscript ([getdroppy.app](https://getdroppy.app/)). Droppy Cloud share links allow 200 MB per file and expire after 3 days.

**Clipboard:** searchable history with type filters, tags, source-app icons, duplicate handling and clear-on-quit ([docs/settings](https://getdroppy.app/docs/settings)). An early review noted it was off by default and could skip passwords and exclude apps ([AppAddict, Jan 2026](https://appaddict.app/post/droppy-a-notch-app-with-a-lot-to-like)).

**Media:** Now Playing with album art, seek slider, audio visualiser, media gestures, selectable playback sources, a "Playing Next" queue, Apple Music motion art and Apple TV control. A Floating Player was still in beta or nightly builds ([getdroppy.app](https://getdroppy.app/)).

**HUDs and status:** volume, brightness and keyboard-backlight HUDs, including on external monitors. Also battery/charging, AirPods battery, Do Not Disturb, power state and mic/camera indicators ([1of1Adam README mirror](https://github.com/1of1Adam/Droppy)).

**Live Activities:** several at once. Examples include coding-agent progress, screen recording with a Stop button, meeting controls, message replies (iMessage, WhatsApp, Telegram), downloads and a next-meeting countdown ([getdroppy.app](https://getdroppy.app/)).

**Lock screen:** Now Playing with motion art and synced lyrics, widgets, brightness and volume sliders, and lock/unlock sounds ([docs/settings](https://getdroppy.app/docs/settings)).

**Droplets (40, all opt-in):** these span productivity (Calendar, Pomodoro, Notes, Weather, Teleprompter, Termi-Notch terminal, a Spotlight-style launcher, Xcode Builds), media (Spotify, Lyrics, per-app Audio Control up to 200%), AI (Remove Background, Voice Transcribe, coding-agent usage, MCP), capture (screen capture with annotation, Camera mirror, OCR), files (LocalSend, Finder Services) and system tools (Window Snap, notification banners, Stay Awake, menu-bar manager, System Stats, uninstaller). Third parties can build Droplets with the DroppyKit SDK and publish them to a Droplet Store ([docs/droplets](https://getdroppy.app/docs/droplets); [docs index](https://getdroppy.app/docs)). There is also an MCP server for AI apps and a free iPhone companion app.

### SuperIsland: modules plus a JavaScript SDK

**Shell:** compact, expanded and full states. You swipe to cycle modules, and modules can appear as auto-dismissing HUDs ([EXTENSIONS-API.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/EXTENSIONS-API.md)). A "minimal notch view" shows one leading and one trailing item around the hardware notch, chosen by a `precedence` value ([extension API](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/SUPER-ISLAND-EXTENSION-API.md)).

**Built-in modules:**

- **Now Playing:** uses the system media feed with Apple Music and Spotify fallbacks. Chrome-only browser detection is opt-in and works through Apple Events JavaScript ([NOW_PLAYING.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/NOW_PLAYING.md)).
- **Volume HUD:** the brightness HUD was removed in 1.0.1/1.0.2 ([Releases](https://github.com/shobhit99/SuperIsland/releases)).
- **Battery:** pulses at 20%.
- **Wi-Fi and Bluetooth connectivity.**
- **Calendar:** per-account calendar filters, a month grid, pre-event reminders and Zoom/Meet/Teams link detection ([CALENDAR.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/CALENDAR.md)).
- **Weather:** includes an hourly forecast.
- **Notifications:** limited to the app's own extensions, a WhatsApp bridge and apps that post distributed notifications, because "macOS does not provide a public API" ([NOTIFICATIONS.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/NOTIFICATIONS.md)).
- **File Shelf:** handles files, folders, URLs, text and images, with pin, Quick Look, Share and AirDrop actions and configurable retention ([SHELF.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/SHELF.md)).
- **Mascot companion.**

Extras include a voice-following Teleprompter and live football scores ([Releases](https://github.com/shobhit99/SuperIsland/releases)).

**Bundled extensions:** AI usage (Codex and Claude limits), coding-agent status that focuses the matching iTerm2 tab, WhatsApp Web (running on a bundled Node binary), Pomodoro, Linear mentions and a Last.fm scrobbler ([project.yml](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/project.yml)).

**SDK:** an extension is a `manifest.json` plus `index.js` running in sandboxed JavaScriptCore. It returns a JSON view tree that SwiftUI renders natively, with permission-gated APIs for storage, network, media and notifications ([EXTENSIONS.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/EXTENSIONS.md)).

**Settings:** three home slots, animation intensity, compact size, power modes (Normal, Smart, Low Power) with a central refresh scheduler, multi-monitor support, a monitor picker and hide-on-fullscreen ([APPEARANCE.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/APPEARANCE.md); [ENERGY.md](https://raw.githubusercontent.com/shobhit99/SuperIsland/main/docs/ENERGY.md)).

### Atoll: everything, individually switchable

**Shell:** hover to expand, with tabs for home, shelf, timer, stats, LLM usage, colour picker, notes, clipboard, terminal and extensions ([enums/generic.swift](https://github.com/Ebullioscopic/Atoll/blob/dev/DynamicIsland/enums/generic.swift)). There are Standard and Alcove-inspired Minimalistic modes. Gestures include two-finger swipe to open or close and horizontal swipe to skip or seek, with haptics. Other settings cover fullscreen media detection, hide from screen capture, and live activities that slide out of the way of app menus ([README](https://github.com/Ebullioscopic/Atoll); [CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)).

**Media:**

- **Sources:** controllers for Apple Music, Spotify, Cider, Amazon Music, TIDAL, YouTube Music and generic MediaRemote ([MediaControllers/](https://github.com/Ebullioscopic/Atoll/tree/dev/DynamicIsland/MediaControllers)).
- **Visualiser:** a real-time spectrum built on CoreAudio process taps and Metal.
- **Artwork:** Spotify Canvas and Apple Music animated artwork.
- **Lyrics:** LRCLIB-synced with word-by-word sweep, and can be pinned under the closed notch.
- **Library and playback controls:** liking songs, shuffle and repeat.
- **Output:** an AirPlay/output selector, and a per-app volume mixer that is still pre-release ([CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)).

**HUDs:**

- **System replacements:** volume, brightness and keyboard backlight in inline, OSD, vertical and circular styles.
- **External displays:** DDC through BetterDisplay or Lunar.
- **Device and status:** Bluetooth connect with battery, an AirPods listening-mode HUD, Caps Lock, and network HUDs.

**Live activities:** Focus, screen recording, camera and mic privacy indicators, downloads, battery including charging wattage, timers, reminders and extension-provided activities, several at once ([README](https://github.com/Ebullioscopic/Atoll)).

**Lock screen:** widgets for media, a timer, battery, Bluetooth, weather, calendar, reminders and Focus, plus a fingerprint-style unlock animation, all drawn through SkyLightWindow ([CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)).

**Utilities:**

- **Stats and timers:** system stats (CPU per core, temperatures, GPU, memory, disk, network) and timers.
- **Calendar and Reminders:** includes Join buttons for meetings.
- **Clipboard history:** opens with ⌘⇧V.
- **Shelf:** supports AirDrop and LocalSend.
- **Notes and tools:** notes with Apple Notes sync, a colour picker, a SwiftTerm terminal, keep-awake and a webcam mirror.

**AI and developer:**

- **Screen Assistant:** works with Gemini, OpenAI, Claude, Groq or local Ollama.
- **LLM Usage tab:** covers Claude Code, Codex, Cursor and Antigravity.
- **Extension SDK:** AtollExtensionKit, over XPC ([CHANGELOG 2.3.0](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)). Its marketplace page listed "No Extensions Found" ([Atoll Marketplace](https://getatoll.app/marketplace)).

### MediaMate: the polished specialist

**HUDs:**

- **Coverage:** replaces the volume, display-brightness and keyboard-backlight HUDs without disabling SIP ([FAQ](https://wouter01.github.io/MediaMate/faq)).
- **Themes:** iOS, Circular, Notch and Classic ([BGR](https://www.bgr.com/2177168/apps-that-make-macbook-notch-useful/)), and each display can use a different style ([releases p3](https://github.com/Wouter01/MediaMate-Releases/releases?page=3)).
- **Interaction and display:** two-finger drag to change values, percentage labels, adjustable on-screen duration, Liquid Glass on macOS 26, and output-device icons for AirPods and Beats ([GitHub releases](https://github.com/Wouter01/MediaMate-Releases/releases)).

**Now Playing HUD:** appears on track change, play/pause or volume change, or by hotkey, and can expand on notch hover. It has previous/next, ±15 s and scrubbing controls, and clicking it opens the source app ([MacStories](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/); [releases p2](https://github.com/Wouter01/MediaMate-Releases/releases?page=2)). Media keys can be routed exclusively to Apple Music or Spotify.

**External displays and automation:** Lunar and BetterDisplay modes handle external-monitor brightness ([FAQ](https://wouter01.github.io/MediaMate/faq)). It also offers Shortcuts actions, Focus Filters and a menu-bar quick-toggle item.

**Not included:** no file shelf, calendar, battery alerts, notifications, clipboard or timers.

### Alcove: few features, executed beautifully

**Now Playing:** album art with a waveform visualiser. Hover, click or swipe reveals controls, a seek bar and a volume slider ([Softpedia](https://mac.softpedia.com/get/System-Utilities/Alcove.shtml)), and swiping sideways skips tracks ([ifun.de](https://www.ifun.de/alcove-bringt-das-dynamic-island-auf-den-mac-246561/)).

**HUDs and status alerts:** replacement volume and brightness HUDs. Toggleable alerts cover Battery, Connectivity, Focus, Display and Sound ([MacSources](https://macsources.com/alcove-for-mac-a-truly-native-looking-mac-app/)).

**Calendar:** a calendar widget with an optional "Duo" view that shows music and calendar together ([Softpedia](https://mac.softpedia.com/get/System-Utilities/Alcove.shtml)).

**Lock screen and pill:** lock-screen versions of these widgets, and a simulated-notch pill on non-notch Macs.

**Settings:** launch at login, hide the menu-bar icon, and per-alert toggles.

**Not included:** comparison pages consistently list no file shelf, AirDrop, clipboard, timers or extensions ([Seam](https://getseam.app/blog/alcove-vs-boring-notch); [Droppy blog](https://getdroppy.app/blog/best-mac-notch-apps-2026)). Its "notifications" cover only Alcove's own alerts.

### Notchy: 74 features, all self-reported

All of the following comes from [notchy.dev](https://notchy.dev) and has not been verified independently.

**Media:** Now Playing (Spotify and Apple Music), synced lyrics, an output switcher, an AirPods manager, a per-app Sound Mixer with EQ (macOS 14.4+), a process-tap spectrum visualiser and mic mute.

**Files and clipboard:** a persistent shelf with AirDrop, a screenshot shelf, clipboard history with smart actions, OCR, text snippets, an image converter, zip/unzip, download alerts, a drive-eject prompt and screen capture.

**Productivity:** Pomodoro and stopwatch, a Focus island, keep-awake, notes, Reminders, a calendar, a Shortcuts launcher, an app launcher, a command palette, search and translate, weather, a stocks ticker and a teleprompter.

**HUDs and status:** volume and brightness HUDs in alternative styles, battery and full-charge alerts, Bluetooth accessory battery, Caps Lock and keystroke HUDs, camera/mic privacy indicators, system stats, keyboard backlight and DDC external-display brightness.

**Communication:**

- **Calls and messages:** a Call Island, and a Message Island with inline reply (works through Accessibility).
- **Notifications:** a Notification Mirror (needs Full Disk Access), and multiple live activities.

**Developer and AI:**

- **AI agents:** an AI usage tracker, Claude Code/Codex approval islands and agent activity.
- **Developer tools:** shell long-command alerts, GitHub PRs, a terminal, and a local API on 127.0.0.1:9999.

**Desktop and security:** window snapping, menu-bar icon hiding, desktop and lock-screen widgets, a camera mirror, a colour eyedropper, Face Unlock, knock gestures, a keyboard cleaning lock and hide-from-capture. It also offers Liquid Glass, Lottie idle animations, a pill on any Mac and Sparkle updates.

## Users reward polish and punish sprawl

The clearest pattern in the feedback is that **the narrow apps collect the warmest praise, and the broad apps collect the bug reports.** Alcove is called "the only notch app that feels like Apple designed it" ([Mac Dept.](https://www.theodorehq.com/macdept/app/alcove)) and scored 99% at MacSources ([MacSources](https://macsources.com/alcove-for-mac-a-truly-native-looking-mac-app/)). MacStories called MediaMate "stable and well-designed", a set-and-forget utility with no app-specific cons ([MacStories](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/)).

Their complaints point the other way: **too little for the money**. Alcove is "a bit on the pricey side" ([SlashGear](https://www.slashgear.com/2175261/macos-apps-give-features-apple-doesnt-include/)), and early commenters noted that DynamicLake offered weather, notifications and file management that Alcove lacked, and that actions had to be set in Settings rather than in the notch ([ifun.de](https://www.ifun.de/alcove-bringt-das-dynamic-island-auf-den-mac-246561/)). MediaMate's developer initially declined richer notch controls "to keep the UI simple", although previous/next and ±15 s buttons arrived later ([Reddit r/MacOS mirror](https://pol1.lr.ggtyler.dev/r/MacOS/comments/wl0hk8/followup_of_my_app_mediamate)).

The kitchen-sink apps show the opposite trade-off. AppAddict measured Droppy v14 at **about 5% CPU and 275 MB RAM idle on an M4** and warned "some users may feel the app tries to do too much" ([AppAddict, May 2026](https://appaddict.app/post/new-droppy-release-is-a-full-featured-utility-suite)). Mac Observer said it "can feel unpolished at times" ([Mac Observer](https://www.macobserver.com/?p=450697)), and Droppy's own docs list **11 macOS permissions** ([docs/permissions](https://getdroppy.app/docs/permissions)).

Atoll's changelog admits that its HUD-suppression polling was "the single largest consumer of CPU in the app" ([CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)). Its issue tracker shows HUD errors, widget overlap, unreliable hover-to-expand and a macOS 27 beta crash ([Issues](https://github.com/Ebullioscopic/Atoll/issues); [Issue #832](https://github.com/Ebullioscopic/Atoll/issues/832)). A German commenter preferred Boring Notch as "more restrained and minimal" ([ifun.de](https://www.ifun.de/atoll-erweitert-macbook-notch-um-neue-steuerelemente-270769/)).

Notchy's own reviews FAQ concedes lag, over-eager hover and a learning curve, and one in-app reviewer asked for a "single tasking" mode ([notchy.dev/reviews](https://notchy.dev/reviews/)). Its changelog is a long run of CPU, energy and crash fixes ([notchy.dev/changelog](https://notchy.dev/changelog)). Even SuperIsland's one critical Product Hunt question was about how it stops competing events from getting noisy, and the maker replied "bro what" ([Product Hunt](https://www.producthunt.com/products/superisland)).

Breadth still earns real praise when users can switch it off. Softpedia's 5/5 review of Atoll said the reviewer did not need most features but valued being able to disable them ([Softpedia](https://mac.softpedia.com/get/Utilities/Atoll.shtml)). Droppy's answer to bloat is to keep every Droplet off until the user enables it.

For a solo developer, the lesson is that **feature count is cheap to claim and expensive to keep working**. Every macOS release breaks notch placement, fullscreen behaviour or media APIs. MediaMate needed several patch releases each for macOS 15 and 26, and the 15.4 MediaRemote change broke Now Playing in MediaMate, Alcove and others ([MediaMate releases](https://github.com/Wouter01/MediaMate-Releases/releases); [AlternativeTo](https://alternativeto.net/software/alcove/about)). A small core with very smooth animations and low idle CPU, plus opt-in modules, matches what users actually reward.

## Master checklist: 77 numbered features to choose from

**How to read the tables:** the app columns are **Drp** Droppy, **SpI** SuperIsland, **Atl** Atoll, **MM** MediaMate, **Alc** Alcove and **Nty** Notchy. **✓** means the app has the feature. **◐** means partial, limited, beta-only or only through an add-on that changes its nature. **✗** means the feature was not found in this research, which does not prove it is absent. **?** means the evidence is unclear. **Build** is a rough difficulty for a Swift/SwiftUI student. **Easy** means public APIs and a few days of work. **Medium** means fiddly but public or well-trodden. **Hard** means private frameworks, permission-heavy work, or something likely to break with each macOS release. Technical notes draw on the building-blocks research. API names marked "unverified" come from general knowledge rather than a fetched source.

### A. Notch shell, window and layout

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Notch overlay that expands on hover/click (compact ↔ expanded) | ✓ | ✓ | ✓ | ◐ | ✓ | ✓ | Medium | Borderless, transparent, non-activating `NSPanel` at `.mainMenu + 3`, placed on `screen.frame` (not `visibleFrame`); notch = `safeAreaInsets.top > 0`, width from `auxiliaryTopLeftArea`/`RightArea` ([boring.notch window](https://raw.githubusercontent.com/TheBoredTeam/boring.notch/main/boringNotch/components/Notch/BoringNotchWindow.swift)). DynamicNotchKit (MIT) does this for you. MM ◐: only its HUDs/Now Playing grow from the notch |
| 2 | Pill / fake notch on notchless Macs and external displays | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | Medium | Menu-bar-height fake notch or `.floating` pill; DynamicNotchKit switches automatically. Atoll's is newer and "second-class" |
| 3 | Multi-display: choose displays / one island per screen | ✓ | ◐ | ✓ | ✓ | ? | ✓ | Medium | One panel per `NSScreen` keyed by display UUID; rebuild on screen-parameter change ([DeepWiki boring.notch](https://deepwiki.com/TheBoredTeam/boring.notch)). SpI: monitor picker, simultaneous islands unverified |
| 4 | Gestures (swipe to skip/switch, swipe to open/close) + haptics | ✓ | ✓ | ✓ | ◐ | ✓ | ✓ | Medium | Trackpad scroll events on the panel; MM ◐ = two-finger drag on HUD values only |
| 5 | Auto-hide in fullscreen apps / during fullscreen video | ✓ | ✓ | ✓ | ? | ? | ✓ | Easy–medium | Alcove users reported it covering toolbars on a second monitor in fullscreen; macOS 26 needed fixes in MM |
| 6 | Hide from screenshots / screen recording | ✓ | ? | ✓ | ? | ? | ✓ | Easy | Window sharing-type flag (unverified); Notchy admits "some apps can still capture it" |
| 7 | Clicks pass through around the island (no dead zone over menus) | ? | ? | ✓ | ? | ◐ | ✓ | Medium | A fully click-through panel cannot detect hover, so resize on hover or toggle `ignoresMouseEvents` ([notch-ui skill](https://skillselion.com/skills/fayazara/macos-app-skills/macos-notch-ui)). Alcove covered app menus (2025 complaint); Notchy once had an unclickable notch rectangle |
| 8 | Several live activities at once + priority rules | ✓ | ◐ | ✓ | ✗ | ◐ | ✓ | Medium–hard | A design problem more than an API one. Alcove ◐ = "Duo" media + calendar; Notchy shares one slot for quick alerts, newest wins |

### B. Media / Now Playing

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 9 | Now Playing: art, title, play/pause/next/prev | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Easy (Music/Spotify) / Medium (any app) | Apple Music and Spotify via AppleScript need the Apple Events entitlement + usage string; any-app needs #10 |
| 10 | Any-app / browser source detection | ? | ◐ | ✓ | ◐ | ◐ | ◐ | Hard | Private MediaRemote stopped working for third-party apps in macOS 15.4; `ungive/mediaremote-adapter` (BSD-3) runs `/usr/bin/perl` because `com.apple.*` processes are allowed, and it reports only the system-"elected" player ([adapter](https://github.com/ungive/mediaremote-adapter); [issue #41](https://github.com/ungive/mediaremote-adapter/issues/41)). Apple could close this at any release |
| 11 | Seek bar / scrubbing and ±10–15 s skip | ✓ | ? | ✓ | ✓ | ✓ | ✓ | Easy (after 9/10) | Adapter exposes `seek` and ±15 s `send` commands |
| 12 | Audio visualiser | ✓ | ◐ | ✓ | ✗ | ✓ | ✓ | Easy (fake bars) / Hard (real spectrum) | Real spectrum needs Core Audio process taps + System Audio Recording permission; always-on visualisers cost battery ([Seam](https://getseam.app/blog/alcove-vs-boring-notch)). SpI ◐ inferred from mic permission |
| 13 | Synced lyrics | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Medium | LRCLIB (free). Query only when enabled: Atoll once sent track metadata to LRCLIB with lyrics off |
| 14 | Animated artwork (Apple Music motion art / Spotify Canvas) | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | Hard | Sources undocumented; Atoll had high memory use and double video decoding |
| 15 | Like / favourite the current song | ? | ✗ | ✓ | ✗ | ✗ | ✓ | Medium | Spotify Web API (OAuth PKCE); Apple Music via scripting |
| 16 | Output device / AirPlay switcher | ? | ✗ | ✓ | ◐ | ✗ | ✓ | Medium | CoreAudio default-output device (unverified). MM ◐ shows only the output-device icon |
| 17 | Per-app volume mixer | ✓ | ✗ | ◐ | ✗ | ✗ | ✓ | Hard | Core Audio process taps; Notchy needs macOS 14.4+. Atoll ◐ = pre-release only |
| 18 | Floating mini-player window | ◐ | ✗ | ✓ | ✗ | ✗ | ✗ | Medium | A second panel sharing the media model; Droppy's is beta/nightly |
| 19 | Route media keys to a chosen player | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | Medium | Conflicts with other media-key tools; MM added an "External App Support" mode ([FAQ](https://wouter01.github.io/MediaMate/faq)) |

### C. HUD replacements

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 20 | Volume HUD replacing the system OSD | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Medium (show alongside) / Hard (suppress OS HUD) | Intercept keys with an active event tap, set volume via CoreAudio and swallow the event. Suppression needs **Accessibility** ([Apple DTS](https://developer.apple.com/forums/thread/820594); [supernotch PR](https://github.com/budimanr3101/supernotch/pull/9)). macOS 26 moved the OS HUD into Control Center. volumeHUD (MIT) disables interception if the level didn't change ([volumeHUD](https://github.com/dannystewart/volumeHUD)) |
| 21 | Display-brightness HUD | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | Hard | Private DisplayServices/CoreBrightness; volumeHUD calls brightness "experimental", built-in display only. SpI removed its brightness HUD |
| 22 | Keyboard-backlight HUD / control | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | Hard | Private frameworks; boring.notch isolates these in an XPC helper |
| 23 | Alternative HUD styles (circular, vertical, iOS, edge bar) | ◐ | ✗ | ✓ | ✓ | ◐ | ✓ | Easy | Pure SwiftUI once #20 works |
| 24 | External-monitor brightness/volume (DDC, Lunar, BetterDisplay) | ◐ | ✗ | ✓ | ✓ | ✗ | ✓ | Hard | DDC/CI via IOAVService (Notchy) or hand off to Lunar/BetterDisplay (Atoll, MM). Droppy ◐ = HUDs display on external screens |
| 25 | Caps Lock indicator | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | Easy | Watch modifier-flag changes |

### D. System status and alerts

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 26 | Mac battery: charging, low and full alerts | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | Easy | IOKit power-source notifications (unverified API names); hide on desktop Macs |
| 27 | Bluetooth device-connected toast | ◐ | ✓ | ✓ | ◐ | ✓ | ✓ | Medium | Droppy ◐ = AirPods HUD; MM ◐ = output icons in the volume HUD |
| 28 | AirPods / accessory battery levels | ✓ | ? | ✓ | ✗ | ? | ✓ | Hard | Private IOBluetooth properties or BLE-advertisement parsing ([cmsj.net](https://cmsj.net/2017/11/27/airpod-battery-ear-data.html)); AirBattery is AGPL-3.0, so do not copy it |
| 29 | Wi-Fi / network connectivity alerts | ? | ✓ | ◐ | ✗ | ✓ | ✗ | Easy | Public network-path monitoring; Atoll ◐ = dev branch only |
| 30 | Focus / Do Not Disturb indicator | ✓ | ✗ | ✓ | ◐ | ✓ | ✓ | Medium | Detection method not documented in research, so check before committing. MM ◐ = Focus Filters hide MediaMate |
| 31 | Camera / mic in-use indicator | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Easy–medium | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` + CoreAudio equivalent; callbacks can be spurious, so debounce ([Apple forums](https://developer.apple.com/forums/thread/697124)) |
| 32 | Mirror other apps' notifications | ✓ | ◐ | ✗ | ✗ | ✗ | ✓ | Hard | No public API (SuperIsland docs); Notchy needs **Full Disk Access**. Alcove shows only its own alerts |
| 33 | Calls / messages island with inline reply | ✓ | ◐ | ✗ | ✗ | ✗ | ✓ | Hard | Notchy uses Accessibility; SpI's WhatsApp bridge ships a Node binary. Fragile |
| 34 | System stats (CPU, RAM, GPU, network, temps) | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Medium (CPU/RAM) / Hard (temps) | Temperatures need SMC/IOReport (private); exelban/Stats (MIT) is the reference |
| 35 | Download progress / new-download alert | ✓ | ✗ | ◐ | ✗ | ✗ | ◐ | Medium | Atoll watches browser partial-file extensions (`.part`, `.opdownload`), in beta; Notchy alerts when a file lands |
| 36 | Screen-recording indicator with Stop | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | Medium–hard | Method not documented in research |

### E. Live activities and timers

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 37 | Timer / stopwatch / Pomodoro | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | Easy | Droppy and SpI provide it via add-ons; use wall-clock time so it doesn't drift (Notchy) |
| 38 | Keep-awake (caffeinate) | ✓ | ✗ | ◐ | ✗ | ✗ | ✓ | Easy | IOKit power assertion; Atoll ◐ = pre-release |
| 39 | Live tickers (sports scores, stocks) | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | Medium | Needs an external data API and refresh budget |

### F. Files and clipboard

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 40 | File shelf: drop on notch, drag back out | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | Medium | Drag detection over the notch region; SpI stores folders as security-scoped bookmarks, but Atoll notes non-sandboxed apps can't create them. NotchDrop (MIT) proves the shelf can ship on the App Store ([NotchDrop](https://github.com/Lakr233/NotchDrop)) |
| 41 | AirDrop / share sheet from the shelf | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | Easy | `NSSharingService(named: .sendViaAirDrop)`; Atoll and Droppy add LocalSend |
| 42 | Floating shelf at the cursor (shake while dragging) | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | Medium | Droppy's signature; global mouse-drag monitoring |
| 43 | File actions: zip, convert, compress, merge PDFs | ✓ | ✗ | ◐ | ✗ | ✗ | ✓ | Medium | Droppy bundles FFmpeg and Ghostscript (check their licences); Notchy uses `ditto` and offline image conversion |
| 44 | Hosted share links | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | Hard | Needs a server you pay for |
| 45 | Clipboard history (search, pins) | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Medium | Poll `NSPasteboard`; Apple's pasteboard-privacy prompt can render clipboard managers "basically useless" if denied ([Michael Tsai](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4)); App Store rejected auto-paste via `CGEvent.post` |
| 46 | Screen capture / screenshot shelf | ✓ | ✗ | ◐ | ✗ | ✗ | ✓ | Medium | Screen Recording permission; Atoll ◐ = snipping inside its AI assistant |
| 47 | OCR text capture | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | Easy | Apple Vision, on-device |

### G. Calendar and productivity

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 48 | Calendar: today / upcoming events | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | Easy | EventKit full access only ("can't request read-only"), `NSCalendarsFullAccessUsageDescription` ([Apple](https://developer.apple.com/documentation/eventkit/accessing-the-event-store.md)) |
| 49 | Meeting countdown + one-click join | ✓ | ✓ | ✓ | ✗ | ◐ | ? | Easy–medium | Parse Zoom/Meet/Teams links from event notes and location (SpI's approach); Alcove ◐ = upcoming-event alerts |
| 50 | Reminders | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | Easy | EventKit, `NSRemindersFullAccessUsageDescription`; Droppy dropped its Reminders extension |
| 51 | Weather | ✓ | ✓ | ✓ | ✗ | ? | ✓ | Easy | Open-Meteo (free, used by Atoll) + Location; cache and refresh only while visible (SpI) |
| 52 | Notes / scratchpad | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Medium | Typing needs a key window, and non-activating panels can't become key; boring.notch avoids text input entirely |
| 53 | Webcam mirror | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Easy | AVFoundation + Camera permission |
| 54 | Teleprompter under the camera | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | Easy (scrolling) / Medium (voice-following) | SpI follows your reading with Speech Recognition + mic |
| 55 | Colour picker | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | Easy | Notchy does it without Screen Recording permission |
| 56 | Command palette / app launcher / search | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | Medium | Droppy's Spotlight-style Droplet; Notchy's ⌃⌥K palette |
| 57 | Shortcuts / Focus Filter integration | ? | ✗ | ✗ | ✓ | ✗ | ✓ | Easy–medium | App Intents; MM exposes each HUD toggle as a Shortcuts action |
| 58 | Bundled desktop utilities (window snap, menu-bar hider, uninstaller) | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | Hard | Breadth with no notch value; Droppy's Window Snap judged weaker than dedicated tools; Notchy's menu-bar hider once pinned a CPU core |

### H. Lock screen

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 59 | Lock-screen widgets / Now Playing | ✓ | ✗ | ✓ | ◐ | ✓ | ✓ | Hard | Private **SkyLight**: Lakr233/SkyLightWindow (MIT) offers `.moveToSky()` but warns private APIs change between updates ([SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)). Alcove's developer locked himself out of his Mac four times building it ([Medium](https://medium.com/@teslathewest/the-story-behind-alcove-macos-dynamic-island-app-dadb5d97e8b0)). MM ◐ = HUDs on the lock screen |
| 60 | Lock/unlock animation and sounds | ✓ | ✗ | ✓ | ✗ | ✗ | ? | Medium (after 59) | Atoll draws a fingerprint-scan animation |
| 61 | Face Unlock | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | Hard / risky | Security-sensitive; even Notchy says it doesn't replace Face ID depth sensing |

### I. Developer and AI

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 62 | AI usage meters (Claude Code, Codex, Cursor limits) | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | Medium | Reads local auth files or OAuth usage endpoints that aren't stable public APIs; Atoll's token refresh once logged users out of Claude Code |
| 63 | Coding-agent status and approve/deny islands | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | Medium | Claude Code hooks → Unix socket, as in Vibe Notch (Apache-2.0) ([vibe-notch](https://github.com/farouqaldori/vibe-notch)) |
| 64 | Terminal in the notch | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | Medium | SwiftTerm (Atoll) or a PTY; same key-window issue as #52 |
| 65 | AI chat / screen assistant (bring your own key) | ◐ | ✗ | ✓ | ✗ | ✗ | ✓ | Medium | Store keys in Keychain; Atoll supports local Ollama. Droppy ◐ = AI action on selected text |
| 66 | Local API / MCP server for scripts and AI apps | ✓ | ✗ | ◐ | ✗ | ✗ | ✓ | Medium | Bind to 127.0.0.1 with a token: Atoll's extension port was once open to the whole LAN |
| 67 | Shell long-command alerts / GitHub PR list | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | Easy–medium | Opt-in zsh hook; GitHub API |

### J. Extensions and plugins

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 68 | Plugin system for extra modules | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | Hard | Lightest model: SpI's JavaScriptCore sandbox returning a JSON view tree rendered natively in SwiftUI. Heavier: Droppy's DroppyKit SDK + store; Atoll's XPC kit (marketplace empty) |
| 69 | API for other apps/scripts to push live activities | ◐ | ◐ | ✓ | ✗ | ✗ | ◐ | Medium | Distributed notifications, XPC or a local socket; Lakr233/NotchNotification (MIT) offers a one-line `present(message:)` |

### K. Settings and customisation

| # | Feature | Drp | SpI | Atl | MM | Alc | Nty | Build | API / risk note |
|---|---|---|---|---|---|---|---|---|---|
| 70 | Per-feature on/off toggles (off until enabled) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Easy | Droppy's off-by-default Droplets are its answer to bloat |
| 71 | Home layout editor / slot arrangement | ✓ | ✓ | ◐ | ✗ | ✗ | ✓ | Medium | SpI: left/centre/right slots; Atoll ◐ = music-control slots |
| 72 | Size, position, animation-speed and bounce tuning | ✓ | ✓ | ✓ | ✓ | ? | ✓ | Easy | Animate width/shape rather than opacity; show the window before toggling state ([notch-ui skill](https://skillselion.com/skills/fayazara/macos-app-skills/macos-notch-ui)) |
| 73 | Materials and themes (Liquid Glass, tints, idle/Lottie animations) | ✓ | ◐ | ✓ | ✓ | ◐ | ✓ | Easy–medium | Lottie for user idle animations (Notchy) |
| 74 | Remappable global shortcuts | ✓ | ◐ | ✓ | ✓ | ? | ✓ | Easy | sindresorhus KeyboardShortcuts (used by Atoll and MediaMate) |
| 75 | Energy / power modes with a central refresh scheduler | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | Medium | SpI's fix for early idle drain (1-second polling); every kitchen-sink app logged CPU fixes |
| 76 | Auto-updates (with a beta channel) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | Easy | Sparkle 2 with an EdDSA-signed appcast on GitHub Pages (boring.notch) |
| 77 | Menu-bar agent app: launch at login, hide icon, permission onboarding | ✓ | ✓ | ✓ | ✓ | ✓ | ? | Easy | `LSUIElement` agent app; onboarding matters when you need several TCC permissions |

### A suggested starting order

Use this table as a default if you want one. Each tier unlocks the next.

| Tier | Features | Why |
|---|---|---|
| **1: core, public APIs** | 1, 2, 3, 4, 5, 7, 9 (AppleScript only), 11, 26, 31, 37, 40, 41, 48, 49, 51, 70, 72, 74, 76, 77 | Matches what every competitor ships and needs few permissions, and the NotchDrop precedent suggests much of it could even pass App Store review |
| **2: differentiators, proven workarounds** | 8, 10 (mediaremote-adapter), 12 (fake bars first), 13, 20, 23, 38, 45, 53, 62, 63, 75 | Where users notice quality; 62–63 suit a developer audience; 75 avoids the CPU complaints every broad app received |
| **3: hard or fragile** | 17, 21, 22, 24, 28, 32, 59, 68 | Private frameworks, Accessibility or Full Disk Access; each will need patches every macOS release |
| **Probably skip** | 14, 33, 44, 58, 61 | High effort, high maintenance or security risk, and little notch-specific value |

## Reusable building blocks and how to ship for free

**Licences decide what you can copy.** The permissive pieces can go into any app, provided you keep their notices:

- **MrKai77/DynamicNotchKit** (MIT, macOS 13+): notch window and animation, with an automatic floating style on non-notch Macs ([repo](https://github.com/MrKai77/DynamicNotchKit)).
- **Lakr233/NotchDrop** (MIT): file shelf and AirDrop, shipped on the Mac App Store ([repo](https://github.com/Lakr233/NotchDrop)).
- **Lakr233/NotchNotification** (MIT): one-line notch notifications ([repo](https://github.com/Lakr233/NotchNotification)).
- **Lakr233/SkyLightWindow** (MIT): lock-screen and above-fullscreen windows ([repo](https://github.com/Lakr233/SkyLightWindow)).
- **ungive/mediaremote-adapter** (BSD-3-Clause): any-app Now Playing on macOS 15.4+ ([repo](https://github.com/ungive/mediaremote-adapter)). The ejbills Swift-package fork's licence is unconfirmed.
- **dannystewart/volumeHUD** (MIT): Tahoe-era HUD interception ([repo](https://github.com/dannystewart/volumeHUD)).
- **exelban/Stats** (MIT): system metrics ([repo](https://github.com/exelban/stats)).
- **farouqaldori/vibe-notch** (Apache-2.0): the Claude Code hook-to-notch pattern ([repo](https://github.com/farouqaldori/vibe-notch)).

The most complete references are **copyleft**: boring.notch (GPL-3.0, about 11.1k stars) ([repo](https://github.com/TheBoredTeam/boring.notch)), Atoll (GPL-3.0) and MewNotch (GPL-3.0) ([repo](https://github.com/monuk7735/mew-notch)). AirBattery is AGPL-3.0 ([repo](https://github.com/lihaoyun6/AirBattery)). Three other codebases are off-limits for copying:

- **SuperIsland** has no licence, which by default means all rights reserved.
- **Old Droppy forks** are GPL-3.0 plus Commons Clause, which forbids resale ([Gumroad](https://iordv.gumroad.com/l/Droppy)).
- **MediaMate, Alcove and Notchy** are closed source.

The GPL restriction is narrower than it sounds for a free app. **If you publish your app's source under GPL-3.0, you may legally reuse boring.notch and Atoll code.** If you want to keep the option of a closed or paid app later, study those repos for architecture only and build on the MIT/BSD pieces.

**Distribution is the other fork in the road.** Feature-rich notch apps ship as direct downloads because their best features conflict with the App Sandbox:

- **Accessibility:** the APIs gated by the Accessibility privilege are "not compatible with the App Sandbox", and App Review has rejected `CGEvent.post` under guideline 2.4.5 ([Apple DTS](https://developer.apple.com/forums/thread/820594)).
- **MediaRemote:** spawning `/usr/bin/perl` for the media adapter is very unlikely to survive sandboxing or review.

Narrow apps do make it onto the App Store: NotchDrop (shelf) and Hudlum (HUD) are both there ([Hudlum](https://manytricks.com/hudlum/)).

The direct route has a cost too. Signing and notarising needs the paid Apple Developer Program, whose €99/yr fee MediaMate's developer cited as a reason it couldn't be free ([Reddit mirror](https://pol1.lr.ggtyler.dev/r/MacOS/comments/wl0hk8/followup_of_my_app_mediamate)). Without it, you are where boring.notch and MewNotch are: un-notarised builds that users must clear with `xattr -dr com.apple.quarantine`, often wrapped in a Homebrew cask ([boring.notch](https://github.com/TheBoredTeam/boring.notch)).

For a personal, free app the cheapest realistic path is a non-sandboxed, ad-hoc-signed build for your own Mac. NotchDrop documents building with ad-hoc signing. Add Sparkle and notarisation only if you later share it widely. Targeting macOS 14 matches Droppy, SuperIsland and boring.notch. Per-app volume (#17) would push that to 14.4.

## Claims to treat with caution

**Pricing:**

- **Notchy** contradicts itself. Its homepage (v1.0.225) still says "free… no trial, license key, or subscription", while its pricing page says $24.99 per Mac. The v2.0.0 that apparently introduced pricing is on the download page but not in the changelog ([notchy.dev](https://notchy.dev); [pricing](https://notchy.dev/pricing); [changelog](https://notchy.dev/changelog)).
- **Droppy** appears at $6.99 on a Product Hunt mirror and $9.99 on the live listing ([hunted.space](https://hunted.space/product/droppy-4); [Product Hunt](https://www.producthunt.com/products/droppy-4)). Its licence history (MIT, then GPL-3.0 + Commons Clause, then paid) and whether its source is still public are unresolved; the canonical repo was unreachable.
- **Alcove** has been quoted at $16.99 (launch), $14.99 and $13.99 ([ifun.de](https://www.ifun.de/alcove-bringt-das-dynamic-island-auf-den-mac-246561/); [apps.deals](https://blog.apps.deals/best-notch-apps-mac); [SlashGear](https://www.slashgear.com/2175261/macos-apps-give-features-apple-doesnt-include/)).
- **MediaMate** ranges from €5.99 to €6.99, $9.20, and "pay what you think is fair" ([BGR](https://www.bgr.com/2177168/apps-that-make-macbook-notch-useful/)).

**Requirements:**

- **Alcove:** Softpedia says macOS 14, while Homebrew and most sources say 15.
- **Atoll:** the README says macOS 14.0 and "MacBook with a notch", while the appcast says 14.6 and non-notch support exists. Several Atoll features (per-app volume, keep-awake, pinned lyrics, charging wattage, network HUDs) exist only in pre-release builds ([CHANGELOG](https://github.com/Ebullioscopic/Atoll/blob/dev/CHANGELOG.md)).
- **Droppy:** one directory claims it needs a notched Mac, which the official site contradicts.

**Features:**

- **SuperIsland's** website claims a brightness HUD it removed and full notification display its docs disclaim. It is called "no tracking" while depending on Aptabase analytics.
- **Alcove's** weather feature is unverified, and only a piracy mirror suggests a version newer than 1.7.7.
- **Notchy's** entire 74-feature list is self-reported.
- **MediaMate's** Touch Bar and lock-screen behaviour in 3.8.x is unconfirmed.
- **The research brief:** its "Notchie" corresponds to no product, and MediaMate's site is wouter01.github.io, not wouter.dev.

**Sources:** many 2026 comparison posts are written by competing notch apps (Droppy, Seam, NotchBay, Notchy, dynamicnotch.tech). Their factual claims mostly agree with neutral sources, but their "cons" lists are biased. Reddit r/macapps was unreachable, so this report contains no Reddit sentiment from 2025–2026.

## Conclusion

The market has already run the experiment you are about to run. Feature breadth reliably earns launch-day attention, and polish earns lasting loyalty. Every app that chased breadth (Droppy, Atoll, Notchy, SuperIsland) then spent months of changelog fixing idle CPU, regressions and permission confusion. The two focused apps are the ones reviewers describe as stable and Apple-like. Notchy's switch from "never monetised" to $24.99 within five months also suggests that maintaining dozens of features is costly even for a dedicated solo developer.

The practical implication is that difficulty, not popularity, should set your scope. Almost everything in Tier 1 uses public APIs and could even ship on the App Store. The features that make apps feel magical (system-wide Now Playing, brightness HUDs, lock-screen widgets) all sit on private frameworks that Apple has already broken once, in macOS 15.4, and can break again. A good plan is to build a small core with excellent animation and an energy scheduler from day one, design media as a protocol with AppleScript and mediaremote-adapter back ends, and keep every extra module off by default. Decide early between GPL (free reuse of boring.notch/Atoll code) and MIT/closed (reuse ideas only), because that choice determines how much code you get to borrow.
