// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spike S1 (M3b): who is using the camera and microphone on macOS 27.2, as the
// system reports it. DEBUG only; removed once ADR-0017 is written.

#if DEBUG
import Observation

@MainActor
enum SensorsProbe {
    private static var service: SensorUsageService?

    static func setRunning(_ on: Bool) {
        if let service {
            service.setDebugSink(nil)
            service.release()
            self.service = nil
            probeLog.notice("sensors: stopped")
        }
        guard on else { return }
        let service = SensorUsageService()
        self.service = service
        service.acquire()
        service.setDebugSink { report in
            for line in report.split(separator: "\n") { probeLog.notice("sensors: \(String(line), privacy: .public)") }
            probeLog.notice("sensors: ---")
        }
        watch(service)
        probeLog.notice("sensors: watching; ResponsibleProcess available=\(ResponsibleProcess.isAvailable)")
    }

    /// Logs what the app itself would show.
    private static func watch(_ service: SensorUsageService) {
        withObservationTracking {
            let snapshot = service.snapshot
            let users = snapshot.micUsers.map { "\($0.appName ?? "An app")[\($0.attribution)] pid \($0.pid) \($0.processBundleID ?? "-")" }
            probeLog.notice("sensors: SNAPSHOT camera=\(snapshot.cameraRunning) mic=\(snapshot.micInUse) unattributed=\(snapshot.micRunningUnattributed) users=\(users.joined(separator: "; "), privacy: .public)")
        } onChange: {
            Task { @MainActor in if let service = SensorsProbe.service { watch(service) } }
        }
    }
}
#endif
