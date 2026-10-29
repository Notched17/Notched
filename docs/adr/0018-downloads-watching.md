# ADR-0018: How Downloads watches the folder (#35)

- Status: accepted, partly verified (M3b A4). The real-browser and permission-prompt checks are on Charlie's list for the end of Part A.
- Date: 2026-10-29
- Mac: Mac16,13, macOS 27.2.

## Context

Downloads shows progress for browser downloads into `~/Downloads` and a banner when one finishes. The plan (`docs/superpowers/specs/2026-10-28-m3b-system-design.md`, S4) listed three routes: a public `Progress` subscriber on the folder, FSEvents on the folder with the browsers' partial-file naming, and the `com.apple.progress.fractionCompleted` attribute. Charlie couldn't run real-browser tests during the build, so each route was judged by what could be proven without one.

## Decisions

1. **FSEvents plus a scan; no `Progress` subscriber.** Whether Safari, Chrome and Firefox publish `NSProgress` for `addSubscriber(forFileURL:)` on 27.2 is unverified, and code for a route nobody has seen work is a guess. The stream (`DownloadsWatcher`) only decides *when to look*; each look (`DownloadsScanner`) is one directory listing plus a `stat` per partial file. The subscriber can be added later, behind a real-browser test, if the size-and-attribute route proves too coarse.
2. **Events deeper than the folder are dropped without a look**, except inside a Safari `.download` bundle. An archive unzipping thousands of files into a subfolder costs a handful of scans, not thousands (tested with 2 000 files).
3. **Progress** comes from `com.apple.progress.fractionCompleted` when a browser writes it (read with either decimal separator: "0,42" or "0.42"), otherwise the combined ring is indeterminate and speed comes from growth between looks. A long gap (sleep) gives no speed, and no false cancel.
4. **Finished means the final file exists, with data, written after the partial appeared.** Firefox leaves an empty placeholder with the final name from the start, and an old file with the same name mustn't count. A partial that just vanishes waits two seconds for its rename, then is treated as cancelled, quietly.
5. **Chrome's `Unconfirmed 123.crdownload`** is a download whose name isn't known yet; when it disappears and a real partial name appears with at least as many bytes, that's one download carrying on.
6. **Permission: Files & Folders (Downloads), asked only when the module is turned on.** The status probe never reads the folder: the read that shows the prompt blocks until it's answered, and `PermissionCenter.refresh()` runs on the main actor. The probe reports the last answer a read made off the main thread left behind (`DownloadsAccess`), and once asked, the read repeats off-main on activation, since the answer can change in System Settings. Nothing is watched until it's allowed, and the stream is removed if it's switched off or the permission goes.
7. **Bounds:** at most 20 downloads tracked, 200 partial files read per look, one banner per look for everything that finished in it, and no more than three banners a minute.

## Found while building

- `URL.resolvingSymlinksInPath()` strips a leading `/private`, so a watched folder under `/var/...` never matched the `/private/var/...` paths FSEvents reports, and no event was ever relevant. The watcher resolves the root with `realpath()`. It wouldn't show on `/Users/…/Downloads`, but would on a redirected or external Downloads folder; a test against real temporary folders caught it.
- The expanded island holds 160 pt of content: three download rows with slim bars fit, more than three show two and "and N more".

## Not yet verified

- That each browser's partial files behave as described (`.crdownload`, a Safari `.download` bundle, Firefox's `.part` and placeholder, Opera's `.opdownload`) on a real download. The conventions come from published notes on other notch apps, and are covered by tests against simulated files only.
- What FSEvents, `stat` and `getxattr` do on `~/Downloads` when the permission is denied, and what the prompt looks like. Until then a denied folder simply means the module watches nothing and says so in its settings.
- Whether a browser writes the progress attribute at all, and onto which path.
