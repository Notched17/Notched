# mediaremote-adapter in Notched

- Upstream: https://github.com/ungive/mediaremote-adapter
- Version: v0.7.7 (commit e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6, 3 Sep 2026)
- Licence: BSD-3-Clause (`LICENSE`), see also `THIRD_PARTY_NOTICES.md`
- Changes: none. Files are copied as published (`bin/`, `include/`, `src/`, `LICENSE`, `README.md`, `CMakeLists.txt` for reference).

## How Notched builds it

`project.yml` builds the same sources as `CMakeLists.txt`, signed with the app's own identity instead of ad hoc:

| Upstream (CMake) | Notched (XcodeGen) | Ends up in |
|---|---|---|
| `MediaRemoteAdapter` framework | `MediaRemoteAdapter` target, `-fvisibility=default`, ARC | `Notched.app/Contents/Frameworks/` (embedded, **not linked**) |
| `MediaRemoteAdapterTestClient` | tool target | `Notched.app/Contents/MacOS/` |
| `bin/mediaremote-adapter.pl` | resource | `Notched.app/Contents/Resources/` |

The app runs `/usr/bin/perl <Resources>/mediaremote-adapter.pl <Frameworks>/MediaRemoteAdapter.framework <MacOS>/MediaRemoteAdapterTestClient stream --micros --debounce=100` (see `Sources/Services/NowPlaying/AdapterNowPlayingProvider.swift`).

## Updating

Replace the files with a newer tag, keep this file's version line current, and check the macOS badge and the open issues upstream. The "elected player only" limitation is tracked in upstream issues #41–#43.
