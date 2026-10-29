// SPDX-License-Identifier: GPL-3.0-or-later

/// The symbol the HUD shows for a level: a slashed speaker when silent, then
/// one, two and three waves; a small sun up to half brightness, a full one above.
enum HUDGlyph {
    static func symbol(kind: HUDKind, level: Double, isMuted: Bool) -> String {
        switch kind {
        case .volume:
            if isMuted || level <= 0 { return "speaker.slash.fill" }
            if level <= 0.34 { return "speaker.wave.1.fill" }
            if level <= 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level <= 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}
