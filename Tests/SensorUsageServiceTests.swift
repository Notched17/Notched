// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The listeners are real CoreAudio and CoreMediaIO ones, so these also prove
/// the monitor starts on this Mac. A disabled module costs nothing: no
/// listener may outlive the last holder.
@Suite("SensorUsageService")
@MainActor
struct SensorUsageServiceTests {
    @Test("Starting and stopping five times leaves no listener behind")
    func startStopNeverLeaks() {
        let service = SensorUsageService()
        #expect(service.listenerCount == 0)
        for _ in 0..<5 {
            service.acquire()
            service.flush()
            #expect(service.listenerCount > 0)
            service.release()
            service.flush()
            #expect(service.listenerCount == 0)
        }
    }

    @Test("Two holders share one set of listeners, and the last release removes them")
    func holdersShareListeners() {
        let service = SensorUsageService()
        service.acquire()
        service.flush()
        let installed = service.listenerCount
        service.acquire()
        service.flush()
        #expect(service.listenerCount == installed)
        service.release()
        service.flush()
        #expect(service.listenerCount == installed)
        service.release()
        service.flush()
        #expect(service.listenerCount == 0)
    }

    @Test("Releasing without acquiring does nothing")
    func unbalancedRelease() {
        let service = SensorUsageService()
        service.release()
        service.flush()
        #expect(service.listenerCount == 0)
        service.acquire()
        service.flush()
        #expect(service.listenerCount > 0)
        service.release()
        service.flush()
    }

    @Test("Call claims are cleared when the last holder lets go, so a stopped Calls module can't hide the microphone")
    func claimsClearedOnRelease() {
        let service = SensorUsageService()
        service.acquire()
        service.setCallClaims(CallClaims(identities: ["us.zoom.xos"], isCallActive: true))
        #expect(service.callClaims.identities == ["us.zoom.xos"])
        #expect(service.callClaims.isCallActive)
        service.release()
        service.flush()
        #expect(service.callClaims == CallClaims())
    }
}
