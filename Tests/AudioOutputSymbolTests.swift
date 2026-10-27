// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// The SF Symbol shown for the current output device (#16).
@Suite("AudioOutputSymbol")
struct AudioOutputSymbolTests {
    private func device(_ name: String, _ transport: AudioOutputDevice.Transport, headphones: Bool = false) -> AudioOutputDevice {
        AudioOutputDevice(id: 1, uid: "uid", name: name, transport: transport, isHeadphonesDataSource: headphones)
    }

    @Test func airPodsPro() {
        #expect(device("Charlie’s AirPods Pro", .bluetooth).symbol == "airpods.pro")
    }

    @Test func airPodsMax() {
        #expect(device("AirPods Max", .bluetooth).symbol == "airpods.max")
    }

    @Test func airPods() {
        #expect(device("Charlie's AirPods", .bluetooth).symbol == "airpods")
    }

    @Test func beats() {
        #expect(device("Beats Studio Pro", .bluetooth).symbol == "beats.headphones")
    }

    @Test func otherBluetooth() {
        #expect(device("WH-1000XM5", .bluetooth).symbol == "headphones")
    }

    @Test func builtInSpeakers() {
        #expect(device("MacBook Pro Speakers", .builtIn).symbol == "laptopcomputer")
    }

    @Test func builtInHeadphoneJack() {
        #expect(device("External Headphones", .builtIn, headphones: true).symbol == "headphones")
    }

    @Test func displays() {
        #expect(device("LG UltraFine", .displayPort).symbol == "tv")
        #expect(device("TV", .hdmi).symbol == "tv")
    }

    @Test func airPlay() {
        #expect(device("Living Room", .airPlay).symbol == "airplayaudio")
    }

    @Test func usb() {
        #expect(device("Scarlett 2i2", .usb).symbol == "hifispeaker")
    }

    @Test func fallback() {
        #expect(device("BlackHole 2ch", .virtual).symbol == "speaker.wave.2")
    }
}
