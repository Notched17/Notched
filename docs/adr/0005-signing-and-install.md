# ADR-0005: Stable signing and a fixed install location

- Status: accepted (M1)
- Date: 2026-10-27

## Context

Ad-hoc signatures change on every build, so macOS forgets TCC grants (Accessibility, Input Monitoring, Screen Recording) each time. The developer's keychain holds two identical "Apple Development" certificates for team `N84NGFQ5R9`.

## Decision

- `project.yml` uses manual signing with `CODE_SIGN_IDENTITY = "Apple Development"` and `DEVELOPMENT_TEAM = N84NGFQ5R9`. A macOS app with no restricted entitlements needs no provisioning profile. Xcode resolves the duplicate certificates itself; if it ever reports an ambiguous identity, pin a SHA-1 in an untracked `Configs/Local.xcconfig`.
- Hardened Runtime is on and the App Sandbox is off (private frameworks, Accessibility and `/usr/bin/perl` are needed later).
- `scripts/install.sh` always copies the build to `~/Applications/DynamicNotch.app` and launches it from there.
- The generated `DynamicNotch.xcodeproj` is not committed; `project.yml` is the single source of truth.

## Consequences

The designated requirement stays the same across builds (same team and bundle ID), so permission grants survive rebuilds. Contributors must change `DEVELOPMENT_TEAM` to their own team.
