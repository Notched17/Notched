// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit

/// DEBUG-only commands, sent as URLs so scripts can drive the island into a
/// state and screenshot it, e.g. `open -g "notched://debug/expand"`.
///
/// Commands: expand, collapse, pill?on=, outline?on=, reduce-motion?on=,
/// reduce-transparency?on=, increase-contrast?on= (on=default clears an override),
/// settings?pane=modules&priority=1 (the Priority page), fullscreen-fallback?on=, hello-alert, hello-session?on=, settings?pane=,
/// theme?notch=&pill=, onboarding?step=, launch-at-login?on=, appearance?mode=dark|light|system,
/// lab?demo=music|call|agent|download&do=start|end|stale|hide|unhide|primary,
/// lab?banner=charging, lab?run=full, lab?do=end-all, lab?download=0.74,
/// page?id=home|music|call|agent|download (expand to that page),
/// setting?multiple=bubbles|sideBySide&click=open|expand&alerts=0|1&keyline=0|1, close-windows,
/// media?on=0|1&adapter=fail|ok&lifecycle=fast|default&backend=auto|adapterOnly|scriptingOnly&lyrics=0|1&ticker=0|1
/// &visualizer=animated|still|off, page?id=media, settings?module=media, quit,
/// module?id=<module>&on=0|1, crash-at-start?on=0|1 (Hello crashes while starting),
/// sensors?camera=1&apps=Zoom,Voice%20Memos&unnamed=1&callapps=us.zoom.xos&claims=Zoom|0 (a simulated camera and microphone reading),
/// downloads?scan=a.zip:400000:0.4,b.dmg:1200000&finish=a.zip (a simulated look at Downloads),
/// battery?power=battery|charging|notCharging|charged&level=N (a simulated reading)&show=0|80|100,
/// keepawake?preset=30m|1h|2h|on|off, page?activity=<activity id> (e.g. keepawake, timers.stopwatch),
/// page?panel=timers|keepawake (Home with that quick action open), network?name=0|1,
/// hud-key?key=up|down|mute|bup|bdown&shift=1&option=1&repeats=N (posts a volume or brightness key),
/// hang?ms=N&key=down (blocks the main thread and posts a key meanwhile, to show the tap doesn't wait for it).
@MainActor
enum DebugCommands {
    static func handle(_ url: URL, environment: AppEnvironment, windows: WindowCoordinator) {
        guard url.scheme == "notched", url.host == "debug" else { return }
        let command = url.lastPathComponent
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "on" }?.value
        let on = value != "0"
        let override: Bool? = value == "default" ? nil : on
        Log.app.debug("Debug command \(command, privacy: .public) value=\(value ?? "-", privacy: .public)")

