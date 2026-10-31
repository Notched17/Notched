// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio
import CoreMediaIO
import Darwin
import Foundation
import os

/// Watches the camera and microphone without polling, on its own queue: the
/// audio system can stall for a second while a Bluetooth device switches, so
/// nothing here ever runs on the main thread.
///
/// - **Camera:** CoreMediaIO's device list, and each video device's
///   "is running somewhere".
/// - **Microphone:** CoreAudio's device list, and each input device's
///   "is running somewhere". That only *triggers* a look: a headset that is
///   playing audio reports "running" too. The truth is a process other than
///   Notched with an input stream running (`kAudioProcessPropertyIsRunningInput`),
///   read only while some input device runs. The process-level listeners exist
///   only for that time, so an idle Mac costs the device listeners alone.
///
/// Every listener is counted (`listenerCount`) so tests can check that none
/// outlives `stop()`.
///
/// All state below `queue` is touched only on that queue, which is why the
/// class is `@unchecked Sendable`.
final class SensorMonitor: @unchecked Sendable {
    private struct AudioListener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private struct VideoListener {
        let object: CMIOObjectID
        var address: CMIOObjectPropertyAddress
        let block: CMIOObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "me.rkck.Notched.sensors", qos: .utility)
    private let log = Log.module("sensors")
    private let ownPID = getpid()
    private let onChange: @Sendable (SensorSnapshot) -> Void
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    // Confined to `queue`.
    private var isRunning = false
    private var apps: [RunningAppInfo] = []
    private var ignoredBundleIDs: Set<String> = []
    private var systemAudioListener: AudioListener?
    private var systemVideoListener: VideoListener?
    private var deviceListeners: [AudioObjectID: AudioListener] = [:]
    private var videoListeners: [CMIOObjectID: VideoListener] = [:]
    private var processListListener: AudioListener?
    private var processListeners: [AudioObjectID: AudioListener] = [:]
    private var pendingRescan: DispatchWorkItem?
    private var cache = AttributionCache()
    private var published: SensorSnapshot?
    private var loggedFailures: Set<String> = []
    #if DEBUG
    private var debugSink: (@Sendable (String) -> Void)?
    #endif

    /// - Parameter onChange: called on the main queue, in order, only when the snapshot changes.
    init(onChange: @escaping @Sendable (SensorSnapshot) -> Void) {
        self.onChange = onChange
    }

    /// Audio and video listeners installed now; zero once stopped and flushed.
    var listenerCount: Int { counter.withLock { $0 } }

    func start(apps: [RunningAppInfo], ignoredBundleIDs: Set<String>) {
        queue.async { self.begin(apps: apps, ignoredBundleIDs: ignoredBundleIDs) }
    }

    func stop() {
        queue.async { self.end() }
    }

    /// Looks again and publishes the result even if it hasn't changed, e.g.
    /// after the Mac wakes, when what we knew may be stale.
    func refresh() {
        queue.async {
            self.published = nil
            self.scheduleRescan()
        }
    }

    /// The running apps changed: owners may now be provable.
    func updateApps(_ apps: [RunningAppInfo]) {
        queue.async {
            self.apps = apps
            self.cache.removeAll()
            if self.isRunning, self.published?.micInUse == true { self.scheduleRescan() }
        }
    }

    #if DEBUG
    /// Spike S1: gets a full report of what the system says after every look.
    func setDebugSink(_ sink: (@Sendable (String) -> Void)?) {
        queue.async {
            self.debugSink = sink
            if sink != nil { self.scheduleRescan() }
        }
    }

    /// Everything the system reports, before any filtering or attribution.
    private func debugReport() -> String {
        var lines: [String] = []
        for device in Self.audioInputDeviceIDs() ?? [] {
            let name = Self.audioString(device, kAudioObjectPropertyName) ?? "?"
            lines.append("input device \"\(name)\" id=\(device) running=\(Self.audioDeviceIsRunning(device))")
        }
        for device in Self.videoDeviceIDs() ?? [] {
            lines.append("camera id=\(device) running=\(Self.videoDeviceIsRunning(device))")
        }
        for object in Self.audioIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) ?? [] {
            let input = Self.audioValue(object, kAudioProcessPropertyIsRunningInput, as: UInt32.self) ?? 9
            let output = Self.audioValue(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 9
            guard input != 0 || output != 0 else { continue }
            let pid = Self.audioValue(object, kAudioProcessPropertyPID, as: Int32.self) ?? -1
            let bundle = Self.audioString(object, kAudioProcessPropertyBundleID) ?? "-"
            let path = Self.executablePath(of: pid) ?? "-"
            let responsible = ResponsibleProcess.pid(responsibleFor: pid)
            let responsiblePath = responsible.flatMap { Self.executablePath(of: $0) } ?? "-"
            lines.append("process pid=\(pid) input=\(input) output=\(output) bundle=\(bundle) path=\(path) responsible=\(responsible.map(String.init) ?? "-") \(responsiblePath)")
        }
        return lines.isEmpty ? "(nothing running)" : lines.joined(separator: "\n")
    }
    #endif

