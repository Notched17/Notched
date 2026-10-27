// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreServices

/// A value returned by an AppleScript, copied out of its Apple Event
/// descriptor so it can cross threads.
enum AppleScriptValue: Equatable, Sendable {
    case none
    case bool(Bool)
    case number(Double)
    case text(String)
    case data(Data)
    case list([AppleScriptValue])

    var string: String? { if case .text(let text) = self { text } else { nil } }
    var double: Double? { if case .number(let number) = self { number } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var items: [AppleScriptValue] { if case .list(let items) = self { items } else { [] } }
}

enum AppleScriptOutcome: Equatable, Sendable {
    case success(AppleScriptValue)
    /// `code` is the AppleScript error number, e.g. −1743 when the user
    /// denied Automation, −1712 on timeout.
    case failure(code: Int, message: String)

    static let notPermitted = -1743

    var value: AppleScriptValue? { if case .success(let value) = self { value } else { nil } }
}

/// Whether Notched may send Apple Events to an app (Automation, per app).
enum AutomationStatus: Equatable, Sendable {
    case granted, denied, notDetermined, notRunning, unknown
}

/// Runs AppleScript off the main thread, one script at a time, each wrapped
/// in a 2 s timeout so a hung player can't stall the island (#9, #15).
final class AppleScriptRunner: Sendable {
    private let queue = DispatchQueue(label: "me.rkck.Notched.applescript", qos: .userInitiated)

    func run(_ source: String) async -> AppleScriptOutcome {
        let wrapped = "with timeout of 2 seconds\n\(source)\nend timeout"
        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: wrapped) else {
                    continuation.resume(returning: .failure(code: 0, message: "Couldn't compile the script"))
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    continuation.resume(returning: .failure(code: code, message: message))
                } else {
                    continuation.resume(returning: .success(Self.value(of: result)))
                }
            }
        }
    }

    /// Asks macOS whether Notched may automate an app, without prompting
    /// unless `askIfNeeded`. The app must be running for macOS to answer.
    func automationStatus(bundleID: String, askIfNeeded: Bool) async -> AutomationStatus {
        await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                guard let address = target.aeDesc else { continuation.resume(returning: .unknown); return }
                let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, askIfNeeded)
                let result: AutomationStatus = switch status {
                case noErr: .granted
                case OSStatus(errAEEventNotPermitted): .denied
                case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
                case OSStatus(procNotFound): .notRunning
                default: .unknown
                }
                continuation.resume(returning: result)
            }
        }
    }

    private static func value(of descriptor: NSAppleEventDescriptor) -> AppleScriptValue {
        switch descriptor.descriptorType {
        case typeNull:
            return .none
        case typeTrue, typeFalse, typeBoolean:
            return .bool(descriptor.booleanValue)
        case typeUnicodeText, typeUTF8Text, typeChar:
            return descriptor.stringValue.map(AppleScriptValue.text) ?? .none
        case typeSInt16, typeSInt32, typeSInt64, typeUInt32, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
            return .number(descriptor.doubleValue)
        case typeAEList:
            let count = descriptor.numberOfItems
            guard count > 0 else { return .list([]) }
            return .list((1...count).map { index in descriptor.atIndex(index).map(value(of:)) ?? .none })
        default:
            // Pictures and raw data ('tdta', 'JPEG', 'PNGf'…).
            return .data(descriptor.data)
        }
    }
}
