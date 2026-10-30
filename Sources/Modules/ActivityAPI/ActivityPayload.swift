// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How an API activity looks (docs/ACTIVITY-API.md).
enum ActivityTemplate: String, Sendable, CaseIterable {
    case status
    case progress
    case countdown
}

/// The only colours a client can ask for.
enum ActivityTint: String, Sendable, CaseIterable {
    case white, blue, green, orange, red, yellow, purple, pink, teal, gray
}

/// A validated, clamped activity from a client. Every string is plain text.
struct ActivitySpec: Equatable, Sendable {
    var template: ActivityTemplate
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: ActivityTint
    var progress: Double?
    var endsAt: Date?
    var trailing: String?
    var openURL: URL?
    var alert: Bool
    var isPassive: Bool
    var staleAfter: TimeInterval
    var expiresAfter: TimeInterval
}

/// Why a payload was refused.
struct APIFieldError: Error, Equatable, Sendable {
    var code: String
    var message: String
    var field: String?

    var response: HTTPResponse { .error(400, code, message, field: field) }
}

/// Validates untrusted JSON. It never trusts a type, clamps every number,
/// strips control and direction-override characters from text, and returns
/// an error instead of crashing on anything odd.
enum ActivityPayload {
    static let titleLimit = 40
    static let subtitleLimit = 80
    static let trailingLimit = 8
    static let urlLimit = 512

    static func isValidID(_ id: String) -> Bool {
        guard (1...64).contains(id.count) else { return false }
        return id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
    }

