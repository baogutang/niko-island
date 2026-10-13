import Foundation

/// Order-preserving JSON model. Object key order and number spelling survive a
/// parse → serialize round trip, which lets the installer rewrite agent configs
/// without reshuffling anything it does not own.
public indirect enum JSONValue: Sendable, Equatable {
    case object(JSONObject)
    case array([JSONValue])
    case string(String)
    /// Raw number text exactly as written (`1`, `1.0`, `1e3`).
    case number(String)
    case bool(Bool)
    case null
}

public struct JSONObject: Sendable, Equatable {
    public struct Member: Sendable, Equatable {
        public var key: String
        public var value: JSONValue
        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    public var members: [Member]

    public init(_ members: [Member] = []) { self.members = members }

    public init(_ pairs: KeyValuePairs<String, JSONValue>) {
        self.members = pairs.map { Member($0.key, $0.value) }
    }

    public var keys: [String] { members.map(\.key) }
    public var isEmpty: Bool { members.isEmpty }
    public var count: Int { members.count }

    public subscript(key: String) -> JSONValue? {
        get { members.first(where: { $0.key == key })?.value }
        set {
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(Member(key, newValue))
            }
        }
    }

    public func contains(_ key: String) -> Bool { members.contains { $0.key == key } }

    /// Later keys win; existing keys keep their position.
    public func merging(_ other: JSONObject) -> JSONObject {
        var copy = self
        for member in other.members { copy[member.key] = member.value }
        return copy
    }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    /// `["a": .int(1), "b": .null]` — order of the literal is kept.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.members = elements.map { Member($0.0, $0.1) }
    }
}

// MARK: - Convenience accessors

