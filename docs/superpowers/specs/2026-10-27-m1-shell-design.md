# DynamicNotch M1: shell and foundations (design and plan)

## Context

The project folder holds only docs (`CLAUDE.md`, `docs/ROADMAP.md`, the research doc, setup notes and the kickoff prompt). There is no code and no git repo yet. M1 builds the stable, beautiful island plus all the plumbing later milestones need: geometry, panel, morph, click-through, fullscreen hiding, activities and modules, settings, permissions, a status item and onboarding. When M1 is done, the app builds with zero warnings in Swift 6 mode, the tests pass, it runs from `~/Applications`, it stays inside the CPU/memory budget, and the screenshots hold up against Apple's own UI.

After approval I'll save this file into the repo in the first commit, split into `docs/superpowers/specs/2026-10-27-m1-shell-design.md` and `docs/superpowers/plans/2026-10-27-m1-shell.md`. I'll then execute it inline (superpowers:executing-plans, as you chose), using TDD for pure logic.

### Environment findings (probed read-only)

| Item | Finding |
|---|---|
| Mac | M4 MacBook Air 15", macOS 27.2 (26B118), Xcode 27.1 |
| Built-in display | Scaled to **1920×1243 pt @2×**. `safeAreaInsets.top = 37.5` (fractional). `auxiliaryTopLeft/Right` widths 856/856, so the **notch is 208 × 37.5 pt at x = 856**. Menu bar is 38 pt. UUID `37D8832A-…B230` |
| Signing | Two *duplicate* "Apple Development: charlie1707@icloud.com" certs (SHA-1 C368F9EC…, expires 23 Jun 2027; D2FB9F33…, expires 11 Jul 2027), both **team `N84NGFQ5R9`** (cert OU) |
| SkyLight | `CGSMainConnectionID` and `CGSCopyManagedDisplaySpaces` resolve through `dlsym` on 27.2 and return per-display space info |
| Apple docs | `/Applications/Xcode.app/…/IDEIntelligenceChat.framework/…/AdditionalDocumentation/`. I've read `SwiftUI-` and `AppKit-Implementing-Liquid-Glass-Design.md` |
| git identity | Charlie Auchter <charlie@rkck.me> |

### Missing tools (I'll carry on, as you asked)

- **liquid-glass skill:** not installed.
- **hig-\* skills:** not installed. I'll use Apple's bundled Xcode docs and the HIG rules in CLAUDE.md instead.
- **Xcode MCP server (`xcode`):** not registered in `claude mcp list`. I'll use `xcodebuild`.
- **xcodegen:** not installed. Step 1 runs `brew install xcodegen` (2.46.0).
- **superpowers:** installed (6.4.1).

### Decisions from your answers

