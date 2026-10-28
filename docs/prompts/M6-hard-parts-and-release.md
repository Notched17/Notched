We're continuing Notched. M1–M4b are done ✅, and the HUD (formerly M5) shipped inside M3b (confirm in `docs/ROADMAP.md`; if M4b isn't merged into `main`, stop and tell me). This is **M6**: the hard and fragile features, then release readiness. Every hard item starts with a **spike and a go/no-go**; I'd rather drop a feature than ship something fragile that breaks the Mac.

## Model guide (for me, not for you)
- Plan mode (Step 0): Opus, high effort.
- Spikes and go/no-go decisions (6.1, 6.2) and the lock-screen safety design (6.3): Opus, xhigh effort.
- Implementation after approval: Sonnet, high effort for 6.1 to 6.3 (fragile system code) and medium effort for the rest.
- Polish, accessibility fixes, README, docs and ROADMAP: Sonnet, medium effort. Repo mechanics: Haiku via `build-runner`.
- Final fresh-reviewer pass: Opus, high effort.

## Read first
1. `CLAUDE.md` (binding): lock-screen window safety rules, private-API rules, event-tap rules.
2. `docs/ROADMAP.md` M6 rows **#17, #28, #59, #13b, #76** and the "Later" section.
3. The M2 lyrics code (13b reuses it), the M2 output/CoreAudio code (17 reuses it), `Sources/Services/Private/`.
4. Licence rules in `CLAUDE.md`: **never copy AirBattery (AGPL), SuperIsland (no licence) or Droppy (Commons Clause).** Lakr233/SkyLightWindow is MIT.

## Step 0: Plan (plan mode)
Propose a plan with a go/no-go gate for each hard item and wait for approval. Questions for me are expected.

## 6.1 Spike: per-app volume mixer (#17)
- Prototype Core Audio **process taps + aggregate devices** (macOS 14.4+) to control the volume of individual apps. Prove: list apps currently producing audio, attenuate one app's audio without glitching others, behaviour when the app quits, when output device changes, and with Bluetooth outputs. Requires the audio-capture permission: record exactly which prompt appears.
- Write an ADR with measured CPU, latency, failure modes and a **go/no-go**. If go: an "Audio" tab with a slider per playing app (reuse the M2 output switcher). If no-go: stop and tell me, and drop it from the roadmap.
## 6.2 AirPods / accessory battery (#28)
- Spike two routes: private IOBluetooth properties via a `Services/Private/` wrapper, and BLE advertisement parsing with CoreBluetooth (Bluetooth permission). Original code only. Document what each returns on this Mac with my real AirPods (ask me to connect them).
- If reliable: left/right/case battery on connect (extends the M3a Bluetooth banner) and in the Audio tab; hidden automatically if unavailable. Otherwise report no-go.
## 6.3 Lock-screen widgets (#59) and lock-screen lyrics (#13b)
- **Safety first (design, wait for my approval):** re-read CLAUDE.md's lock-screen rules. Windows are created only on lock and destroyed on unlock; nothing sensitive is shown unless the setting is on; a kill switch in Settings and a launch argument that disables the feature; if anything fails the lock screen must be untouched. Off by default, with a clear warning.
- Use Lakr233/SkyLightWindow (MIT, `moveToSky()`), attributed. Widgets: Now Playing (artwork, controls), battery, next calendar event. Then #13b: the current lyric line under the lock-screen player (reuse #13 timing).
- Test lock/unlock many times, fast user switching, display sleep, external displays, and a crash while locked (the lock screen must still work and the app must recover). Give me a numbered list for any physical test.
## 6.4 Auto-updates (#76) — ask me first
- Ask whether I want this at all, and whether to set up **Sparkle 2** keys (EdDSA appcast on GitHub Pages) now. If yes: Sparkle with stable/beta channels, never auto-install without consent, keys documented but never committed. If no: skip and mark the row parked.

## 6.5 Release readiness (always do)
- **Polish pass:** an accessibility audit (VoiceOver labels on every control, keyboard navigation, Reduce Motion/Transparency/Increase Contrast) using the `hig-compliance-auditor` skill; fix findings. Review onboarding end to end for a brand-new user (permissions explained, each optional).
- **Robustness audit:** crash-loop protection works, safe mode works, every module toggles cleanly, no leaked listeners/assertions/timers/processes after 30 minutes of mixed use. Leave it running overnight; report CPU and memory after 8 hours.
- **Performance budget table** for the whole app, one row per module (idle, active), measured with `scripts/cpu.sh`.
- **Repo and docs:** README (what it is, screenshots, features, permissions table explaining each permission and why, build instructions, known limits such as no Maps turn-by-turn), CONTRIBUTING, `LICENSE` (GPL-3.0), a complete `THIRD_PARTY_NOTICES.md` audit, a "Privacy" doc (what touches the network: lyrics, weather, updates only), and a donations link placeholder if I want one (ask me).
- **Signing and notarisation:** if I want to share builds, set up Developer ID signing and notarisation steps in `docs/RELEASING.md` and a script (`scripts/release.sh`); don't run anything that publishes without my say-so.
- Update ROADMAP: mark everything ✅/🟨/✖ honestly. Parked items stay parked: Teleprompter (#54), Face Unlock (#61), Spotify likes.
- Fresh-reviewer pass on the whole branch (Opus high) and fix critical/important findings.

## Final report
For each hard item: go or no-go with evidence; screenshots in `docs/screenshots/m6/`; performance table; overnight results; what works on macOS 27.2; decisions; things for me to try; and a short list of "next ideas" (e.g. teleprompter, file shelf, energy modes).

If a spec is impossible or unsafe, stop and tell me. Don't merge or push without asking.
