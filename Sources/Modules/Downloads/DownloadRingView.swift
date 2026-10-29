// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore
import SwiftUI

/// A download's progress ring. Determinate, it's one `strokeEnd`; with no
/// total it's a short arc turning forever. Both are Core Animation: the
/// rotation runs in the render server with no work in this process
/// (ADR-0010), and is removed while the ring is hidden or its window covered.
struct DownloadRing: NSViewRepresentable {
    /// 0…1, or nil when the total isn't known.
    let progress: Double?
    var lineWidth: CGFloat = 2.5
    var tint: Color = DownloadsPresentation.tint

    func makeNSView(context: Context) -> DownloadRingView { DownloadRingView() }

    func updateNSView(_ view: DownloadRingView, context: Context) {
        view.configure(DownloadRingView.Configuration(progress: progress, lineWidth: lineWidth, tint: NSColor(tint).cgColor))
    }
}

final class DownloadRingView: NSView {
    struct Configuration: Equatable {
        var progress: Double?
        var lineWidth: CGFloat
        var tint: CGColor
    }

    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var configuration: Configuration?
    private var occlusionObserver: (any NSObjectProtocol)?

    /// The arc that turns while the total is unknown.
    private static let indeterminateArc: CGFloat = 0.28

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
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ next: Configuration) {
        guard next != configuration else { return }
        configuration = next
        updatePaths()
        apply()
    }

    override func layout() {
        super.layout()
        updatePaths()
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

    override func viewDidHide() { super.viewDidHide(); apply() }
    override func viewDidUnhide() { super.viewDidUnhide(); apply() }

    private var isVisible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !isHiddenOrHasHiddenAncestor
    }

    private func updatePaths() {
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
            shape.lineWidth = configuration.lineWidth
        }
        track.strokeColor = configuration.tint.copy(alpha: 0.25)
        ring.strokeColor = configuration.tint
        CATransaction.commit()
    }

    private func apply() {
        guard let configuration else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.removeAnimation(forKey: "spin")
        if let progress = configuration.progress {
            ring.strokeEnd = CGFloat(min(max(progress, 0), 1))
        } else {
            ring.strokeEnd = Self.indeterminateArc
            if isVisible {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * Double.pi
                spin.duration = 1.1
                spin.repeatCount = .infinity
                spin.isRemovedOnCompletion = false
                spin.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 20)
                ring.add(spin, forKey: "spin")
            }
        }
        CATransaction.commit()
    }
}
