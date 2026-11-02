// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uses Core Audio's public process-tap API (macOS 14.2+) the way Apple's
// "Capturing system audio with Core Audio taps" sample does: a tap on a
// process, inside a private aggregate device. Original code.

#if DEBUG
import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import Synchronization

/// M6 spike 6.1 (#17): can Notched turn one app's volume down, safely, with a
/// Core Audio **process tap**?
///
/// For the chosen app it creates a tap with `mutedWhenTapped` (the app's own
/// output goes silent while the tap is read) inside a private aggregate device
/// whose main sub-device is the current output. An IOProc copies the tapped
/// audio to that output at the chosen gain. It rebuilds the tap when the output
/// device changes or the app's audio processes change, and it measures what
/// the go/no-go needs: latency, glitches (processor overloads), recovery time,
/// whether audio actually arrives (it doesn't if permission is denied), and the
/// permission state before and after.
///
///     open -g "notched://debug/probe?name=audiotap&action=list"
///     open -g "notched://debug/probe?name=audiotap&action=tap&app=com.apple.Music&gain=0.3"
///     open -g "notched://debug/probe?name=audiotap&action=gain&app=com.apple.Music&gain=1"
///     open -g "notched://debug/probe?name=audiotap&action=report"
///     open -g "notched://debug/probe?name=audiotap&action=untap"          (all apps)
///
/// Results: `~/Library/Logs/Notched/spike-audiotap.txt`.
@MainActor
enum AudioTapProbe {
    private static var report: ProbeReport?
    private static var sessions: [String: AudioTapSession] = [:]
    private static var systemListeners: [AudioListener] = []

    static func handle(action: String, app: String?, gain: Double?) {
        let report = Self.report ?? ProbeReport(name: "audiotap")
        Self.report = report
        startSystemListeners()
        let level = Float(min(max(gain ?? 1, 0), 1))
        switch action {
        case "list":
            report.line("permission (TCC preflight, kTCCServiceAudioCapture): \(permission())")
            let processes = AudioProcessInfo.all()
            report.line("\(processes.count) audio process objects; playing now:")
            for process in processes where process.isRunningOutput { report.line("  \(process.summary)") }
        case "tap":
            guard let app else { report.line("tap: add &app=<bundle id>"); return }
            if let session = sessions[app] {
                session.setGain(level)
                report.line("tap \(app): already tapped; gain now \(level)")
                return
            }
            report.line("tap \(app) at \(level): permission before = \(permission())")
            let session = AudioTapSession(app: app, gain: level, report: report)
            sessions[app] = session
            session.build(reason: "first tap")
            // Whether audio actually arrives tells us more than any API: a denied
            // permission delivers silence while the app stays muted.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard sessions[app] === session else { return }
                report.line("tap \(app): after 3 s, permission = \(permission()); \(session.countersSummary)")
            }
        case "gain":
            guard let app, let session = sessions[app] else { report.line("gain: \(app ?? "-") isn't tapped"); return }
            session.setGain(level)
            report.line("gain \(app) → \(level)")
        case "untap":
            let targets = app.map { [$0] } ?? Array(sessions.keys)
            for target in targets {
                sessions.removeValue(forKey: target)?.tearDown(reason: "untap")
            }
            report.line("untapped \(targets.isEmpty ? "nothing" : targets.joined(separator: ", "))")
        case "report":
            report.line("--- report: permission = \(permission()), \(sessions.count) tapped app(s), Notched pid \(getpid())")
            for session in sessions.values { session.writeReport() }
            if let output = AudioDevices.defaultOutput() {
                report.line("default output: \(AudioDevices.describe(output))")
            }
        default:
            report.line("unknown action \(action)")
        }
    }

    private static func permission() -> String {
        TCCPreflight.isAvailable ? TCCPreflight.check("kTCCServiceAudioCapture").rawValue : "preflight unavailable"
    }

    /// The default output and the process list, watched once for the probe's life.
    private static func startSystemListeners() {
        guard systemListeners.isEmpty else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let output = AudioListener(object: system, selector: kAudioHardwarePropertyDefaultOutputDevice, handler: {
            let name = AudioDevices.defaultOutput().map(AudioDevices.describe) ?? "none"
            report?.line("default output changed → \(name)")
            for session in sessions.values { session.build(reason: "output device changed") }
        }) { systemListeners.append(output) }
        if let processes = AudioListener(object: system, selector: kAudioHardwarePropertyProcessObjectList, handler: {
            for (app, session) in sessions {
                switch session.processesChanged() {
                case .unchanged: break
                case .changed: session.build(reason: "the app's audio processes changed")
                case .gone:
                    report?.line("\(app): its audio processes are gone (quit or stopped); tearing down")
                    sessions.removeValue(forKey: app)?.tearDown(reason: "app gone")
                }
            }
        }) { systemListeners.append(processes) }
    }
}

