import Foundation

/// Per-token prices from the vendored LiteLLM snapshot (PROTOCOLS §6.2).
/// Costs computed from it are estimates: flat per-token rates, no tiering.
public struct Pricing: Sendable {
    public struct Rate: Sendable, Equatable {
        public var input: Double
        public var output: Double
        public var cacheRead: Double?
        public var cacheWrite: Double?
    }

    public static let refreshURL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    static let providerPrefixes = ["anthropic/", "openai/", "gemini/", "xai/", "deepseek/", "moonshot/", "mistral/", "dashscope/"]

    public private(set) var rates: [String: Rate]
    public private(set) var source: String

    public init(rates: [String: Rate] = [:], source: String = "none") {
        self.rates = rates
        self.source = source
    }

    public var isEmpty: Bool { rates.isEmpty }

    /// Reads LiteLLM's JSON (full or pruned): `{model: {input_cost_per_token, …}}`.
    public static func parse(_ data: Data, source: String) -> Pricing? {
        guard let object = (try? JSONValue.parse(data))?.objectValue else { return nil }
        var rates: [String: Rate] = [:]
        for member in object.members {
            guard let input = member.value["input_cost_per_token"]?.doubleValue,
                  let output = member.value["output_cost_per_token"]?.doubleValue,
                  input >= 0, output >= 0, input < 1, output < 1 else { continue }
            rates[member.key.lowercased()] = Rate(input: input, output: output,
                                                  cacheRead: member.value["cache_read_input_token_cost"]?.doubleValue,
                                                  cacheWrite: member.value["cache_creation_input_token_cost"]?.doubleValue)
        }
        return rates.isEmpty ? nil : Pricing(rates: rates, source: source)
    }

    /// Reduces a full LiteLLM table to the fields we use, for the local cache.
    public static func prune(_ data: Data) -> Data? {
        guard let object = (try? JSONValue.parse(data))?.objectValue else { return nil }
        var out = JSONObject()
        for member in object.members {
            guard member.value["input_cost_per_token"]?.doubleValue != nil,
                  ["chat", "responses", "completion"].contains(member.value["mode"]?.stringValue ?? "chat") else { continue }
            var entry = JSONObject()
            for key in ["input_cost_per_token", "output_cost_per_token", "cache_read_input_token_cost",
                        "cache_creation_input_token_cost", "litellm_provider"] {
                if let value = member.value[key] { entry[key] = value }
            }
            out[member.key] = .object(entry)
        }
        return out.isEmpty ? nil : JSONValue.object(out).serializedData(.compact)
    }

    /// Lookup order: refreshed cache → bundled snapshot → repository copy (dev runs) → nothing.
    public static func load(paths: NikoPaths, bundle: Bundle = .main, extraCandidates: [URL] = []) -> Pricing {
        var candidates: [(URL, String)] = [(paths.pricingCache, "refreshed")]
        if let bundled = bundle.url(forResource: "pricing", withExtension: "json") { candidates.append((bundled, "bundled")) }
        if let executable = bundle.executableURL {
            // `swift run`: walk up from .build/<triple>/<config>/ to the checkout.
            var directory = executable.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append((directory.appendingPathComponent("Assets/pricing.json"), "repository"))
                directory = directory.deletingLastPathComponent()
            }
        }
        candidates.append(contentsOf: extraCandidates.map { ($0, "explicit") })
        for (url, source) in candidates {
            if let data = try? Data(contentsOf: url), let pricing = parse(data, source: source) { return pricing }
        }
        return Pricing()
    }

    public func rate(for model: String) -> Rate? {
        let name = model.lowercased()
        if let hit = rates[name] { return hit }
        var candidates: [String] = []
        if let slash = name.lastIndex(of: "/") { candidates.append(String(name[name.index(after: slash)...])) }
        let bare = candidates.first ?? name
        candidates.append(contentsOf: Pricing.providerPrefixes.map { $0 + bare })
        // claude-x-20251101 / gpt-x-2025-08-07 / model@20250101 / model-latest
        var undated = bare
        for pattern in [#"[-@]\d{8}$"#, #"-\d{4}-\d{2}-\d{2}$"#, #"-latest$"#, #"\[[^\]]*\]$"#] {
            undated = undated.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        if undated != bare {
            candidates.append(undated)
            candidates.append(contentsOf: Pricing.providerPrefixes.map { $0 + undated })
        }
        for candidate in candidates {
            if let hit = rates[candidate] { return hit }
        }
        // Last resort: the longest known name that the model name starts with
        // (e.g. a dated or suffixed variant of a model we do know).
        var best: (key: String, rate: Rate)?
        for (key, rate) in rates where key.count >= 8 && undated.hasPrefix(key) {
            if key.count > (best?.key.count ?? 0) { best = (key, rate) }
        }
        return best?.rate
    }

    /// Estimated cost in USD, or nil when the model is not in the table.
    public func cost(of record: UsageRecord) -> Double? {
        guard let rate = rate(for: record.model) else { return nil }
        return Double(record.input) * rate.input
            + Double(record.output) * rate.output
            + Double(record.cacheRead) * (rate.cacheRead ?? rate.input)
            + Double(record.cacheWrite) * (rate.cacheWrite ?? rate.input)
    }
}

/// The one network request this app can make on its own, and only when the
/// user has switched it on (SPEC §5).
public enum PricingRefresher {
    public enum Outcome: Sendable, Equatable {
        case updated(models: Int)
        case failed(String)
    }

    public static let interval: TimeInterval = 7 * 24 * 3600

    public static func isDue(paths: NikoPaths, now: Date = Date()) -> Bool {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: paths.pricingCache.path))?[.modificationDate] as? Date else {
            return true
        }
        return now.timeIntervalSince(modified) > interval
    }

    /// Downloads, validates and atomically replaces the cached table.
    public static func refresh(paths: NikoPaths, session: URLSession = .shared) async -> Outcome {
        guard let url = URL(string: Pricing.refreshURL) else { return .failed("bad URL") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed("unexpected response") }
            guard data.count < 16 << 20, let pruned = Pricing.prune(data),
                  let pricing = Pricing.parse(pruned, source: "refreshed"), pricing.rates.count > 50 else {
                return .failed("the downloaded table did not look right; keeping the current one")
            }
            try SecureDirectory.ensure(paths.root)
            try SecureDirectory.ensure(paths.cache)
            guard AtomicFile.write(pruned, to: paths.pricingCache.path, mode: 0o600) else { return .failed("could not write the cache") }
            return .updated(models: pricing.rates.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
