// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import QuartzCore
import SwiftUI

/// The media visualiser (#12): rounded bars that move like music while it
/// plays and settle to dots when it pauses.
///
/// The motion is Core Animation keyframe loops, which the render server
/// plays on its own, so Notched itself does no work per frame (a SwiftUI
/// `TimelineView` meter cost ~7% CPU in M1.5; ADR-0010). Every animation
/// is removed while the bars are off screen, covered, paused, or Reduce
/// Motion is on.
struct MediaVisualizer: NSViewRepresentable {
    var isPlaying: Bool
    var tint: ArtworkColor.RGB
    var barCount: Int
    var barWidth: CGFloat
    var height: CGFloat
    var style: VisualizerStyle
    @Environment(\.islandReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> VisualizerView {
        VisualizerView(barCount: barCount, barWidth: barWidth)
    }

    func updateNSView(_ view: VisualizerView, context: Context) {
        view.configure(VisualizerView.Configuration(
            isPlaying: isPlaying,
            tint: tint,
            animates: style == .animated && !reduceMotion
        ))
    }
}

final class VisualizerView: NSView {
    struct Configuration: Equatable {
        var isPlaying: Bool
        var tint: ArtworkColor.RGB
        /// False for the Still style and with Reduce Motion: bars stand at fixed heights.
        var animates: Bool
    }

    private let barWidth: CGFloat
    private var bars: [CALayer] = []
    private var configuration = Configuration(isPlaying: false, tint: .white, animates: true)
    private var isLooping = false
    private var occlusionObserver: (any NSObjectProtocol)?
    /// How long the amplitude takes to rise on play and fall on pause.
    private static let easeDuration: CFTimeInterval = 0.35
    private static let stillLevels: [CGFloat] = [0.55, 0.9, 0.7, 1, 0.6]

    init(barCount: Int, barWidth: CGFloat) {
        self.barWidth = barWidth
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.cornerRadius = barWidth / 2
            bar.cornerCurve = .continuous
            bar.backgroundColor = CGColor(gray: 1, alpha: 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    override func layout() {
        super.layout()
        let gap = barWidth * 0.9
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (barWidth + gap) + barWidth / 2, y: bounds.midY)
        }
        CATransaction.commit()
        apply(animated: false)
    }

    func configure(_ next: Configuration) {
        guard next != configuration else { return }
        let tintChanged = next.tint != configuration.tint
        configuration = next
        if tintChanged { applyTint() }
        apply(animated: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply(animated: false) }
            }
        }
        apply(animated: false)
    }

    // MARK: Animation

    private var isVisible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !isHiddenOrHasHiddenAncestor
    }

    /// The scale a bar rests at: a dot as wide as the bar.
    private var restScale: CGFloat { bounds.height > 0 ? min(barWidth / bounds.height, 1) : 1 }

    private func applyTint() {
        let color = CGColor(srgbRed: configuration.tint.r, green: configuration.tint.g, blue: configuration.tint.b, alpha: 1)
        for bar in bars {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = bar.presentation()?.backgroundColor ?? bar.backgroundColor
            fade.duration = 0.45
            bar.backgroundColor = color
            bar.add(fade, forKey: "tint")
        }
    }

    private func apply(animated: Bool) {
        guard bounds.height > 0 else { return }
        let shouldLoop = configuration.isPlaying && configuration.animates && isVisible
        if shouldLoop {
            if !isLooping { startLoops(easeIn: animated) }
        } else {
            stopLoops(easeOut: animated && isVisible)
        }
    }

    private func startLoops(easeIn: Bool) {
        isLooping = true
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            let levels = VisualizerKeyframes.levels(bar: index, count: 40).map { max(CGFloat($0), restScale) }
            let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? restScale
            bar.removeAllAnimations()
            setScale(levels[0], of: bar)
            let loop = CAKeyframeAnimation(keyPath: "transform.scale.y")
            loop.values = levels
            loop.calculationMode = .cubic
            loop.duration = VisualizerKeyframes.period(bar: index)
            loop.repeatCount = .infinity
            loop.isRemovedOnCompletion = false
            loop.beginTime = now + (easeIn ? Self.easeDuration : 0)
            if easeIn {
                let rise = CABasicAnimation(keyPath: "transform.scale.y")
                rise.fromValue = current
                rise.toValue = levels[0]
                rise.duration = Self.easeDuration
                rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.add(rise, forKey: "ease")
            }
            bar.add(loop, forKey: "loop")
        }
    }

    private func stopLoops(easeOut: Bool) {
        let wasLooping = isLooping
        isLooping = false
        for (index, bar) in bars.enumerated() {
            let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? restScale
            let target = configuration.isPlaying && !configuration.animates
                ? max(Self.stillLevels[index % Self.stillLevels.count], restScale)
                : restScale
            bar.removeAnimation(forKey: "loop")
            bar.removeAnimation(forKey: "ease")
            setScale(target, of: bar)
            if easeOut && (wasLooping || abs(current - target) > 0.01) {
                let fall = CABasicAnimation(keyPath: "transform.scale.y")
                fall.fromValue = current
                fall.toValue = target
                fall.duration = Self.easeDuration
                fall.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(fall, forKey: "ease")
            }
        }
    }

    private func setScale(_ scale: CGFloat, of bar: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.transform = CATransform3DMakeScale(1, scale, 1)
        CATransaction.commit()
    }
}

/// The visualiser's motion, worked out once per bar. Each bar is two sine
/// waves with a whole number of cycles per loop (so the loop is seamless),
/// a per-bar phase, and smooth value noise from a fixed seed, so it looks
/// alive without being random: the same every time, and different per bar.
enum VisualizerKeyframes {
    /// The quietest a moving bar gets, as a fraction of full height.
    static let minimumLevel = 0.18

    /// `count + 1` levels (the last equals the first), each minimumLevel…1.
    static func levels(bar: Int, count: Int) -> [Double] {
        let phase = Double(bar) * 0.37 + 0.11
        let slow = Double(2 + bar % 2)
        let fast = Double(5 + (bar * 2) % 3)
        var levels = (0..<count).map { step -> Double in
            let t = Double(step) / Double(count)
            let wave = 0.55
                + 0.22 * sin(2 * .pi * (t * slow + phase))
                + 0.12 * sin(2 * .pi * (t * fast + phase * 1.7))
                + 0.16 * (noise(bar: bar, at: t * 8) - 0.5) * 2
            return min(max(wave, minimumLevel), 1)
        }
        levels.append(levels[0])
        return levels
    }

    /// Seconds per loop for a bar: 2.3–3.4 s, different for each of the first five.
    static func period(bar: Int) -> Double {
        [2.3, 2.95, 2.6, 3.4, 2.45][bar % 5] + Double(bar / 5) * 0.07
    }

    /// Smooth value noise, periodic over 8 lattice points, 0…1.
    private static func noise(bar: Int, at x: Double) -> Double {
        let lattice = 8
        let cell = Int(x.rounded(.down))
        let fraction = x - Double(cell)
        let a = hash(bar, cell % lattice)
        let b = hash(bar, (cell + 1) % lattice)
        let smooth = fraction * fraction * (3 - 2 * fraction)
        return a + (b - a) * smooth
    }

    /// A deterministic 0…1 value for a bar and lattice point (SplitMix64).
    private static func hash(_ bar: Int, _ point: Int) -> Double {
        var z = UInt64(bar &* 7919 &+ point &* 104_729) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
