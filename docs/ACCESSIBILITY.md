# Accessibility and HIG audit (M6 6.5)

Audited 2 Nov 2026 from the source, against Apple's Human Interface Guidelines (macOS) with the `hig-compliance-auditor` skill. Scope: VoiceOver labels, keyboard access, Reduce Motion, Reduce Transparency, Increase Contrast, contrast ratios, click-target sizes. Platform: macOS 26, SwiftUI with AppKit. **Not run on a Mac**: items marked "check with VoiceOver" need Charlie's spot-check (list at the end).

## Executive summary

- **Total issues**: 6 found. **Critical**: 0 | **High**: 1 | **Medium**: 3 | **Low**: 2
- **Fixed in this pass**: 5 of 6 (the High and four others); the sixth is a larger design change, noted below.
- **Estimated remaining work**: about half a day for the contrast tokens, plus the VoiceOver spot-check.
- **What was already good**: 158 explicit accessibility labels/hints; every icon-only button found has a label or `.help` (a scan of all `Button`s with an icon found none without one); decorative images are hidden (`accessibilityHidden`); Settings uses native `Form`/controls; Reduce Transparency turns the island's glass surfaces solid (`surfaceIsGlass` checks it), and the small glass control buttons use the system's Liquid Glass, which adapts to the setting itself (check this on the Mac); the island's springs and expand transitions already switch to a short fade under Reduce Motion; custom controls announce traits and values (`isSelected`, `accessibilityAdjustableAction` on the timer stepper).

## Issues by severity

### **[HIGH]** No keyboard or VoiceOver route to open the island - FIXED

- **Platform(s)**: macOS
- **Current behaviour**: the island opened only on hover or a click. The menu bar item had no way to open it, so a keyboard-only or VoiceOver user could not reach any tab (only the clipboard shortcut opened a tab).
- **HIG reference**: Per Apple's Human Interface Guidelines (Accessibility, Keyboard): every function should be reachable without a pointing device.
- **Fix**: *Open Island* in the menu bar item (works with Control-F8 and VoiceOver), and an optional global shortcut in Settings ▸ General with no default (nothing registers until chosen). Opening takes keyboard focus, so ⌘1 to ⌘5, the arrow keys and Esc work (existing behaviour of the focused island).

### **[MEDIUM]** Animations ignored Reduce Motion - FIXED

- **Current behaviour**: `blurReplace` transitions on the compact and expanded content, album art and lyric lines, plus springs on the media buttons and scrubber and the battery ring, played with Reduce Motion on.
- **Fix**: they use a plain fade or the shared `Motion.reduced` when `islandReduceMotion` is on. A source-level test (`AccessibilityLintTests`) fails if an ungated `blurReplace` transition returns.
- **Left**: `contentTransition(.symbolEffect(.replace))` and `.numericText()` (system-provided, small), and one `symbolEffect(.bounce)` on banners. Check these with Reduce Motion on.

### **[MEDIUM]** Captions too dim on black - FIXED

- **Current behaviour**: four captions at 40 to 45 % white on black (about 3.7:1 to 4.4:1), under the 4.5:1 that small text needs.
- **Fix**: raised to 60 % (about 7:1). `AccessibilityLintTests` fails if any `foregroundStyle(.white.opacity(x))` goes below 55 %.

### **[MEDIUM]** Increase Contrast only adds the island's outline - NOT FIXED

- **Current behaviour**: semantic styles (`.secondary`, `.primary`) adapt to Increase Contrast on their own, but about 100 hard-coded `.white.opacity(0.55 ... 0.9)` text colours do not.
- **Recommended fix**: a small token set (`IslandText.primary/secondary/tertiary`) that switches opacity with `model.accessibility.increaseContrast`, then replace the hard-coded values. It touches many views, so it should be done with screenshots of each tab in both modes.

### **[LOW]** Small click targets - FIXED

- Terminal *Keep Open* and *End Session* and the clipboard search *clear* button were icon-only with no minimum size (about 12 to 16 pt). They now have a 22 x 22 pt hit area. The island's own chip buttons were already 22 pt or more.

### **[LOW]** Fixed font sizes (108 `.font(.system(size:))`) - NOT FIXED, by design

- macOS has no Dynamic Type for apps, and the island's size is set by the notch, so fixed sizes are the usual choice there. Settings and onboarding use system text styles. No change planned.

## Accessibility audit

- **VoiceOver navigation**: labels and traits look complete in the source; reading order is the view order. **Check with VoiceOver**: the island's tab bar, the Today tab (calendar, reminders, weather), the Layout pane's up/down buttons and switches, and the Terminal tab (it captures keys, so VoiceOver keys may not reach it, which is expected).
- **Dynamic Type**: not applicable on macOS.
- **Colour contrast**: see above; secondary text uses system styles in Settings.
- **Motor accessibility**: click targets fixed; every Layout control works without dragging; nothing requires a drag or a long press.
- **Motion sensitivity**: see above. The Reduce Motion setting is read from the system, with a debug override.
- **Reduce Transparency**: the island, bubbles and chips go solid; the glass control buttons rely on the system's own adaptation (**check**: with it on, are the media buttons still clearly visible?).
- **Keyboard**: island tabs are reachable once it is open (focused); Settings is standard.

## Charlie's VoiceOver spot-check (about 15 minutes)

1. Turn on VoiceOver (⌘F5). Press the menu bar item and choose *Open Island*: does VoiceOver announce the island and the tab bar? Do ⌘1 to ⌘5 and the arrow keys change tab? Does Esc close it?
2. In Settings ▸ General, record a shortcut for *Open the island*; press it from another app.
3. Settings ▸ Modules ▸ Layout: move a tab up and down; are the buttons read as "Move AI up", and the switch as "Show AI"?
4. Open the Today, Clipboard and AI tabs: are items read in a sensible order, with the pin, copy and cost values spoken?
5. Turn on *Reduce Motion* (System Settings ▸ Accessibility ▸ Display): hover the island open, play music, change a track with lyrics on. No blur or springs should play.
6. Turn on *Increase Contrast*: is everything still readable? (Known gap: see the Medium item above.)
7. Onboarding: reset it (`defaults delete me.rkck.Notched onboarding.completed`), relaunch, and go through it with the keyboard only (Tab, Space, Return). Is every permission explained and skippable?

> Audit powered by HIG Compliance Auditor by Omraj Kumar (omrajguru.com/linktree, GitHub @omrajguru05, X @omrajguru_). Reference material sourced from Apple's Human Interface Guidelines. Portfolio: https://om.bearblog.dev/projects
