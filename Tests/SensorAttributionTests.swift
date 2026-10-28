// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Which app is using the microphone? The island only names an app it can
/// prove, so every route that can't prove it must end in "An app".
@Suite("SensorAttribution")
struct SensorAttributionTests {
    private let zoom = RunningAppInfo(pid: 100, bundleID: "us.zoom.xos", name: "zoom.us", bundlePath: "/Applications/zoom.us.app")
    private let safari = RunningAppInfo(pid: 200, bundleID: "com.apple.Safari", name: "Safari", bundlePath: "/Applications/Safari.app")
    private let facetime = RunningAppInfo(pid: 300, bundleID: "com.apple.FaceTime", name: "FaceTime", bundlePath: "/System/Applications/FaceTime.app")

    private func process(_ pid: Int32, bundle: String? = nil, path: String? = nil, input: Bool = true) -> RawInputProcess {
        RawInputProcess(pid: pid, bundleID: bundle, executablePath: path, isRunningInput: input)
    }

    @Test("A running app using the microphone is the exact owner")
    func exactApp() {
        let user = SensorAttribution.attribute(process(100, bundle: "us.zoom.xos"), apps: [zoom, safari], responsiblePID: nil)
        #expect(user.attribution == .exact)
        #expect(user.appName == "zoom.us")
        #expect(user.appBundleID == "us.zoom.xos")
    }

    @Test("A helper nested inside an app bundle belongs to the outermost app")
    func nestedHelper() {
        let helper = process(101, path: "/Applications/zoom.us.app/Contents/Frameworks/zoom.us Helper.app/Contents/MacOS/zoom.us Helper")
        let user = SensorAttribution.attribute(helper, apps: [zoom, safari], responsiblePID: nil)
        #expect(user.attribution == .containingApp)
        #expect(user.appName == "zoom.us")
        #expect(user.identity == "us.zoom.xos")
    }

    @Test("A helper inside an app that isn't running is not claimed")
    func helperOfAppNotRunning() {
        let helper = process(102, path: "/Applications/Discord.app/Contents/Frameworks/Discord Helper.app/Contents/MacOS/Discord Helper")
        let user = SensorAttribution.attribute(helper, apps: [zoom], responsiblePID: nil)
        #expect(user.attribution == .unknown)
        #expect(user.appName == nil)
    }

    @Test("WebKit's GPU process, outside any app bundle, is Safari's only if macOS says Safari is responsible")
    func webKitGPUProcess() {
        let gpu = process(250, bundle: "com.apple.WebKit.GPU", path: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU")
        let withoutLookup = SensorAttribution.attribute(gpu, apps: [safari], responsiblePID: nil)
        #expect(withoutLookup.attribution == .unknown)
        #expect(withoutLookup.appName == nil)
        let withLookup = SensorAttribution.attribute(gpu, apps: [safari], responsiblePID: 200)
        #expect(withLookup.attribution == .responsible)
        #expect(withLookup.appName == "Safari")
    }

    @Test("A daemon that is responsible for itself, like FaceTime's call daemon, is not guessed to be FaceTime")
    func selfResponsibleDaemon() {
        let daemon = process(301, bundle: "com.apple.avconferenced", path: "/usr/libexec/avconferenced")
        let user = SensorAttribution.attribute(daemon, apps: [facetime], responsiblePID: 301)
        #expect(user.attribution == .unknown)
        #expect(user.appName == nil)
        #expect(user.processBundleID == "com.apple.avconferenced")
        #expect(user.identity == "com.apple.avconferenced")
    }

    @Test("A responsible pid that isn't a running app is not an owner (launchd is pid 1)")
    func responsibleNotAnApp() {
        #expect(SensorAttribution.attribute(process(400), apps: [safari], responsiblePID: 1).attribution == .unknown)
        #expect(SensorAttribution.attribute(process(400), apps: [safari], responsiblePID: 999).attribution == .unknown)
    }

    @Test("Without any bundle ID the identity falls back to the pid")
    func identityFallsBackToPid() {
        #expect(SensorAttribution.attribute(process(500), apps: [], responsiblePID: nil).identity == "pid:500")
    }

    @Test("Finding the outermost app in a path")
    func outermostApp() {
        #expect(SensorAttribution.outermostAppPath("/Applications/A.app/Contents/MacOS/A") == "/Applications/A.app")
        #expect(SensorAttribution.outermostAppPath("/Applications/A.app/Contents/Helpers/B.app/Contents/MacOS/B") == "/Applications/A.app")
        #expect(SensorAttribution.outermostAppPath("/usr/libexec/avconferenced") == nil)
        #expect(SensorAttribution.outermostAppPath("/Applications/Chrome.app") == "/Applications/Chrome.app")
    }

    @Test("Users are only processes with input running; Notched and ignored daemons are left out; the list is stable")
    func usersFilter() {
        let processes = [
            process(300, bundle: "com.apple.FaceTime"),
            process(100, bundle: "us.zoom.xos"),
            process(900, bundle: "me.rkck.Notched"),
            process(901, bundle: "com.apple.corespeechd"),
            process(100, bundle: "us.zoom.xos", input: false),
            process(777, bundle: "com.example.idle", input: false),
        ]
        let apps = [zoom, facetime]
        let users = SensorAttribution.users(from: processes, ownPID: 900, ignoredBundleIDs: ["com.apple.corespeechd"]) {
            SensorAttribution.attribute($0, apps: apps, responsiblePID: nil)
        }
        #expect(users.map(\.pid) == [100, 300])
    }

    @Test("The cache remembers an owner until the process is gone, and a reused pid is looked up again")
    func cacheKeysOnStartTime() {
        var cache = AttributionCache()
        var lookups = 0
        func resolve(_ key: AttributionCache.Key, name: String) -> InputUser {
            cache.user(for: key) {
                lookups += 1
                return InputUser(pid: key.pid, processBundleID: nil, appBundleID: name, appName: name, attribution: .exact)
            }
        }
        let first = AttributionCache.Key(pid: 100, startTime: 1)
        #expect(resolve(first, name: "Zoom").appName == "Zoom")
        #expect(resolve(first, name: "Zoom").appName == "Zoom")
        #expect(lookups == 1)
        // The same pid, started later, is a different process.
        let reused = AttributionCache.Key(pid: 100, startTime: 2)
        #expect(resolve(reused, name: "Discord").appName == "Discord")
        #expect(lookups == 2)
        cache.prune(keeping: [reused])
        #expect(cache.count == 1)
        cache.removeAll()
        #expect(cache.count == 0)
    }

    @Test("A snapshot's microphone is in use for an attributed user or an unattributed running device")
    func snapshotMicInUse() {
        #expect(!SensorSnapshot.idle.micInUse)
        var snapshot = SensorSnapshot()
        snapshot.micRunningUnattributed = true
        #expect(snapshot.micInUse)
        snapshot = SensorSnapshot(micUsers: [InputUser(pid: 1, processBundleID: nil, appBundleID: nil, appName: nil, attribution: .unknown)])
        #expect(snapshot.micInUse)
        #expect(!snapshot.cameraRunning)
    }
}
