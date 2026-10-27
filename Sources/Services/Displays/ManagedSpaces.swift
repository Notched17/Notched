// SPDX-License-Identifier: GPL-3.0-or-later

/// Interprets SkyLight's managed-display-spaces snapshot. Pure, so it's tested
/// with fixtures and never crashes on unexpected shapes.
enum ManagedSpaces {
    /// SkyLight's space type for a fullscreen app's Space.
    static let fullscreenSpaceType = 4

    /// The displays whose current Space is a fullscreen Space.
    /// - Parameter mainDisplay: used when Spaces span all displays ("Main").
    static func fullscreenDisplays(in snapshot: [[String: Any]], mainDisplay: DisplayID?) -> Set<DisplayID> {
        var result = Set<DisplayID>()
        for display in snapshot {
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let currentID = current["ManagedSpaceID"] as? Int,
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let space = spaces.first(where: { ($0["ManagedSpaceID"] as? Int) == currentID })
            else { continue }

            let isFullscreen = space["TileLayoutManager"] != nil
                || (space["type"] as? Int) == fullscreenSpaceType
            guard isFullscreen else { continue }

            if identifier == "Main" {
                if let mainDisplay { result.insert(mainDisplay) }
            } else {
                result.insert(DisplayID(rawValue: identifier))
            }
        }
        return result
    }
}
