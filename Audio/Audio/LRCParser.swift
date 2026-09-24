import Foundation

struct LRCParser {
    static func parse(content: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{1,3}):(\d{2}(?:\.\d{1,6})?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in content.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let matches = regex.matches(
                in: rawLine,
                options: [],
                range: NSRange(location: 0, length: nsLine.length)
            )
            guard !matches.isEmpty else { continue }

            let lastTimeTagEnd = matches.reduce(0) { max($0, NSMaxRange($1.range)) }
            let text = nsLine
                .substring(from: lastTimeTagEnd)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            for match in matches {
                guard match.numberOfRanges == 3 else { continue }
                let minute = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let second = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let timestamp = minute * 60 + second
                lines.append(LyricLine(time: max(0, timestamp), text: text))
            }
        }

        if lines.isEmpty {
            var offset: TimeInterval = 0
            for line in content.components(separatedBy: .newlines) {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                lines.append(LyricLine(time: offset, text: clean))
                offset += 4.0
            }
        }

        return lines.sorted {
            if $0.time == $1.time { return $0.id.uuidString < $1.id.uuidString }
            return $0.time < $1.time
        }
    }
}
