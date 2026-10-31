// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How browsers name a download that isn't finished. Pure and tested.
///
/// - Chrome, Edge, Brave, Arc: `name.ext.crdownload` (and `Unconfirmed 123.crdownload`
///   before the name is known), renamed to `name.ext` when done.
/// - Safari: a `name.ext.download` bundle, replaced by `name.ext`.
/// - Firefox: `name.ext.part`, plus an empty `name.ext` placeholder that the
///   finished file replaces.
/// - Opera: `name.ext.opdownload`.
///
/// (The extensions come from published notes on other notch apps' watchers and
/// the browsers' behaviour; they're checked against real browsers at the end of M3b.)
enum DownloadNaming {
    static let extensions = ["crdownload", "download", "part", "opdownload"]

    struct Partial: Equatable, Sendable {
        /// The name the finished file will have. For an unconfirmed Chrome
        /// download, that isn't known yet: this is the partial name itself.
        var finalName: String
        var isUnconfirmed: Bool

        var displayName: String { isUnconfirmed ? "Download" : finalName }
    }

    static func partial(_ filename: String) -> Partial? {
        let lowered = filename.lowercased()
        for ext in extensions where lowered.hasSuffix("." + ext) {
            let base = String(filename.dropLast(ext.count + 1))
            guard !base.isEmpty else { return nil }
            let unconfirmed = ext == "crdownload" && base.hasPrefix("Unconfirmed ")
            return Partial(finalName: unconfirmed ? filename : base, isUnconfirmed: unconfirmed)
        }
        return nil
    }

    /// `com.apple.progress.fractionCompleted` is stored as text whose decimal
    /// separator follows the user's locale ("0,42" as often as "0.42").
    static func parseFraction(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value >= 0, value <= 1 else { return nil }
        return value
    }
}