// MARK: One tapped app

/// The gain the IOProc reads, as `Float` bits, so the real-time thread never locks.
final class TapGain: Sendable {
    let bits: Atomic<UInt32>
    init(_ value: Float) { bits = Atomic(value.bitPattern) }
    var value: Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
    func set(_ value: Float) { bits.store(value.bitPattern, ordering: .relaxed) }
}

/// Counted on the real-time thread with relaxed atomics: cheap and lock-free.
final class TapCounters: Sendable {
    let callbacks = Atomic<Int>(0)
    let audibleCallbacks = Atomic<Int>(0)
    let formatMismatches = Atomic<Int>(0)

    func reset() {
        callbacks.store(0, ordering: .relaxed)
        audibleCallbacks.store(0, ordering: .relaxed)
        formatMismatches.store(0, ordering: .relaxed)
    }
}

@MainActor
final class AudioTapSession {
    enum ProcessChange { case unchanged, changed, gone }

    let app: String
    private let gain: TapGain
    private let counters = TapCounters()
    private let report: ProbeReport
    private var processObjects: [AudioObjectID] = []
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUID = UUID()
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var overloadListener: AudioListener?
    private var overloads = 0
    private var builds = 0
    private var outputName = "-"

    init(app: String, gain: Float, report: ProbeReport) {
        self.app = app
        self.gain = TapGain(gain)
        self.report = report
    }

    func setGain(_ value: Float) { gain.set(value) }

    /// (Re)creates the tap and aggregate for the app's current audio processes
    /// and the current default output, and reports how long that took.
    func build(reason: String) {
        let started = DispatchTime.now()
        tearDown(reason: nil)
        processObjects = AudioProcessInfo.objects(belongingTo: app)
        guard !processObjects.isEmpty else {
            report.line("\(app): no audio process belongs to it yet (start playback first) [\(reason)]")
            return
        }
        guard let output = AudioDevices.defaultOutput(), let outputUID = AudioDevices.string(output, kAudioDevicePropertyDeviceUID) else {
            report.line("\(app): no default output device [\(reason)]")
            return
        }
        outputName = AudioDevices.describe(output)

        // 1. The tap: a stereo mix of the app's processes, muting them while we read it.
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "Notched spike tap (\(app))"
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { return fail("AudioHardwareCreateProcessTap", status, reason) }
        tapID = tap

        // 2. A private aggregate: the real output as main sub-device, the tap as input.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notched spike (\(app))",
            kAudioAggregateDeviceUIDKey: "me.rkck.Notched.spike.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else { return fail("AudioHardwareCreateAggregateDevice", status, reason) }
        aggregateID = device

        // 3. The IOProc: tapped audio × gain → the output. Built off the main actor (see makeIOBlock).
        counters.reset()
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil, AudioTapRealtime.makeIOBlock(gain: gain, counters: counters))
        guard status == noErr, let procID else { return fail("AudioDeviceCreateIOProcIDWithBlock", status, reason) }
        ioProcID = procID
        overloadListener = AudioListener(object: device, selector: kAudioDeviceProcessorOverload) { [weak self] in
            self?.overloads += 1
        }
        status = AudioDeviceStart(device, procID)
        guard status == noErr else { return fail("AudioDeviceStart", status, reason) }

