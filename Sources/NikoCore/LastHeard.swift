import Foundation

/// When each agent's hooks last reached the app, kept between launches (agent id → time), so that
/// an agent heard from yesterday is not said to have sent nothing since the app started.
public enum LastHeard {
    public static func file(_ paths: NikoPaths) -> URL { paths.cache.appendingPathComponent("last-heard.json") }

    public static func load(paths: NikoPaths) -> [String: Date] {
        guard let data = try? Data(contentsOf: file(paths)), let object = (try? JSONValue.parse(data))?.objectValue else { return [:] }
        var out: [String: Date] = [:]
        for member in object.members {
            if let seconds = member.value.doubleValue, seconds > 0 { out[member.key] = Date(timeIntervalSince1970: seconds) }
        }
        return out
    }

    public static func save(_ heard: [String: Date], paths: NikoPaths) {
        var object = JSONObject()
        for (agent, date) in heard { object[agent] = .number(String(date.timeIntervalSince1970)) }
        AtomicFile.write(JSONValue.object(object).serializedData(.compact), to: file(paths).path, mode: 0o600)
    }
}
