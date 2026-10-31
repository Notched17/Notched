// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The click that a volume key makes, as on macOS: the "Play feedback when
/// volume is changed" preference decides, Shift flips it for that press, and
/// the fine step (Shift+Option) is always silent.
enum HUDFeedback {
    static func shouldPlay(preference: Bool, modifiers: MediaKeyEvent.Modifiers) -> Bool {
        if modifiers.contains(.shift), modifiers.contains(.option) { return false }
        return modifiers.contains(.shift) ? !preference : preference
    }

    /// System Settings ▸ Sound ▸ "Play feedback when volume is changed" (off by default).
    @MainActor static var systemPreference: Bool {
        UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback")
    }

    private static let soundPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
    @MainActor private static var sound: NSSound?
    @MainActor private static var missingLogged = false

    /// The system's own volume click. If the file is ever gone, there's no click.
    @MainActor static func play() {
        guard let click = NSSound(contentsOfFile: soundPath, byReference: true) else {
            if !missingLogged {
                missingLogged = true
                Log.module("hud").notice("The volume feedback sound isn't available")
            }
            return
        }
        sound = click
        click.play()
    }
}
