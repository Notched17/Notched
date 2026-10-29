// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Settings ▸ Modules ▸ Calls.
struct CallsSettingsPane: View {
    @Bindable var settings: CallsSettings

    private var browsers: [(id: String, name: String)] {
        CallApps.browsers.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(Set(CallApps.known.values)).sorted(), id: \.self) { name in
                    Label(name, systemImage: "phone.fill")
                }
            } header: {
                Text("Call apps")
            } footer: {
                Text("Notched shows \"In a call\" and how long it has lasted while one of these is using your microphone. It can't see who's calling or when it rings, and it can't mute or hang up for you.")
            }

            Section {
                ForEach(browsers, id: \.id) { browser in
                    Toggle(browser.name, isOn: Binding(
                        get: { settings.binding(for: browser.id) },
                        set: { settings.set(browser.id, enabled: $0) }
                    ))
                }
            } header: {
                Text("Calls in a browser")
            } footer: {
                Text("Turn a browser on to count its microphone use as a call, for Google Meet and similar. Off by default, since a browser also uses the microphone for dictation and sound tests.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calls")
    }
}