        builds += 1
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        report.line("\(app): tap #\(builds) running in \(String(format: "%.1f", milliseconds)) ms on \(outputName); \(processObjects.count) process object(s); gain \(gain.value) [\(reason)]")
        report.line("\(app): tap format \(AudioDevices.tapFormat(tap)); aggregate \(AudioDevices.latencySummary(device))")
    }

    func processesChanged() -> ProcessChange {
        let now = AudioProcessInfo.objects(belongingTo: app)
        if now.isEmpty { return processObjects.isEmpty ? .unchanged : .gone }
        return Set(now) == Set(processObjects) ? .unchanged : .changed
    }

    var countersSummary: String {
        let callbacks = counters.callbacks.load(ordering: .relaxed)
        let audible = counters.audibleCallbacks.load(ordering: .relaxed)
        let mismatches = counters.formatMismatches.load(ordering: .relaxed)
        var text = "\(callbacks) IO callbacks, \(audible) with sound, \(overloads) overloads, \(mismatches) non-float buffers"
        if callbacks > 50, audible == 0 {
            text += ". SILENT: no audio is arriving (permission denied, or nothing playing). With mutedWhenTapped the app is silenced!"
        }
        return text
    }

    func writeReport() {
        report.line("\(app): output \(outputName), gain \(gain.value), builds \(builds); \(countersSummary)")
        if aggregateID != AudioObjectID(kAudioObjectUnknown) { report.line("\(app): aggregate \(AudioDevices.latencySummary(aggregateID))") }
    }

    func tearDown(reason: String?) {
        overloadListener = nil
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
        if let reason { report.line("\(app): torn down (\(reason)); \(countersSummary)") }
    }

    private func fail(_ call: String, _ status: OSStatus, _ reason: String) {
        report.line("\(app): \(call) failed: \(AudioDevices.fourCC(status)) [\(reason)]")
        tearDown(reason: nil)
    }
}

// MARK: Real-time path

/// Everything that runs on Core Audio's I/O thread. `nonisolated` on purpose:
/// a closure written inside a `@MainActor` method is main-actor isolated in
/// Swift 6, and calling it on the I/O thread would trip the runtime's
/// isolation check. No allocation, locks or logging in here.
enum AudioTapRealtime {
    nonisolated static func makeIOBlock(gain: TapGain, counters: TapCounters) -> AudioDeviceIOBlock {
        { _, input, _, output, _ in
            _ = counters.callbacks.wrappingAdd(1, ordering: .relaxed)
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            let audible = mix(from: inputs, to: outputs, gain: gain.value, counters: counters)
            if audible { _ = counters.audibleCallbacks.wrappingAdd(1, ordering: .relaxed) }
        }
    }

    /// Copies the tapped Float32 audio to the output at `gain`, for any layout
    /// (interleaved, or a buffer per channel). Output channels past the tap's
    /// (an 8-channel HDMI output) get silence. Returns whether any input sample
    /// was non-zero.
    nonisolated static func mix(from inputs: UnsafeMutableAudioBufferListPointer, to outputs: UnsafeMutableAudioBufferListPointer,
                                gain: Float, counters: TapCounters) -> Bool {
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
        if inputChannels == 0 { _ = counters.formatMismatches.wrappingAdd(1, ordering: .relaxed) }
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

// MARK: Core Audio helpers

/// A property listener on the main queue, removed when released. Not
/// main-actor isolated, so its block isn't either (see `AudioTapRealtime`);
/// the handler is called on the main queue.
final class AudioListener: @unchecked Sendable {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
        self.object = object
        address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        block = { _, _ in MainActor.assumeIsolated { handler() } }
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return nil }
    }

    deinit {
        // AudioObjectRemovePropertyListenerBlock is thread-safe; `address` is copied for the call.
        var address = address
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
    }
}

/// One process object Core Audio knows about.
struct AudioProcessInfo {
    var object: AudioObjectID
    var pid: pid_t
    var bundleID: String?
    var responsibleBundleID: String?
    var isRunningOutput: Bool

