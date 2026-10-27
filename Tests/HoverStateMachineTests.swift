// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

@Suite("HoverStateMachine")
struct HoverStateMachineTests {
    let delay = Duration.milliseconds(150)

    private func machine(in state: HoverStateMachine.State = .compact) -> HoverStateMachine {
        HoverStateMachine(state: state)
    }

    @Test("Hovering schedules the expand after the configured delay")
    func hoverSchedulesExpand() {
        var sut = machine()
        let effects = sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: delay)
        #expect(effects == [.scheduleExpand(after: delay)])
        #expect(sut.state == .pendingExpand)
    }

    @Test("When the hover delay elapses the island expands")
    func delayElapsedExpands() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.expandDelayElapsed, hoverEnabled: true, hoverDelay: delay) == [.expand(.hover)])
        #expect(sut.state == .expanded)
    }

    @Test("Leaving before the delay elapses cancels the expand")
    func leavingEarlyCancels() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.pointerExited, hoverEnabled: true, hoverDelay: delay) == [.cancelTimers])
        #expect(sut.state == .compact)
    }

    @Test("A zero hover delay expands immediately")
    func zeroDelayExpandsImmediately() {
        var sut = machine()
        #expect(sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: .zero) == [.expand(.hover)])
        #expect(sut.state == .expanded)
    }

    @Test("A click expands immediately, even while a hover expand is pending")
    func clickExpandsImmediately() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.clicked, hoverEnabled: true, hoverDelay: delay) == [.cancelTimers, .expand(.click)])
        #expect(sut.state == .expanded)
    }

    @Test("With hover-to-expand off, hovering does nothing but a click still expands")
    func hoverDisabled() {
        var sut = machine()
        #expect(sut.handle(.pointerEntered, hoverEnabled: false, hoverDelay: delay).isEmpty)
        #expect(sut.state == .compact)
        #expect(sut.handle(.clicked, hoverEnabled: false, hoverDelay: delay) == [.cancelTimers, .expand(.click)])
        #expect(sut.state == .expanded)
    }

    @Test("Leaving the expanded island schedules a collapse after a short grace period")
    func leavingSchedulesCollapse() {
        var sut = machine(in: .expanded)
        let effects = sut.handle(.pointerExited, hoverEnabled: true, hoverDelay: delay)
        #expect(effects == [.scheduleCollapse(after: HoverStateMachine.collapseGrace)])
        #expect(sut.state == .pendingCollapse)
        #expect(sut.handle(.collapseGraceElapsed, hoverEnabled: true, hoverDelay: delay) == [.collapse])
        #expect(sut.state == .compact)
    }

    @Test("Coming back during the grace period keeps the island expanded")
    func reenteringCancelsCollapse() {
        var sut = machine(in: .pendingCollapse)
        #expect(sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: delay) == [.cancelTimers])
        #expect(sut.state == .expanded)
    }

    @Test("Clicking inside the expanded island doesn't change its state")
    func clickWhileExpanded() {
        var sut = machine(in: .expanded)
        #expect(sut.handle(.clicked, hoverEnabled: true, hoverDelay: delay).isEmpty)
        #expect(sut.state == .expanded)
    }

    @Test("Timer events that arrive after the state moved on are ignored")
    func staleTimersIgnored() {
        var sut = machine(in: .compact)
        #expect(sut.handle(.expandDelayElapsed, hoverEnabled: true, hoverDelay: delay).isEmpty)
        #expect(sut.handle(.collapseGraceElapsed, hoverEnabled: true, hoverDelay: delay).isEmpty)
        #expect(sut.state == .compact)
        var expanded = machine(in: .expanded)
        #expect(expanded.handle(.collapseGraceElapsed, hoverEnabled: true, hoverDelay: delay).isEmpty)
        #expect(expanded.state == .expanded)
    }

    @Test("A forced collapse collapses an expanded island and cancels timers")
    func forceCollapse() {
        var sut = machine(in: .pendingCollapse)
        #expect(sut.handle(.forceCollapse, hoverEnabled: true, hoverDelay: delay) == [.cancelTimers, .collapse])
        #expect(sut.state == .compact)
        var compact = machine(in: .pendingExpand)
        #expect(compact.handle(.forceCollapse, hoverEnabled: true, hoverDelay: delay) == [.cancelTimers])
        #expect(compact.state == .compact)
    }

    @Test("A forced expand (debug, keyboard) expands without hover")
    func forceExpand() {
        var sut = machine()
        #expect(sut.handle(.forceExpand, hoverEnabled: false, hoverDelay: delay) == [.cancelTimers, .expand(.programmatic)])
        #expect(sut.state == .expanded)
    }

    @Test("Leaving a compact island does nothing")
    func exitWhileCompact() {
        var sut = machine()
        #expect(sut.handle(.pointerExited, hoverEnabled: true, hoverDelay: delay).isEmpty)
        #expect(sut.state == .compact)
    }
}
