// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItemController: StatusItemController?

    /// True when the app is only hosting the unit-test bundle. Tests exercise
    /// pure logic, so the island, status item and windows are never created.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Log.app.info("DynamicNotch launched")
        let environment = AppEnvironment()
        self.environment = environment
        statusItemController = StatusItemController()
        environment.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        #if DEBUG
        guard let environment else { return }
        for url in urls { DebugCommands.handle(url, environment: environment) }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
