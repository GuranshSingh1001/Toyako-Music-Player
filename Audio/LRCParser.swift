import Foundation

struct LRCParser {
    static func parse(content: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{2,}):(\d{2}(?:\.\d{1,3})?)\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsContent = content as NSString

        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let minStr = nsContent.substring(with: match.range(at: 1))
            let secStr = nsContent.substring(with: match.range(at: 2))
            let text = nsContent.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)

            if let mins = Double(minStr), let secs = Double(secStr), !text.isEmpty {
                lines.append(LyricLine(time: (mins * 60.0) + secs, text: text))
            }
        }

        if lines.isEmpty {
            let splitLines = content.components(separatedBy: .newlines)
            var offset: TimeInterval = 0
            for line in splitLines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(LyricLine(time: offset, text: line))
                offset += 4.0
            }
        }

        return lines.sorted { $0.time < $1.time }
    }
}
