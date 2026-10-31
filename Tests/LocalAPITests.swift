// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

private func http(_ text: String) -> Data { Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) }

private func request(method: String = "GET", path: String = "/v1/activities", headers: [String: String] = [:], body: String = "") -> HTTPRequest {
    var all = ["host": "127.0.0.1:50000"]
    if method == "POST" || method == "PUT" { all["content-type"] = "application/json" }
    for (key, value) in headers { all[key.lowercased()] = value }
    return HTTPRequest(method: method, path: path, query: [:], headers: all, body: Data(body.utf8))
}

@Suite("HTTPRequestParser")
struct HTTPRequestParserTests {
    @Test("A GET is read: method, path, query and lowercased headers")
    func get() {
        let result = HTTPRequestParser.parse(http("GET /v1/activities?dismiss=immediate HTTP/1.1\nHost: 127.0.0.1:5000\nAuthorization: Bearer x\n\n"))
        guard case .request(let parsed) = result else { Issue.record("expected a request, got \(result)"); return }
        #expect(parsed.method == "GET")
        #expect(parsed.path == "/v1/activities")
        #expect(parsed.query == ["dismiss": "immediate"])
        #expect(parsed.header("HOST") == "127.0.0.1:5000")
        #expect(parsed.header("authorization") == "Bearer x")
    }

    @Test("A PUT body is read by Content-Length")
    func putBody() {
        let body = #"{"a":1}"#
        let result = HTTPRequestParser.parse(http("PUT /v1/activities/x HTTP/1.1\nHost: h\nContent-Length: \(body.utf8.count)\n\n\(body)"))
        guard case .request(let parsed) = result else { Issue.record("expected a request"); return }
        #expect(String(decoding: parsed.body, as: UTF8.self) == body)
    }

    @Test("A partial request asks for more bytes at every cut")
    func partial() {
        let full = http("PUT /v1/activities/x HTTP/1.1\nHost: h\nContent-Length: 5\n\nhello")
        for cut in 1..<full.count {
            #expect(HTTPRequestParser.parse(full.prefix(cut)) == .needMore, "cut at \(cut)")
        }
        #expect(HTTPRequestParser.parse(full) != .needMore)
    }

    @Test("Limits: huge headers, huge bodies, missing length, chunked and Expect")
    func limits() {
        let hugeHeader = http("GET / HTTP/1.1\nHost: h\nX: " + String(repeating: "a", count: 9000) + "\n\n")
        #expect(HTTPRequestParser.parse(hugeHeader) == .failure(.headersTooLarge))
        #expect(HTTPRequestParser.parse(Data(String(repeating: "a", count: 9000).utf8)) == .failure(.headersTooLarge))
        #expect(HTTPRequestParser.parse(http("PUT /v1/x HTTP/1.1\nHost: h\nContent-Length: 99999\n\n")) == .failure(.bodyTooLarge))
        // The Claude hook route takes bigger bodies (up to 256 KB), nothing else does.
        #expect(HTTPRequestParser.parse(http("POST /v1/claude/hook HTTP/1.1\nHost: h\nContent-Length: 99999\n\n")) == .needMore)
        #expect(HTTPRequestParser.parse(http("POST /v1/claude/hook HTTP/1.1\nHost: h\nContent-Length: 300000\n\n")) == .failure(.bodyTooLarge))
        #expect(HTTPRequestParser.parse(http("POST /v1/x HTTP/1.1\nHost: h\n\n")) == .failure(.lengthRequired))
        #expect(HTTPRequestParser.parse(http("POST /v1/x HTTP/1.1\nHost: h\nTransfer-Encoding: chunked\n\n")) == .failure(.unsupported))
        #expect(HTTPRequestParser.parse(http("POST /v1/x HTTP/1.1\nHost: h\nExpect: 100-continue\nContent-Length: 1\n\n")) == .failure(.unsupported))
    }

    @Test("Malformed requests are refused")
    func malformed() {
        let bad = [
            "GARBAGE\n\n",
            "GET / HTTP/2\nHost: h\n\n",
            "get / HTTP/1.1\nHost: h\n\n",
            "GET / HTTP/1.1\nNoColonHere\n\n",
            "GET / HTTP/1.1\nHost: a\nHost: b\n\n",
            "PUT /x HTTP/1.1\nHost: h\nContent-Length: 1\nContent-Length: 2\n\nab",
            "PUT /x HTTP/1.1\nHost: h\nContent-Length: -1\n\n",
            "PUT /x HTTP/1.1\nHost: h\nContent-Length: 1x\n\n",
            "GET /v1/../etc HTTP/1.1\nHost: h\n\n",
            "GET /v1//x HTTP/1.1\nHost: h\n\n",
            "GET /v1/%2e%2e/x HTTP/1.1\nHost: h\n\n",
            "GET http://evil/ HTTP/1.1\nHost: h\n\n",
        ]
        for text in bad {
            guard case .failure = HTTPRequestParser.parse(http(text)) else { Issue.record("accepted: \(text.debugDescription)"); continue }
        }
    }

