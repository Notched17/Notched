# ADR-0017: Sensing the camera and microphone (#31, Calls)

- Status: accepted, partly verified (M3b spike S1). The real-app tests are still to do; they're on Charlie's list for the end of Part A.
- Date: 2026-10-28
- Mac: Mac16,13, macOS 27.2, Debug build signed with Apple Development, run from `~/Applications`.

## Context

Camera & Microphone (#31) and Calls need to know that the camera or microphone is in use, and by which app. The plan (`docs/superpowers/specs/2026-10-28-m3b-system-design.md`, S1) listed five questions to answer by experiment.

## What was verified

1. **Reading the state causes no permission prompt and no crash.** A DEBUG probe (`SensorUsageService` with a raw report) listed this Mac's three input devices (the MacBook's microphone, Charlie's iPhone's, and Zoom's virtual device), four cameras, and every audio process, with no prompt, no `tccd` request from the sensor code, and no crash report, under Hardened Runtime and without `device.audio-input` or `device.camera`. The listeners are public CoreAudio and CoreMediaIO property listeners; the process list uses `kAudioHardwarePropertyProcessObjectList` and `kAudioProcessPropertyIsRunningInput`.
2. **A real SensorUsageService starts and stops cleanly:** five start/stop cycles with real listeners leave none behind (`SensorUsageServiceTests`).
3. **`responsibility_get_pid_responsible_for_pid`** loads on 27.2 (`ResponsibleProcess.isAvailable` is true).

## Not yet verified (Charlie was unavailable)

- Which process reports an input stream during a FaceTime, Zoom, Teams, Slack or Discord call, a Continuity call, or a web page's microphone in Safari or Chrome. The design expects daemons (such as `avconferenced` for FaceTime) and helper processes (WebKit's GPU process), and falls back to "An app" for any it can't prove. **Nothing is named unless it is proven**, so this can't produce a wrong name; it can only produce a less specific one.
- Whether a call app drops its microphone stream while muted, which decides whether the 3 s grace period in Calls is enough.
- Whether output-only playback on a combined input and output device (AirPods, a USB headset) makes the device-level "running" flag true. The design doesn't depend on it: that flag only triggers a look, and the microphone counts as in use only when a process other than Notched has an input stream running.
- Which system daemons use the microphone without macOS showing an indicator (Siri, dictation), for the ignore list. `SensorUsageService.ignoredBundleIDs` is empty until measured.
- Whether the responsibility lookup names Safari for WebKit's GPU process.

## Also found

Every launch of Notched this session, since before M3b started (first seen 18:52), logs `tccd: Prompting policy for hardened runtime; service: kTCCServiceMicrophone requires entitlement com.apple.security.device.audio-input but it is missing`. No prompt appears, and the sensor code isn't the cause (the probe starting after launch added nothing). The trigger is somewhere in the launch path, and hasn't been found.

## Decision

Build Camera & Microphone and Calls on the design as planned, with "An app" wherever a name isn't proven. Run the real-app tests at the end of Part A and update this ADR and the ignore list with what they show.
