import Foundation

/// Scrubs anything credential-shaped before text reaches a log file or a
/// diagnostics export (SPEC §5). Deliberately over-eager: a false positive
/// costs a `[REDACTED]`, a false negative costs a leaked key.
public enum Redactor {
    public static let placeholder = "[REDACTED]"

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static func rule(_ pattern: String, _ template: String, _ options: NSRegularExpression.Options = []) -> Rule? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return Rule(regex: regex, template: template)
    }

    /// NSRegularExpression is immutable and documented thread-safe; the box
    /// says so to the compiler on SDKs where it is not yet annotated Sendable.
    private final class RuleSet: @unchecked Sendable {
        let rules: [Rule]
        init(_ rules: [Rule?]) { self.rules = rules.compactMap { $0 } }
    }

    private static let ruleSet = RuleSet([
        // Authorization: Bearer abc / authorization=Basic xyz
        rule(#"\b((?:proxy-)?authorization)(["']?\s*[:=]\s*["']?)(?:(?:bearer|basic|token)\s+)?[^\s"',;]+"#,
             "$1$2\(placeholder)", [.caseInsensitive]),
        rule(#"\bbearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "Bearer \(placeholder)", [.caseInsensitive]),
        // key = value / "key": "value" for secret-sounding keys
        rule(#"(["']?[A-Za-z0-9_.-]*(?:api[_-]?key|apikey|secret|token|passwd|password|credential|cookie|session[_-]?key|licen[sc]e|private[_-]?key|access[_-]?key)[A-Za-z0-9_.-]*["']?\s*[:=]\s*)("[^"]*"|'[^']*'|[^\s,;}&]+)"#,
             "$1\(placeholder)", [.caseInsensitive]),
        // Well-known token prefixes
        rule(#"\b(?:sk-ant-[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|glpat-[A-Za-z0-9_-]{16,}|npm_[A-Za-z0-9]{30,}|hf_[A-Za-z0-9]{30,})"#,
             placeholder),
        // JWT
        rule(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}"#, placeholder),
        // License-key shapes: XXXX-XXXX-XXXX-XXXX
        rule(#"\b[A-Z0-9]{4,6}(?:-[A-Z0-9]{4,6}){3,}\b"#, placeholder),
        // Long opaque blobs (hex digests, base64 without slashes)
        rule(#"\b[A-Za-z0-9+_-]{40,}={0,2}"#, placeholder),
    ])

    public static func redact(_ text: String, home: String? = nil) -> String {
        var out = text
        for rule in ruleSet.rules {
            let range = NSRange(out.startIndex..., in: out)
            out = rule.regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: rule.template)
        }
        let homePath = home ?? NikoPaths.userHome().path
        if homePath.count > 1 {
            out = out.replacingOccurrences(of: homePath, with: "~")
        }
        return out
    }
}
