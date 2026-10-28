// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore
import SwiftUI

/// A timer's progress ring (#37), like the Clock app's. While running it's
/// one Core Animation `strokeEnd` animation from what's left to zero over
/// the time left, so it moves in the render server with no work in this
/// process (ADR-0010). The animation is removed while the ring is hidden or
/// its window covered, and rebuilt from the dates when it shows again. It
/// moves with Reduce Motion too: like the Clock app's ring, it's information.
struct TimerRing: NSViewRepresentable {
    let item: TimerItem
    var lineWidth: CGFloat = 3
    var tint: Color = TimersPresentation.tint

    func makeNSView(context: Context) -> TimerRingView {
        TimerRingView()
    }

    func updateNSView(_ view: TimerRingView, context: Context) {
        let progress: TimerRingView.Progress = switch item.phase {
        case .running(let endsAt): .running(endsAt: endsAt, duration: item.duration)
        case .paused: .still(item.fractionLeft(at: Date()))
        case .done: .still(0)
        }
        view.configure(TimerRingView.Configuration(progress: progress, lineWidth: lineWidth, tint: NSColor(tint).cgColor))
    }
}

final class TimerRingView: NSView {
    enum Progress: Equatable {
        case running(endsAt: Date, duration: TimeInterval)
        /// 0…1 of the ring, not moving.
        case still(Double)
    }

    struct Configuration: Equatable {
        var progress: Progress
        var lineWidth: CGFloat
        var tint: CGColor
    }

    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var configuration: Configuration?
    private var occlusionObserver: (any NSObjectProtocol)?
    /// The render server needn't redraw a slowly shrinking arc 120 times a second.
    private static let frameRate = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 20)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for shape in [track, ring] {
            shape.fillColor = nil
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    /// True while a ring animation is installed (tests check it stops when hidden).
    var isAnimating: Bool { ring.animation(forKey: "progress") != nil }

    func configure(_ next: Configuration) {
        guard next != configuration else { return }
        configuration = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = next.tint.copy(alpha: 0.25)
        ring.strokeColor = next.tint
        track.lineWidth = next.lineWidth
        ring.lineWidth = next.lineWidth
        CATransaction.commit()
        needsLayout = true
        apply()
    }

    override func layout() {
        super.layout()
        guard let configuration else { return }
        let inset = configuration.lineWidth / 2
        let radius = max(min(bounds.width, bounds.height) / 2 - inset, 0)
        let path = CGMutablePath()
        // From twelve o'clock, clockwise (AppKit's y axis points up).
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, ring] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
        apply()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }
        apply()
    }

    override func viewDidHide() {
        super.viewDidHide()
        apply()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        apply()
    }

    private var isVisible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !isHiddenOrHasHiddenAncestor
    }

    /// Sets the ring from the dates, then (if it's running and seen) lets
    /// Core Animation carry it to zero.
    private func apply() {
        guard let configuration else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.removeAnimation(forKey: "progress")
        switch configuration.progress {
        case .still(let fraction):
            ring.strokeEnd = CGFloat(min(max(fraction, 0), 1))
        case .running(let endsAt, let duration):
            let left = max(endsAt.timeIntervalSinceNow, 0)
            let fraction = duration > 0 ? min(left / duration, 1) : 0
            ring.strokeEnd = CGFloat(fraction)
            if isVisible && left > 0 {
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = fraction
                animation.toValue = 0
                animation.duration = left
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                animation.preferredFrameRateRange = Self.frameRate
                ring.add(animation, forKey: "progress")
            }
        }
        CATransaction.commit()
    }
}
