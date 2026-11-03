// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Darwin
import Foundation

/// Reads whether the screen is locked from `CGSessionCopyCurrentDictionary()`
/// (public function; the key is undocumented but long-standing). ADR-0031 §2.
///
/// Only a present, true `CGSSessionScreenIsLocked` counts as locked: that is
/// the one answer that lets the card show. On many macOS versions the key is
/// simply absent while unlocked, so "absent, on console" is unlocked. Off the
/// console (another user's session in front) or no dictionary is unknown.
enum LockStateReader {
    static func current() -> LockState {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return .unknown }
        return interpret(dictionary)
    }

    /// Pure, for tests.
    static func interpret(_ dictionary: [String: Any]) -> LockState {
        if let onConsole = (dictionary["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue, !onConsole { return .unknown }
        guard let locked = dictionary["CGSSessionScreenIsLocked"] else {
            return dictionary["kCGSSessionOnConsoleKey"] == nil ? .unknown : .unlocked
        }
        guard let value = (locked as? NSNumber)?.boolValue else { return .unknown }
        return value ? .locked : .unlocked
    }
}

extension LocalAccounts {
    /// The local accounts from the user database (`getpwent`), with no
    /// permission needed.
    static func systemEntries() -> [Entry] {
        var entries: [Entry] = []
        setpwent()
        defer { endpwent() }
        while let pointer = getpwent() {
            let record = pointer.pointee
            guard let name = record.pw_name else { continue }
            entries.append(Entry(name: String(cString: name), uid: record.pw_uid,
                                 shell: record.pw_shell.map { String(cString: $0) } ?? ""))
        }
        return entries
    }

    static func otherLoginAccountsExist() -> Bool {
        !otherLoginAccounts(in: systemEntries(), current: NSUserName()).isEmpty
    }
}
