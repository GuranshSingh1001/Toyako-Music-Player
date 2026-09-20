import Foundation

struct TTMLParser {

    static func parse(content: String) -> [LyricLine] {
        guard let data = content.data(using: .utf8) else {
            return []
        }

        let delegate = TTMLDelegate()

        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            return []
        }

        return delegate.lines
            .compactMap { $0.makeLyricLine() }
            .sorted { $0.time < $1.time }
    }

    private final class TTMLDelegate: NSObject, XMLParserDelegate {
        var lines: [TTMLParagraph] = []

        private var paragraph: TTMLParagraph?
        private var span: TTMLSpan?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(elementName)

            if name == "p" {
                paragraph = TTMLParagraph(
                    start: parseTime(attributeDict["begin"]),
                    end: parseTime(attributeDict["end"]),
                    duration: parseTime(attributeDict["dur"])
                )
                span = nil
                return
            }

            guard name == "span", paragraph != nil else {
                return
            }

            span = TTMLSpan(
                start: parseTime(attributeDict["begin"]),
                end: parseTime(attributeDict["end"]),
                duration: parseTime(attributeDict["dur"])
            )
        }

        func parser(
            _ parser: XMLParser,
            foundCharacters string: String
        ) {
            if let span {
                span.text += string
            } else if paragraph != nil {
                paragraph?.plainText += string
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
                if let span {
                    paragraph?.spans.append(span)
                }
                span = nil
            } else if name == "p" {
                if let paragraph {
                    lines.append(paragraph)
                }
                self.paragraph = nil
                self.span = nil
            }
        }

        private func localName(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        private func parseTime(_ value: String?) -> TimeInterval? {
            guard let value else { return nil }

            let string = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !string.isEmpty else { return nil }

            if let seconds = Double(string) {
                return seconds
            }

            if string.hasSuffix("ms") {
                let number = String(string.dropLast(2))
                if let milliseconds = Double(number) {
                    return milliseconds / 1000.0
                }
            }

            if string.hasSuffix("s") {
                let number = String(string.dropLast())
                if let seconds = Double(number) {
                    return seconds
                }
            }

            let components = string.split(separator: ":")

            if components.count == 2,
               let minutes = Double(components[0]),
               let seconds = Double(components[1]) {
                return minutes * 60.0 + seconds
            }

            if components.count == 3,
               let hours = Double(components[0]),
               let minutes = Double(components[1]),
               let seconds = Double(components[2]) {
                return hours * 3600.0 + minutes * 60.0 + seconds
            }

            return nil
        }
    }

    private final class TTMLParagraph {
        let start: TimeInterval?
        let end: TimeInterval?
        let duration: TimeInterval?

        var plainText = ""
        var spans: [TTMLSpan] = []

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
            // Apple-style TTML can split one spoken/sung word across multiple
            // timed spans (for example "to" + "geth" + "er"). Whitespace
            // spans are the authoritative word boundaries. The old parser
            // treated every timed span as a separate word and later the UI
            // inserted spacing between them, producing "to geth er".
            var timedWords: [LyricWord] = []
            var pendingText = ""
            var pendingStart: TimeInterval?
            var pendingEnd: TimeInterval?

            func flushPending() {
                let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, let start = pendingStart else {
                    pendingText = ""
                    pendingStart = nil
                    pendingEnd = nil
                    return
                }

                timedWords.append(
                    LyricWord(
                        text: text,
                        startTime: start,
                        endTime: max(start, pendingEnd ?? start)
                    )
                )

                pendingText = ""
                pendingStart = nil
                pendingEnd = nil
            }

            for span in spans {
                let raw = span.text
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

                // Untimed whitespace spans are explicit word boundaries.
                if trimmed.isEmpty {
                    flushPending()
                    continue
                }

                guard let start = span.start else {
                    continue
                }

                let end: TimeInterval
                if let explicitEnd = span.end {
                    end = max(start, explicitEnd)
                } else if let duration = span.duration {
                    end = start + max(0, duration)
                } else {
                    end = start
                }

                let hasLeadingWhitespace = raw.first?.isWhitespace == true
                let hasTrailingWhitespace = raw.last?.isWhitespace == true

                // A leading whitespace character means this starts a new word.
                if hasLeadingWhitespace {
                    flushPending()
                }

                if pendingStart == nil {
                    pendingStart = start
                }

                pendingText += trimmed
                pendingEnd = max(pendingEnd ?? end, end)

                // A trailing whitespace character explicitly terminates this word.
                if hasTrailingWhitespace {
                    flushPending()
                }
            }

            flushPending()

            let lineStart =
                start ??
                timedWords.first?.startTime ??
                0

            let lineEnd: TimeInterval

            if let end {
                lineEnd = max(lineStart, end)
            } else if let duration {
                lineEnd = lineStart + max(0, duration)
            } else {
                lineEnd = timedWords.last?.endTime ?? lineStart
            }

            let fallbackText = plainText
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !timedWords.isEmpty || !fallbackText.isEmpty else {
                return nil
            }

            // Reconstruct the line without inventing spaces between timed
            // spans. Explicit whitespace spans are preserved by the grouping
            // above, so syllable spans such as "to" + "geth" + "er" become
            // the single visual word "together".
            let text: String
            if !timedWords.isEmpty {
                text = timedWords.map(\.text).joined(separator: " ")
            } else {
                text = fallbackText
            }

            return LyricLine(
                time: lineStart,
                text: text,
                endTime: lineEnd,
                words: timedWords
            )
        }
    }

    private final class TTMLSpan {
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
}
