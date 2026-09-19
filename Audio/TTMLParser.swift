import Foundation

/// Parses Apple Music-style TTML lyric files.
///
/// The parser intentionally ignores TTML metadata and only turns timed
/// paragraph/span content into LyricLine/LyricWord models. It supports both
/// line-timed TTML and Apple-style word-timed TTML (`itunes:timing="Word"`).
struct TTMLParser {
    static func parse(content: String) -> [LyricLine] {
        guard let data = content.data(using: .utf8) else { return [] }

        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse(), !delegate.paragraphs.isEmpty else {
            return []
        }

        return delegate.paragraphs
            .compactMap { $0.makeLyricLine() }
            .sorted { $0.time < $1.time }
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var paragraphs: [Paragraph] = []
        private var currentParagraph: Paragraph?
        private var currentSpan: Span?
        private var elementStack: [String] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(elementName)
            elementStack.append(name)

            if name == "p" {
                currentParagraph = Paragraph(
                    start: parseTime(attributeDict["begin"]),
                    end: parseTime(attributeDict["end"]),
                    duration: parseTime(attributeDict["dur"])
                )
                currentSpan = nil
                return
            }

            guard name == "span", currentParagraph != nil else { return }

            let span = Span(
                start: parseTime(attributeDict["begin"]),
                end: parseTime(attributeDict["end"]),
                duration: parseTime(attributeDict["dur"])
            )
            currentSpan = span
        }

        func parser(
            _ parser: XMLParser,
            foundCharacters string: String
        ) {
            guard currentParagraph != nil else { return }

            if let currentSpan {
                currentSpan.text += string
            } else {
                currentParagraph?.directText += string
            }
        }

        func parser(
            _ parser: XMLParser,
            foundIgnorableWhitespace whitespace: String
        ) {
            // XMLParser may classify indentation as ignorable whitespace.
            // It is not lyric content and is therefore intentionally ignored.
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(elementName)

            if name == "span", let span = currentSpan {
                currentParagraph?.spans.append(span)
                currentSpan = nil
            } else if name == "p", let paragraph = currentParagraph {
                paragraphs.append(paragraph)
                currentParagraph = nil
                currentSpan = nil
            }

            _ = elementStack.popLast()
        }

        private func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }
    }

    private final class Paragraph {
        var start: TimeInterval?
        var end: TimeInterval?
        var duration: TimeInterval?
        var directText = ""
        var spans: [Span] = []

        init(start: TimeInterval?, end: TimeInterval?, duration: TimeInterval?) {
            self.start = start
            self.end = end
            self.duration = duration
        }

        func makeLyricLine() -> LyricLine? {
            let timedSpans = spans.compactMap { span -> TimedSpan? in
                guard let start = span.start else { return nil }
                let text = normalizeInlineText(span.text)
                guard !text.isEmpty else { return nil }

                let resolvedEnd: TimeInterval
                if let end = span.end {
                    resolvedEnd = max(start, end)
                } else if let duration = span.duration {
                    resolvedEnd = start + max(0, duration)
                } else {
                    resolvedEnd = start
                }

                return TimedSpan(
                    text: text,
                    start: start,
                    end: resolvedEnd
                )
            }

            let paragraphStart = start
                ?? timedSpans.first?.start
                ?? 0

            let paragraphEnd: TimeInterval = {
                if let end {
                    return max(paragraphStart, end)
                }
                if let duration {
                    return paragraphStart + max(0, duration)
                }
                return timedSpans.last?.end ?? paragraphStart
            }()

            let text: String
            if !timedSpans.isEmpty {
                text = joinTimedText(timedSpans.map(\.text))
            } else {
                text = normalizeBlockText(directText)
            }

            guard !text.isEmpty else { return nil }

            let words = timedSpans.map {
                LyricWord(
                    text: $0.text,
                    startTime: $0.start,
                    endTime: $0.end
                )
            }

            return LyricLine(
                time: paragraphStart,
                text: text,
                endTime: paragraphEnd,
                words: words
            )
        }
    }

    private final class Span {
        let start: TimeInterval?
        let end: TimeInterval?
        let duration: TimeInterval?
        var text = ""

        init(start: TimeInterval?, end: TimeInterval?, duration: TimeInterval?) {
            self.start = start
            self.end = end
            self.duration = duration
        }
    }

    private struct TimedSpan {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    private static func normalizeBlockText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeInlineText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func joinTimedText(_ pieces: [String]) -> String {
        var result = ""

        for piece in pieces {
            guard !piece.isEmpty else { continue }

            if result.isEmpty {
                result = piece
                continue
            }

            let needsSpace =
                !result.last!.isWhitespace &&
                !piece.first!.isWhitespace &&
                !isPunctuation(piece.first!)

            result += needsSpace ? " " + piece : piece
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    private static func parseTime(_ value: String?) -> TimeInterval? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if let seconds = Double(raw) {
            return max(0, seconds)
        }

        let lower = raw.lowercased()
        if lower.hasSuffix("ms"),
           let number = Double(lower.dropLast(2)) {
            return max(0, number / 1000.0)
        }

        if lower.hasSuffix("s"),
           let number = Double(lower.dropLast()) {
            return max(0, number)
        }

        let parts = lower.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        if parts.count == 2,
           let minutes = Double(parts[0]),
           let seconds = Double(parts[1]) {
            return max(0, minutes * 60 + seconds)
        }

        if parts.count == 3,
           let hours = Double(parts[0]),
           let minutes = Double(parts[1]),
           let seconds = Double(parts[2]) {
            return max(0, hours * 3600 + minutes * 60 + seconds)
        }

        return nil
    }
}
