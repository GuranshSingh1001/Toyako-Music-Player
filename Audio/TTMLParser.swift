import Foundation

struct TTMLParser {

    static func parse(content: String) -> [LyricLine] {
        guard let data = content.data(using: .utf8) else {
            return []
        }

        let delegate = ParserDelegate()

        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return []
        }

        return delegate.paragraphs
            .compactMap { $0.makeLyricLine() }
            .sorted { $0.time < $1.time }
    }

    // MARK: - XML Delegate

    private final class ParserDelegate: NSObject, XMLParserDelegate {

        var paragraphs: [Paragraph] = []

        private var currentParagraph: Paragraph?
        private var currentSpan: Span?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {

            let name = localName(elementName)

            if name == "p" {
                currentParagraph = Paragraph(
                    start: parseTime(attributeDict["begin"]),
                    end: parseTime(attributeDict["end"]),
                    duration: parseTime(attributeDict["dur"])
                )

                currentSpan = nil
                return
            }

            guard name == "span",
                  currentParagraph != nil
            else {
                return
            }

            currentSpan = Span(
                start: parseTime(attributeDict["begin"]),
                end: parseTime(attributeDict["end"]),
                duration: parseTime(attributeDict["dur"])
            )
        }

        func parser(
            _ parser: XMLParser,
            foundCharacters string: String
        ) {

            guard currentParagraph != nil else {
                return
            }

            if let currentSpan {
                currentSpan.text += string
            } else {
                currentParagraph?.directText += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {

            let name = localName(elementName)

            if name == "span" {
                if let span = currentSpan {
                    currentParagraph?.spans.append(span)
                }

                currentSpan = nil

            } else if name == "p" {

                if let paragraph = currentParagraph {
                    paragraphs.append(paragraph)
                }

                currentParagraph = nil
                currentSpan = nil
            }
        }

        private func localName(_ name: String) -> String {
            if let last = name.split(separator: ":").last {
                return String(last)
            }

            return name
        }

        private func parseTime(_ value: String?) -> TimeInterval? {

            guard let value else {
                return nil
            }

            let raw = value
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard !raw.isEmpty else {
                return nil
            }

            // Plain seconds:
            // 12.45
            if let seconds = Double(raw) {
                return max(0, seconds)
            }

            let lower = raw.lowercased()

            // milliseconds:
            // 1250ms
            if lower.hasSuffix("ms") {
                let number = String(
                    lower.dropLast(2)
                )

                if let value = Double(number) {
                    return max(0, value / 1000.0)
                }
            }

            // seconds:
            // 12.45s
            if lower.hasSuffix("s") {
                let number = String(
                    lower.dropLast()
                )

                if let value = Double(number) {
                    return max(0, value)
                }
            }

            // MM:SS.mmm
            // HH:MM:SS.mmm
            let components = lower.split(
                separator: ":"
            )

            if components.count == 2,
               let minutes = Double(components[0]),
               let seconds = Double(components[1]) {

                return max(
                    0,
                    minutes * 60 + seconds
                )
            }

            if components.count == 3,
               let hours = Double(components[0]),
               let minutes = Double(components[1]),
               let seconds = Double(components[2]) {

                return max(
                    0,
                    hours * 3600 +
                    minutes * 60 +
                    seconds
                )
            }

            return nil
        }
    }

    // MARK: - Paragraph

    private final class Paragraph {

        var start: TimeInterval?
        var end: TimeInterval?
        var duration: TimeInterval?

        var directText = ""
        var spans: [Span] = []

        init(
            start: TimeInterval?,
            end: TimeInterval?,
            duration: TimeInterval?
        ) {
            self.start = start
            self.end = end
            self.duration = duration
        }

        func makeLyricLine() -> LyricLine? {

            let timedSpans: [TimedSpan] = spans.compactMap {
                span in

                guard let start = span.start else {
                    return nil
                }

                let text = normalize(
                    span.text
                )

                guard !text.isEmpty else {
                    return nil
                }

                let resolvedEnd: TimeInterval

                if let end = span.end {
                    resolvedEnd = max(
                        start,
                        end
                    )
                } else if let duration = span.duration {
                    resolvedEnd = start + max(
                        0,
                        duration
                    )
                } else {
                    resolvedEnd = start
                }

                return TimedSpan(
                    text: text,
                    start: start,
                    end: resolvedEnd
                )
            }

            let lineStart =
                start ??
                timedSpans.first?.start ??
                0

            let lineEnd: TimeInterval

            if let end {
                lineEnd = max(
                    lineStart,
                    end
                )
            } else if let duration {
                lineEnd = lineStart + max(
                    0,
                    duration
                )
            } else {
                lineEnd =
                    timedSpans.last?.end ??
                    lineStart
            }

            let text: String

            if timedSpans.isEmpty {
                text = normalize(
                    directText
                )
            } else {
                text = join(
                    timedSpans.map(\.text)
                )
            }

            guard !text.isEmpty else {
                return nil
            }

            let words = timedSpans.map {
                LyricWord(
                    text: $0.text,
                    startTime: $0.start,
                    endTime: $0.end
                )
            }

            return LyricLine(
                time: lineStart,
                text: text,
                endTime: lineEnd,
                words: words
            )
        }
    }

    // MARK: - Span

    private final class Span {

        let start: TimeInterval?
        let end: TimeInterval?
        let duration: TimeInterval?

        var text = ""

        init(
            start: TimeInterval?,
            end: TimeInterval?,
            duration: TimeInterval?
        ) {
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

    // MARK: - Text Helpers

    private static func normalize(
        _ text: String
    ) -> String {

        text
            .replacingOccurrences(
                of: "\n",
                with: " "
            )
            .replacingOccurrences(
                of: "\r",
                with: " "
            )
            .split(
                whereSeparator: {
                    $0.isWhitespace
                }
            )
            .joined(
                separator: " "
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }

    private static func join(
        _ pieces: [String]
    ) -> String {

        var result = ""

        for piece in pieces {

            guard !piece.isEmpty else {
                continue
            }

            if result.isEmpty {
                result = piece
                continue
            }

            if let first = piece.first,
               first.isPunctuation ||
               first.isSymbol {

                result += piece

            } else {

                result += " " + piece
            }
        }

        return result
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
    }
}
