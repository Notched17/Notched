// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Notched

/// Two-finger trackpad swipes on the island (ISLAND-BEHAVIOR.md §6): one
/// gesture per swipe, in the direction the fingers moved.
@Suite("SwipeRecognizer")
struct SwipeRecognizerTests {
    typealias Sample = SwipeRecognizer.Sample

    /// Natural scrolling (the macOS default): moving the fingers right gives
    /// a positive x delta, moving them up a negative y delta.
    private func natural(_ dx: CGFloat, _ dy: CGFloat, _ phase: SwipeRecognizer.Phase) -> Sample {
        Sample(deltaX: dx, deltaY: dy, phase: phase, isDirectionInverted: true)
    }

    @Test("A swipe right past the threshold fires once")
    func swipeRight() {
        var sut = SwipeRecognizer()
        #expect(sut.handle(natural(0, 0, .began)) == nil)
        #expect(sut.handle(natural(15, 1, .changed)) == nil)
        #expect(sut.handle(natural(20, 0, .changed)) == .right)
        #expect(sut.handle(natural(30, 0, .changed)) == nil)
        #expect(sut.handle(natural(0, 0, .ended)) == nil)
    }

    @Test("A short swipe does nothing")
    func shortSwipe() {
        var sut = SwipeRecognizer()
        _ = sut.handle(natural(0, 0, .began))
        #expect(sut.handle(natural(-10, 0, .changed)) == nil)
        #expect(sut.handle(natural(0, 0, .ended)) == nil)
    }

    @Test("Fingers moving up fire an up swipe")
    func swipeUp() {
        var sut = SwipeRecognizer()
        _ = sut.handle(natural(0, 0, .began))
        #expect(sut.handle(natural(2, -40, .changed)) == .up)
    }

    @Test("Without natural scrolling the deltas are reversed, but the finger direction is the same")
    func traditionalScrolling() {
        var sut = SwipeRecognizer()
        _ = sut.handle(Sample(deltaX: 0, deltaY: 0, phase: .began, isDirectionInverted: false))
        #expect(sut.handle(Sample(deltaX: -40, deltaY: 0, phase: .changed, isDirectionInverted: false)) == .right)
    }

    @Test("A diagonal swipe fires only once one direction clearly dominates")
    func diagonal() {
        var sut = SwipeRecognizer()
        _ = sut.handle(natural(0, 0, .began))
        #expect(sut.handle(natural(30, -30, .changed)) == nil)
        #expect(sut.handle(natural(40, 0, .changed)) == .right)
    }

    @Test("Momentum after a swipe is ignored, and the next swipe can fire again")
    func momentumIgnored() {
        var sut = SwipeRecognizer()
        _ = sut.handle(natural(0, 0, .began))
        #expect(sut.handle(natural(-40, 0, .changed)) == .left)
        _ = sut.handle(natural(0, 0, .ended))
        #expect(sut.handle(natural(-60, 0, .momentum)) == nil)
        _ = sut.handle(natural(0, 0, .began))
        #expect(sut.handle(natural(-40, 0, .changed)) == .left)
    }

    @Test("A mouse wheel, which has no gesture phases, never swipes")
    func mouseWheelIgnored() {
        var sut = SwipeRecognizer()
        #expect(sut.handle(natural(0, -80, .none)) == nil)
    }
}
