// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// Where the bundled mediaremote-adapter lives (Vendor/mediaremote-adapter/NOTCHED.md).
struct AdapterPaths: Sendable {
    var script: URL
    var framework: URL
    var testClient: URL

    /// The copies inside Notched.app, or nil if the bundle is incomplete.
    static var bundled: AdapterPaths? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let paths = AdapterPaths(
            script: script,
            framework: frameworks.appending(path: "MediaRemoteAdapter.framework"),
            testClient: Bundle.main.bundleURL.appending(path: "Contents/MacOS/MediaRemoteAdapterTestClient")
        )
        let files = FileManager.default
        guard files.fileExists(atPath: paths.framework.path), files.isExecutableFile(atPath: paths.testClient.path) else { return nil }
        return paths
    }

    /// The perl invocation for an adapter command. Paths must be absolute.
    func arguments(_ command: [String]) -> [String] {
        [script.path, framework.path, testClient.path] + command
    }
}

/// Reads Now Playing from any app through ungive/mediaremote-adapter (#10).
///
/// macOS 15.4+ only lets Apple-signed processes use MediaRemote, so the
/// adapter runs inside `/usr/bin/perl` and streams JSON lines. One long-lived
/// `stream` process reports changes as they happen (no polling); commands
/// are short one-shot processes.
///
/// Health: the first real payload proves it works. A non-zero exit means it
/// can't work here, and per the adapter's README it is not relaunched. A
/// death by signal is relaunched with backoff, three times at most.
@MainActor
final class AdapterNowPlayingProvider: NowPlayingProvider {
    var onUpdate: (NowPlayingSnapshot?) -> Void = { _ in }
    var onHealthChange: (AdapterHealth) -> Void = { _ in }
    private(set) var health: AdapterHealth = .unknown {
        didSet { if health != oldValue { onHealthChange(health) } }
    }

    private nonisolated static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let maxRelaunches = 3
    private let paths: AdapterPaths
    private let log = Log.module("media")
    private var process: Process?
    private var isRunning = false
    private var relaunches = 0
    private var relaunch: Task<Void, Never>?
    /// DEBUG: point the adapter at a missing framework to test the fallback.
    private let simulateFailure: Bool

    init(paths: AdapterPaths, simulateFailure: Bool = false) {
        self.paths = paths
        self.simulateFailure = simulateFailure
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        relaunches = 0
        launch()
    }

    func stop() {
        isRunning = false
        relaunch?.cancel()
        relaunch = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
    }

    // MARK: Stream

    private func launch() {
        let process = Process()
        process.executableURL = Self.perl
        var paths = self.paths
        if simulateFailure { paths.framework = paths.framework.deletingLastPathComponent().appending(path: "Missing.framework") }
        process.arguments = paths.arguments(["stream", "--micros", "--debounce=100"])
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let reader = StreamReader { [weak self] snapshot in
            // FIFO onto the main queue, so updates keep their order.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(snapshot) } }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { reader.feed(data) }
        }
        let log = self.log
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            // Every stderr line is an error message; non-fatal unless the process exits non-zero.
            let text = String(decoding: data.prefix(400), as: UTF8.self)
            log.notice("Adapter: \(text, privacy: .public)")
        }
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            let bySignal = ended.terminationReason == .uncaughtSignal
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.terminated(ended, status: status, bySignal: bySignal) }
            }
        }
        do {
            try process.run()
            self.process = process
            log.info("Adapter stream started (pid \(process.processIdentifier))")
        } catch {
            health = .failed("Couldn't start /usr/bin/perl: \(error.localizedDescription)")
            log.error("Adapter failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func received(_ snapshot: NowPlayingSnapshot?) {
        guard isRunning else { return }
        if snapshot != nil { health = .healthy }
        onUpdate(snapshot)
    }

    private func terminated(_ ended: Process, status: Int32, bySignal: Bool) {
        guard ended === process else { return }
        process = nil
        guard isRunning else { return }
        if !bySignal && status != 0 {
            // A fatal error: don't relaunch (adapter README).
            health = .failed("The adapter exited with status \(status).")
            log.error("Adapter exited with status \(status); not relaunching")
            onUpdate(nil)
            return
        }
        guard relaunches < Self.maxRelaunches else {
            health = .failed("The adapter stopped repeatedly.")
            log.error("Adapter stopped \(self.relaunches + 1) times; giving up")
            onUpdate(nil)
            return
        }
        relaunches += 1
        let delay = Double(1 << (relaunches - 1))
        log.notice("Adapter stopped (signal: \(bySignal)); relaunching in \(delay) s")
        relaunch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.launch()
        }
    }

    // MARK: Commands

    func send(_ command: MediaCommand) {
        let arguments: [String] = switch command {
        case .play: ["send", "0"]
        case .pause: ["send", "1"]
        case .togglePlayPause: ["send", "2"]
        case .next: ["send", "4"]
        case .previous: ["send", "5"]
        case .skipBackward15: ["send", "12"]
        case .skipForward15: ["send", "13"]
        case .seek(let seconds): ["seek", String(Int64(max(seconds, 0) * 1_000_000))]
        }
        let log = self.log
        Self.run(paths.arguments(arguments)) { status in
            if status != 0 { log.error("Adapter command \(arguments.joined(separator: " "), privacy: .public) failed with \(status)") }
        }
    }

    /// Runs the adapter's own self-test: exit 0 means it can read media.
    /// It may briefly publish a fake now-playing entry when nothing plays,
    /// so it only runs when there's reason to doubt the adapter.
    func runSelfTest() async -> Bool {
        let arguments = paths.arguments(["test"])
        let passed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Self.run(arguments) { status in continuation.resume(returning: status == 0) }
        }
        log.info("Adapter self-test \(passed ? "passed" : "failed", privacy: .public)")
        health = passed ? .healthy : .failed("The adapter's self-test failed.")
        return passed
    }

    /// Runs one perl invocation and reports its exit status (−1 if it couldn't start).
    private nonisolated static func run(_ arguments: [String], completion: @escaping @Sendable (Int32) -> Void) {
        let process = Process()
        process.executableURL = perl
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { completion($0.terminationStatus) }
        do { try process.run() } catch { completion(-1) }
    }
}

/// Decodes stream output on the pipe's background queue.
private final class StreamReader: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    // Guarded by `lock`.
    private var decoder = AdapterStreamDecoder()
    private let emit: @Sendable (NowPlayingSnapshot?) -> Void

    init(emit: @escaping @Sendable (NowPlayingSnapshot?) -> Void) {
        self.emit = emit
    }

    func feed(_ data: Data) {
        let results = lock.withLockUnchecked { decoder.feed(data) }
        for result in results { emit(result) }
    }
}