    @Test("Fuzz: random and mutated bytes never crash and never yield a request with a bad method")
    func fuzz() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
        let template = Array(http("PUT /v1/activities/x HTTP/1.1\nHost: 127.0.0.1:5000\nContent-Length: 5\n\nhello"))
        for _ in 0..<3000 {
            var bytes = template
            for _ in 0..<(Int(next() % 6) + 1) {
                let index = Int(next() % UInt64(bytes.count))
                switch next() % 3 {
                case 0: bytes[index] = UInt8(truncatingIfNeeded: next())
                case 1: bytes.remove(at: index)
                default: bytes.insert(UInt8(truncatingIfNeeded: next()), at: index)
                }
                if bytes.isEmpty { bytes = [0] }
            }
            if case .request(let parsed) = HTTPRequestParser.parse(Data(bytes)) {
                #expect(parsed.method.allSatisfy { $0.isASCII && $0.isUppercase })
                #expect(parsed.path.hasPrefix("/"))
                #expect(parsed.body.count <= HTTPRequestParser.maxBodyBytes)
            }
        }
        for _ in 0..<500 {
            let random = Data((0..<Int(next() % 600)).map { _ in UInt8(truncatingIfNeeded: next()) })
            _ = HTTPRequestParser.parse(random)
        }
    }

    @Test("Responses serialise with length, JSON and no caching")
    func responseBytes() {
        let text = String(decoding: HTTPResponse.error(401, "invalid_token", "No.").serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(text.contains("Content-Type: application/json; charset=utf-8\r\n"))
        #expect(text.contains("Cache-Control: no-store\r\n"))
        #expect(text.contains("\"code\":\"invalid_token\""))
        let body = text.components(separatedBy: "\r\n\r\n")[1]
        #expect(text.contains("Content-Length: \(body.utf8.count)\r\n"))
    }
}

@Suite("LocalAPIGuard")
struct LocalAPIGuardTests {
    let sut = LocalAPIGuard(port: 50000)

    private func status(_ request: HTTPRequest) -> Int? {
        if case .reject(let response) = sut.check(request) { return response.status }
        return nil
    }

    @Test("Loopback hosts with the right port pass")
    func allowed() {
        #expect(status(request()) == nil)
        #expect(status(request(headers: ["Host": "localhost:50000"])) == nil)
        #expect(status(request(headers: ["Host": "LOCALHOST:50000"])) == nil)
    }

    @Test("A rebinding hostname, a wrong port, or no Host is refused with 421")
    func badHosts() {
        for host in ["evil.example.com:50000", "127.0.0.1:50001", "127.0.0.1", "localhost", "127.0.0.1.evil.com:50000", "[::1]:50000", "0.0.0.0:50000"] {
            #expect(status(request(headers: ["Host": host])) == 421, "\(host)")
        }
        var missing = request()
        missing.headers["host"] = nil
        #expect(status(missing) == 421)
    }

    @Test("Browser requests (Origin or Sec-Fetch-Site) are refused with 403")
    func browsers() {
        #expect(status(request(headers: ["Origin": "https://evil.example"])) == 403)
        #expect(status(request(headers: ["Origin": "null"])) == 403)
        #expect(status(request(headers: ["Sec-Fetch-Site": "cross-site"])) == 403)
        // Node's fetch sends Sec-Fetch-Mode alone; that is allowed.
        #expect(status(request(headers: ["Sec-Fetch-Mode": "cors"])) == nil)
    }

    @Test("Preflight and odd methods get 405; writes need application/json")
    func methodsAndTypes() {
        #expect(status(request(method: "OPTIONS")) == 405)
        #expect(status(request(method: "PATCH")) == 405)
        #expect(status(request(method: "POST", headers: ["Content-Type": "text/plain"])) == 415)
        #expect(status(request(method: "POST", headers: ["Content-Type": "application/x-www-form-urlencoded"])) == 415)
        #expect(status(request(method: "PUT", headers: ["Content-Type": "application/json; charset=utf-8"])) == nil)
        var none = request(method: "POST")
        none.headers["content-type"] = nil
        #expect(status(none) == 415)
    }

    @Test("The checks run in order: a bad Host wins over a browser header")
    func order() {
        #expect(status(request(headers: ["Host": "evil:1", "Origin": "x"])) == 421)
    }
}