- **Themes (#73).** On notched displays the compact island is always pure black. The chosen theme fills the expanded body, blending from black during the morph. Pill displays use the theme in every state.
- **"Main display".** Means the built-in notched screen when it's on; otherwise the macOS primary display. "All displays" and "Specific display…" are the other options.

---

## Architecture and file tree

```
project.yml  README.md  LICENSE  THIRD_PARTY_NOTICES.md  .gitignore
App/
  main.swift                 NSApplication bootstrap (AppKit lifecycle, see ADR-0001)
  AppDelegate.swift          composition root; skips bootstrapping when hosted by tests
  AppEnvironment.swift       owns long-lived services (settings, coordinator, registry, scheduler, permissions, islands)
  StatusItemController.swift NSStatusItem + NSMenu
  WindowCoordinator.swift    Settings and Onboarding NSWindows (NSHostingController)
  DebugCommands.swift        #if DEBUG: dynamicnotch:// URL commands + debug submenu
  Info.plist  Assets.xcassets (placeholder AppIcon, AccentColor)
Sources/
  Core/Island/      NotchGeometry, ScreenDescriptor, IslandPresentation, HoverStateMachine,
                    IslandPanel, IslandHostingView, IslandController, IslandManager, IslandViewModel,
                    Views/ IslandRootView, IslandShape, IslandSurface, CompactContentView,
                           ExpandedContentView, ExpandedHeaderView
  Core/Activities/  Activity, ActivityCoordinator
  Core/Modules/     IslandModule, ModuleDescriptor, ModuleContext, ModuleRegistry
  Core/Scheduling/  RefreshScheduler, RefreshPlan (pure), PowerStateMonitor, SystemActivityMonitor (sleep/lock)
  Core/Permissions/ Permission, PermissionCenter, PermissionProbes
  Core/Settings/    SettingsStore, SettingsTypes (IslandTheme, AnimationStyle, DisplaySelection)
  Core/Logging/     Log (os.Logger factory, one subsystem per area/module)
  DesignSystem/     Tokens (Spacing, Radius, IslandMetrics), Motion, IslandButtonStyle, Typography
  Modules/Hello/    HelloModule, HelloViews            (#if DEBUG)
  Services/Displays/ DisplayID, FullscreenMonitor, WindowListFullscreenHeuristic
  Services/LaunchAtLogin.swift                         (SMAppService.mainApp)
  Services/Private/  SkyLightSpaces.swift              (dlopen/dlsym; fails gracefully, logs once)
  SettingsUI/       SettingsRootView, GeneralPane, AppearancePane, IslandPreview, ModulesPane, PermissionsPane, AboutPane
  Onboarding/       OnboardingView, WelcomeStep, ChooseModulesStep, PermissionsStep, DoneStep
Tests/              NotchGeometryTests, HoverStateMachineTests, ActivityCoordinatorTests,
                    ModuleRegistryTests, RefreshPlanTests, SettingsStoreTests   (Swift Testing)
scripts/            install.sh (build → ~/Applications → relaunch), island-shot.sh, window-bounds.swift, perf.sh
docs/adr/           0001-appkit-lifecycle, 0002-click-through-frame-follows-island,
                    0003-fullscreen-detection, 0004-activity-rules, 0005-signing-and-install
```

Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`. Files adapted from references get an attribution comment and an entry in `THIRD_PARTY_NOTICES.md`:
- DynamicNotchKit (MIT): notch-shape curve idea and the NSScreen notch maths.
- boring.notch (GPL-3.0): panel configuration and sizing constants.
- MacroVisionKit (MIT, TheBoredTeam): fullscreen detection through the CGS managed-spaces API.

M1 has **no SPM dependencies**.

## `project.yml` design

```yaml
name: DynamicNotch
options: { bundleIdPrefix: me.rkck, deploymentTarget: { macOS: "26.0" }, createIntermediateGroups: true }
settings:
  base:
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "6.0"                     # Swift 6 language mode → complete strict concurrency
    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES      # enforces "zero warnings"
    GCC_TREAT_WARNINGS_AS_ERRORS: YES
    DEVELOPMENT_TEAM: N84NGFQ5R9
    CODE_SIGN_STYLE: Manual                  # no provisioning profile needed for this macOS app
    CODE_SIGN_IDENTITY: "Apple Development"
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES
targets:
  DynamicNotch:
    type: application
    platform: macOS
    sources: [App, Sources]
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: me.rkck.DynamicNotch, ENABLE_APP_SANDBOX: NO,
                        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon } }
    info:
      path: App/Info.plist
      properties:
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 Charlie Auchter. Free software under GPL-3.0-or-later."
        CFBundleURLTypes: [{ CFBundleURLName: me.rkck.DynamicNotch, CFBundleURLSchemes: [dynamicnotch] }]
        # Usage strings for later milestones (inert until a module requests them):
        NSAppleEventsUsageDescription: …control Music and Spotify and read what's playing (Now Playing).
        NSCalendarsFullAccessUsageDescription: …show your upcoming events (Calendar).
        NSRemindersFullAccessUsageDescription: …show and complete today's reminders (Reminders).
        NSBluetoothAlwaysUsageDescription: …show when headphones and other devices connect.
        NSLocationWhenInUseUsageDescription / NSLocationUsageDescription: …show local weather.
        NSAudioCaptureUsageDescription: …animate the visualiser to the audio that's playing.
  DynamicNotchTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies: [{ target: DynamicNotch }]
    settings: { base: { TEST_HOST: "$(BUILT_PRODUCTS_DIR)/DynamicNotch.app/Contents/MacOS/DynamicNotch",
                        BUNDLE_LOADER: "$(TEST_HOST)", GENERATE_INFOPLIST_FILE: YES } }
