// SPDX-License-Identifier: GPL-3.0-or-later

/// System services that several modules share, so each one runs once.
@MainActor
struct ModuleServices {
    /// The audio output list. Now Playing's switcher and Bluetooth's connect
    /// banners share one set of CoreAudio listeners (`acquire`/`release`).
    let audioOutputs: AudioOutputService
    /// Permission status and requests. Nil only in tests.
    let permissions: PermissionCenter?

    init(audioOutputs: AudioOutputService = AudioOutputService(), permissions: PermissionCenter? = nil) {
        self.audioOutputs = audioOutputs
        self.permissions = permissions
    }
}
