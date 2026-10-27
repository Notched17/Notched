// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The current output device's symbol (AirPods, speakers, a display…) at the
/// end of the controls row, like AirPlay on iPhone. Clicking it lists every
/// output, with a check beside the current one (#16).
///
/// The list is a native menu popped up from the button, so it stays open
/// and usable even if the island collapses behind it.
struct MediaOutputButton: View {
    let outputs: AudioOutputService

    var body: some View {
        let current = outputs.current
        MediaControlButton(symbol: current?.symbol ?? "speaker.wave.2", label: current.map { "Playing on \($0.name)" } ?? "Audio Output",
                           size: 15, tint: .white.opacity(0.85)) {
            OutputMenu.show(outputs)
        }
    }
}

@MainActor
enum OutputMenu {
    static func show(_ outputs: AudioOutputService, cancelAfter: Duration? = nil) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for device in outputs.devices {
            let item = ClosureMenuItem(title: device.name) { outputs.select(device) }
            item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            item.state = device.id == outputs.current?.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Sound Settings…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
        })
        #if DEBUG
        // Debug screenshots: close the menu by itself. Main-actor tasks don't
        // run while a menu tracks, so this is scheduled in the tracking run-loop mode.
        if let cancelAfter {
            menu.perform(#selector(NSMenu.cancelTracking), with: nil, afterDelay: cancelAfter.timeInterval, inModes: [.common])
        }
        #endif
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