    /// Waits for everything queued so far (tests, and a clean quit).
    func flush() {
        queue.sync {}
    }

    // MARK: Lifecycle (on the queue)

    private func begin(apps: [RunningAppInfo], ignoredBundleIDs: Set<String>) {
        guard !isRunning else { return }
        isRunning = true
        self.apps = apps
        self.ignoredBundleIDs = ignoredBundleIDs
        systemAudioListener = addAudio(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        systemVideoListener = addVideo(CMIOObjectID(kCMIOObjectSystemObject), CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        rescan()
    }

    private func end() {
        guard isRunning else { return }
        isRunning = false
        pendingRescan?.cancel()
        pendingRescan = nil
        if let systemAudioListener { remove(systemAudioListener) }
        if let systemVideoListener { remove(systemVideoListener) }
        systemAudioListener = nil
        systemVideoListener = nil
        for listener in deviceListeners.values { remove(listener) }
        deviceListeners = [:]
        for listener in videoListeners.values { remove(listener) }
        videoListeners = [:]
        removeProcessListeners()
        cache.removeAll()
        published = nil
    }

    /// Listener callbacks arrive in bursts (a device list change fires
    /// several); one look after a short pause covers them all.
    private func scheduleRescan() {
        guard isRunning, pendingRescan == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingRescan = nil
            self?.rescan()
        }
        pendingRescan = item
        queue.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    // MARK: Looking

    private func rescan() {
        guard isRunning else { return }
        var snapshot = SensorSnapshot()

        let cameras = Self.videoDeviceIDs()
        if cameras == nil { logOnce("camera", "The camera list couldn't be read; the camera indicator is off") }
        let videoDevices = cameras ?? []
        syncVideoListeners(videoDevices)
        snapshot.cameraRunning = videoDevices.contains { Self.videoDeviceIsRunning($0) }

        let inputs = Self.audioInputDeviceIDs()
        if inputs == nil { logOnce("microphone", "The input device list couldn't be read; the microphone indicator is off") }
        let inputDevices = inputs ?? []
        syncDeviceListeners(inputDevices)
        if inputDevices.contains(where: { Self.audioDeviceIsRunning($0) }) {
            watchProcessList()
            if let processes = readInputProcesses() {
                snapshot.micUsers = users(from: processes)
            } else {
                logOnce("processes", "The audio process list couldn't be read; the microphone shows as in use by an app")
                snapshot.micRunningUnattributed = true
            }
        } else {
            removeProcessListeners()
        }
        publish(snapshot)
        #if DEBUG
        debugSink?(debugReport())
        #endif
    }

    private func publish(_ snapshot: SensorSnapshot) {
        guard snapshot != published else { return }
        published = snapshot
        let onChange = onChange
        DispatchQueue.main.async { onChange(snapshot) }
    }

    private func users(from processes: [(raw: RawInputProcess, key: AttributionCache.Key)]) -> [InputUser] {
        let apps = apps
        var keysByPID: [Int32: AttributionCache.Key] = [:]
        for entry in processes { keysByPID[entry.raw.pid] = entry.key }
        let users = SensorAttribution.users(from: processes.map(\.raw), ownPID: ownPID, ignoredBundleIDs: ignoredBundleIDs) { raw in
            guard let key = keysByPID[raw.pid] else {
                return SensorAttribution.attribute(raw, apps: apps, responsiblePID: nil)
            }
            return cache.user(for: key) {
                SensorAttribution.attribute(raw, apps: apps, responsiblePID: ResponsibleProcess.pid(responsibleFor: raw.pid))
            }
        }
        cache.prune(keeping: Set(processes.map(\.key)))
        return users
    }

    // MARK: Listeners (on the queue)

    private func syncVideoListeners(_ devices: [CMIOObjectID]) {
        for (id, listener) in videoListeners where !devices.contains(id) {
            remove(listener)
            videoListeners[id] = nil
        }
        for id in devices where videoListeners[id] == nil {
            videoListeners[id] = addVideo(id, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        }
    }

    private func syncDeviceListeners(_ devices: [AudioObjectID]) {
        for (id, listener) in deviceListeners where !devices.contains(id) {
            remove(listener)
            deviceListeners[id] = nil
        }
        for id in devices where deviceListeners[id] == nil {
            deviceListeners[id] = addAudio(id, kAudioDevicePropertyDeviceIsRunningSomewhere)
        }
    }

    /// Listening for processes starting and stopping audio is only worth it
    /// while an input device is running.
    private func watchProcessList() {
        guard processListListener == nil else { return }
        processListListener = addAudio(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    private func removeProcessListeners() {
        if let processListListener { remove(processListListener) }
        processListListener = nil
        for listener in processListeners.values { remove(listener) }
        processListeners = [:]
    }

    private func syncProcessListeners(_ processes: [AudioObjectID]) {
        for (id, listener) in processListeners where !processes.contains(id) {
            remove(listener)
            processListeners[id] = nil
        }
        for id in processes where processListeners[id] == nil {
            processListeners[id] = addAudio(id, kAudioProcessPropertyIsRunningInput)
        }
    }

    private func addAudio(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioListener? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRescan() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        counter.withLock { $0 += 1 }
        return AudioListener(object: object, address: address, block: block)
    }

    private func addVideo(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> VideoListener? {
        var address = CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRescan() }
        guard CMIOObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        counter.withLock { $0 += 1 }
        return VideoListener(object: object, address: address, block: block)
    }

    private func remove(_ listener: AudioListener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, queue, listener.block)
        counter.withLock { $0 -= 1 }
    }

    private func remove(_ listener: VideoListener) {
        var address = listener.address
        CMIOObjectRemovePropertyListenerBlock(listener.object, &address, queue, listener.block)
        counter.withLock { $0 -= 1 }
    }

    private func logOnce(_ key: String, _ message: String) {
        guard loggedFailures.insert(key).inserted else { return }
        log.error("\(message, privacy: .public)")
    }

    // MARK: CoreAudio and CoreMediaIO reads

    private func readInputProcesses() -> [(raw: RawInputProcess, key: AttributionCache.Key)]? {
        guard let objects = Self.audioIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) else { return nil }
        syncProcessListeners(objects)
        var running: [(raw: RawInputProcess, key: AttributionCache.Key)] = []
        for object in objects {
            guard Self.audioValue(object, kAudioProcessPropertyIsRunningInput, as: UInt32.self) == 1,
                  let pid = Self.audioValue(object, kAudioProcessPropertyPID, as: Int32.self) else { continue }
            let raw = RawInputProcess(pid: pid, bundleID: Self.audioString(object, kAudioProcessPropertyBundleID),
                                      executablePath: Self.executablePath(of: pid), isRunningInput: true)
            running.append((raw, AttributionCache.Key(pid: pid, startTime: Self.startTime(of: pid))))
        }
        return running
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID]? {
        var address = audioAddress(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids
    }

    private static func audioValue<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                                         as _: T.Type) -> T? {
        var address = audioAddress(selector, scope)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func audioString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = audioAddress(selector, kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// Devices with at least one input stream.
    private static func audioInputDeviceIDs() -> [AudioObjectID]? {
        guard let devices = audioIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) else { return nil }
        return devices.filter { !(audioIDs($0, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput) ?? []).isEmpty }
    }

    private static func audioDeviceIsRunning(_ device: AudioObjectID) -> Bool {
        audioValue(device, kAudioDevicePropertyDeviceIsRunningSomewhere, as: UInt32.self) == 1
    }

    private static func videoAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func videoDeviceIDs() -> [CMIOObjectID]? {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = videoAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return nil }
        return ids
    }

    private static func videoDeviceIsRunning(_ device: CMIOObjectID) -> Bool {
        var address = videoAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr else { return false }
        return value != 0
    }

    // MARK: Processes

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// When the process started, so a reused pid isn't mistaken for the old one.
    private static func startTime(of pid: Int32) -> UInt64 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return UInt64(info.pbi_start_tvsec) &* 1_000_000 &+ UInt64(info.pbi_start_tvusec)
    }
}
