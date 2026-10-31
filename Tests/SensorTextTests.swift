// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("SensorText")
struct SensorTextTests {
    private func model(camera: Bool = false, mic: Bool = false, apps: [String] = [], unnamed: Bool = false) -> SensorIndicatorReducer.Model {
        .init(camera: camera, mic: mic, micApps: apps, micHasUnnamedApp: unnamed)
    }

    @Test("The title says what is in use")
    func titles() {
        #expect(SensorText.title(model(mic: true)) == "Microphone in Use")
        #expect(SensorText.title(model(camera: true)) == "Camera in Use")
        #expect(SensorText.title(model(camera: true, mic: true)) == "Camera & Microphone in Use")
    }

    @Test("Microphone owners: proven names are listed, anything unproven is 'an app'")
    func microphoneDetail() {
        #expect(SensorText.micDetail(model(mic: true)) == "An app")
        #expect(SensorText.micDetail(model(mic: true, unnamed: true)) == "An app")
        #expect(SensorText.micDetail(model(mic: true, apps: ["Zoom"])) == "Zoom")
        #expect(SensorText.micDetail(model(mic: true, apps: ["Voice Memos", "Zoom"])) == "Voice Memos and Zoom")
        #expect(SensorText.micDetail(model(mic: true, apps: ["A", "B", "C"])) == "A, B and C")
        #expect(SensorText.micDetail(model(mic: true, apps: ["Zoom"], unnamed: true)) == "Zoom and another app")
        #expect(SensorText.micDetail(model(mic: true, apps: ["Zoom", "Safari"], unnamed: true)) == "Zoom, Safari and another app")
    }

    @Test("The camera's owner is never named")
    func cameraIsNeverNamed() {
        #expect(SensorText.cameraDetail == "An app")
        #expect(SensorText.accessibilityLabel(model(camera: true)) == "Camera in use by an app")
    }

    @Test("VoiceOver hears each sensor in use")
    func accessibility() {
        #expect(SensorText.accessibilityLabel(model(camera: true, mic: true, apps: ["Zoom"]))
                == "Microphone in use by Zoom. Camera in use by an app")
        #expect(SensorText.accessibilityLabel(model(mic: true, apps: ["Zoom"])) == "Microphone in use by Zoom")
    }
}
