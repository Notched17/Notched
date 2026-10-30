// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import Security

/// What a client may do. Granted when the client is created.
enum APIScope: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Post, update and end activities.
    case activity
    /// Show banners.
    case banner
    /// Ask the user to approve something and wait for the answer.
    case approval
    /// The Claude Code hook (internal; not offered for other clients).
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: "Post activities"
        case .banner: "Show banners"
        case .approval: "Request approval"
        case .claude: "Claude Code hooks"
        }
    }
}

/// Bearer tokens: `ntch_` plus 43 URL-safe characters (32 random bytes).
/// Only SHA-256 hashes are stored, and they're compared in constant time.
enum APIToken {
    static let prefix = "ntch_"
    static let length = prefix.count + 43

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Practically unreachable; fall back to the system generator rather than crash.
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
        return make(from: bytes)
    }

    static func make(from bytes: [UInt8]) -> String {
        let encoded = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return prefix + encoded
    }

    static func isWellFormed(_ token: String) -> Bool {
        guard token.count == length, token.hasPrefix(prefix) else { return false }
        return token.dropFirst(prefix.count).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func hash(_ token: String) -> Data { Data(SHA256.hash(data: Data(token.utf8))) }

    /// Compares without stopping at the first difference.
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    /// The token from an `Authorization: Bearer …` header value.
    static func bearer(from header: String?) -> String? {
        guard let header else { return nil }
        let parts = header.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return String(parts[1])
    }
}

/// A named client of the local API. The record holds no secret.
struct APIClient: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var scopes: Set<APIScope>
    var createdAt: Date
    var lastSeen: Date?
    /// Created by Notched for its own use (Claude Code); hidden from the client list.
    var isInternal: Bool = false
}

/// The clients and their token hashes, in memory. Pure.
struct ClientDirectory: Sendable {
    enum AuthResult: Equatable, Sendable {
        case ok(APIClient)
        case missing
        case invalid
    }

    private(set) var clients: [APIClient] = []
    private var hashes: [String: Data] = [:]

    init() {}

    mutating func add(_ client: APIClient, tokenHash: Data) {
        clients.removeAll { $0.id == client.id }
        clients.append(client)
        hashes[client.id] = tokenHash
    }

    mutating func remove(id: String) {
        clients.removeAll { $0.id == id }
        hashes[id] = nil
    }

    func client(id: String) -> APIClient? { clients.first { $0.id == id } }

    mutating func touch(id: String, at date: Date) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[index].lastSeen = date
    }

    /// Checks the token against every client's hash, without an early exit.
    func authenticate(header: String?) -> AuthResult {
        guard let token = APIToken.bearer(from: header) else { return .missing }
        guard APIToken.isWellFormed(token) else { return .invalid }
        let candidate = APIToken.hash(token)
        var match: APIClient?
        for client in clients {
            let stored = hashes[client.id] ?? Data(repeating: 0, count: candidate.count)
            if APIToken.constantTimeEqual(stored, candidate) { match = client }
        }
        return match.map { .ok($0) } ?? .invalid
    }
}
