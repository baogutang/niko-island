import Foundation

/// Extracts usage numbers from one transcript format. A parser instance
/// follows a single file from its first byte, so it may keep context
/// (current model, session id) between lines.
public protocol UsageParser {
    static var provider: String { get }
    /// Bump when the extraction logic changes: files are then re-read from the start.
    static var version: Int { get }
    /// Cheap byte-level test that lets the tailer skip lines without parsing JSON.
    static var needles: [Data] { get }
    init()
    /// `offset` is the byte offset of the line within `file`.
    mutating func parse(line: JSONValue, offset: Int, file: String) -> [UsageRecord]
}

public enum ISOTime {
    /// Parses `2026-10-12T13:45:12.345Z` / `…+08:00` into unix seconds. No allocations, no formatter.
    public static func parse(_ text: String) -> Double? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                guard index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 else { return nil }
                value = value * 10 + Int(bytes[index] - 48)
            }
            return value
        }
        guard let year = number(0..<4), bytes[4] == 45, let month = number(5..<7), bytes[7] == 45,
              let day = number(8..<10), bytes[10] == 84 || bytes[10] == 32, let hour = number(11..<13), bytes[13] == 58,
              let minute = number(14..<16), bytes[16] == 58, let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 62 else { return nil }
        var index = 19
        var fraction = 0.0
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            var scale = 0.1
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                fraction += Double(bytes[index] - 48) * scale
                scale /= 10
                index += 1
            }
        }
        var offsetSeconds = 0
        if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
            let sign = bytes[index] == 43 ? 1 : -1
            guard let hours = number((index + 1)..<(index + 3)) else { return nil }
            let minutesStart = index + 3 < bytes.count && bytes[index + 3] == 58 ? index + 4 : index + 3
            let minutes = number(minutesStart..<(minutesStart + 2)) ?? 0
            offsetSeconds = sign * (hours * 3600 + minutes * 60)
        }
        // Days since the epoch (proleptic Gregorian), then seconds.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return Double(days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds) + fraction
    }

    /// Accepts ISO strings, unix seconds, or unix milliseconds.
    public static func flexible(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if let text = value.stringValue { return parse(text) ?? Double(text).map(normalize) }
        return value.doubleValue.map(normalize)
    }

    private static func normalize(_ number: Double) -> Double { number > 100_000_000_000 ? number / 1000 : number }
}

/// Claude Code: `~/.claude/projects/**/*.jsonl`, one assistant message per line.
public struct ClaudeUsageParser: UsageParser {
    public static let provider = "claude"
    public static let version = 1
    public static let needles = [Data("\"usage\"".utf8)]

    public init() {}

    public mutating func parse(line: JSONValue, offset: Int, file: String) -> [UsageRecord] {
        guard line["type"]?.stringValue == "assistant", let message = line["message"], let usage = message["usage"],
              usage.objectValue != nil else { return [] }
        let model = message["model"]?.stringValue ?? "unknown"
        guard model != "<synthetic>" else { return [] }
        let input = usage["input_tokens"]?.intValue ?? 0
        let output = usage["output_tokens"]?.intValue ?? 0
        let cacheRead = usage["cache_read_input_tokens"]?.intValue ?? 0
        let cacheWrite = usage["cache_creation_input_tokens"]?.intValue ?? 0
        guard input + output + cacheRead + cacheWrite > 0 else { return [] }

        // A resumed session copies earlier messages into a new file, and a
        // streaming message is logged once per content block: the message and
        // request ids, not the file position, say what is the same message.
        let identity: String
        if let id = message["id"]?.stringValue, !id.isEmpty {
            identity = UsageRecord.identity("claude", id, line["requestId"]?.stringValue ?? "")
        } else {
            identity = UsageRecord.identity("claude", file, String(offset))
        }
        return [UsageRecord(identityKey: identity,
                            timestamp: ISOTime.flexible(line["timestamp"]) ?? Date().timeIntervalSince1970,
                            agent: "claude", model: model,
                            session: line["sessionId"]?.stringValue, project: line["cwd"]?.stringValue,
                            input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite)]
    }
}

/// Codex CLI rollouts: `~/.codex/sessions/**`. Token counts arrive as events
/// that refer back to the session and model announced earlier in the file.
public struct CodexUsageParser: UsageParser {
    public static let provider = "codex"
    public static let version = 1
    public static let needles = [Data("token_count".utf8), Data("turn_context".utf8), Data("session_meta".utf8)]

    private var session: String?
    private var project: String?
    private var model = "unknown"
    private var lastTotal: (input: Int, cached: Int, output: Int, reasoning: Int)?

    public init() {}

