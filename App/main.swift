// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

// AppKit lifecycle (see docs/adr/0001-appkit-lifecycle.md): the app is a
// menu-bar agent whose windows are all managed by AppKit and hosted SwiftUI.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