@Suite("APIToken and ClientDirectory")
struct APITokenTests {
    @Test("Tokens are ntch_ plus 43 URL-safe characters, and differ each time")
    func format() {
        let a = APIToken.generate(), b = APIToken.generate()
        #expect(a.count == APIToken.length)
        #expect(a.hasPrefix("ntch_"))
        #expect(APIToken.isWellFormed(a))
        #expect(a != b)
        #expect(!a.contains("+") && !a.contains("/") && !a.contains("="))
        #expect(APIToken.make(from: [UInt8](repeating: 0xFF, count: 32)) == "ntch_" + String(repeating: "_", count: 42) + "8")
    }

    @Test("Malformed tokens are not well formed")
    func malformed() {
        #expect(!APIToken.isWellFormed(""))
        #expect(!APIToken.isWellFormed("ntch_short"))
        #expect(!APIToken.isWellFormed("xxxxx" + String(repeating: "a", count: 43)))
        #expect(!APIToken.isWellFormed("ntch_" + String(repeating: "!", count: 43)))
    }

    @Test("Constant-time comparison is equality")
    func comparison() {
        let a = APIToken.hash("one"), b = APIToken.hash("two")
        #expect(APIToken.constantTimeEqual(a, a))
        #expect(!APIToken.constantTimeEqual(a, b))
        #expect(!APIToken.constantTimeEqual(a, a.dropLast()))
        #expect(a.count == 32)
    }

    @Test("Bearer headers are read strictly")
    func bearer() {
        #expect(APIToken.bearer(from: "Bearer abc") == "abc")
        #expect(APIToken.bearer(from: "bearer abc") == "abc")
        #expect(APIToken.bearer(from: "Basic abc") == nil)
        #expect(APIToken.bearer(from: "Bearer") == nil)
        #expect(APIToken.bearer(from: "Bearer a b") == nil)
        #expect(APIToken.bearer(from: nil) == nil)
    }

    @Test("The directory authenticates the right client, and nobody else")
    func directory() {
        var sut = ClientDirectory()
        let t1 = APIToken.generate(), t2 = APIToken.generate()
        let c1 = APIClient(id: "1", name: "One", scopes: [.activity], createdAt: Date())
        let c2 = APIClient(id: "2", name: "Two", scopes: [.banner], createdAt: Date())
        sut.add(c1, tokenHash: APIToken.hash(t1))
        sut.add(c2, tokenHash: APIToken.hash(t2))
        #expect(sut.authenticate(header: "Bearer " + t1) == .ok(c1))
        #expect(sut.authenticate(header: "Bearer " + t2) == .ok(c2))
        #expect(sut.authenticate(header: "Bearer " + APIToken.generate()) == .invalid)
        #expect(sut.authenticate(header: "Bearer nonsense") == .invalid)
        #expect(sut.authenticate(header: nil) == .missing)
        sut.remove(id: "1")
        #expect(sut.authenticate(header: "Bearer " + t1) == .invalid)
        sut.touch(id: "2", at: Date(timeIntervalSinceReferenceDate: 5))
        #expect(sut.client(id: "2")?.lastSeen == Date(timeIntervalSinceReferenceDate: 5))
    }
}

@Suite("TokenBucket and FailureLimiter")
struct LimiterTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 90_000)

    @Test("A burst is allowed, then requests wait, then it refills")
    func bucket() {
        var sut = TokenBucket(burst: 3, perSecond: 1)
        let burst = (0..<3).map { _ in sut.take(at: t0) }
        let fourth = sut.take(at: t0)
        let early = sut.take(at: t0 + 0.5)
        let refilled = sut.take(at: t0 + 1.2)
        let again = sut.take(at: t0 + 1.2)
        let later = sut.take(at: t0 + 100)
        #expect(burst == [nil, nil, nil])
        #expect(fourth != nil)
        #expect(early != nil)
        #expect(refilled == nil)
        #expect(again != nil)
        #expect(later == nil)
    }

    @Test("Refill never exceeds the burst")
    func cap() {
        var sut = TokenBucket(burst: 2, perSecond: 100)
        _ = sut.take(at: t0)
        let results = (0..<4).map { _ in sut.take(at: t0 + 1000) == nil }
        #expect(results == [true, true, false, false])
    }

    @Test("Failures block after the limit, and clear after the window")
    func failures() {
        var sut = FailureLimiter(maxFailures: 3, window: 60)
        #expect(!sut.isBlocked(at: t0))
        for _ in 0..<3 { sut.recordFailure(at: t0) }
        #expect(sut.isBlocked(at: t0 + 30))
        #expect(!sut.isBlocked(at: t0 + 61))
    }
}
