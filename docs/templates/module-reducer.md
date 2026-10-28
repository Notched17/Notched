# Module reducer template

Every live module keeps its rules in a **pure reducer**: a value type that takes an event and the current time, updates its state, and returns the effects to carry out. The module class stays a thin shell around it:

- It turns system callbacks (IOKit, CoreAudio, `NWPathMonitor`, `NSEvent`, timers) into `Event`s.
- It carries out the `Effect`s: post or end an activity, show a banner, schedule a wake, play a sound.

The reducer is where the bugs live (flapping, thresholds, sleep, relaunch), so that's what gets unit-tested. It never touches the system.

Worked examples: `Sources/Modules/Media/MediaActivityReducer.swift` (M2) and every M3a module's `<Name>Reducer.swift`.

## Rules

- **Foundation only.** No AppKit, SwiftUI, IOKit or CoreAudio types in the reducer or its events. Convert them in the shell. This keeps it `Sendable`, and means the tests also run with plain `swift test`.
- **The clock is a parameter** (`now: Date`), never `Date()` inside the reducer.
- **Deadlines are effects.** The reducer asks for a wake (`.wake(Date)` / `.schedule(Date?)`). The shell owns one `OneShotTimer` and feeds the result back in as an event (`.tick`, `.deadline`). No polling.
- **The first observation is silent.** Seed the state from what's true at `start()` without announcing it, because the user didn't just plug in a charger that was already there.
- **Effects carry values, not ids to look up later.** The shell may run them after the state has moved on (a timer removed in the same step).
- **Banners go through `BannerSource`** when events can flap (ADR-0012).

## Template

```swift
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// <What the module shows, and the rules that are easy to get wrong.>
struct ThingReducer: Sendable {
    struct State: Equatable, Sendable {
        var seeded = false
        // what the module last saw and last announced
    }

    enum Event: Equatable, Sendable {
        case observed(ThingSnapshot)   // from the system shell
        case tick                      // the wake the reducer asked for
    }

    enum Effect: Equatable, Sendable {
        case banner(ThingBanner)
        case post(ThingSnapshot)
        case end
        case wake(Date)
    }

    private(set) var state = State()

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .observed(let snapshot):
            guard state.seeded else {
                state.seeded = true      // first observation: silent
                return []
            }
            return []
        case .tick:
            return []
        }
    }
}
```

## Shell

```swift
@MainActor
final class ThingModule: IslandModule {
    private var reducer = ThingReducer()
    private let wake = OneShotTimer()

    func start() {
        wake.action = { [weak self] in self?.send(.tick) }
        // register the system source; call send(.observed(...)) from its callback
    }

    func stop() {
        wake.schedule(at: nil)
        // unregister everything: a stopped module costs nothing
        context.activities.endAll()
        reducer = ThingReducer()
    }

    private func send(_ event: ThingReducer.Event) {
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .banner(let banner): context.activities.show(banner.transientBanner)
            case .post(let snapshot): context.activities.post(ThingPresentation.activity(snapshot))
            case .end: context.activities.end(Self.activityID)
            case .wake(let date): wake.schedule(at: date)
            }
        }
    }
}
```

## Tests

One `@Suite("<Name>Reducer")` in `Tests/<Name>ReducerTests.swift`, with a fixed `t0` and the clock moved by hand. Cover at least:

- the first observation is silent
- each announcement fires once, and not again for the same state
- flapping or jitter around a boundary doesn't spam
- sleep and wake, and relaunch, where the module has them
- an invariant across random event sequences (a fuzz test) when the module holds a system resource (assertions, listeners)