        switch command {
        case "expand": environment.islands.expandAll()
        case "collapse": environment.islands.collapseAll()
        case "pill": environment.settings.debugForcePill = on
        case "appearance":
            switch query(url, "mode") {
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            default: NSApp.appearance = nil
            }
        case "launch-at-login": environment.launchAtLogin.setEnabled(on)
            Log.app.info("Launch at login status: \(String(describing: environment.launchAtLogin.status), privacy: .public)")
        case "onboarding": windows.showOnboarding(startAt: query(url, "step").flatMap(OnboardingView.Step.init(name:)) ?? .welcome)
        case "settings":
            if query(url, "priority") == "1" {
                windows.showPriority()
            } else {
                windows.showSettings(query(url, "pane").flatMap(SettingsPane.init(rawValue:)), module: query(url, "module").map { ModuleID($0) })
            }
        case "theme":
            if let theme = query(url, "notch").flatMap(IslandTheme.init(rawValue:)) { environment.settings.notchTheme = theme }
            if let theme = query(url, "pill").flatMap(IslandTheme.init(rawValue:)) { environment.settings.pillTheme = theme }
        case "outline":
            for controller in environment.islands.controllers.values { controller.model.debugOutline = on }
        case "reduce-motion": environment.accessibility.overrideReduceMotion = override
        case "reduce-transparency": environment.accessibility.overrideReduceTransparency = override
        case "increase-contrast": environment.accessibility.overrideIncreaseContrast = override
        case "fullscreen-fallback": environment.fullscreen.forceFallback = on
        case "hello-alert": DebugMenu.hello(environment)?.showAlert()
        case "hello-session":
            if let hello = DebugMenu.hello(environment), hello.isLiveSessionRunning != on { hello.toggleLiveSession() }
        case "lab": lab(url, environment.scenarioLab)
        case "media": media(url, environment)
        case "quit": NSApp.terminate(nil)  // like the status menu's Quit (runs applicationWillTerminate)
        case "close-windows":
            // Closes Settings and onboarding without finishing onboarding (for clean measurements).
            for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) { window.close() }
        case "page":
            if let panel = query(url, "panel") {
                environment.islands.openHomeAction(panel)
                return
            }
            if let activity = query(url, "activity") {
                environment.islands.expandAll(to: .activity(ActivityID(activity)))
                return
            }
            let id = query(url, "id") ?? "home"
            let page: IslandViewModel.ExpandedPage = id == "media" ? .activity(MediaModule.activityID)
                : ScenarioLab.Demo(rawValue: id).map { .activity($0.activityID) } ?? .home
            environment.islands.expandAll(to: page)
        case "module":
            if let id = query(url, "id").map({ ModuleID($0) }) {
                if on { environment.settings.enabledModules.insert(id) } else { environment.settings.enabledModules.remove(id) }
            }
        case "crash-at-start":
            UserDefaults.standard.set(on, forKey: HelloModule.crashAtStartKey)
            if on { environment.settings.enabledModules.insert(HelloModule.descriptor.id) }
        case "battery":
            battery(url, environment)
        case "network":
            if let name = query(url, "name") { environment.settings.network.showWiFiName = name == "1" }
        case "probe": Probes.handle(url)
        case "hud-key":
            DebugHUD.postKey(query(url, "key") ?? "up", shift: query(url, "shift") == "1",
                             option: query(url, "option") == "1", repeats: query(url, "repeats").flatMap(Int.init) ?? 0)
        case "hang": DebugHUD.hang(milliseconds: query(url, "ms").flatMap(Double.init) ?? 1000, key: query(url, "key"))
        case "downloads": downloads(url, environment)
        case "sensors": sensors(url, environment)
        case "keepawake":
            guard let module = environment.modules.module(KeepAwakeModule.descriptor.id) as? KeepAwakeModule else { return }
            switch query(url, "preset") {
            case "30m": module.turnOn(.thirtyMinutes)
            case "1h": module.turnOn(.oneHour)
            case "2h": module.turnOn(.twoHours)
            case "on": module.turnOn(.indefinitely)
            default: module.turnOff()
            }
        case "setting":
            if let mode = query(url, "multiple").flatMap(CompactLayout.Mode.init(rawValue:)) { environment.settings.multipleActivities = mode }
            if let click = query(url, "click").flatMap(ClickBehavior.init(rawValue:)) { environment.settings.clickBehavior = click }
            if let alerts = query(url, "alerts") { environment.settings.alertExpansion = alerts != "0" }
            if let keyline = query(url, "keyline") { environment.settings.keyline = keyline != "0" }
        default: Log.app.error("Unknown debug command \(command, privacy: .public)")
        }
    }

    private static func lab(_ url: URL, _ lab: ScenarioLab) {
        if query(url, "run") == "full" { lab.runFullDemo() }
        if query(url, "banner") == "charging" { lab.showChargingBanner() }
        if let progress = query(url, "download").flatMap(Double.init) { lab.setDownloadProgress(progress) }
        let action = query(url, "do")
        if action == "end-all" { lab.endAll() }
        if let demo = query(url, "demo").flatMap(ScenarioLab.Demo.init(rawValue:)),
           let action = action.flatMap(ScenarioLab.Action.init(rawValue:)) {
            lab.perform(action, on: demo)
        }
    }

    private static func media(_ url: URL, _ environment: AppEnvironment) {
        if let on = query(url, "on") {
            if on == "0" { environment.settings.enabledModules.remove(MediaModule.descriptor.id) }
            else { environment.settings.enabledModules.insert(MediaModule.descriptor.id) }
            environment.modules.reconcile(enabled: environment.settings.enabledModules)
        }
        if let backend = query(url, "backend").flatMap(BackendPreference.init(rawValue:)) { environment.settings.media.backend = backend }
        if let lyrics = query(url, "lyrics") { environment.settings.media.lyricsEnabled = lyrics == "1" }
        if let ticker = query(url, "ticker") { environment.settings.media.lyricsTicker = ticker == "1" }
        if let style = query(url, "visualizer").flatMap(VisualizerStyle.init(rawValue:)) { environment.settings.media.visualizer = style }
        guard let module = environment.modules.module(MediaModule.descriptor.id) as? MediaModule else { return }
        if let adapter = query(url, "adapter") { module.service.simulateAdapterFailure = adapter == "fail" }
        if let seconds = query(url, "outputMenu").flatMap(Double.init), let outputs = module.model.outputs {
            // Popped up from a later turn of the run loop, so this URL handler returns first.
            Task { OutputMenu.show(outputs, cancelAfter: .seconds(seconds)) }
        }
        switch query(url, "lifecycle") {
        case "fast": module.debugLifecycle = MediaLifecycle(staleAfter: 10, endAfter: 30)
        case "default": module.debugLifecycle = nil
        default: break
        }
    }

    private static func downloads(_ url: URL, _ environment: AppEnvironment) {
        guard let module = environment.modules.module(DownloadsModule.descriptor.id) as? DownloadsModule else { return }
        // scan=a.zip:400000:0.4,b.dmg:1200000 are in-progress downloads (name:bytes[:fraction]);
        // finish=a.zip adds a finished file by that name; an empty scan=  ends them all.
        let entries = (query(url, "scan") ?? "").split(separator: ",").compactMap { item -> DownloadsScan.Entry? in
            let parts = item.split(separator: ":").map(String.init)
            guard parts.count >= 2, let bytes = Int64(parts[1]), let partial = DownloadNaming.partial(parts[0] + ".crdownload") else { return nil }
            return DownloadsScan.Entry(key: partial.finalName, name: partial.displayName, partialName: parts[0] + ".crdownload", bytes: bytes,
                                       fraction: parts.count > 2 ? Double(parts[2]) : nil, isUnconfirmed: false)
        }
        var finals: [String: DownloadsScan.Final] = [:]
        if let name = query(url, "finish") { finals[name] = DownloadsScan.Final(size: 1_000, modified: Date()) }
        module.simulate(DownloadsScan(entries: entries, finals: finals))
    }

    private static func sensors(_ url: URL, _ environment: AppEnvironment) {
        let sensorsModule = environment.modules.module(SensorsModule.descriptor.id) as? SensorsModule
        let callsModule = environment.modules.module(CallsModule.descriptor.id) as? CallsModule
        guard sensorsModule != nil || callsModule != nil else { return }
        // Names with a bundle id each, e.g. apps=Zoom,Voice%20Memos; unnamed=1 adds one we can't name;
        // callapps=us.zoom.xos,com.apple.FaceTime adds real call apps.
        var users = (query(url, "apps") ?? "").split(separator: ",").enumerated().map { index, name in
            InputUser(pid: Int32(1000 + index), processBundleID: "debug.\(name)", appBundleID: "debug.\(name)", appName: String(name), attribution: .exact)
        }
        for (index, id) in (query(url, "callapps") ?? "").split(separator: ",").enumerated() {
            users.append(InputUser(pid: Int32(3000 + index), processBundleID: String(id), appBundleID: String(id),
                                   appName: CallApps.known[String(id)], attribution: .exact))
        }
        if query(url, "unnamed") == "1" {
            users.append(InputUser(pid: 2000, processBundleID: "debug.unnamed", appBundleID: nil, appName: nil, attribution: .unknown))
        }
        let reading = SensorSnapshot(cameraRunning: query(url, "camera") == "1", micUsers: users)
        // Both modules share one service, so one of them is enough to feed it.
        if let sensorsModule { sensorsModule.simulate(reading) } else { callsModule?.simulate(reading) }
        if let claims = query(url, "claims") {
            sensorsModule?.simulate(claims: claims == "0" ? CallClaims() : CallClaims(identities: Set(claims.split(separator: ",").map { "debug.\($0)" }), isCallActive: true))
        }
    }

    private static func battery(_ url: URL, _ environment: AppEnvironment) {
        if let until = query(url, "show").flatMap(Int.init) { environment.settings.battery.showWhileChargingUntil = until }
        guard let module = environment.modules.module(BatteryModule.descriptor.id) as? BatteryModule else { return }
        let power: PowerSnapshot.Power = switch query(url, "power") {
        case "charging": .charging
        case "notCharging": .notCharging
        case "charged": .charged
        default: .battery
        }
        let level = query(url, "level").flatMap(Int.init) ?? 50
        module.simulate(PowerSnapshot(level: level, power: power, minutesToFull: power == .charging ? 84 : nil, adapterWatts: 70))
    }

    private static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// The status menu's Debug submenu.