schemes:
  DynamicNotch: { build: { targets: { DynamicNotch: all, DynamicNotchTests: [test] } },
                  test: { targets: [DynamicNotchTests] }, run: { config: Debug }, archive: { config: Release } }
```

No entitlements file in M1: no sandbox, and nothing restricted. M2 adds `com.apple.security.automation.apple-events` when it needs it. With duplicate certs, Xcode normally resolves "Apple Development" to one SHA-1 itself. If codesign reports "ambiguous", I'll pin the newer cert's SHA-1 in a gitignored `Configs/Local.xcconfig`. Deleting the older duplicate cert in Keychain Access is optional.

## Key type signatures

```swift
// Core/Island/NotchGeometry.swift: pure, unit-tested
struct ScreenDescriptor: Equatable, Sendable {           // built from NSScreen; fixtures in tests
    var frame: CGRect; var visibleFrame: CGRect; var safeAreaTop: CGFloat
    var auxiliaryTopLeftWidth: CGFloat?; var auxiliaryTopRightWidth: CGFloat?; var backingScale: CGFloat
}
struct NotchGeometry: Equatable, Sendable {
    enum Kind: Sendable { case notch, pill }
    let kind: Kind; let screenFrame: CGRect; let hardwareNotch: CGSize?   // 208 × 37.5 on this Mac
    let compactBaseSize: CGSize; let scale: CGFloat
    static func resolve(_ screen: ScreenDescriptor, widthOffset: CGFloat = 0, forcePill: Bool = false) -> NotchGeometry
    func compactRect(leadingWidth: CGFloat, trailingWidth: CGFloat) -> CGRect   // global coords, centred, pixel-aligned
    func expandedRect(size: CGSize) -> CGRect                                   // notch: flush to top; pill: below menu bar
    func panelFrame(for islandRect: CGRect, shadowPadding: CGFloat) -> CGRect   // padding on sides/bottom only
}
// Notch exists when safeAreaTop > 0 and both auxiliary areas are present;
// width = frame.width − auxLeft − auxRight (+ widthOffset). Pill: menuBarHeight = frame.maxY − visibleFrame.maxY,
// falling back to 24 when the menu bar auto-hides. Pixel alignment rounds to 1/scale (37.5 is valid at 2×).

// Core/Activities
struct ActivityID: Hashable, Sendable, ExpressibleByStringLiteral { let rawValue: String }
struct ModuleID:   Hashable, Sendable, ExpressibleByStringLiteral { let rawValue: String }
enum ActivityPriority: Int, Comparable, Sendable { case idle = 0, media = 100, liveSession = 200, alert = 300 }
enum ActivityLifetime: Equatable, Sendable { case untilRemoved, transient(Duration) }
@MainActor struct ActivityContent { let width: CGFloat; let accessibilityLabel: String; let view: () -> AnyView }
@MainActor struct Activity: Identifiable {
    let id: ActivityID; let moduleID: ModuleID
    var priority: ActivityPriority; var lifetime: ActivityLifetime
    var compactLeading: ActivityContent?; var compactTrailing: ActivityContent?; var expanded: ActivityContent?
}
@MainActor @Observable final class ActivityCoordinator {
    struct CompactSlots { var leading: (ActivityID, ActivityContent)?; var trailing: (ActivityID, ActivityContent)? }
    private(set) var compact: CompactSlots
    private(set) var ranked: [Activity]            // drives the expanded view
    private(set) var alertSerial: Int              // bumps on each new alert, which triggers the bounce
    var nextExpiry: Date? { get }
    init(now: @escaping () -> Date = Date.init, scheduleWake: @escaping (Date?) -> Void = { _ in })
    func post(_ activity: Activity)                // insert, or replace by id (a transient re-post resets its expiry)
    func remove(_ id: ActivityID)
    func removeAll(from module: ModuleID)
    func expire(at now: Date)                      // drops expired transients and recomputes
}
// Rules (ADR-0004, all tested): rank by priority desc, then newest first. If the top activity is an .alert
// it owns both compact slots. Otherwise leading = first ranked activity with a leading item and trailing =
// first ranked activity with a trailing item. When a transient expires, the island returns to the prior state.

