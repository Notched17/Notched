// SPDX-License-Identifier: GPL-3.0-or-later

import CoreAudio

/// An audio output device, as CoreAudio describes it (#16).
struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    enum Transport: Equatable, Sendable {
        case builtIn, bluetooth, airPlay, hdmi, displayPort, usb, thunderbolt, virtual, aggregate, other
    }

    let id: AudioObjectID
    /// Stable across reconnections and restarts (`kAudioDevicePropertyDeviceUID`).
    let uid: String
    let name: String
    let transport: Transport
    /// The built-in output is the headphone jack rather than the speakers.
    let isHeadphonesDataSource: Bool

    /// The SF Symbol for this kind of device.
    var symbol: String {
        let name = self.name.lowercased()
        switch transport {
        case .bluetooth:
            if name.contains("airpods pro") { return "airpods.pro" }
            if name.contains("airpods max") { return "airpods.max" }
            if name.contains("airpods") { return "airpods" }
            if name.contains("beats") { return "beats.headphones" }
            return "headphones"
        case .builtIn:
            return isHeadphonesDataSource ? "headphones" : "laptopcomputer"
        case .hdmi, .displayPort:
            return "tv"
        case .airPlay:
            return "airplayaudio"
        case .usb, .thunderbolt:
            return "hifispeaker"
        case .virtual, .aggregate, .other:
            return "speaker.wave.2"
        }
    }
}
