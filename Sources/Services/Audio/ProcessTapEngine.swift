// SPDX-License-Identifier: GPL-3.0-or-later

import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import Synchronization

/// Per-app volume with Core Audio process taps (#17, ADR-0029).
///
/// A tap mixes one app's audio down to stereo and mutes the app itself
/// (`mutedWhenTapped`). A private aggregate device with the real output as its
/// main sub-device plays the tap back through an IOProc at the chosen gain.
/// Everything that talks to Core Audio runs on one serial background queue:
/// **creating a tap blocks for as long as the permission prompt is up** (56 s
/// seen), so it must never run on the main thread. The IOProc allocates,
/// locks and logs nothing; the gain is an atomic.
///
/// Taps belong to Notched's process, so they end with it: after a crash or
/// `kill -9` the app's sound comes straight back (ADR-0029 step 1.4).
@MainActor
final class ProcessTapEngine {
    /// The tap is running (also after a rebuild).
    var onStarted: ((String) -> Void)?
    /// Core Audio refused to build it.
    var onFailed: ((String) -> Void)?

    private let log = Log.module("audio")
    private let queue = DispatchQueue(label: "me.rkck.Notched.process-tap", qos: .userInitiated)
    private var handles: [String: TapHandle] = [:]

    var tappedApps: Set<String> { Set(handles.keys) }

    func start(app: String, gain: Float) {
        guard handles[app] == nil else { handles[app]?.gain.set(gain); return }
        let handle = TapHandle(app: app, gain: gain)
        handles[app] = handle
        build(handle, rebuilding: false)
    }

    func setGain(app: String, _ gain: Float) {
        handles[app]?.gain.set(gain)
    }

    /// Tears the tap down, so the app is no longer muted or recorded.
    func stop(app: String) {
        guard let handle = handles.removeValue(forKey: app) else { return }
        queue.async { handle.tearDown() }
    }

    func stopAll() {
        for app in Array(handles.keys) { stop(app: app) }
    }

    /// Rebuilds the tap on the current default output (the output changed).
    func rebuild(app: String) {
        guard let handle = handles[app] else { return }
        build(handle, rebuilding: true)
    }

    /// Whether sound has arrived through the app's tap since it was built.
    func hasHeardSound(app: String) -> Bool {
        (handles[app]?.counters.audibleCallbacks.load(ordering: .relaxed) ?? 0) > 0
    }

    private func build(_ handle: TapHandle, rebuilding: Bool) {
        let log = log
        queue.async { [weak self] in
            if rebuilding { handle.tearDown() }
            let started = DispatchTime.now()
            let failure = handle.build()
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            if let failure {
                log.error("Tap for an app failed: \(failure, privacy: .public)")
            } else {
                log.info("Tap built in \(Int(milliseconds)) ms")
            }
            Task { @MainActor in
                // Ignore an answer for a tap that was stopped, or replaced, meanwhile.
                guard let self, self.handles[handle.app] === handle else {
                    if failure == nil { self?.queue.async { handle.tearDown() } }
                    return
                }
                if failure == nil { self.onStarted?(handle.app) } else { self.onFailed?(handle.app) }
            }
        }
    }
}

// MARK: One tap

/// The gain the IOProc reads, as `Float` bits, so the real-time thread never locks.
final class ProcessTapGain: Sendable {
    private let bits: Atomic<UInt32>
    init(_ value: Float) { bits = Atomic(value.bitPattern) }
    var value: Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
    func set(_ value: Float) { bits.store(value.bitPattern, ordering: .relaxed) }
}

/// Counted on the real-time thread with relaxed atomics.
final class ProcessTapCounters: Sendable {
    let audibleCallbacks = Atomic<Int>(0)
}

/// One app's tap, aggregate and IOProc. Core Audio state is touched only on
/// the engine's queue; `gain` and `counters` are safe from anywhere.
private final class TapHandle: @unchecked Sendable {
    let app: String
    let gain: ProcessTapGain
    let counters = ProcessTapCounters()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    init(app: String, gain: Float) {
        self.app = app
        self.gain = ProcessTapGain(gain)
    }

