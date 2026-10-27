// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct AboutPane: View {
    var showWelcome: () -> Void
    @State private var document: BundledDocument?

    var body: some View {
        Form {
            Section {
                VStack(spacing: Spacing.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    VStack(spacing: Spacing.xs) {
                        Text("DynamicNotch")
                            .font(.system(.title, weight: .semibold))
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("A free, open-source Dynamic Island for your Mac's notch.")
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.l)
            }

            Section {
                LabeledContent("Licence") {
                    Button("GNU GPL v3 or Later") { document = .licence }
                }
                LabeledContent("Acknowledgements") {
                    Button("Third-Party Notices") { document = .notices }
                }
                LabeledContent("Welcome") {
                    Button("Show Welcome Again", action: showWelcome)
                }
            } footer: {
                Text("DynamicNotch is free software: you can redistribute it and modify it under the terms of the GNU General Public License, version 3 or later.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $document) { document in
            BundledDocumentView(document: document)
        }
    }
}

/// A text file shipped inside the app bundle.
enum BundledDocument: String, Identifiable {
    case licence = "LICENSE"
    case notices = "THIRD_PARTY_NOTICES"

    var id: Self { self }

    var title: String {
        switch self {
        case .licence: "Licence"
        case .notices: "Third-Party Notices"
        }
    }

    var text: String {
        let url = Bundle.main.url(forResource: rawValue, withExtension: self == .notices ? "md" : nil)
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Not found in the app bundle."
    }
}

private struct BundledDocumentView: View {
    let document: BundledDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(document.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.l)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.m)
        }
        .frame(width: 620, height: 520)
        .navigationTitle(document.title)
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}