// Core/Modules
struct ModuleDescriptor: Identifiable, Sendable {
    let id: ModuleID; let name: String; let symbol: String; let summary: String
    let permissions: [Permission]; let isDebugOnly: Bool
}
@MainActor protocol IslandModule: AnyObject {
    static var descriptor: ModuleDescriptor { get }
    init(context: ModuleContext)
    func start()
    func stop()                                    // must release every timer, observer and process
    var expandedTab: ModuleTab? { get }            // default nil (protocol extension)
    var settingsPane: AnyView? { get }             // default nil
}
@MainActor struct ModuleContext { let activities: ActivitySink   // scoped to this module's id
                                  let scheduler: RefreshScheduler; let settings: SettingsStore; let log: Logger }
@MainActor final class ModuleRegistry {
    init(moduleTypes: [any IslandModule.Type], settings: SettingsStore, permissions: PermissionCenter,
         makeContext: @escaping (ModuleID) -> ModuleContext)
    var descriptors: [ModuleDescriptor] { get }
    func reconcile()   // instantiates and starts enabled modules (after their permissions);
                       // stops and releases disabled ones, so a disabled module has no instance at all
}

// Core/Island
final class IslandPanel: NSPanel {   // [.borderless, .nonactivatingPanel], level .mainMenu + 3,
    // [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle], clear, no shadow,
    // not movable, hidesOnDeactivate false, animationBehavior .none
    override var canBecomeKey: Bool { false }      // M4's terminal will flip this temporarily
    override var canBecomeMain: Bool { false }
    var hiddenFromCapture: Bool                    // sharingType = .none / .readOnly (#6)
}
final class IslandHostingView: NSHostingView<IslandRootView> { // acceptsFirstMouse = true;
    var trackingRect: CGRect                                    // NSTrackingArea(.mouseEnteredAndExited, .activeAlways)
    var onPointer: (PointerEvent) -> Void }
@MainActor final class IslandController {          // one per NSScreen, keyed by DisplayID (UUID string)
    init(displayID: DisplayID, geometry: NotchGeometry, coordinator: ActivityCoordinator,
         settings: SettingsStore, actions: IslandActions)
    func update(geometry: NotchGeometry)
    func setHidden(_ hidden: Bool, reason: HideReason)   // .fullscreen, .paused
    func expand(_ reason: ExpandReason); func collapse(); func tearDown()
}
@MainActor final class IslandManager {             // reconciles controllers with screens and settings
    init(settings: SettingsStore, coordinator: ActivityCoordinator, fullscreen: FullscreenMonitor, actions: IslandActions)
    func start(); func reconcileScreens()
}
struct HoverStateMachine: Sendable {               // pure, unit-tested
    enum State { case compact, pendingExpand, expanded, pendingCollapse }
    enum Event { case pointerEntered, pointerExited, clicked, expandDelayElapsed, collapseGraceElapsed, forceCollapse }
    enum Effect { case scheduleExpand(after: Duration), scheduleCollapse(after: Duration), cancelTimers, expand, collapse }
    mutating func handle(_ event: Event, hoverEnabled: Bool, hoverDelay: Duration) -> [Effect]
}

// Core/Scheduling
@MainActor final class RefreshScheduler {          // one DispatchSourceTimer for the whole app
    struct Token: Hashable, Sendable
    enum Condition: Sendable { case always, whileIslandVisible, whileExpanded, whileUIVisible(String) }
    func register(_ name: String, every: Duration, tolerance: Double = 0.1, when: Condition = .always,
                  _ work: @escaping @MainActor () -> Void) -> Token      // tolerance clamped to ≥ 10%
    func unregister(_ token: Token)
    func setUIVisible(_ key: String, _ visible: Bool)
}
struct RefreshPlan: Sendable {                     // pure: next deadline + due set (tested)
    static func next(registrations: [Entry], now: Date, power: PowerState, suspended: Bool,
                     visibility: VisibilityState) -> (deadline: Date, leeway: Duration)?
}
enum PowerState: Sendable { case ac, battery, lowPower }   // interval ×1, ×2, ×4; suspended when screens sleep or lock

// Core/Permissions
enum Permission: String, CaseIterable, Sendable {
    case accessibility, inputMonitoring, screenRecording, automation, calendars, reminders, bluetooth, location }
