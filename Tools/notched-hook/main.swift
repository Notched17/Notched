// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// notched-hook: run by Claude Code's hooks. It passes the hook's JSON to
// Notched's local API and, for a permission request, waits for the user's
// answer and prints it. Whatever goes wrong (Notched closed, no token, a
// timeout, a bad reply) it prints nothing and exits 0, which makes Claude
// Code carry on and ask in its own prompt. Foundation only.

let helperVersion = 1
let environment = ProcessInfo.processInfo.environment
let debug = environment["NOTCHED_HOOK_DEBUG"] == "1"

func note(_ message: String) {
    if debug { FileHandle.standardError.write(Data(("notched-hook: " + message + "\n").utf8)) }
}

/// The only way out: no decision.
func giveUp(_ reason: String) -> Never {
    note(reason)
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "--version" {
    print(helperVersion)
    exit(0)
}

let maxInput = 256 * 1024
let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty, input.count <= maxInput else { giveUp("no input, or too large") }
guard let object = try? JSONSerialization.jsonObject(with: input), let payload = object as? [String: Any],
      let eventName = payload["hook_event_name"] as? String else { giveUp("not a hook payload") }

let support = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Notched")
guard let discovery = try? Data(contentsOf: support.appendingPathComponent("api.json")),
      let info = try? JSONSerialization.jsonObject(with: discovery) as? [String: Any],
      let port = info["port"] as? Int, (1...65535).contains(port) else { giveUp("Notched isn't listening") }
guard let tokenData = try? Data(contentsOf: support.appendingPathComponent("claude-hook.token")),
      let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !token.isEmpty else { giveUp("no token") }

guard let url = URL(string: "http://127.0.0.1:\(port)/v1/claude/hook") else { giveUp("bad url") }
let waitsForAnswer = eventName == "PermissionRequest"
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.httpBody = input
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
// Longer than the longest wait Notched allows (300 s); Claude Code's own hook timeout cuts in first if needed.
request.timeoutInterval = waitsForAnswer ? 330 : 2

let configuration = URLSessionConfiguration.ephemeral
configuration.connectionProxyDictionary = [:]
configuration.waitsForConnectivity = false
configuration.timeoutIntervalForResource = request.timeoutInterval

final class Outcome: @unchecked Sendable {
    var status = 0
    var body = Data()
}
let outcome = Outcome()
let done = DispatchSemaphore(value: 0)
URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
    if let error { note("request failed: \(error.localizedDescription)") }
    outcome.status = (response as? HTTPURLResponse)?.statusCode ?? 0
    outcome.body = data ?? Data()
    done.signal()
}.resume()
done.wait()

guard outcome.status == 200, !outcome.body.isEmpty, (try? JSONSerialization.jsonObject(with: outcome.body)) != nil else {
    giveUp("no decision (status \(outcome.status))")
}
FileHandle.standardOutput.write(outcome.body)
exit(0)
