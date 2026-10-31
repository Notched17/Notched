// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// One-click Join (#49): finding a call link in an event.
@Suite("MeetingLinkDetector")
struct MeetingLinkDetectorTests {
    @Test("Each service's own links are recognised", arguments: [
        ("https://zoom.us/j/123456789?pwd=abc", MeetingService.zoom),
        ("https://us02web.zoom.us/j/123456789", .zoom),
        ("https://acme.zoom.us/my/alex", .zoom),
        ("zoommtg://zoom.us/join?confno=123", .zoom),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("https://meet.google.com/lookup/xyz123", .meet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0?context=x", .teams),
        ("https://teams.live.com/meet/9876543210", .teams),
        ("https://acme.webex.com/meet/alex", .webex),
        ("https://acme.webex.com/acme/j.php?MTID=abc", .webex),
    ])
    func recognises(link: String, service: MeetingService) {
        let found = MeetingLinkDetector.detect(url: link, location: nil, notes: nil)
        #expect(found?.service == service)
        #expect(found?.url.absoluteString == link)
    }

    @Test("Look-alike hosts and other pages on a real host are not meetings", arguments: [
        "https://zoom.us.evil.com/j/123",
        "https://notzoom.us/j/123",
        "https://evil.com/?u=https://zoom.us/j/1",
        "https://zoom.us/pricing",
        "https://meet.google.com/",
        "https://meet.google.com/landing",
        "https://teams.microsoft.com/",
        "https://example.com/meet/abc",
        "ftp://zoom.us/j/123",
    ])
    func rejects(link: String) {
        #expect(MeetingLinkDetector.detect(url: link, location: nil, notes: nil) == nil)
    }

    @Test("The event's URL wins over its location, and the location over its notes")
    func fieldOrder() {
        let zoom = "https://zoom.us/j/1", meet = "https://meet.google.com/abc-defg-hij", teams = "https://teams.live.com/meet/2"
        #expect(MeetingLinkDetector.detect(url: zoom, location: meet, notes: teams)?.service == .zoom)
        #expect(MeetingLinkDetector.detect(url: nil, location: meet, notes: teams)?.service == .meet)
        #expect(MeetingLinkDetector.detect(url: "https://example.com", location: "Room 4", notes: "Join: \(teams)")?.service == .teams)
        #expect(MeetingLinkDetector.detect(url: nil, location: "Room 4", notes: nil) == nil)
        #expect(MeetingLinkDetector.detect(url: "", location: "", notes: "") == nil)
    }

    @Test("A link inside notes text is found, and trailing punctuation is dropped")
    func inText() {
        let notes = "Agenda below.\nJoin Zoom Meeting: https://zoom.us/j/555123, passcode 42.\nSee you there."
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)?.url.absoluteString == "https://zoom.us/j/555123")
        let bracketed = "(https://meet.google.com/abc-defg-hij)."
        #expect(MeetingLinkDetector.detect(url: nil, location: bracketed, notes: nil)?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("A link in quoted reply text is ignored; the next real one is used")
    func quotedLines() {
        let notes = "> Join https://zoom.us/j/111\n\nNew link: https://meet.google.com/abc-defg-hij"
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)?.service == .meet)
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: "> https://zoom.us/j/111") == nil)
    }

    @Test("Ordinary links before the meeting link are skipped")
    func skipsOtherLinks() {
        let notes = "Doc: https://docs.example.com/plan and call https://acme.zoom.us/j/777"
        #expect(MeetingLinkDetector.detect(url: nil, location: nil, notes: notes)?.service == .zoom)
    }

    @Test("Upper-case schemes and hosts still match")
    func caseInsensitive() {
        #expect(MeetingLinkDetector.detect(url: "HTTPS://ZOOM.US/J/123", location: nil, notes: nil)?.service == .zoom)
    }
}