enum PermissionStatus: Sendable { case granted, denied, notDetermined, unknown }
@MainActor @Observable final class PermissionCenter {
    private(set) var statuses: [Permission: PermissionStatus]
    func refresh()                                  // on app activation, plus every 2 s while a permissions UI is visible
    func request(_ p: Permission) async -> PermissionStatus   // only when a module that needs it is enabled
    func openSystemSettings(for p: Permission)      // x-apple.systempreferences deep links, checked on 27.2
}

// Core/Settings: stored properties with didSet persistence, typed keys, defaults in one table
@MainActor @Observable final class SettingsStore {
    init(defaults: UserDefaults = .standard)
    var displaySelection: DisplaySelection        // .main (default) | .all | .specific(DisplayID)
    var hideInFullscreen = true;  var hideFromScreenCapture = false;  var isPaused = false
    var expandOnHover = true;     var hapticsEnabled = true
    var notchTheme: IslandTheme = .notchBlack;    var pillTheme: IslandTheme = .liquidGlass
    var animationStyle: AnimationStyle = .smooth
    var hoverDelay = 0.15        // s, 0…1
    var widthOffset = 0.0        // pt, −20…+60
    var expandedScale = 1.0      // 0.85…1.25
    var enabledModules: Set<ModuleID> = []        // everything off by default (#70)
    var hasCompletedOnboarding = false
    #if DEBUG
    var debugForcePill = false
    #endif
}

// DesignSystem
enum Spacing { static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12,
               l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32 }
enum Radius  { static let compactBottom: CGFloat = 10, compactShoulder: CGFloat = 6,
               expandedBottom: CGFloat = 32, expandedShoulder: CGFloat = 14 }   // tuned by eye
enum IslandMetrics { static let expandedBase = CGSize(width: 600, height: 190)
                     static let pillCompact = CGSize(width: 190, height: 32)
                     static let pillGap: CGFloat = 6, shadowPadding: CGFloat = 20 }
