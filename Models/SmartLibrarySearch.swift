import Foundation

struct SmartLibrarySearch {
    static func rank(_ tracks: [LocalTrack], query: String) -> [LocalTrack] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tracks }
        let normalizedQuery = normalize(q)
        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))

        return tracks.compactMap { track in
            let fields: [(String, Double)] = [
                (track.title, 100),
                (track.artist, 75),
                (track.album, 60),
                (track.genre, 40),
                (track.url.deletingPathExtension().lastPathComponent, 30)
            ]
            var best = 0.0
            for (field, weight) in fields {
                let value = normalize(field)
                if value == normalizedQuery { best = max(best, weight + 40) }
                else if value.hasPrefix(normalizedQuery) { best = max(best, weight + 25) }
                else if value.contains(normalizedQuery) { best = max(best, weight + 15) }
                let tokens = Set(value.split(separator: " ").map(String.init))
                let overlap = queryTokens.intersection(tokens).count
                if !queryTokens.isEmpty { best = max(best, weight * Double(overlap) / Double(queryTokens.count)) }
                if normalizedQuery.count >= 3 {
                    let distance = levenshtein(normalizedQuery, value)
                    let maxLen = max(normalizedQuery.count, value.count)
                    if maxLen > 0 {
                        let similarity = 1.0 - Double(distance) / Double(maxLen)
                        if similarity >= 0.72 { best = max(best, weight * similarity) }
                    }
                }
            }
            return best > 0 ? (best, track) : nil
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[_-]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(prev[j] + 1, current[j-1] + 1, prev[j-1] + (a[i-1] == b[j-1] ? 0 : 1))
            }
            prev = current
        }
        return prev[b.count]
    }
}