extension JSONValue {
    public var objectValue: JSONObject? { if case .object(let o) = self { return o } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var isNull: Bool { self == .null }

    public var doubleValue: Double? {
        switch self {
        case .number(let raw): return Double(raw)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .number(let raw):
            if let i = Int(raw) { return i }
            if let d = Double(raw), d.isFinite, abs(d) < 9.0e15 { return Int(d) }
            return nil
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// Walk a dotted path of object keys.
    public func at(_ path: String...) -> JSONValue? {
        var current: JSONValue? = self
        for key in path { current = current?[key] }
        return current
    }

    public static func int(_ value: Int) -> JSONValue { .number(String(value)) }

    public static func double(_ value: Double) -> JSONValue {
        guard value.isFinite else { return .null }
        if value == value.rounded(), abs(value) < 9.0e15 { return .number(String(Int64(value))) }
        return .number(String(value))
    }

    /// Order-insensitive structural equality (object key order ignored, numbers compared numerically).
    public func semanticallyEquals(_ other: JSONValue) -> Bool {
        switch (self, other) {
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            for member in a.members {
                guard let rhs = b[member.key], member.value.semanticallyEquals(rhs) else { return false }
            }
            return true
        case (.array(let a), .array(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.semanticallyEquals($1) }
        case (.number(let a), .number(let b)):
            return a == b || Double(a) == Double(b)
        default:
            return self == other
        }
    }
}

// MARK: - Parsing

public struct JSONParseError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public let offset: Int
    public var description: String { "JSON error at byte \(offset): \(message)" }
}

extension JSONValue {
    public static let maxDepth = 128

    public static func parse(_ data: Data) throws -> JSONValue {
        try data.withUnsafeBytes { raw -> JSONValue in
            var parser = Parser(bytes: raw.bindMemory(to: UInt8.self))
            return try parser.parseDocument()
        }
    }

    /// Parses a document but leaves out every object member whose key is in
    /// `skipping`, at any depth. A skipped value is stepped over, checking
    /// only that its strings end and its brackets balance; it is never built.
    /// For reading a few numbers out of lines that are mostly something else.
    public static func parse(_ data: Data, skipping: Set<String>) throws -> JSONValue {
        try data.withUnsafeBytes { raw -> JSONValue in
            var parser = Parser(bytes: raw.bindMemory(to: UInt8.self))
            parser.skipping = skipping
            return try parser.parseDocument()
        }
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    private struct Parser {
        let bytes: UnsafeBufferPointer<UInt8>
        var i = 0
        var skipping: Set<String> = []

        init(bytes: UnsafeBufferPointer<UInt8>) {
            self.bytes = bytes
            // Tolerate a UTF-8 BOM.
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { i = 3 }
        }

        func fail(_ message: String) -> JSONParseError { JSONParseError(message: message, offset: i) }

        mutating func skipWhitespace() {
            while i < bytes.count {
                switch bytes[i] {
                case 0x20, 0x09, 0x0A, 0x0D: i += 1
                default: return
                }
            }
        }

        mutating func parseDocument() throws -> JSONValue {
            skipWhitespace()
            let value = try parseValue(depth: 0)
            skipWhitespace()
            guard i == bytes.count else { throw fail("trailing characters") }
            return value
        }

        mutating func parseValue(depth: Int) throws -> JSONValue {
            guard depth <= JSONValue.maxDepth else { throw fail("nesting too deep") }
            guard i < bytes.count else { throw fail("unexpected end of input") }
            switch bytes[i] {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
            default: throw fail("unexpected character")
            }
        }

        mutating func expect(_ literal: StaticString) throws {
            let count = literal.utf8CodeUnitCount
            guard i + count <= bytes.count else { throw fail("unexpected end of input") }
            let matches = literal.withUTF8Buffer { lit in
                (0..<count).allSatisfy { bytes[i + $0] == lit[$0] }
            }
            guard matches else { throw fail("invalid literal") }
            i += count
        }

        mutating func parseObject(depth: Int) throws -> JSONValue {
            i += 1
            var members: [JSONObject.Member] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(JSONObject(members)) }
            while true {
                skipWhitespace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected object key") }
                let key = try parseString()
                skipWhitespace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected ':'") }
                i += 1
                skipWhitespace()
                if !skipping.isEmpty, skipping.contains(key) {
                    try skipValue(depth: depth + 1)
                    skipWhitespace()
                    guard i < bytes.count else { throw fail("unterminated object") }
                    if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                    if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(JSONObject(members)) }
                    throw fail("expected ',' or '}'")
                }
                let value = try parseValue(depth: depth + 1)
                if let existing = members.firstIndex(where: { $0.key == key }) {
                    members[existing].value = value   // duplicate key: last one wins, first position kept
                } else {
                    members.append(.init(key, value))
                }
                skipWhitespace()
                guard i < bytes.count else { throw fail("unterminated object") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(JSONObject(members)) }
                throw fail("expected ',' or '}'")
            }
        }

        /// Steps over one value without building it.
        mutating func skipValue(depth: Int) throws {
            guard depth <= JSONValue.maxDepth else { throw fail("nesting too deep") }
            guard i < bytes.count else { throw fail("unexpected end of input") }
            switch bytes[i] {
            case UInt8(ascii: "\""):
                try skipString()
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                // Brackets only have to balance; strings are the one place they do not count.
                var open = 0
                while i < bytes.count {
                    let b = bytes[i]
                    if b == UInt8(ascii: "\"") {
                        try skipString()
                        continue
                    }
                    if b == UInt8(ascii: "{") || b == UInt8(ascii: "[") {
                        open += 1
                        guard open + depth <= JSONValue.maxDepth else { throw fail("nesting too deep") }
                    } else if b == UInt8(ascii: "}") || b == UInt8(ascii: "]") {
                        open -= 1
                        if open == 0 { i += 1; return }
                    }
                    i += 1
                }
                throw fail("unterminated value")
            case UInt8(ascii: "t"): try expect("true")
            case UInt8(ascii: "f"): try expect("false")
            case UInt8(ascii: "n"): try expect("null")
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): _ = try parseNumber()
            default: throw fail("unexpected character")
            }
        }

        mutating func skipString() throws {
            i += 1
            while i < bytes.count {
                let b = bytes[i]
                if b == UInt8(ascii: "\"") { i += 1; return }
                i += b == UInt8(ascii: "\\") ? 2 : 1
            }
            throw fail("unterminated string")
        }

        mutating func parseArray(depth: Int) throws -> JSONValue {
            i += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard i < bytes.count else { throw fail("unterminated array") }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                throw fail("expected ',' or ']'")
            }
        }

        mutating func parseNumber() throws -> JSONValue {
            let start = i
            if bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard i < bytes.count, isDigit(bytes[i]) else { throw fail("invalid number") }
            if bytes[i] == UInt8(ascii: "0") {
                i += 1
            } else {
                while i < bytes.count, isDigit(bytes[i]) { i += 1 }
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
                i += 1
                guard i < bytes.count, isDigit(bytes[i]) else { throw fail("invalid fraction") }
                while i < bytes.count, isDigit(bytes[i]) { i += 1 }
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                i += 1
                if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
                guard i < bytes.count, isDigit(bytes[i]) else { throw fail("invalid exponent") }
                while i < bytes.count, isDigit(bytes[i]) { i += 1 }
            }
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<i]), as: UTF8.self)
            return .number(text)
        }

        func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

        mutating func parseHex4() throws -> UInt32 {
            guard i + 4 <= bytes.count else { throw fail("truncated \\u escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[i]
                let digit: UInt32
                switch b {
                case 0x30...0x39: digit = UInt32(b - 0x30)
                case 0x41...0x46: digit = UInt32(b - 0x41 + 10)
                case 0x61...0x66: digit = UInt32(b - 0x61 + 10)
                default: throw fail("invalid \\u escape")
                }
                value = value << 4 | digit
                i += 1
            }
            return value
        }

        mutating func parseString() throws -> String {
            i += 1
            var out: [UInt8] = []
            while true {
                guard i < bytes.count else { throw fail("unterminated string") }
                let b = bytes[i]
                if b == UInt8(ascii: "\"") { i += 1; break }
                if b < 0x20 { throw fail("control character in string") }
                if b != UInt8(ascii: "\\") { out.append(b); i += 1; continue }
                i += 1
                guard i < bytes.count else { throw fail("unterminated escape") }
                let e = bytes[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try parseHex4()
                    if scalar >= 0xD800, scalar <= 0xDBFF,
                       i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        let low = try parseHex4()
                        if low >= 0xDC00, low <= 0xDFFF {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                    let unicode = Unicode.Scalar(scalar) ?? "\u{FFFD}"
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default:
                    throw fail("invalid escape")
                }
            }
            // `String(decoding:)` repairs invalid UTF-8 rather than failing.
            return String(decoding: out, as: UTF8.self)
        }
    }
}

