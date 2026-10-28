// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How downloads read on the island. Pure, so the wording is tested.
enum DownloadText {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "3.2 MB/s", or nil if the speed isn't known or is nothing.
    static func speed(_ bytesPerSecond: Double?) -> String? {
        guard let bytesPerSecond, bytesPerSecond >= 1 else { return nil }
        return size(Int64(bytesPerSecond)) + "/s"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// "Downloading 2 files", for VoiceOver and the expanded title.
    static func title(count: Int) -> String {
        count == 1 ? "Downloading" : "Downloading \(count) files"
    }

    /// The compact trailing text: progress if known, else speed, else how many.
    static func compact(_ model: DownloadsReducer.Model) -> String {
        if let overall = model.overall { return percent(overall) }
        if let total = totalSpeed(model), let text = speed(total) { return text }
        return model.items.count == 1 ? "…" : "\(model.items.count) files"
    }

    static func totalSpeed(_ model: DownloadsReducer.Model) -> Double? {
        let speeds = model.items.compactMap(\.speed)
        return speeds.isEmpty ? nil : speeds.reduce(0, +)
    }

    /// One row's detail: "42% · 3.2 MB/s", or the size so far when there's no progress.
    static func detail(_ item: DownloadsReducer.Model.Item) -> String {
        var parts: [String] = []
        if let fraction = item.fraction { parts.append(percent(fraction)) } else { parts.append(size(item.bytes)) }
        if let speed = speed(item.speed) { parts.append(speed) }
        return parts.joined(separator: " · ")
    }

    static func accessibilityLabel(_ model: DownloadsReducer.Model) -> String {
        var label = title(count: model.items.count)
        if let overall = model.overall { label += ", \(Int((overall * 100).rounded())) percent" }
        return label
    }
}
