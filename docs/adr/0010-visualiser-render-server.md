# ADR-0010: The media visualiser animates in the render server

- Status: accepted (M2)
- Date: 2026-10-28

## Context

The visualiser (#12) is 4–5 rounded bars beside the notch while media plays. In M1.5, a SwiftUI `TimelineView(.animation)` level meter in the Scenario Lab cost about 7% CPU, because SwiftUI re-evaluates the view and re-renders on every frame. The M2 budget is < 1.5% while playing with the island compact, and < 3% expanded, with the adapter's helper process included. The brief suggested `TimelineView` or `Canvas`; both run per frame in the app process.

## Decision

- **Core Animation, not SwiftUI, moves the bars.** `MediaVisualizer` is a small `NSViewRepresentable`. Each bar is a `CALayer` with an infinitely repeating `CAKeyframeAnimation` on `transform.scale.y`, so the render server interpolates every frame and Notched itself does nothing per frame.
- **Alive, not random:** `VisualizerKeyframes` (tested) builds each bar's loop from two sines with a whole number of cycles per loop (seamless), a per-bar phase, and smooth value noise from a fixed seed. Loops last 2.3–3.4 s and differ per bar, so the pattern doesn't visibly repeat. Cubic keyframe interpolation keeps the motion soft.
- **Amplitude eases in and out** over 0.35 s: play animates from rest into the loop, and pause animates from the current presentation value down to a dot.
- **Stops completely** when playback pauses, when the view leaves its window (the island collapses or the activity ends), when the window is covered (`NSWindow.occlusionState`), and with Reduce Motion. The Still style shows bars at fixed heights; the Off style hides them.
- **Tinted** with the artwork's accent (`ArtworkColor`, tested), cross-faded over 0.45 s on track change.

## Consequences

Measured on macOS 27.2 with the Debug build, 28 Oct 2026, over 60 s, from cumulative CPU time (`ps -o time`):

| State | Notched | adapter helper (perl) | Total | Footprint |
|---|---|---|---|---|
| Module on, nothing playing (a paused video) | 0.000% | 0.000% | **0.000%** | 21 MB |
| Playing, compact, bars animating | 0.017% | 0.000% | **0.017%** | 22 MB |
| Playing, expanded (bars + scrubber ticking twice a second) | 0.317% | 0.000% | **0.317%** | 21 MB |

- The frame work moves to WindowServer, as for any Core Animation animation, and costs nothing in Notched.
- The bars can't react to the real audio. Audio-reactive bars would need Core Audio process taps and the System Audio Recording permission; that stays a later, opt-in option (#12 note).