// MARK: - Serialisation

public struct JSONStyle: Sendable, Equatable {
    /// `nil` → compact single line. Otherwise the indent unit (e.g. two spaces).
    public var indent: String?
    public var trailingNewline: Bool
    /// Compact style only: `{"a": 1, "b": 2}` instead of `{"a":1,"b":2}`.
    public var spacedSeparators: Bool

    public init(indent: String? = "  ", trailingNewline: Bool = false, spacedSeparators: Bool = false) {
        self.indent = indent
        self.trailingNewline = trailingNewline
        self.spacedSeparators = spacedSeparators
    }

    public static let compact = JSONStyle(indent: nil)
    public static let pretty = JSONStyle(indent: "  ", trailingNewline: true)

    /// Infer formatting from existing text so a rewrite keeps the file's look.
    public static func detect(from text: String) -> JSONStyle {
        var style = JSONStyle(indent: nil, trailingNewline: text.hasSuffix("\n"))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 1 {
            style.indent = "  "
            for line in lines.dropFirst() {
                let lead = line.prefix { $0 == " " || $0 == "\t" }
                if !lead.isEmpty { style.indent = String(lead); break }
            }
        } else if text.contains("\": ") {
            style.spacedSeparators = true
        }
        return style
    }
}

extension JSONValue {
    public func serialized(_ style: JSONStyle = .compact) -> String {
        var out = ""
        write(into: &out, style: style, depth: 0)
        if style.trailingNewline { out.append("\n") }
        return out
    }

    public func serializedData(_ style: JSONStyle = .compact) -> Data {
        Data(serialized(style).utf8)
    }

    private func write(into out: inout String, style: JSONStyle, depth: Int) {
        switch self {
        case .null: out.append("null")
        case .bool(let b): out.append(b ? "true" : "false")
        case .number(let raw): out.append(raw)
        case .string(let s): JSONValue.writeString(s, into: &out)
        case .array(let items):
            guard !items.isEmpty else { out.append("[]"); return }
            out.append("[")
            for (n, item) in items.enumerated() {
                if n > 0 { out.append(style.indent == nil && style.spacedSeparators ? ", " : ",") }
                JSONValue.newline(into: &out, style: style, depth: depth + 1)
                item.write(into: &out, style: style, depth: depth + 1)
            }
            JSONValue.newline(into: &out, style: style, depth: depth)
            out.append("]")
        case .object(let object):
            guard !object.isEmpty else { out.append("{}"); return }
            out.append("{")
            for (n, member) in object.members.enumerated() {
                if n > 0 { out.append(style.indent == nil && style.spacedSeparators ? ", " : ",") }
                JSONValue.newline(into: &out, style: style, depth: depth + 1)
                JSONValue.writeString(member.key, into: &out)
                out.append(style.indent != nil || style.spacedSeparators ? ": " : ":")
                member.value.write(into: &out, style: style, depth: depth + 1)
            }
            JSONValue.newline(into: &out, style: style, depth: depth)
            out.append("}")
        }
    }

    private static func newline(into out: inout String, style: JSONStyle, depth: Int) {
        guard let indent = style.indent else { return }
        out.append("\n")
        for _ in 0..<depth { out.append(indent) }
    }

    static func writeString(_ s: String, into out: inout String) {
        out.append("\"")
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out.append("\\\"")
            case 0x5C: out.append("\\\\")
            case 0x0A: out.append("\\n")
            case 0x0D: out.append("\\r")
            case 0x09: out.append("\\t")
            case 0x08: out.append("\\b")
            case 0x0C: out.append("\\f")
            case 0..<0x20:
                out.append("\\u" + String(format: "%04x", scalar.value))
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out.append("\"")
    }
}
