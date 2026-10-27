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
        let effects = sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: delay, clickExpands: true)
        #expect(effects == [.scheduleExpand(after: delay)])
        #expect(sut.state == .pendingExpand)
    }

    @Test("When the hover delay elapses the island expands")
    func delayElapsedExpands() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.expandDelayElapsed, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.expand(.hover)])
        #expect(sut.state == .expanded)
    }

    @Test("Leaving before the delay elapses cancels the expand")
    func leavingEarlyCancels() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.pointerExited, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.cancelTimers])
        #expect(sut.state == .compact)
    }

    @Test("A zero hover delay expands immediately")
    func zeroDelayExpandsImmediately() {
        var sut = machine()
        #expect(sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: .zero, clickExpands: true) == [.expand(.hover)])
        #expect(sut.state == .expanded)
    }

    @Test("A click expands immediately, even while a hover expand is pending")
    func clickExpandsImmediately() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.clicked, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.cancelTimers, .expand(.click)])
        #expect(sut.state == .expanded)
    }

    @Test("With hover-to-expand off, hovering does nothing but a click still expands")
    func hoverDisabled() {
        var sut = machine()
        #expect(sut.handle(.pointerEntered, hoverEnabled: false, hoverDelay: delay, clickExpands: true).isEmpty)
        #expect(sut.state == .compact)
        #expect(sut.handle(.clicked, hoverEnabled: false, hoverDelay: delay, clickExpands: true) == [.cancelTimers, .expand(.click)])
        #expect(sut.state == .expanded)
    }

    @Test("Leaving the expanded island schedules a collapse after a short grace period")
    func leavingSchedulesCollapse() {
        var sut = machine(in: .expanded)
        let effects = sut.handle(.pointerExited, hoverEnabled: true, hoverDelay: delay, clickExpands: true)
        #expect(effects == [.scheduleCollapse(after: HoverStateMachine.collapseGrace)])
        #expect(sut.state == .pendingCollapse)
        #expect(sut.handle(.collapseGraceElapsed, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.collapse])
        #expect(sut.state == .compact)
    }

    @Test("Coming back during the grace period keeps the island expanded")
    func reenteringCancelsCollapse() {
        var sut = machine(in: .pendingCollapse)
        #expect(sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.cancelTimers])
        #expect(sut.state == .expanded)
    }

    @Test("Clicking inside the expanded island doesn't change its state")
    func clickWhileExpanded() {
        var sut = machine(in: .expanded)
        #expect(sut.handle(.clicked, hoverEnabled: true, hoverDelay: delay, clickExpands: true).isEmpty)
        #expect(sut.state == .expanded)
    }

    @Test("Timer events that arrive after the state moved on are ignored")
    func staleTimersIgnored() {
        var sut = machine(in: .compact)
        #expect(sut.handle(.expandDelayElapsed, hoverEnabled: true, hoverDelay: delay, clickExpands: true).isEmpty)
        #expect(sut.handle(.collapseGraceElapsed, hoverEnabled: true, hoverDelay: delay, clickExpands: true).isEmpty)
        #expect(sut.state == .compact)
        var expanded = machine(in: .expanded)
        #expect(expanded.handle(.collapseGraceElapsed, hoverEnabled: true, hoverDelay: delay, clickExpands: true).isEmpty)
        #expect(expanded.state == .expanded)
    }

    @Test("A forced collapse collapses an expanded island and cancels timers")
    func forceCollapse() {
        var sut = machine(in: .pendingCollapse)
        #expect(sut.handle(.forceCollapse, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.cancelTimers, .collapse])
        #expect(sut.state == .compact)
        var compact = machine(in: .pendingExpand)
        #expect(compact.handle(.forceCollapse, hoverEnabled: true, hoverDelay: delay, clickExpands: true) == [.cancelTimers])
        #expect(compact.state == .compact)
    }

    @Test("A forced expand (debug, keyboard) expands without hover")
    func forceExpand() {
        var sut = machine()
        #expect(sut.handle(.forceExpand, hoverEnabled: false, hoverDelay: delay, clickExpands: true) == [.cancelTimers, .expand(.programmatic)])
        #expect(sut.state == .expanded)
    }

    @Test("Leaving a compact island does nothing")
    func exitWhileCompact() {
        var sut = machine()
        #expect(sut.handle(.pointerExited, hoverEnabled: true, hoverDelay: delay, clickExpands: true).isEmpty)
        #expect(sut.state == .compact)
    }

    // MARK: Click to open (the default)

    @Test("With Click to Open, clicking the compact island activates the activity instead of expanding")
    func clickActivates() {
        var sut = machine()
        #expect(sut.handle(.clicked, hoverEnabled: true, hoverDelay: delay, clickExpands: false) == [.activate])
        #expect(sut.state == .compact)
    }

    @Test("With Click to Open, a click while a hover expand is pending cancels it and activates")
    func clickDuringPendingActivates() {
        var sut = machine(in: .pendingExpand)
        #expect(sut.handle(.clicked, hoverEnabled: true, hoverDelay: delay, clickExpands: false) == [.cancelTimers, .activate])
        #expect(sut.state == .compact)
    }

    // MARK: Alert expansion

    @Test("An alert expands the compact island")
    func alertExpands() {
        var sut = machine()
        #expect(sut.handle(.alertBegan, hoverEnabled: true, hoverDelay: delay, clickExpands: false) == [.expand(.alert)])
        #expect(sut.state == .alerting)
    }

    @Test("When the alert ends, the island collapses back to what it showed")
    func alertEndsCollapses() {
        var sut = machine(in: .alerting)
        #expect(sut.handle(.alertEnded, hoverEnabled: true, hoverDelay: delay, clickExpands: false) == [.collapse])
        #expect(sut.state == .compact)
    }

    @Test("Moving onto an alert expansion keeps it open as a normal hover")
    func pointerTakesOverAlert() {
        var sut = machine(in: .alerting)
        #expect(sut.handle(.pointerEntered, hoverEnabled: true, hoverDelay: delay, clickExpands: false) == [.userTookOverAlert])
        #expect(sut.state == .expanded)
        #expect(sut.handle(.alertEnded, hoverEnabled: true, hoverDelay: delay, clickExpands: false).isEmpty)
        #expect(sut.state == .expanded)
    }

    @Test("An alert never interrupts an island the user has open")
    func alertDoesNotInterrupt() {
        var sut = machine(in: .expanded)
        #expect(sut.handle(.alertBegan, hoverEnabled: true, hoverDelay: delay, clickExpands: false).isEmpty)
        #expect(sut.state == .expanded)
    }

    @Test("The user is interacting while hovering or with the island open, not during an alert or at rest")
    func isInteracting() {
        #expect(machine(in: .pendingExpand).isInteracting)
        #expect(machine(in: .expanded).isInteracting)
        #expect(machine(in: .pendingCollapse).isInteracting)
        #expect(!machine(in: .compact).isInteracting)
        #expect(!machine(in: .alerting).isInteracting)
    }
}
