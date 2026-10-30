// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One parsed request. Header names are lowercased.
struct HTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }
}

enum HTTPParseError: Error, Equatable, Sendable {
    case headersTooLarge
    case malformed
    case unsupported
    case lengthRequired
    case bodyTooLarge
}

enum HTTPParseResult: Equatable, Sendable {
    /// The buffer holds only part of a request.
    case needMore
    case request(HTTPRequest)
    case failure(HTTPParseError)
}

/// A deliberately small HTTP/1.1 reader for the local API: one request per
/// connection, `Content-Length` bodies only, hard size limits. Pure; fed the
/// whole buffer each time more bytes arrive.
enum HTTPRequestParser {
    static let maxHeaderBytes = 8 * 1024
    static let maxBodyBytes = 16 * 1024
    private static let separator = Data("\r\n\r\n".utf8)
    /// Headers that must not repeat: a repeat is how request smuggling starts.
    private static let singleValued: Set<String> = ["host", "content-length", "content-type", "authorization", "origin"]
    private static let bodyMethods: Set<String> = ["POST", "PUT", "PATCH"]

    static func parse(_ data: Data) -> HTTPParseResult {
        guard let end = data.range(of: separator) else {
            return data.count > maxHeaderBytes ? .failure(.headersTooLarge) : .needMore
        }
        guard end.lowerBound <= maxHeaderBytes else { return .failure(.headersTooLarge) }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .failure(.malformed) }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .failure(.malformed) }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else { return .failure(.malformed) }
        let method = String(parts[0])
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return .failure(.malformed) }
        guard let (path, query) = splitTarget(String(parts[1])) else { return .failure(.malformed) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return .failure(.malformed) }
            let name = line[line.startIndex..<colon].lowercased()
            guard name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return .failure(.malformed) }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[name] != nil, singleValued.contains(name) { return .failure(.malformed) }
            headers[name] = headers[name].map { $0 + ", " + value } ?? value
        }
        if headers["transfer-encoding"] != nil || headers["expect"] != nil { return .failure(.unsupported) }

        var length = 0
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.count <= 9, raw.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(raw) else {
                return .failure(.malformed)
            }
            guard value <= maxBodyBytes else { return .failure(.bodyTooLarge) }
            length = value
        } else if bodyMethods.contains(method) {
            return .failure(.lengthRequired)
        }

        let bodyStart = end.upperBound
        guard data.endIndex - bodyStart >= length else { return .needMore }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return .request(HTTPRequest(method: method, path: path, query: query, headers: headers, body: body))
    }

    /// Splits "/v1/x?a=b" into a path and query. The path allows only the
    /// characters the API uses, so nothing needs percent-decoding or
    /// normalising (no `..`, no `%2e`).
    private static func splitTarget(_ target: String) -> (String, [String: String])? {
        guard target.hasPrefix("/"), target.count <= 512 else { return nil }
        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces[0])
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/")
        guard path.allSatisfy({ allowed.contains($0) }), !path.contains("//"), !path.contains("..") else { return nil }
        var query: [String: String] = [:]
        if pieces.count == 2 {
            for pair in pieces[1].split(separator: "&").prefix(16) {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = String(kv[0]).removingPercentEncoding, !key.isEmpty else { return nil }
                query[key] = kv.count == 2 ? String(kv[1]).removingPercentEncoding ?? "" : ""
            }
        }
        return (path, query)
    }
}

/// What the server sends back. Always JSON.
struct HTTPResponse: Equatable, Sendable {
    var status: Int
    var body: Data
    var extraHeaders: [String: String] = [:]

    static func json(_ status: Int, _ object: [String: Any], headers: [String: String] = [:]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data, extraHeaders: headers)
    }

    static func error(_ status: Int, _ code: String, _ message: String, field: String? = nil,
                      headers: [String: String] = [:]) -> HTTPResponse {
        var inner: [String: Any] = ["code": code, "message": message]
        if let field { inner["field"] = field }
        return json(status, ["error": inner], headers: headers)
    }

    static let noContent = HTTPResponse(status: 204, body: Data())

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 421: "Misdirected Request"
        case 429: "Too Many Requests"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }

    /// The bytes to write to the socket.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        for (name, value) in extraHeaders.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

extension HTTPParseError {
    /// The response for a request that couldn't be read.
    var response: HTTPResponse {
        switch self {
        case .headersTooLarge: .error(413, "too_large", "The request headers are too large.")
        case .bodyTooLarge: .error(413, "too_large", "The request body is larger than \(HTTPRequestParser.maxBodyBytes) bytes.")
        case .lengthRequired: .error(411, "length_required", "Send a Content-Length header with the body.")
        case .unsupported: .error(400, "unsupported", "Chunked bodies and Expect headers aren't supported.")
        case .malformed: .error(400, "bad_request", "The request couldn't be read.")
        }
    }
}
