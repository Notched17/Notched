// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The checks that keep web pages and other hosts away from the local API,
/// before any token is looked at (ADR-0021).
struct LocalAPIGuard: Sendable {
    enum Verdict: Equatable, Sendable {
        case allow
        case reject(HTTPResponse)
    }

    let port: UInt16

    func check(_ request: HTTPRequest) -> Verdict {
        // DNS rebinding arrives with the attacker's hostname in Host.
        let allowedHosts: Set<String> = ["127.0.0.1:\(port)", "localhost:\(port)"]
        guard let host = request.header("host")?.lowercased(), allowedHosts.contains(host) else {
            return .reject(.error(421, "bad_host", "Send requests to 127.0.0.1:\(port)."))
        }
        // Browsers always send one of these on a cross-site request; curl and scripts don't. (Node's fetch sends
        // Sec-Fetch-Mode, so that header alone isn't a sign of a web page.)
        let browserHeaders = request.headers.keys.contains { $0 == "origin" || $0 == "sec-fetch-site" }
        if browserHeaders {
            return .reject(.error(403, "browser_forbidden", "Requests from web pages aren't allowed."))
        }
        guard ["GET", "PUT", "POST", "DELETE"].contains(request.method) else {
            return .reject(.error(405, "method_not_allowed", "Use GET, PUT, POST or DELETE.", headers: ["Allow": "GET, PUT, POST, DELETE"]))
        }
        if request.method == "POST" || request.method == "PUT" {
            let type = request.header("content-type")?.split(separator: ";").first
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard type == "application/json" else {
                return .reject(.error(415, "unsupported_media_type", "Send Content-Type: application/json."))
            }
        }
        return .allow
    }
}
