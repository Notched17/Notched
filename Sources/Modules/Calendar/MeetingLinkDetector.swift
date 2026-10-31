// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum MeetingService: String, Equatable, Sendable {
    case zoom = "Zoom"
    case meet = "Google Meet"
    case teams = "Microsoft Teams"
    case webex = "Webex"
}

struct MeetingLink: Equatable, Sendable {
    var service: MeetingService
    var url: URL
}

/// Finds a video-call link in an event (#49): its URL, then its location, then
/// its notes, first match in each. Pure.
///
/// Only the services' own addresses count, matched on the exact host or a
/// subdomain of it, so `zoom.us.example.com` and `notzoom.us` are not Zoom.
/// Lines quoted from an earlier message (starting with `>`) are ignored.
enum MeetingLinkDetector {
    static func detect(url: String?, location: String?, notes: String?) -> MeetingLink? {
        for field in [url, location, notes] {
            guard let field, !field.isEmpty else { continue }
            if let link = firstLink(in: field) { return link }
        }
        return nil
    }

    static func firstLink(in text: String) -> MeetingLink? {
        // Built here, not shared: it runs once per event when the agenda refreshes.
        guard let candidate = try? NSRegularExpression(pattern: #"(?:https?|zoommtg)://[^\s<>"'\)\]]+"#, options: [.caseInsensitive]) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
        for line in lines {
            let string = String(line)
            let range = NSRange(string.startIndex..., in: string)
            for match in candidate.matches(in: string, range: range) {
                guard let swiftRange = Range(match.range, in: string) else { continue }
                var raw = String(string[swiftRange])
                while let last = raw.last, ".,;:!?".contains(last) { raw.removeLast() }
                if let link = classify(raw) { return link }
            }
        }
        return nil
    }

    static func classify(_ raw: String) -> MeetingLink? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "zoommtg" { return MeetingLink(service: .zoom, url: url) }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()

        func isHost(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if isHost("zoom.us") || isHost("zoomgov.com") {
            if ["/j/", "/my/", "/wc/", "/s/"].contains(where: path.hasPrefix) { return MeetingLink(service: .zoom, url: url) }
        } else if host == "meet.google.com" {
            // abc-defg-hij, or a lookup link.
            let code = path.dropFirst()
            if code.range(of: #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil || path.hasPrefix("/lookup/") {
                return MeetingLink(service: .meet, url: url)
            }
        } else if host == "teams.microsoft.com" {
            if path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/") { return MeetingLink(service: .teams, url: url) }
        } else if host == "teams.live.com" {
            if path.hasPrefix("/meet/") { return MeetingLink(service: .teams, url: url) }
        } else if isHost("webex.com") {
            if path.contains("/meet/") || path.hasSuffix("/j.php") || path.contains("/join") { return MeetingLink(service: .webex, url: url) }
        }
        return nil
    }
}
