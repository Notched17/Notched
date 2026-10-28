// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var windows: WindowCoordinator?
    private var statusItemController: StatusItemController?
    private var terminationSignal: (any DispatchSourceSignal)?

    /// True when the app is only hosting the unit-test bundle. Tests exercise
    /// pure logic, so the island, status item and windows are never created.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Log.app.info("Notched launched")
        quitGracefullyOnSIGTERM()
        let environment = AppEnvironment()
        let windows = WindowCoordinator(environment: environment)
        self.environment = environment
        self.windows = windows

        NSApp.mainMenu = MainMenu.make { windows.showSettings() }
        environment.islands.actions = IslandActions(
            openSettings: { windows.showSettings() },
            pauseIsland: { environment.settings.isPaused = true }
        )
        statusItemController = StatusItemController(environment: environment, windows: windows)
        environment.start()
        if !environment.settings.hasCompletedOnboarding {
            windows.showOnboarding()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let environment, let windows else { return }
        for url in urls { URLRouter.handle(url, environment: environment, windows: windows) }
    }

    /// Opening the app again (e.g. from Finder or Spotlight) shows Settings,
    /// since a menu-bar app has no other window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showSettings()
        return false
    }

    /// `kill`/`pkill` (and scripts/install.sh) send SIGTERM, which would end
    /// the process without `applicationWillTerminate`. Treat it as Quit.
    private func quitGracefullyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        terminationSignal = source
    }

    /// Stops every module, so nothing they started (the media adapter's
    /// perl process, a keep-awake assertion) outlives the app, and records
    /// a clean quit for crash-loop protection.
    func applicationWillTerminate(_ notification: Notification) {
        environment?.modules.shutDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
