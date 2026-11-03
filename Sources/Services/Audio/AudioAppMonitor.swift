// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// A Core Audio property listener, removed when released. Not main-actor
/// isolated, so its block isn't either; the handler runs on the main queue.
final class AudioPropertyListener: @unchecked Sendable {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
        self.object = object
        address = CAProperty.address(selector)
        block = { _, _ in MainActor.assumeIsolated { handler() } }
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return nil }
    }

    deinit {
        var address = address
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
    }
}

/// Which apps have audio, and which are playing now (#17). Event-driven: a
/// listener on Core Audio's process list, and one on each process's
/// "running output" flag. Nothing runs unless `start()` was called.
@MainActor
final class AudioAppMonitor {
    /// Every app with an audio process, whenever that changes.
    var onChange: (([MixerReducer.Observed]) -> Void)?

    private var processListListener: AudioPropertyListener?
    private var playingListeners: [AudioObjectID: AudioPropertyListener] = [:]
    private var refreshPending = false
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        processListListener = AudioPropertyListener(object: AudioObjectID(kAudioObjectSystemObject),
                                                    selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.scheduleRefresh()
        }
        refresh()
    }

    func stop() {
        isRunning = false
        processListListener = nil
        playingListeners = [:]
        onChange = nil
    }

    /// Coalesces bursts (an app starting makes several processes appear).
    private func scheduleRefresh() {
        guard isRunning, !refreshPending else { return }
        refreshPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            refreshPending = false
            refresh()
        }
    }

    private func refresh() {
        guard isRunning else { return }
        let processes = AudioProcess.all()
        let objects = Set(processes.map(\.object))
        for object in playingListeners.keys where !objects.contains(object) { playingListeners[object] = nil }
        for object in objects where playingListeners[object] == nil {
            playingListeners[object] = AudioPropertyListener(object: object, selector: kAudioProcessPropertyIsRunningOutput) { [weak self] in
                self?.scheduleRefresh()
            }
        }
        var order: [String] = []
        var playing: [String: Bool] = [:]
        for process in processes {
            if playing[process.appID] == nil { order.append(process.appID) }
            playing[process.appID] = (playing[process.appID] ?? false) || process.isRunningOutput
        }
        onChange?(order.map { MixerReducer.Observed(id: $0, name: Self.name(of: $0), isPlaying: playing[$0] ?? false) })
    }

    /// The app's display name, or the last part of its bundle id.
    static func name(of bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