enum AnimationStyle: String, CaseIterable, Sendable { case snappy, smooth, bouncy
    var expand: Animation   // snappy (0.32, 0.86) · smooth (0.42, 0.78) · bouncy (0.48, 0.68)
    var collapse: Animation // response ×0.85, damping +0.1 (≤ 1): faster and less bouncy
}
enum Motion { static let alertBounce = Animation.spring(response: 0.28, dampingFraction: 0.55)
              static let reduced = Animation.easeInOut(duration: 0.18)       // Reduce Motion: quick fades
              static let contentIn: AnyTransition                            // .blurReplace / .opacity + .scale(0.9)
}
enum IslandTheme: String, CaseIterable, Sendable { case notchBlack, liquidGlass, tintedGlass }
struct IslandButtonStyle: ButtonStyle   // .glass on a black body; on a glass body, a vibrant fill instead (never glass on glass)
```

## The hardest M1 problems

**1. Click-through with hover (#7): the panel frame follows the island (ADR-0002).** A window takes clicks over its whole frame, even its transparent parts, so the fix is to never let the panel be bigger than what you can see.
- **Compact state:** the panel is exactly the island rect. On a notch display, idle, that is the 208 × 37.5 pt hardware notch, where macOS never puts menu items anyway. Menus beside it stay clickable by construction.
- **Expand:** first grow the panel synchronously to `union(current, target)` plus the shadow padding. Then run the SwiftUI spring. The island is drawn top-centre and every rect is symmetric about `screen.midX`, so resizing never moves it on screen.
- **Collapse:** run the spring with `withAnimation(_:completionCriteria: .logicallyComplete)`. In the completion handler, shrink the panel back, but only if the state is still collapsed, so an interrupted animation is handled.
- **Hover:** an `NSTrackingArea` (`.activeAlways`) on the hosting view. **No global mouse monitor**, so idle hover detection costs zero CPU.
- **Clicks:** `acceptsFirstMouse` lets clicks work in the non-activating panel without stealing focus.
- **Verification:** a script that reads `CGWindowListCopyWindowInfo` asserts the panel bounds in every state. You also do a manual check of the File/Edit menus in a wide-menu app.
- **Fallback, if resizing ever shows a frame of jank:** keep a fixed panel and toggle `ignoresMouseEvents` from a tiny always-hit-testable sensor panel over the notch.

**2. Fullscreen detection (#5) (ADR-0003).**
- **Primary method:** `Services/Private/SkyLightSpaces.swift` loads `CGSMainConnectionID` and `CGSCopyManagedDisplaySpaces` with `dlsym`. For each display, the current space counts as fullscreen when it has a `TileLayoutManager` or `type == 4`. This is MacroVisionKit's MIT approach, rewritten as a graceful wrapper, and I confirmed it works on 27.2. A `"Main"` display identifier maps to the primary display's UUID.
- **Fallback, if the symbols disappear:** use `CGWindowListCopyWindowInfo` (bounds only, no Screen Recording needed). A space counts as fullscreen when a layer-0 window from another app exactly covers `screen.frame`.
- **Triggers (event-driven):** `activeSpaceDidChangeNotification`, `didActivateApplicationNotification` and screen-parameter changes, plus a single one-shot re-check about 0.4 s later to catch the end of the transition animation.
- **Effect:** hiding is per display (`orderOut`), and "visible-only" refresh work pauses with it.
- The "keep showing during fullscreen media" option depends on Now Playing, so it **moves to M2**.

**3. Multi-display.**
- `IslandManager` keeps `[DisplayID: IslandController]`. `DisplayID` is the `CGDisplayCreateUUIDFromDisplayID` string.
- It reconciles (create, tear down or update geometry) on `didChangeScreenParametersNotification` (debounced 200 ms), `NSWorkspace.didWakeNotification` / `screensDidWakeNotification`, and changes to the display, offset or force-pill settings.
- The selection rule is `.main`: the built-in notched screen if it's on, else `NSScreen.screens[0]`. The other options are `.all` and `.specific(uuid)`. A specific display that is missing falls back to `.main`.
- On sleep and lock (`screensDidSleep`, `com.apple.screenIsLocked`, `sessionDidResignActive`) the scheduler suspends. On wake, geometry is rebuilt.

**4. One continuous morph (#1).**
- `IslandRootView` draws **one** `IslandShape` whose width, height, shoulder radius and bottom radius are all animatable. On a notch display it is a notch shape: a flat top flush with the screen edge, concave top shoulders (quad curves, DynamicNotchKit-style) and continuous bottom corners. On a pill display it is a continuous rounded rect, with a capsule radius when compact.
- One `withAnimation(style.expand)` changes the presentation. Size and corners spring together inside the already-grown panel.
- The surface is black on notch displays when compact. When expanded it uses the theme (glass: `.glassEffect(.regular / .regular.tint(accent), in: shape)`), blended from black.
- Content uses `matchedGeometryEffect` in a shared `@Namespace` (for example the activity symbol moves from compact leading to the expanded content), and `glassEffectID` inside a `GlassEffectContainer` for the glass buttons. Content transitions are `.blurReplace` / `.opacity + .scale(0.9)`.
- **Accessibility:**
  - **Reduce Motion:** swaps the springs for `Motion.reduced` (no overshoot) plus a content fade.
  - **Reduce Transparency:** replaces the glass themes with a solid dark surface.
  - **Increase Contrast:** adds a 1 pt hairline stroke on the expanded and pill shapes only. On the compact notch it would outline the camera housing.
- **Expanded layout:** a header band as tall as the notch, with the time and date on the left of the hardware notch and the glass Settings and Pause buttons on its right (nothing sits under the camera). Below it is a content area that shows the ranked activities' expanded views, or a quiet empty state.

## Implementation steps

Each step: build → test → `scripts/install.sh` (copy to `~/Applications`, relaunch) → screenshot → **look at the image and critique it** → commit. I can't physically hover, click or fullscreen, so a DEBUG-only URL scheme (`open -g "dynamicnotch://debug/expand"`, also `collapse`, `pill`, `outline`, `hello`, `reduce-motion`…) drives the states for screenshots. The few checks only a human can do are listed at the end.

1. **Scaffolding.**
   - `brew install xcodegen`, `git init`, `.gitignore` (Xcode, `build/`, DerivedData, `.DS_Store`, `Configs/Local.xcconfig`).
   - `LICENSE` (curl gnu.org GPL-3.0 text), `THIRD_PARTY_NOTICES.md`, `README.md` (prerequisites, `xcodegen generate`, the build command, `scripts/install.sh`), and the spec and plan docs.
   - `project.yml` → `xcodegen generate` → the `main.swift` / `AppDelegate` / `StatusItemController` agent with a menu of Settings… (disabled until step 6), Pause and Quit.
   - Verify: `codesign -dv --verbose=4` shows Apple Development, team N84NGFQ5R9 and the `runtime` flag. No Dock icon. A screenshot shows the status item.
   - Commit `chore: scaffold DynamicNotch app (M1)`.
2. **NotchGeometry + IslandPanel (TDD).**
   - Write `NotchGeometryTests` first. Fixtures: this Mac (1920×1243, aux 856/856, 37.5 → 208×37.5 @ x 856); a 14" MBP default; a 2560×1440 @1× external with a 25 pt menu bar; an auto-hidden menu bar; a secondary-screen origin offset; width offset; force-pill; and pixel rounding.
   - Then implement the panel, hosting view, black compact `IslandShape`, `IslandManager` reconciliation, and the sleep/wake and connect/disconnect handling.
   - Verify:
     - The panel bounds equal the notch rect (window-bounds script).
     - A `screencapture -R` of the notch region is identical with the app running and quit, which proves it is invisible.
     - A DEBUG `outline` overlay checks pixel alignment.
     - A forced-pill screenshot.
   - Commit `feat(#1,#2,#3): notch geometry and island panel`.
3. **Compact ↔ expanded morph (#1).**
   - `HoverStateMachineTests` come first: the hover delay, the collapse grace period, click expanding immediately, re-entering cancelling a collapse, and hover being disabled.
   - Then `IslandShape` animation, the grow-first/shrink-after panel logic, the expanded header, placeholder and glass buttons, the spring tokens, Reduce Motion/Transparency/Increase Contrast (with DEBUG overrides so I can screenshot each), and the haptic (`.levelChange`) on hover-expand.
   - Verify:
     - Screenshots of compact and expanded on the notch, and on a forced pill.
     - A burst of about 8 captures during the expansion to inspect the intermediate frames for jumps.
     - A compare against iPhone's Dynamic Island and Tahoe/Golden Gate system UI.
   - Commit `feat(#1): compact↔expanded morph`.
4. **Click-through (#7) + fullscreen (#5).**
   - Add the bounds assertions across every state.
   - Add `FullscreenMonitor` with the SkyLight wrapper and the public fallback (the fallback can be forced in DEBUG and is tested that way too).
   - Verify: `log stream --predicate 'subsystem BEGINSWITH "me.rkck.DynamicNotch"'` while fullscreening Safari and Xcode or a game, with screenshots. I'll script the fullscreen with System Events if Terminal has Accessibility; otherwise I'll ask you to toggle it.
   - Commit `feat(#7,#5): click-through and fullscreen auto-hide`.
5. **ActivityCoordinator + IslandModule + ModuleRegistry (TDD).**
   - `ActivityCoordinatorTests` cover: ranking, alert takeover, the leading/trailing split, transient expiry restoring the previous state, replace-by-id, `removeAll(from:)` and `nextExpiry`.
   - `ModuleRegistryTests` cover: a disabled module is never instantiated, and disabling it calls `stop()` and removes its activities.
   - The compact island widens for its slots (`compactRect(leadingWidth:trailingWidth:)`).
   - DEBUG `HelloModule` with two status-menu actions: "Show Hello alert (4 s)" and "Toggle Hello live session".
   - Verify: screenshots of compact with Hello, expanded with Hello, and the return to idle after the alert expires.
   - Commit `feat(#8): activity coordinator, module registry, Hello demo`.
6. **SettingsStore + Settings window.**
   - `SettingsStoreTests` (defaults, plus a persistence round-trip using a throwaway suite).
   - `WindowCoordinator` opens an `NSWindow` hosting a `NavigationSplitView`: a sidebar of General, Appearance, Modules, Permissions and About, each pane a `Form` with `.formStyle(.grouped)`.
   - #70 module toggles with descriptions and permission chips.
   - #72 sliders and a live `IslandPreview` that reuses `IslandRootView` and replays on change.
   - #73 per-display-type theme pickers.
   - #6 the capture toggle, with a footnote that ScreenCaptureKit-based tools may still see the island.
   - Every setting applies live.
   - Verify:
     - Screenshot each pane, light and dark (`screencapture -l <windowID>`).
     - Change settings, quit, relaunch, then `defaults read me.rkck.DynamicNotch`.
     - Screenshots of the glass and tinted themes on a forced pill.
     - Test whether `screencapture` honours hide-from-capture, and report the result.
   - Commit `feat(#70,#72,#73,#6): settings window`.
7. **#77 status item, launch at login, PermissionCenter, onboarding.**
   - Final menu: Settings… ⌘,, Pause island ✓, About DynamicNotch, Debug ▸ (DEBUG only), Quit ⌘Q.
   - `SMAppService.mainApp`, showing the live status and a "requires approval" state with a link to Login Items.
   - `PermissionCenter` and the Permissions pane.
   - `RefreshScheduler` with `RefreshPlanTests` (coalescing, tolerance ≥ 10%, battery/LPM multipliers, sleep/lock suspension, visible-only).
   - Onboarding window: Welcome (an animated mini island) → Choose modules (data-driven from the registry) → Permissions (only what the chosen modules need, with a "Nothing to grant" state) → Done (launch-at-login toggle). It shows on first run, and "Show Welcome Again" lives in About.
   - Verify: reset `hasCompletedOnboarding` → relaunch → screenshot every step. Toggle launch at login and confirm `SMAppService` status.
   - Commit `feat(#77): status menu, launch at login, permissions, onboarding`.
8. **Polish + performance.**
   - Review every screen against Apple's bundled Liquid Glass docs and the CLAUDE.md HIG rules: the 4/8 grid, continuous corners, symbol effects, typography, and light/dark/Increase Contrast.
   - `scripts/perf.sh`: launch the **Release** build, idle 60 s, then `top -l 31 -s 2 -pid` → mean CPU and peak RSS, plus `footprint`. Repeat for Debug, and with the island expanded, then collapsed. Budget: < 0.5% CPU, < 120 MB.
   - Fix anything over budget.
   - Grep the build log for `warning:` (expect 0).
   - Mark the ROADMAP M1 rows ✅, finish the ADRs, write the final report.
   - Commit `chore(M1): polish, perf check, roadmap`.

## Verification (end-to-end)

- **Tests:** `xcodebuild … -scheme DynamicNotch test` (Swift Testing) before every commit. They cover NotchGeometry, HoverStateMachine, ActivityCoordinator, ModuleRegistry, RefreshPlan and SettingsStore.
- **Build:** `xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug -derivedDataPath build build` with warnings as errors (zero warnings).
- **Install and run:** `scripts/install.sh` → `~/Applications/DynamicNotch.app`, signed with the stable Apple Development identity so TCC grants persist.
- **Visual:** `scripts/island-shot.sh` computes the notch rect and runs `screencapture -x -R…` for compact, expanded and pill. The whole screen is captured with `screencapture -x`. I read every image before calling a step done.
- **Click-through:** the window-bounds script, plus your manual menu check.
- **Fullscreen:** a log stream plus screenshots.
- **Persistence:** quit, relaunch, `defaults read`.
- **Performance:** `scripts/perf.sh` numbers in the final report.

## Manual checks I'll ask you for (about 2 minutes total)

1. Click the File/Edit menus of a wide-menu app right next to the notch while the island is idle.
2. Fullscreen Safari video and one other app (or a game), unless I can script it.
3. Feel the trackpad haptic on hover-expand.
4. Toggle the real Reduce Motion and Reduce Transparency settings once.

## Known compromises and open items

- **Fullscreen detection uses a private API** (SkyLight, wrapped and with a public fallback). That's allowed by CLAUDE.md and recorded in ADR-0003.
- **`sharingType = .none`** is ignored by ScreenCaptureKit-based capture on macOS 15+. The UI says so.
- **The Modules pane and onboarding's module step** contain only the DEBUG Hello module until M2 adds real modules. Release builds show a "More modules are coming" empty state.
- **The app icon** is a simple placeholder. A real Liquid Glass icon (Icon Composer) can come later.
- **There's no GitHub remote yet,** so About and README omit a repo link until you add one.