    /// The app this audio belongs to: the responsible app for helpers (WebKit's GPU process → Safari).
    var appBundleID: String? { responsibleBundleID ?? bundleID }

    var summary: String {
        "pid \(pid) object \(object) bundle \(bundleID ?? "-") app \(responsibleBundleID ?? "-") output \(isRunningOutput)"
    }

    @MainActor
    static func all() -> [AudioProcessInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        return AudioDevices.ids(system, kAudioHardwarePropertyProcessObjectList).compactMap { object in
            guard let pid = AudioDevices.value(object, kAudioProcessPropertyPID, as: pid_t.self), pid != getpid() else { return nil }
            let responsible = ResponsibleProcess.pid(responsibleFor: pid).flatMap { $0 == pid ? nil : $0 }
            return AudioProcessInfo(
                object: object, pid: pid,
                bundleID: AudioDevices.string(object, kAudioProcessPropertyBundleID),
                responsibleBundleID: responsible.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
                isRunningOutput: AudioDevices.value(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            )
        }
    }

    /// The process objects of `app` (by bundle id, or as the responsible app of a helper).
    @MainActor
    static func objects(belongingTo app: String) -> [AudioObjectID] {
        all().filter { $0.bundleID == app || $0.responsibleBundleID == app }.map(\.object)
    }
}

enum AudioDevices {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = Self.address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func value<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as _: T.Type) -> T? {
        var address = Self.address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func float64(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float64? {
        var address = Self.address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func defaultOutput() -> AudioObjectID? {
        value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self).flatMap { $0 == 0 ? nil : $0 }
    }

    static func describe(_ device: AudioObjectID) -> String {
        let name = string(device, kAudioObjectPropertyName) ?? "?"
        let transport = value(device, kAudioDevicePropertyTransportType, as: UInt32.self).map { fourCC($0) } ?? "?"
        let rate = float64(device, kAudioDevicePropertyNominalSampleRate).map { "\(Int($0)) Hz" } ?? "?"
        let latency = value(device, kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput, as: UInt32.self).map { "\($0)" } ?? "?"
        return "\"\(name)\" (\(transport), \(rate), own output latency \(latency) frames)"
    }

    /// The numbers that make up the tap path's extra delay.
    static func latencySummary(_ device: AudioObjectID) -> String {
        let rate = float64(device, kAudioDevicePropertyNominalSampleRate) ?? 48_000
        func frames(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32 {
            value(device, selector, scope: scope, as: UInt32.self) ?? 0
        }
        let buffer = frames(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal)
        let inLatency = frames(kAudioDevicePropertyLatency, kAudioObjectPropertyScopeInput)
        let inSafety = frames(kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeInput)
        let outLatency = frames(kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput)
        let outSafety = frames(kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput)
        // The tap adds roughly its input side plus a round trip of one buffer;
        // the output side is paid by any app playing on that device.
        let added = Double(inLatency + inSafety + 2 * buffer) / rate * 1000
        return "rate \(Int(rate)) Hz, buffer \(buffer), in latency \(inLatency) + safety \(inSafety), out latency \(outLatency) + safety \(outSafety) frames → estimated extra delay \(String(format: "%.1f", added)) ms"
    }

    static func tapFormat(_ tap: AudioObjectID) -> String {
        var address = Self.address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr else { return "unreadable" }
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        return "\(Int(format.mSampleRate)) Hz, \(format.mChannelsPerFrame) ch, \(format.mBitsPerChannel)-bit \(isFloat ? "float" : "INTEGER (unsupported)"), \(interleaved ? "interleaved" : "non-interleaved")"
    }

    /// "!obj" for an OSStatus that is a four-character code, else the number.
    static func fourCC(_ status: OSStatus) -> String { fourCC(UInt32(bitPattern: status)) }

    static func fourCC(_ value: UInt32) -> String {
        let bytes = [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return String(Int32(bitPattern: value)) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }
}
#endif
