// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the island says about the camera and microphone. Pure, so the wording
/// rules (only proven names; the camera's owner is never claimed) are tested.
enum SensorText {
    static let cameraDetail = "An app"

    static func title(_ model: SensorIndicatorReducer.Model) -> String {
        switch (model.camera, model.mic) {
        case (true, true): "Camera & Microphone in Use"
        case (true, false): "Camera in Use"
        default: "Microphone in Use"
        }
    }

    /// "Zoom", "Zoom and Voice Memos", "Zoom, Voice Memos and another app", or "An app".
    static func micDetail(_ model: SensorIndicatorReducer.Model) -> String {
        var parts = model.micApps
        if model.micHasUnnamedApp { parts.append(parts.isEmpty ? "An app" : "another app") }
        switch parts.count {
        case 0: return "An app"
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    static func accessibilityLabel(_ model: SensorIndicatorReducer.Model) -> String {
        var sentences: [String] = []
        if model.mic { sentences.append("Microphone in use by \(micDetail(model))") }
        if model.camera { sentences.append("Camera in use by \(cameraDetail.lowercased())") }
        return sentences.joined(separator: ". ")
    }
}
