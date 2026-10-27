# ADR-0001: AppKit app lifecycle with SwiftUI views

- Status: accepted (M1)
- Date: 2026-10-27

## Context

DynamicNotch is a menu-bar agent (`LSUIElement`). Its main surface is a custom borderless `NSPanel` per display, and it also opens a Settings window and a first-run onboarding window. The island's buttons (for example Settings) must be able to open those windows.

A SwiftUI `App` with `MenuBarExtra` and `Settings`/`Window` scenes looks simpler, but the island lives in an `NSHostingView` outside the scene graph, where `openWindow`/`openSettings` environment actions aren't reliably available. Agent apps also need explicit activation when a window opens.

## Decision

Use the AppKit lifecycle: `main.swift` starts `NSApplication` with an `AppDelegate` that is the composition root. AppKit owns the status item (`NSStatusItem` + `NSMenu`), the island panels, and the Settings and onboarding windows (`NSWindow` + `NSHostingController`, managed by `WindowCoordinator`). Every view is SwiftUI.

## Consequences

- Any code, including island buttons, can open windows through `WindowCoordinator`.
- Opening a window calls `NSApp.activate()` because the app has no Dock icon.
- We write a little more window plumbing than a SwiftUI `App` would need.