    public mutating func parse(line: JSONValue, offset: Int, file: String) -> [UsageRecord] {
        let payload = line["payload"] ?? line
        switch line["type"]?.stringValue {
        case "session_meta":
            session = payload["id"]?.stringValue ?? session
            project = payload["cwd"]?.stringValue ?? project
            if let model = payload["model"]?.stringValue { self.model = model }
            return []
        case "turn_context":
            if let model = payload["model"]?.stringValue { self.model = model }
            project = payload["cwd"]?.stringValue ?? project
            return []
        case "event_msg":
            guard payload["type"]?.stringValue == "token_count", let info = payload["info"], info.objectValue != nil else { return [] }
            func counts(_ value: JSONValue?) -> (input: Int, cached: Int, output: Int, reasoning: Int)? {
                guard let value, value.objectValue != nil else { return nil }
                return (value["input_tokens"]?.intValue ?? 0, value["cached_input_tokens"]?.intValue ?? 0,
                        value["output_tokens"]?.intValue ?? 0, value["reasoning_output_tokens"]?.intValue ?? 0)
            }
            let total = counts(info["total_token_usage"])
            var delta = counts(info["last_token_usage"])
            if delta == nil, let total {
                // Older builds only log running totals.
                let previous = lastTotal ?? (0, 0, 0, 0)
                delta = (max(0, total.input - previous.input), max(0, total.cached - previous.cached),
                         max(0, total.output - previous.output), max(0, total.reasoning - previous.reasoning))
            }
            if let total { lastTotal = total }
            guard let delta, delta.input + delta.output > 0 else { return [] }

            // `input_tokens` includes the cached part; keep the two apart so each is priced once.
            let cached = min(delta.cached, delta.input)
            let identity: String
            if let session, let total {
                // The running total is unique within a session and survives the
                // file being moved to the archive directory.
                identity = UsageRecord.identity("codex", session, String(total.input), String(total.output))
            } else {
                identity = UsageRecord.identity("codex", file, String(offset))
            }
            return [UsageRecord(identityKey: identity,
                                timestamp: ISOTime.flexible(line["timestamp"]) ?? Date().timeIntervalSince1970,
                                agent: "codex", model: model, session: session, project: project,
                                input: delta.input - cached, output: delta.output, cacheRead: cached, cacheWrite: 0,
                                reasoning: delta.reasoning)]
        default:
            return []
        }
    }
}

/// OpenCode-family JSONL (`transcript.jsonl`, `wire.jsonl`, `events-recent.jsonl`).
/// These files are less uniform, so this parser looks for a token block in the
/// usual places and takes what it can identify. Best effort by design.
public struct OpenCodeUsageParser: UsageParser {
    public static let provider = "opencode"
    public static let version = 1
    public static let needles = [Data("\"tokens\"".utf8), Data("\"usage\"".utf8)]

    public init() {}

    public mutating func parse(line: JSONValue, offset: Int, file: String) -> [UsageRecord] {
        // The message object may be the line itself or sit one or two levels down.
        let containers: [JSONValue] = [
            line, line["message"], line["info"], line["data"], line["payload"],
            line.at("properties", "info"), line.at("properties", "message"), line.at("data", "message"), line.at("payload", "message"),
        ].compactMap { $0 }
        for container in containers {
            guard let record = record(from: container, line: line, offset: offset, file: file) else { continue }
            return [record]
        }
        return []
    }

    private func record(from object: JSONValue, line: JSONValue, offset: Int, file: String) -> UsageRecord? {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0, reasoning = 0
        if let tokens = object["tokens"], tokens.objectValue != nil {
            input = tokens["input"]?.intValue ?? 0
            output = tokens["output"]?.intValue ?? 0
            reasoning = tokens["reasoning"]?.intValue ?? 0
            cacheRead = tokens.at("cache", "read")?.intValue ?? 0
            cacheWrite = tokens.at("cache", "write")?.intValue ?? 0
        } else if let usage = object["usage"], usage.objectValue != nil {
            if let prompt = usage["prompt_tokens"]?.intValue {
                // OpenAI style: prompt tokens include the cached ones.
                cacheRead = min(usage.at("prompt_tokens_details", "cached_tokens")?.intValue ?? 0, prompt)
                input = prompt - cacheRead
                output = usage["completion_tokens"]?.intValue ?? 0
                reasoning = usage.at("completion_tokens_details", "reasoning_tokens")?.intValue ?? 0
            } else {
                input = usage["input_tokens"]?.intValue ?? 0
                output = usage["output_tokens"]?.intValue ?? 0
                cacheRead = usage["cache_read_input_tokens"]?.intValue ?? 0
                cacheWrite = usage["cache_creation_input_tokens"]?.intValue ?? 0
            }
        } else {
            return nil
        }
        guard input + output + cacheRead + cacheWrite > 0 else { return nil }
        if let role = object["role"]?.stringValue, role != "assistant" { return nil }

        func first(_ keys: String...) -> JSONValue? {
            for key in keys {
                if let value = object[key] ?? line[key], !value.isNull { return value }
            }
            return nil
        }
        let model = first("modelID", "model_id", "model")?.stringValue ?? "unknown"
        let identity: String
        if let id = first("id", "messageID", "message_id")?.stringValue, !id.isEmpty {
            identity = UsageRecord.identity("opencode", id)
        } else {
            identity = UsageRecord.identity("opencode", file, String(offset))
        }
        let time = ISOTime.flexible(object.at("time", "completed")) ?? ISOTime.flexible(object.at("time", "created"))
            ?? ISOTime.flexible(first("timestamp", "ts", "time")) ?? Date().timeIntervalSince1970
        return UsageRecord(identityKey: identity, timestamp: time, agent: "opencode", model: model,
                           session: first("sessionID", "session_id")?.stringValue,
                           project: (object.at("path", "cwd") ?? first("cwd", "directory"))?.stringValue,
                           input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, reasoning: reasoning,
                           reportedCost: first("cost")?.doubleValue.flatMap { $0 > 0 ? $0 : nil })
    }
}