    /// Plain text for display: no control characters, no bidi overrides or
    /// zero-width characters, newlines as spaces, trimmed and cut to length.
    static func sanitize(_ text: String, limit: Int) -> String {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x2028, 0x2029, 0x85:
                cleaned.append(" ")
            case 0x00...0x1F, 0x7F...0x9F, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x206F, 0xFEFF, 0xFFF9...0xFFFB:
                continue
            default:
                cleaned.append(scalar)
            }
        }
        let collapsed = String(cleaned).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    static func parse(_ data: Data, now: Date) -> Result<ActivitySpec, APIFieldError> {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return .failure(APIFieldError(code: "invalid_json", message: "The body must be a JSON object.", field: nil))
        }
        func fail(_ field: String, _ message: String) -> Result<ActivitySpec, APIFieldError> {
            .failure(APIFieldError(code: "invalid_payload", message: message, field: field))
        }

        guard let templateRaw = json["template"] as? String, let template = ActivityTemplate(rawValue: templateRaw) else {
            return fail("template", "template must be status, progress or countdown.")
        }
        guard let rawTitle = json["title"] as? String else { return fail("title", "title is required.") }
        let title = sanitize(rawTitle, limit: titleLimit)
        guard !title.isEmpty else { return fail("title", "title can't be empty.") }

        var subtitle: String?
        if let value = json["subtitle"] {
            guard let text = value as? String else { return fail("subtitle", "subtitle must be a string.") }
            let cleaned = sanitize(text, limit: subtitleLimit)
            subtitle = cleaned.isEmpty ? nil : cleaned
        }

        var symbol: String?
        if let value = json["symbol"] {
            guard let name = value as? String, isValidSymbolName(name) else {
                return fail("symbol", "symbol must be an SF Symbol name such as \"bolt.fill\".")
            }
            symbol = name
        }

        var tint = ActivityTint.white
        if let value = json["tint"] {
            guard let name = value as? String, let found = ActivityTint(rawValue: name) else {
                return fail("tint", "tint must be one of: \(ActivityTint.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            tint = found
        }

        var progress: Double?
        if let value = json["progress"] {
            guard let number = number(value), number.isFinite else { return fail("progress", "progress must be a number from 0 to 1.") }
            progress = min(max(number, 0), 1)
        } else if template == .progress {
            return fail("progress", "progress is required for the progress template.")
        }

        var endsAt: Date?
        if let value = json["endsAt"] {
            guard let text = value as? String, let date = parseDate(text) else {
                return fail("endsAt", "endsAt must be an ISO 8601 date such as 2026-10-29T10:30:00Z.")
            }
            let seconds = date.timeIntervalSince(now)
            guard seconds >= 1, seconds <= 24 * 3600 else { return fail("endsAt", "endsAt must be between 1 second and 24 hours from now.") }
            endsAt = date
        } else if template == .countdown {
            return fail("endsAt", "endsAt is required for the countdown template.")
        }

        var trailing: String?
        if let value = json["trailing"] {
            guard let text = value as? String else { return fail("trailing", "trailing must be a string.") }
            let cleaned = sanitize(text, limit: trailingLimit)
            trailing = cleaned.isEmpty ? nil : cleaned
        }

        var openURL: URL?
        if let value = json["openURL"] {
            guard let text = value as? String, text.count <= urlLimit, let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host?.isEmpty == false else {
                return fail("openURL", "openURL must be an http or https URL.")
            }
            openURL = url
        }

        var alert = false
        if let value = json["alert"] {
            guard let flag = bool(value) else { return fail("alert", "alert must be true or false.") }
            alert = flag
        }

        var isPassive = false
        if let value = json["kind"] {
            guard let text = value as? String, text == "live" || text == "passive" else { return fail("kind", "kind must be live or passive.") }
            isPassive = text == "passive"
        }

        let staleAfter = clampedSeconds(json["staleAfter"], default: 600, range: 10...14_400)
        let expiresAfter = clampedSeconds(json["expiresAfter"], default: 3600, range: 60...28_800)
        if json["staleAfter"] != nil, staleAfter == nil { return fail("staleAfter", "staleAfter must be a number of seconds.") }
        if json["expiresAfter"] != nil, expiresAfter == nil { return fail("expiresAfter", "expiresAfter must be a number of seconds.") }

        return .success(ActivitySpec(
            template: template, title: title, subtitle: subtitle, symbol: symbol, tint: tint, progress: progress,
            endsAt: endsAt, trailing: trailing, openURL: openURL, alert: alert, isPassive: isPassive,
            staleAfter: staleAfter ?? 600, expiresAfter: expiresAfter ?? 3600
        ))
    }

    /// Lowercase letters, digits and dots, like "arrow.up.circle.fill".
    static func isValidSymbolName(_ name: String) -> Bool {
        guard (1...64).contains(name.count), let first = name.first, first.isASCII, first.isLowercase || first.isNumber else { return false }
        return name.allSatisfy { $0.isASCII && (($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == ".") }
    }

    static func parseDate(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    /// A JSON number, but not a boolean (which Foundation bridges to NSNumber).
    private static func number(_ value: Any) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func bool(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// Nil if the value is present but not a number; the default if absent.
    private static func clampedSeconds(_ value: Any?, default fallback: TimeInterval, range: ClosedRange<TimeInterval>) -> TimeInterval? {
        guard let value else { return fallback }
        guard let seconds = number(value), seconds.isFinite else { return nil }
        return min(max(seconds, range.lowerBound), range.upperBound)
    }

    /// A banner from `POST /v1/banners`.
    struct BannerSpec: Equatable, Sendable {
        var title: String
        var subtitle: String?
        var symbol: String?
        var tint: ActivityTint
    }

    static func parseBanner(_ data: Data) -> Result<BannerSpec, APIFieldError> {
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = object as? [String: Any] else {
            return .failure(APIFieldError(code: "invalid_json", message: "The body must be a JSON object.", field: nil))
        }
        guard let rawTitle = json["title"] as? String else {
            return .failure(APIFieldError(code: "invalid_payload", message: "title is required.", field: "title"))
        }
        let title = sanitize(rawTitle, limit: 24)
        guard !title.isEmpty else { return .failure(APIFieldError(code: "invalid_payload", message: "title can't be empty.", field: "title")) }
        var subtitle: String?
        if let value = json["subtitle"] {
            guard let text = value as? String else { return .failure(APIFieldError(code: "invalid_payload", message: "subtitle must be a string.", field: "subtitle")) }
            let cleaned = sanitize(text, limit: 16)
            subtitle = cleaned.isEmpty ? nil : cleaned
        }
        var symbol: String?
        if let value = json["symbol"] {
            guard let name = value as? String, isValidSymbolName(name) else {
                return .failure(APIFieldError(code: "invalid_payload", message: "symbol must be an SF Symbol name.", field: "symbol"))
            }
            symbol = name
        }
        var tint = ActivityTint.white
        if let value = json["tint"] {
            guard let name = value as? String, let found = ActivityTint(rawValue: name) else {
                return .failure(APIFieldError(code: "invalid_payload", message: "tint isn't one of the allowed colours.", field: "tint"))
            }
            tint = found
        }
        return .success(BannerSpec(title: title, subtitle: subtitle, symbol: symbol, tint: tint))
    }
}
