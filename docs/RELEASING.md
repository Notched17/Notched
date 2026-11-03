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
4. Idle CPU and memory with your usual modules: `scripts/cpu.sh 60 "release idle"`. Budget: CPU under 0.5 %, memory under 120 MB (the budget in `CLAUDE.md`).
5. For a longer check, `scripts/soak.sh 8` overnight, and read the summary.
6. The status menu offers Settings, Pause island and Quit. (Once lock-screen widgets ship: the kill switches in ADR-0031 work, including `--no-lock-screen`.)

## Giving a copy to someone else

A build signed with your personal Apple Development certificate runs on your Mac. On another Mac, Gatekeeper will refuse it, because it isn't notarised. The honest options:

- **Have them build it themselves.** Point them at the README. They need Xcode, XcodeGen and their own free Apple ID team (change `DEVELOPMENT_TEAM`).
- **A zip for a friend you trust, installed with one command** (below). This is for people who understand what they're running, not a public release.

### Share a build with friends (GitHub Release + one-line install)

macOS only blocks apps that carry the *quarantine* flag, and files saved by a browser, AirDrop or Messages get it. A file downloaded with `curl` does not. So friends install with a script that downloads the release zip, checks its SHA-256, unzips it into `~/Applications` and opens it. No trip to System Settings. (Their permission prompts for Accessibility and so on still appear, as normal.)

**Each time you want to publish a build**

1. Make sure `main` is committed and the tests pass: `scripts/go.sh --no-install`.
2. Set the version in `project.yml` (`MARKETING_VERSION`, top of the file) if it changed, then commit it.
3. Pack it: `scripts/package-release.sh`. It builds Release, checks the signature and that the app holds nothing but the app, then writes `build/release/Notched.zip` and `build/release/Notched.zip.sha256`.
4. Tag the commit and push the tag (ask yourself first: pushing is public):
   ```
   git tag v0.1.0
   git push origin v0.1.0
   ```
5. On GitHub: **Releases ▸ Draft a new release**, choose the tag, give it a title (`Notched 0.1.0`) and a few lines of notes, and **drag both files** from `build/release/` into the box. The file names must stay exactly `Notched.zip` and `Notched.zip.sha256`: the install script finds the newest release through GitHub's `releases/latest/download/Notched.zip` link. Leave **Set as a pre-release** unticked (GitHub's `latest` link skips pre-releases and drafts), keep **Set as the latest release** ticked, and click **Publish release**.
6. Test it on a Mac that isn't your dev Mac if you can, then send friends this (one line, in Terminal):
   ```
   curl -fsSL https://raw.githubusercontent.com/Notched17/Notched/main/scripts/install-from-release.sh | bash
   ```
   Running it again later installs the newest release over the old one (their settings are kept).

Command-line alternative to step 5, if you have the GitHub CLI (`gh auth login` once):
```
gh release create v0.1.0 build/release/Notched.zip build/release/Notched.zip.sha256 --title "Notched 0.1.0" --notes "First build for friends."
```

**If a friend's Mac says the app "can't be opened"** they got the zip through a browser or AirDrop. Either use the one-liner above, or run `xattr -dr com.apple.quarantine /path/to/Notched.app` once, or open *System Settings ▸ Privacy & Security* and click **Open Anyway**.

**If the install script fails:** "could not download" means there is no published release yet (a draft doesn't count) or the file names are wrong; "does not match its checksum" means the two uploaded files are from different builds, so repack and re-upload both.

## If you want a real public release later

That needs a paid Apple Developer Program membership, so it is out of scope for now. The steps, for when that changes:

1. A *Developer ID Application* certificate; set `CODE_SIGN_IDENTITY` and the team for Release only.
2. Hardened Runtime is already on. Check the entitlements still cover Apple Events, Calendars and Location (`App/Notched.entitlements`).
3. Archive, then notarise with `xcrun notarytool submit … --wait` using a keychain profile (never commit credentials), then `xcrun stapler staple`.
4. Zip or DMG, upload to a GitHub Release, and (with Sparkle) sign the update with an EdDSA key kept in the Keychain and documented, never committed.

Nothing here publishes anything. A release script (`scripts/release.sh`) will be written only if that route is taken.

## Before the repo goes public

Done on 3 Nov 2026; repeat before each public push of a new branch.

- **Private test artefacts are never committed.** `docs/spikes/results/lockscreen-label.jpg` (a phone number, a face and a name) and `docs/prompts/M6-spike-1-assist.md` were committed by accident in `229d1e7` and merged to `main`. They were removed from `main`'s history, are now in `.gitignore`, and a test (`PrivacyGuardTests`) keeps them there. Keep personal files in `private/` (ignored, never part of the app or a release) or outside the repo. Before pushing, run `git status` and read what `git add` is about to take.
- **If the old commit was ever public, it still exists** in GitHub's cache and in the merged pull request's page (`refs/pull/12/head`) until GitHub Support purges it, and on any clone made before the rewrite. Treat what the photo showed as exposed.
- **History scan (text):** no tokens, keys, phone numbers or device names in any commit. The only matches are fake keys in tests, the copyright line (Charlie Auchter) and the commit email in one early design note.
- **History scan (images, OCR of all 150):** nothing sensitive. A few screenshots show a browser behind the island with the Mac username (`charlie`) in the address bar and course-site tab names (QUT Canvas, HiQ). Retake or crop them if that matters.
- **Personal device names** ("Kirby's WONDERBOOM") stay redacted in committed results.
