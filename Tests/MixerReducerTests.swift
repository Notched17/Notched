// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The per-app volume mixer's rules (#17, ADR-0029): taps only below 100 %,
/// and the probation that turns a refused permission into a sub-second blip.
@Suite("MixerReducer")
struct MixerReducerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 90_000)
    let spotify = MixerReducer.Observed(id: "com.spotify.client", name: "Spotify", isPlaying: true)
    let safari = MixerReducer.Observed(id: "com.apple.Safari", name: "Safari", isPlaying: true)
    let window = MixerReducer.probationWindow

    private func with(_ observed: [MixerReducer.Observed]) -> MixerReducer {
        var sut = MixerReducer()
        _ = sut.reduce(.apps(observed), now: t0)
        return sut
    }

    /// Spotify at 50 %, tap running and on probation since t0.
    private func tapped() -> MixerReducer {
        var sut = with([spotify])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        _ = sut.reduce(.tapStarted(spotify.id), now: t0)
        return sut
    }

    @Test("Apps appearing, untouched, cost nothing")
    func appearingIsSilent() {
        var sut = MixerReducer()
        #expect(sut.reduce(.apps([spotify, safari]), now: t0).isEmpty)
        #expect(sut.apps.map(\.id) == [spotify.id, safari.id])
        #expect(sut.apps.allSatisfy { $0.tap == .none })
    }

    @Test("Lowering a volume starts a tap at that gain; more movement only changes the gain")
    func lowerStartsTap() {
        var sut = with([spotify])
        #expect(sut.reduce(.setVolume(spotify.id, 0.6), now: t0) == [.startTap(spotify.id, gain: 0.6)])
        #expect(sut.apps[0].tap == .starting)
        #expect(sut.reduce(.setVolume(spotify.id, 0.4), now: t0) == [.setGain(spotify.id, 0.4)])
    }

    @Test("Back to 100 % removes the tap, so the recording dot goes")
    func fullVolumeRemovesTap() {
        var sut = tapped()
        #expect(sut.reduce(.setVolume(spotify.id, 1), now: t0 + 1) == [.stopTap(spotify.id)])
        #expect(sut.apps[0].tap == .none)
        #expect(sut.reduce(.setVolume(spotify.id, 1), now: t0 + 2).isEmpty)
    }

    @Test("Mute is a tap at gain zero; unmuting at 100 % removes it")
    func muteIsGainZero() {
        var sut = with([spotify])
        #expect(sut.reduce(.setMuted(spotify.id, true), now: t0) == [.startTap(spotify.id, gain: 0)])
        #expect(sut.reduce(.setMuted(spotify.id, false), now: t0) == [.stopTap(spotify.id)])
    }

    @Test("Volumes are clamped to 0…100 %")
    func clamped() {
        var sut = with([spotify])
        _ = sut.reduce(.setVolume(spotify.id, -3), now: t0)
        #expect(sut.apps[0].volume == 0)
        #expect(sut.reduce(.setVolume(spotify.id, 9), now: t0) == [.stopTap(spotify.id)])
        #expect(sut.apps[0].volume == 1)
    }

    @Test("A started tap goes on probation and asks to be judged after the window")
    func probationStarts() {
        var sut = with([spotify])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        #expect(sut.reduce(.tapStarted(spotify.id), now: t0 + 2) == [.wake(t0 + 2 + window)])
        #expect(sut.apps[0].tap == .probation(until: t0 + 2 + window))
        #expect(sut.onProbation == [spotify.id])
    }

    @Test("Sound proves the permission, records it once, and ends probation")
    func heardProves() {
        var sut = tapped()
        #expect(sut.reduce(.heard(spotify.id), now: t0 + 0.2) == [.recordPermission(granted: true)])
        #expect(sut.isPermissionProven)
        #expect(sut.apps[0].tap == .running)
        #expect(sut.reduce(.heard(spotify.id), now: t0 + 0.3).isEmpty)
        // The deadline then finds nothing to judge.
        #expect(sut.reduce(.tick, now: t0 + window).isEmpty)
        #expect(sut.apps[0].problem == nil)
    }

    @Test("Only silence while playing: the tap is removed, the app is marked, the refusal is recorded")
    func silenceIsRefusal() {
        var sut = tapped()
        let effects = sut.reduce(.tick, now: t0 + window)
        #expect(effects == [.stopTap(spotify.id), .recordPermission(granted: false)])
        #expect(sut.apps[0].tap == .none)
        #expect(sut.apps[0].problem == .silent)
        #expect(!sut.isPermissionProven)
    }

    @Test("A tick before the deadline waits for it")
    func tickEarly() {
        var sut = tapped()
        #expect(sut.reduce(.tick, now: t0 + 0.3) == [.wake(t0 + window)])
        #expect(sut.apps[0].tap == .probation(until: t0 + window))
    }

    @Test("A quiet app can't be judged; its clock starts when it plays")
    func quietAppWaits() {
        var sut = with([spotify])
        _ = sut.reduce(.apps([.init(id: spotify.id, name: "Spotify", isPlaying: false)]), now: t0)
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        #expect(sut.reduce(.tapStarted(spotify.id), now: t0) == [])
        #expect(sut.apps[0].tap == .probation(until: nil))
        // Nothing to judge, and no timer.
        #expect(sut.reduce(.tick, now: t0 + 10).isEmpty)
        #expect(sut.reduce(.apps([spotify]), now: t0 + 20) == [.wake(t0 + 20 + window)])
        #expect(sut.reduce(.tick, now: t0 + 20 + window) == [.stopTap(spotify.id), .recordPermission(granted: false)])
    }

    @Test("A playing app that pauses during probation isn't blamed")
    func pauseDuringProbation() {
        var sut = tapped()
        _ = sut.reduce(.apps([.init(id: spotify.id, name: "Spotify", isPlaying: false)]), now: t0 + 0.1)
        #expect(sut.reduce(.tick, now: t0 + window).isEmpty)
        #expect(sut.apps[0].tap == .probation(until: nil))
        #expect(sut.apps[0].problem == nil)
    }

    @Test("Once proven, later taps skip probation")
    func provenSkipsProbation() {
        var sut = with([spotify, safari])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        _ = sut.reduce(.tapStarted(spotify.id), now: t0)
        _ = sut.reduce(.heard(spotify.id), now: t0 + 0.2)
        _ = sut.reduce(.setVolume(safari.id, 0.3), now: t0 + 5)
        #expect(sut.reduce(.tapStarted(safari.id), now: t0 + 5).isEmpty)
        #expect(sut.apps[1].tap == .running)
    }

    @Test("Nothing retries by itself after a refusal")
    func noAutoRetry() {
        var sut = tapped()
        _ = sut.reduce(.tick, now: t0 + window)
        #expect(sut.reduce(.apps([spotify]), now: t0 + 5).isEmpty)
        #expect(sut.reduce(.outputChanged, now: t0 + 6).isEmpty)
        #expect(sut.apps[0].problem == .silent)
    }

    @Test("Try Again, or moving the slider, tries once more")
    func retry() {
        var sut = tapped()
        _ = sut.reduce(.tick, now: t0 + window)
        #expect(sut.reduce(.retry(spotify.id), now: t0 + 9) == [.startTap(spotify.id, gain: 0.5)])
        #expect(sut.apps[0].problem == nil)

        var other = tapped()
        _ = other.reduce(.tick, now: t0 + window)
        #expect(other.reduce(.setVolume(spotify.id, 0.4), now: t0 + 9) == [.startTap(spotify.id, gain: 0.4)])
    }

    @Test("Back to 100 % clears a refusal without trying again")
    func fullVolumeClearsProblem() {
        var sut = tapped()
        _ = sut.reduce(.tick, now: t0 + window)
        #expect(sut.reduce(.setVolume(spotify.id, 1), now: t0 + 3).isEmpty)
        #expect(sut.apps[0].problem == nil)
    }

    @Test("A tap that fails to build marks the app and doesn't retry")
    func buildFailure() {
        var sut = with([spotify])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        #expect(sut.reduce(.tapFailed(spotify.id), now: t0) == [.stopTap(spotify.id)])
        #expect(sut.apps[0].problem == .failed)
        #expect(sut.apps[0].tap == .none)
        #expect(sut.reduce(.apps([spotify]), now: t0 + 1).isEmpty)
    }

    @Test("A tap result for an app whose tap was already removed is ignored")
    func lateResult() {
        var sut = with([spotify])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        _ = sut.reduce(.setVolume(spotify.id, 1), now: t0 + 0.1)   // back to normal while the prompt was up
        #expect(sut.reduce(.tapStarted(spotify.id), now: t0 + 30).isEmpty)
        #expect(sut.reduce(.tapFailed(spotify.id), now: t0 + 30).isEmpty)
        #expect(sut.apps[0].tap == .none)
        #expect(sut.apps[0].problem == nil)
    }

    @Test("An app that quits loses its tap and its place")
    func appQuits() {
        var sut = with([spotify, safari])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        #expect(sut.reduce(.apps([safari]), now: t0 + 1) == [.stopTap(spotify.id)])
        #expect(sut.apps.map(\.id) == [safari.id])
        #expect(sut.reduce(.setVolume(spotify.id, 0.2), now: t0 + 2).isEmpty)
    }

    @Test("An output change rebuilds every tap; before proof, probation starts over")
    func outputChange() {
        var sut = tapped()
        #expect(sut.reduce(.outputChanged, now: t0 + 1) == [.rebuildTap(spotify.id)])
        #expect(sut.apps[0].tap == .starting)
        #expect(sut.reduce(.tapStarted(spotify.id), now: t0 + 1.2) == [.wake(t0 + 1.2 + window)])

        var proven = tapped()
        _ = proven.reduce(.heard(spotify.id), now: t0 + 0.2)
        #expect(proven.reduce(.outputChanged, now: t0 + 1) == [.rebuildTap(spotify.id)])
        #expect(proven.apps[0].tap == .running)
        #expect(proven.reduce(.tapStarted(spotify.id), now: t0 + 1.1).isEmpty)
    }

    @Test("Apps at normal volume have no taps to rebuild")
    func outputChangeWithoutTaps() {
        var sut = with([spotify, safari])
        #expect(sut.reduce(.outputChanged, now: t0).isEmpty)
    }

    @Test("Reset puts everything back to 100 % and removes every tap")
    func reset() {
        var sut = with([spotify, safari])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        _ = sut.reduce(.setMuted(safari.id, true), now: t0)
        let effects = sut.reduce(.resetAll, now: t0 + 1)
        #expect(effects == [.stopTap(spotify.id), .stopTap(safari.id)])
        #expect(sut.apps.allSatisfy { $0.volume == 1 && !$0.isMuted && $0.tap == .none && $0.problem == nil })
    }

    @Test("The list shows apps that play, or are still changed")
    func listing() {
        var sut = with([spotify])
        _ = sut.reduce(.apps([.init(id: spotify.id, name: "Spotify", isPlaying: false)]), now: t0)
        #expect(!sut.apps[0].isListed)
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        #expect(sut.apps[0].isListed)
    }

    @Test("Two wakes: the next deadline is kept after one app is judged")
    func nextDeadline() {
        var sut = with([spotify, safari])
        _ = sut.reduce(.setVolume(spotify.id, 0.5), now: t0)
        _ = sut.reduce(.tapStarted(spotify.id), now: t0)
        _ = sut.reduce(.setVolume(safari.id, 0.5), now: t0 + 0.5)
        _ = sut.reduce(.tapStarted(safari.id), now: t0 + 0.5)
        let effects = sut.reduce(.tick, now: t0 + window)
        #expect(effects == [.stopTap(spotify.id), .recordPermission(granted: false), .wake(t0 + 0.5 + window)])
    }
}
