# Building and sharing Notched

Notched is built from source and signed with **your own Apple Development certificate**. There is no Developer ID signing, no notarisation and no auto-update for now (decided 2 Nov 2026: local builds only; Sparkle updates are wanted later). This page is how to build a Release version, install it, and give a copy to someone else.

## Build and install a Release build

```bash
scripts/go.sh --release          # pull, regenerate, test, build Release, install to ~/Applications/Notched.app
# or, without the tests:
scripts/install.sh Release
```

Always run it from `~/Applications/Notched.app`, not from `build/`. macOS ties permission grants to the app's signature and location, and an Apple Development signature is stable across builds of the same team and bundle ID (ADR-0005).

## Before calling a build good

1. `scripts/test.sh` passes.
2. Debug-only features are absent in Release: the Debug menu, `notched://debug/…` URLs and the research probes are compiled out (`#if DEBUG`). Check the status menu.
3. First launch on a clean account or after `defaults delete me.rkck.Notched`: onboarding runs, nothing asks for a permission, and every module that needs one asks only when turned on.
4. Idle CPU and memory with your usual modules: `scripts/cpu.sh 60 "release idle"`. Budget: CPU under 0.5 %, memory under 150 MB.
5. For a longer check, `scripts/soak.sh 8` overnight, and read the summary.
6. The status menu offers Settings, Pause island and Quit. (Once lock-screen widgets ship: the kill switches in ADR-0031 work, including `--no-lock-screen`.)

## Giving a copy to someone else

A build signed with your personal Apple Development certificate runs on your Mac. On another Mac, Gatekeeper will refuse it, because it isn't notarised. The honest options:

- **Have them build it themselves.** Point them at the README. They need Xcode, XcodeGen and their own free Apple ID team (change `DEVELOPMENT_TEAM`).
- **A zip for a friend you trust:** `ditto -c -k --keepParent ~/Applications/Notched.app Notched.zip`. They must clear the quarantine flag with `xattr -dr com.apple.quarantine Notched.app` and approve it in *System Settings ▸ Privacy & Security*, and their permissions are asked fresh. This is for people who understand what they're running, not a public release.

## If you want a real public release later

That needs a paid Apple Developer Program membership, so it is out of scope for now. The steps, for when that changes:

1. A *Developer ID Application* certificate; set `CODE_SIGN_IDENTITY` and the team for Release only.
2. Hardened Runtime is already on. Check the entitlements still cover Apple Events, Calendars and Location (`App/Notched.entitlements`).
3. Archive, then notarise with `xcrun notarytool submit … --wait` using a keychain profile (never commit credentials), then `xcrun stapler staple`.
4. Zip or DMG, upload to a GitHub Release, and (with Sparkle) sign the update with an EdDSA key kept in the Keychain and documented, never committed.

Nothing here publishes anything. A release script (`scripts/release.sh`) will be written only if that route is taken.
