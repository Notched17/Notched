// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Settings ▸ Modules ▸ Activity API: the server's state, the port, and the
/// clients that may use it.
struct ActivityAPISettingsPane: View {
    let api: APIGateway
    let registry: ModuleRegistry
    @State private var showingNewClient = false
    @State private var revoking: APIClient?
    @State private var portText = ""

    private var isOn: Bool { registry.isRunning(ActivityAPIModule.descriptor.id) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { statusText }
                LabeledContent("Port") {
                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(applyPort)
                }
                Toggle("Allow banners from notched:// links", isOn: Bindable(api.settings).allowLinkBanners)
            } footer: {
                Text("The API listens on 127.0.0.1 only, and only while this module is on. Anything that uses it needs a token you create below.")
            }

            Section("Clients") {
                if api.clients.isEmpty {
                    Text("No clients yet. Create one for each script or app, and revoke it when you're done with it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(api.clients) { client in
                    ClientRow(client: client) { revoking = client }
                }
                Button("New Client…") { showingNewClient = true }
            }

            Section {
                Button("Copy Example curl") { copyExample() }
            } footer: {
                Text("Replace $NOTCHED_TOKEN with a client's token. Tokens are shown once, when you create them.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Activity API")
        .onAppear { portText = api.settings.port == 0 ? "" : String(api.settings.port) }
        .sheet(isPresented: $showingNewClient) { NewClientSheet(api: api) }
        .confirmationDialog("Revoke \(revoking?.name ?? "client")?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                            titleVisibility: .visible) {
            Button("Revoke", role: .destructive) {
                if let client = revoking { api.revoke(clientID: client.id) }
                revoking = nil
            }
        } message: {
            Text("Its token stops working at once and its activities leave the island.")
        }
    }

    @ViewBuilder private var statusText: some View {
        if !isOn {
            Text("Off").foregroundStyle(.secondary)
        } else {
            switch api.serverStatus {
            case .listening(let port): Text("Listening on 127.0.0.1:\(String(port))").foregroundStyle(.green)
            case .failed(let message): Text(message).foregroundStyle(.red)
            case .stopped: Text("Starting…").foregroundStyle(.secondary)
            }
        }
    }

    private func applyPort() {
        guard let port = Int(portText), (1024...65535).contains(port) else {
            portText = api.settings.port == 0 ? "" : String(api.settings.port)
            return
        }
        api.settings.port = port
        api.restartServer()
    }

    private func copyExample() {
        let port = api.settings.port == 0 ? "PORT" : String(api.settings.port)
        let example = """
        curl -X PUT http://127.0.0.1:\(port)/v1/activities/build \\
          -H "Authorization: Bearer $NOTCHED_TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{"template":"progress","title":"Build","subtitle":"Compiling","progress":0.4,"symbol":"hammer.fill"}'
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(example, forType: .string)
    }
}

private struct ClientRow: View {
    let client: APIClient
    let revoke: () -> Void

    var body: some View {
        LabeledContent {
            Button("Revoke", role: .destructive, action: revoke)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: client.name)
                Text(verbatim: client.scopes.map(\.title).sorted().joined(separator: ", ") + " · " + lastSeen)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastSeen: String {
        client.lastSeen.map { "Last seen \($0.formatted(.relative(presentation: .named)))" } ?? "Never used"
    }
}

private struct NewClientSheet: View {
    let api: APIGateway
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scopes: Set<APIScope> = [.activity, .banner]
    @State private var token: String?
    @State private var failed = false

    private static let offered: [APIScope] = [.activity, .banner, .approval]

    var body: some View {
        Form {
            if let token {
                Section {
                    Text(verbatim: token)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Button("Copy Token") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(token, forType: .string)
                    }
                } header: {
                    Text("Token for \(name)")
                } footer: {
                    Text("Copy it now. Notched keeps only a hash, so it can't be shown again.")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Section {
                    TextField("Name", text: $name)
                    ForEach(Self.offered) { scope in
                        Toggle(scope.title, isOn: Binding(
                            get: { scopes.contains(scope) },
                            set: { if $0 { scopes.insert(scope) } else { scopes.remove(scope) } }
                        ))
                    }
                } footer: {
                    if failed { Text("Couldn't create the client. Check the name and scopes.").foregroundStyle(.red) }
                }
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create") {
                        if let created = api.createClient(name: name, scopes: scopes) {
                            token = created.token
                            name = created.client.name
                        } else {
                            failed = true
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || scopes.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