    /// Builds the tap, aggregate and IOProc for the app's current audio
    /// processes and the current default output. Returns a reason on failure,
    /// after cleaning up.
    func build() -> String? {
        tearDown()
        let objects = AudioProcess.objects(of: app)
        guard !objects.isEmpty else { return "no audio process belongs to the app" }
        guard let output = CAProperty.defaultOutput(), let outputUID = CAProperty.string(output, kAudioDevicePropertyDeviceUID) else {
            return "no default output device"
        }

        // 1. The tap: a stereo mix of the app's processes, muting them while we read it.
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        let uuid = UUID()
        description.uuid = uuid
        description.name = "Notched app volume"
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { return fail("AudioHardwareCreateProcessTap", status) }
        tapID = tap

        // 2. A private aggregate: the real output as main sub-device, the tap as input.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notched app volume",
            kAudioAggregateDeviceUIDKey: "me.rkck.Notched.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else { return fail("AudioHardwareCreateAggregateDevice", status) }
        aggregateID = device

        // 3. The IOProc: tapped audio × gain → the output.
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil, ProcessTapRealtime.makeIOBlock(gain: gain, counters: counters))
        guard status == noErr, let procID else { return fail("AudioDeviceCreateIOProcIDWithBlock", status) }
        ioProcID = procID
        status = AudioDeviceStart(device, procID)
        guard status == noErr else { return fail("AudioDeviceStart", status) }
        return nil
    }

    /// Removes everything, in the order Core Audio needs. Safe to repeat.
    func tearDown() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID) }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func fail(_ call: String, _ status: OSStatus) -> String {
        tearDown()
        return "\(call) failed (\(status))"
    }
}

// MARK: Real-time path

/// Everything that runs on Core Audio's I/O thread. `nonisolated` on purpose:
/// a closure written in a `@MainActor` method is main-actor isolated in
/// Swift 6, and running it on the I/O thread would trip the runtime's
/// isolation check. No allocation, locks or logging in here.
enum ProcessTapRealtime {
    nonisolated static func makeIOBlock(gain: ProcessTapGain, counters: ProcessTapCounters) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            if mix(from: inputs, to: outputs, gain: gain.value) {
                _ = counters.audibleCallbacks.wrappingAdd(1, ordering: .relaxed)
            }
        }
    }

    /// Copies the tapped Float32 audio to the output at `gain`, for any layout
    /// (interleaved, or a buffer per channel). Output channels past the tap's
    /// get silence. Returns whether any input sample was non-zero.
    nonisolated static func mix(from inputs: UnsafeMutableAudioBufferListPointer, to outputs: UnsafeMutableAudioBufferListPointer,
                                gain: Float) -> Bool {
        var inputChannels = 0
        for buffer in inputs { inputChannels += Int(buffer.mNumberChannels) }
        var audible = false
        var outputChannelBase = 0
        for output in outputs {
            let outChannels = Int(output.mNumberChannels)
            guard outChannels > 0, let outData = output.mData else { continue }
            let out = outData.assumingMemoryBound(to: Float.self)
            let outFrames = Int(output.mDataByteSize) / (outChannels * MemoryLayout<Float>.size)
            for channel in 0..<outChannels {
                let global = outputChannelBase + channel
                var written = 0
                if global < inputChannels, let source = locate(channel: global, in: inputs) {
                    let frames = min(source.frames, outFrames)
                    for frame in 0..<frames {
                        let sample = source.data[frame * source.stride + source.offset]
                        if sample != 0 { audible = true }
                        out[frame * outChannels + channel] = sample * gain
                    }
                    written = frames
                }
                for frame in written..<outFrames { out[frame * outChannels + channel] = 0 }
            }
            outputChannelBase += outChannels
        }
        return audible
    }

    private nonisolated static func locate(channel: Int, in inputs: UnsafeMutableAudioBufferListPointer)
        -> (data: UnsafeMutablePointer<Float>, stride: Int, offset: Int, frames: Int)? {
        var remaining = channel
        for buffer in inputs {
            let channels = Int(buffer.mNumberChannels)
            if remaining < channels {
                guard let data = buffer.mData else { return nil }
                let frames = Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size)
                return (data.assumingMemoryBound(to: Float.self), channels, remaining, frames)
            }
            remaining -= channels
        }
        return nil
    }
}
