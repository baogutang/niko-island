import Foundation

/// How far an agent is through the list of steps it wrote for itself.
public struct TaskProgress: Sendable, Equatable {
    public var done: Int
    public var total: Int
    /// The step being worked on, in the agent's words.
    public var current: String?

    public init(done: Int, total: Int, current: String? = nil) {
        self.done = done
        self.total = total
        self.current = current
    }

    public var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    public var isComplete: Bool { total > 0 && done >= total }

    /// A list of `{status, content | step | subject, activeForm}` items: the
    /// shape Claude Code's `TodoWrite`, Codex's `update_plan` and ZCode's todo
    /// table all share, give or take the name of the text field.
    public static func from(items: [JSONValue]) -> TaskProgress? {
        var done = 0, total = 0
        var current: String?
        for item in items {
            guard item.objectValue != nil else { continue }
            let status = (item["status"]?.stringValue ?? "").lowercased()
            if status == "cancelled" || status == "deleted" { continue }
            total += 1
            if status == "completed" || status == "done" { done += 1 }
            if current == nil, status == "in_progress" || status == "in-progress" {
                current = (item["activeForm"] ?? item["content"] ?? item["step"] ?? item["subject"])?.stringValue
            }
        }
        guard total > 0 else { return nil }
        return TaskProgress(done: done, total: total, current: current.map { Activity.oneLine($0, limit: 96) })
    }

    /// From a tool call that carries the whole list.
    public static func from(tool name: String?, input: JSONValue?) -> TaskProgress? {
        switch name {
        case "TodoWrite", "todo_write", "todowrite": return (input?["todos"]?.arrayValue).flatMap(from(items:))
        case "update_plan": return (input?["plan"]?.arrayValue).flatMap(from(items:))
        default: return nil
        }
    }

    /// Claude Code's newer task tools keep one small file per task in
    /// `~/.claude/tasks/<session id>/`. Counted, never changed.
    public static func claudeTasks(home: URL, sessionID: String) -> TaskProgress? {
        let directory = home.appendingPathComponent(".claude/tasks").appendingPathComponent(sessionID)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil), !files.isEmpty else { return nil }
        let items = files.filter { $0.pathExtension == "json" }.prefix(200).compactMap { file -> JSONValue? in
            guard let data = try? Data(contentsOf: file), data.count < 64_000 else { return nil }
            return try? JSONValue.parse(data)
        }
        return from(items: Array(items))
    }
}

/// The branch a working directory is on, read from `.git` without running git.
public enum GitInfo {
    /// `nil` outside a repository, or on a detached HEAD.
    public static func branch(cwd: String) -> String? {
        var directory = URL(fileURLWithPath: cwd).standardizedFileURL
        let manager = FileManager.default
        for _ in 0..<24 {
            let dotGit = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                var head = dotGit.appendingPathComponent("HEAD")
                if !isDirectory.boolValue {
                    // A worktree or a submodule: `.git` is a file that says where the real one is.
                    guard let pointer = try? String(contentsOf: dotGit, encoding: .utf8),
                          let line = pointer.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
                    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    let base = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
                    head = base.appendingPathComponent("HEAD")
                }
                guard let data = try? Data(contentsOf: head), data.count < 4096, let text = String(data: data, encoding: .utf8) else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("ref:") else { return nil }
                let reference = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                let name = reference.hasPrefix("refs/heads/") ? String(reference.dropFirst("refs/heads/".count)) : reference
                return name.isEmpty ? nil : name
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
        return nil
    }
}

/// A model's name as an agent writes it, shortened to what fits on a chip.
public enum ModelLabel {
    public static func short(_ model: String) -> String {
        var name = model
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        for prefix in ["claude-", "models/"] where name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        // A trailing date stamp says nothing a person needs: claude-sonnet-5-20260101 → sonnet-5.
        if let range = name.range(of: #"-20\d{6}$"#, options: .regularExpression) { name.removeSubrange(range) }
        return name
    }
}
