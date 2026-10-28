// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import Testing
@testable import Notched

/// Every SF Symbol name the app uses exists on this macOS, so a typo (or a
/// symbol Apple renames) fails here instead of drawing nothing.
@MainActor
@Suite("SF Symbols")
struct SymbolNameTests {
    @Test("Every symbol name written in the sources exists")
    func literalSymbolsExist() throws {
        let names = try Self.literalSymbolNames()
        #expect(names.count > 50, "The scan found too few names; has the source layout changed?")
        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted()
        #expect(missing.isEmpty, "Unknown SF Symbols: \(missing)")
    }

    @Test("Symbols chosen at runtime exist")
    func runtimeSymbolsExist() {
        var names: [String] = []
        let kinds: [BluetoothDevice.Kind] = [.keyboard, .mouse(isApple: true), .mouse(isApple: false), .trackpad, .gameController, .other]
        names += kinds.map { BluetoothDevice(address: nil, name: "Device", kind: $0).symbol }
        let transports: [AudioOutputDevice.Transport] = [.builtIn, .bluetooth, .airPlay, .hdmi, .displayPort, .usb, .thunderbolt, .virtual, .aggregate, .other]
        for transport in transports {
            for name in ["AirPods Pro", "AirPods Max", "AirPods", "Beats Studio", "Speaker"] {
                for headphones in [false, true] {
                    names.append(AudioOutputDevice(id: 0, uid: "uid", name: name, transport: transport, isHeadphonesDataSource: headphones).symbol)
                }
            }
        }
        names += [KeepAwakePresentation.symbol] + ModuleRegistryCatalog.descriptors.map(\.symbol)
        let missing = Set(names).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }.sorted()
        #expect(missing.isEmpty, "Unknown SF Symbols: \(missing)")
    }

    /// Names passed as `systemName:`, `systemImage:`, `symbol:` or
    /// `systemSymbolName:` (including both sides of a `? :`), and assigned to
    /// a `symbol` constant, across `Sources/` and `App/`.
    static func literalSymbolNames() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let patterns = [
            #"(?:systemName|systemImage|symbol|systemSymbolName):\s*"([^"\\]+)""#,
            #"(?:systemName|systemImage|symbol|systemSymbolName):\s*[^,()"]*\?\s*"([^"\\]+)"\s*:\s*"([^"\\]+)""#,
            #"\bsymbol\s*=\s*"([^"\\]+)""#,
        ].map { try! NSRegularExpression(pattern: $0) }
        var names = Set<String>()
        for folder in ["Sources", "App"] {
            let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                let range = NSRange(text.startIndex..., in: text)
                for pattern in patterns {
                    for match in pattern.matches(in: text, range: range) {
                        for group in 1..<match.numberOfRanges {
                            guard let captured = Range(match.range(at: group), in: text) else { continue }
                            names.insert(String(text[captured]))
                        }
                    }
                }
            }
        }
        return names
    }
}

/// Every module's descriptor, for tests that check them all.
@MainActor
enum ModuleRegistryCatalog {
    static var descriptors: [ModuleDescriptor] { AppEnvironment.moduleTypes.map { $0.descriptor } }
}
