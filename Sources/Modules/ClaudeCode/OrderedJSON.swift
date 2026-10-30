// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// JSON that keeps object keys in the order they were written, so editing
/// `~/.claude/settings.json` never reorders the user's file. Numbers keep
/// their original text. Pure.
indirect enum OrderedJSON: Equatable, Sendable {
    struct Member: Equatable, Sendable {
        var key: String
        var value: OrderedJSON
    }

    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([OrderedJSON])
    case object([Member])

    struct ParseError: Error, Equatable, Sendable {
        var message: String
        var line: Int
        var column: Int

        var description: String { "\(message) (line \(line), column \(column))" }
    }

    // MARK: Access

    var members: [Member]? {
        if case .object(let members) = self { members } else { nil }
    }

    var elements: [OrderedJSON]? {
        if case .array(let elements) = self { elements } else { nil }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    subscript(key: String) -> OrderedJSON? {
        members?.first { $0.key == key }?.value
    }

    // MARK: Parsing

    static func parse(_ text: String) -> Result<OrderedJSON, ParseError> {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        return parser.parseDocument()
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0
        static let maxDepth = 64

        init(scalars: [Unicode.Scalar]) {
            // A byte-order mark is not part of the JSON.
            self.scalars = scalars.first == "\u{FEFF}" ? Array(scalars.dropFirst()) : scalars
        }

        mutating func parseDocument() -> Result<OrderedJSON, ParseError> {
            do {
                skipWhitespace()
                let value = try parseValue(depth: 0)
                skipWhitespace()
                guard index == scalars.count else { throw error("Unexpected text after the JSON value") }
                return .success(value)
            } catch let error as ParseError {
                return .failure(error)
            } catch {
                return .failure(ParseError(message: "Couldn't read the JSON", line: 1, column: 1))
            }
        }

        func error(_ message: String) -> ParseError {
            var line = 1, column = 1
            for scalar in scalars[0..<min(index, scalars.count)] {
                if scalar == "\n" { line += 1; column = 1 } else { column += 1 }
            }
            return ParseError(message: message, line: line, column: column)
        }

        mutating func skipWhitespace() {
            while index < scalars.count, [" ", "\t", "\n", "\r"].contains(scalars[index]) { index += 1 }
        }

        mutating func parseValue(depth: Int) throws -> OrderedJSON {
            guard depth <= Self.maxDepth else { throw error("Nested too deeply") }
            guard index < scalars.count else { throw error("Unexpected end of the file") }
            switch scalars[index] {
            case "{": return try parseObject(depth: depth)
            case "[": return try parseArray(depth: depth)
            case "\"": return .string(try parseString())
            case "t": try expect("true"); return .bool(true)
            case "f": try expect("false"); return .bool(false)
            case "n": try expect("null"); return .null
            case "-", "0"..."9": return .number(try parseNumber())
            default: throw error("Unexpected character \"\(scalars[index])\"")
            }
        }

        mutating func expect(_ word: String) throws {
            for scalar in word.unicodeScalars {
                guard index < scalars.count, scalars[index] == scalar else { throw error("Expected \"\(word)\"") }
                index += 1
            }
        }

        mutating func parseNumber() throws -> String {
            let start = index
            if scalars[index] == "-" { index += 1 }
            let digitsStart = index
            while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
            guard index > digitsStart else { throw error("Expected digits") }
            // JSON has no leading zeros: 0 may only be followed by . e or E.
            if scalars[digitsStart] == "0", index - digitsStart > 1 { throw error("Numbers can't have leading zeros") }
            if index < scalars.count, scalars[index] == "." {
                index += 1
                let fractionStart = index
                while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
                guard index > fractionStart else { throw error("Expected digits after the decimal point") }
            }
            if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                index += 1
                if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
                let exponentStart = index
                while index < scalars.count, ("0"..."9").contains(scalars[index]) { index += 1 }
                guard index > exponentStart else { throw error("Expected digits in the exponent") }
            }
            var text = String.UnicodeScalarView()
            text.append(contentsOf: scalars[start..<index])
            return String(text)
        }

        mutating func parseString() throws -> String {
            index += 1 // opening quote
            var result = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"":
                    return String(result)
                case "\\":
                    guard index < scalars.count else { throw error("Unfinished escape") }
                    let escape = scalars[index]
                    index += 1
                    switch escape {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append("\u{08}")
                    case "f": result.append("\u{0C}")
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u":
                        var unit = try hex4()
                        if (0xD800...0xDBFF).contains(unit) {
                            // A surrogate pair: 😀
                            guard index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" else { throw error("Unpaired surrogate") }
                            index += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("Unpaired surrogate") }
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        } else if (0xDC00...0xDFFF).contains(unit) {
                            throw error("Unpaired surrogate")
                        }
                        guard let decoded = Unicode.Scalar(unit) else { throw error("Invalid character") }
                        result.append(decoded)
                    default:
                        throw error("Unknown escape \"\\\(escape)\"")
                    }
                default:
                    guard scalar.value >= 0x20 else { throw error("Unescaped control character in a string") }
                    result.append(scalar)
                }
            }
            throw error("Unterminated string")
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= scalars.count else { throw error("Short \\u escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let digit = Character(scalars[index]).hexDigitValue else { throw error("Bad \\u escape") }
                value = value * 16 + UInt32(digit)
                index += 1
            }
            return value
        }

        mutating func parseArray(depth: Int) throws -> OrderedJSON {
            index += 1
            var elements: [OrderedJSON] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" { index += 1; return .array([]) }
            while true {
                skipWhitespace()
                elements.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard index < scalars.count else { throw error("Unterminated array") }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "]" { index += 1; return .array(elements) }
                throw error("Expected \",\" or \"]\"")
            }
        }

        mutating func parseObject(depth: Int) throws -> OrderedJSON {
            index += 1
            var members: [Member] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" { index += 1; return .object([]) }
            while true {
                skipWhitespace()
                guard index < scalars.count, scalars[index] == "\"" else { throw error("Expected a string key") }
                let key = try parseString()
                skipWhitespace()
                guard index < scalars.count, scalars[index] == ":" else { throw error("Expected \":\"") }
                index += 1
                skipWhitespace()
                members.append(Member(key: key, value: try parseValue(depth: depth + 1)))
                skipWhitespace()
                guard index < scalars.count else { throw error("Unterminated object") }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "}" { index += 1; return .object(members) }
                throw error("Expected \",\" or \"}\"")
            }
        }
    }

    // MARK: Printing

    /// Two-space indentation, like `JSON.stringify(value, null, 2)`, plus a final newline.
    func pretty() -> String {
        var output = ""
        write(into: &output, indent: 0)
        return output + "\n"
    }

    private func write(into output: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent + 1)
        let closePad = String(repeating: "  ", count: indent)
        switch self {
        case .null: output += "null"
        case .bool(let value): output += value ? "true" : "false"
        case .number(let text): output += text
        case .string(let text): output += Self.quote(text)
        case .array(let elements):
            guard !elements.isEmpty else { output += "[]"; return }
            output += "[\n"
            for (offset, element) in elements.enumerated() {
                output += pad
                element.write(into: &output, indent: indent + 1)
                output += offset == elements.count - 1 ? "\n" : ",\n"
            }
            output += closePad + "]"
        case .object(let members):
            guard !members.isEmpty else { output += "{}"; return }
            output += "{\n"
            for (offset, member) in members.enumerated() {
                output += pad + Self.quote(member.key) + ": "
                member.value.write(into: &output, indent: indent + 1)
                output += offset == members.count - 1 ? "\n" : ",\n"
            }
            output += closePad + "}"
        }
    }

    private static func quote(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
