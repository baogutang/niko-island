import Foundation

/// Matching typed letters against session names, for the quick switcher.
///
/// Every word typed has to be found in one of the fields. A word found whole
/// scores most, more at the start of the text or of one of its words; letters
/// found in order but apart score less, more when they start words or run
/// together ("nkis" finds "niko-island"). Case and accents are ignored.
public enum QuickFind {
    /// The best score of the query over the fields (the first field counts a little more), or nil.
    public static func score(_ query: String, fields: [String]) -> Int? {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return 0 }
        let folded = fields.map(fold)
        var total = 0
        for word in words {
            var best: Int?
            for (index, field) in folded.enumerated() {
                guard let value = score(word: word, in: field) else { continue }
                let weighted = value + (index == 0 ? 6 : 0)
                best = max(best ?? weighted, weighted)
            }
            guard let best else { return nil }
            total += best
        }
        return total
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func isBoundary(_ previous: Character?) -> Bool {
        guard let previous else { return true }
        return !(previous.isLetter || previous.isNumber) || previous.isWhitespace
    }

    /// One word (already folded) against one field (already folded).
    static func score(word: String, in text: String) -> Int? {
        guard !word.isEmpty, !text.isEmpty else { return nil }
        let characters = Array(text)
        if let range = text.range(of: word) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            var value = 100 - min(start, 30)
            if start == 0 { value += 60 } else if isBoundary(characters[start - 1]) { value += 40 }
            if range.upperBound == text.endIndex { value += 5 }
            return value
        }
        // Letters in order, possibly apart.
        let wanted = Array(word)
        var value = 10, at = 0, previousMatch = -2
        for (index, character) in characters.enumerated() where at < wanted.count && character == wanted[at] {
            if index == previousMatch + 1 { value += 5 }
            if isBoundary(index > 0 ? characters[index - 1] : nil) { value += 8 }
            previousMatch = index
            at += 1
        }
        guard at == wanted.count else { return nil }
        return value
    }
}