@MainActor
enum DebugMenu {
    static func make(environment: AppEnvironment) -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(title: "Expand Island") { environment.islands.expandAll() })
        menu.addItem(ClosureMenuItem(title: "Collapse Island") { environment.islands.collapseAll() })
        menu.addItem(ClosureMenuItem(title: "Toggle Pill Geometry") { environment.settings.debugForcePill.toggle() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Show Hello Alert") { hello(environment)?.showAlert() })
        menu.addItem(ClosureMenuItem(title: "Toggle Hello Live Session") { hello(environment)?.toggleLiveSession() })
        menu.addItem(.separator())
        menu.addItem(scenarioLab(environment.scenarioLab))
        item.submenu = menu
        return item
    }

    /// Debug ▸ Scenario Lab: demo activities driven through the real coordinator.
    private static func scenarioLab(_ lab: ScenarioLab) -> NSMenuItem {
        let item = NSMenuItem(title: "Scenario Lab", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ClosureMenuItem(title: "Run Full Demo") { lab.runFullDemo() })
        menu.addItem(ClosureMenuItem(title: "End All") { lab.endAll() })
        menu.addItem(.separator())
        for demo in ScenarioLab.Demo.allCases {
            let demoItem = NSMenuItem(title: demo.title, action: nil, keyEquivalent: "")
            let demoMenu = NSMenu()
            demoMenu.autoenablesItems = false
            for action in ScenarioLab.Action.allCases {
                demoMenu.addItem(ClosureMenuItem(title: action.title) { lab.perform(action, on: demo) })
            }
            demoItem.submenu = demoMenu
            menu.addItem(demoItem)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Show “Charging 80%” Banner") { lab.showChargingBanner() })
        item.submenu = menu
        return item
    }

    /// The Hello demo module, turning it on first if needed.
    static func hello(_ environment: AppEnvironment) -> HelloModule? {
        environment.settings.enabledModules.insert(HelloModule.descriptor.id)
        environment.modules.reconcile(enabled: environment.settings.enabledModules)
        return environment.modules.module(HelloModule.descriptor.id) as? HelloModule
    }
}
#endif
