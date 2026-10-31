// SPDX-License-Identifier: GPL-3.0-or-later

/// System services that several modules share, so each one runs once.
@MainActor
struct ModuleServices {
    /// The audio output list. Now Playing's switcher and Bluetooth's connect
    /// banners share one set of CoreAudio listeners (`acquire`/`release`).
    let audioOutputs: AudioOutputService
    /// Whether the camera and microphone are in use, and by which app. Camera
    /// & Microphone and Calls share one set of listeners.
    let sensors: SensorUsageService
    /// Permission status and requests. Nil only in tests.
    let permissions: PermissionCenter?
    /// Whether the island can show a HUD right now. Nil only in tests.
    let presence: IslandPresence?
    /// The local HTTP API. Modules register routes; the socket exists only while one is registered.
    let api: APIGateway

    init(audioOutputs: AudioOutputService = AudioOutputService(), sensors: SensorUsageService = SensorUsageService(),
         permissions: PermissionCenter? = nil, presence: IslandPresence? = nil, api: APIGateway = APIGateway()) {
        self.api = api
        self.presence = presence
        self.audioOutputs = audioOutputs
        self.sensors = sensors
        self.permissions = permissions
    }
}
