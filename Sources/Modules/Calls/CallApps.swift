// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which apps count as calls. Matching is by app identity, so a call app's
/// helper processes count as the app. Data, not code: a wrong id never matches.
enum CallApps {
    /// Call apps, by bundle ID. FaceTime, Phone, Discord and Zoom were checked
    /// on a Mac that has them; the others are the apps' published IDs, not yet
    /// checked here.
    static let known: [String: String] = [
        "com.apple.FaceTime": "FaceTime",
        "com.apple.mobilephone": "Phone",
        "us.zoom.xos": "Zoom",
        "com.hnc.Discord": "Discord",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "Cisco-Systems.Spark": "Webex",
    ]

    /// Browsers a call can happen in (Google Meet and friends). They count only
    /// when the user ticks them: a browser also uses the microphone for dictation
    /// and sound tests. Safari and Chrome were checked on a Mac that has them.
    static let browsers: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Chrome",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
    ]

    /// The call apps among the processes using the microphone.
    static func apps(from users: [InputUser], browsers enabled: Set<String>) -> Set<CallReducer.App> {
        var result = Set<CallReducer.App>()
        for user in users {
            let id = user.identity
            if let name = known[id] ?? (enabled.contains(id) ? browsers[id] : nil) {
                result.insert(CallReducer.App(id: id, name: name))
            }
        }
        return result
    }
}
