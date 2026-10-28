// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Settings ▸ Modules ▸ Downloads: what Notched can and can't see.
struct DownloadsSettingsPane: View {
    let permissions: PermissionCenter?

    private var status: PermissionStatus { permissions?.status(.downloadsFolder) ?? .notDetermined }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Spacing.m) {
                        PermissionStatusBadge(status: status)
                        if status != .granted {
                            Button(status == .denied ? "Open System Settings" : "Allow…") {
                                Task { await request() }
                            }
                            .controlSize(.small)
                        }
                    }
                } label: {
                    Label("Downloads folder", systemImage: Permission.downloadsFolder.symbol)
                }
            } header: {
                Text("Access")
            } footer: {
                Text(footer)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Downloads")
    }

    private var footer: String {
        switch status {
        case .granted:
            "Notched shows your browser downloads as they happen and tells you when one finishes. It only looks at the names and sizes of files directly in Downloads, never what's in them."
        case .denied:
            "Notched can't see your Downloads folder, so it shows nothing. Allow it in System Settings > Privacy & Security > Files & Folders."
        default:
            "Notched will ask for access to your Downloads folder when you turn Downloads on."
        }
    }

    private func request() async {
        guard let permissions else { return }
        await permissions.request(.downloadsFolder)
    }
}
