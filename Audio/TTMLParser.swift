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
            } else if let paragraph {
                // IMPORTANT: text outside a <span> is part of the TTML
                // document order. In Apple-style word timing this is often
                // where the actual spaces between timed spans live. The old
                // parser discarded this boundary information and therefore
                // merged unrelated words such as "So" + "I" + "guess".
                paragraph.events.append(.text(string))
                paragraph.plainText += string
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
                    paragraph?.events.append(.span(span))
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

    private enum TTMLEvent {
        case text(String)
        case span(TTMLSpan)
    }

    private final class TTMLParagraph {
        let start: TimeInterval?
        let end: TimeInterval?
        let duration: TimeInterval?

        var plainText = ""
        var spans: [TTMLSpan] = []
        var events: [TTMLEvent] = []

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
            // TTML word timing is not equivalent to "one span = one word".
            // A word can be split across adjacent timed spans ("to" +
            // "geth" + "er"), while a real word boundary can be represented
            // by whitespace OUTSIDE a span or by a dedicated whitespace span.
            // We therefore process the original child order and only merge
            // timed fragments when no whitespace boundary occurred between
            // them.
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

            for event in events {
                switch event {
                case .text(let rawText):
                    // Text outside timed spans is especially important: in
                    // Apple/TTML lyrics a literal space between two spans is
                    // the authoritative word boundary. Any whitespace here
                    // terminates the pending word.
                    if rawText.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                        flushPending()
                    } else if !rawText.isEmpty {
                        // Untimed visible text cannot safely be assigned a
                        // karaoke timestamp, so it is kept only in plainText.
                        // It must nevertheless prevent timed fragments on
                        // either side from being merged together.
                        flushPending()
                    }

                case .span(let span):
                    let raw = span.text

                    // A whitespace-only span is an explicit word boundary.
                    if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        flushPending()
                        continue
                    }

                    guard let start = span.start else {
                        // Untimed visible spans are not safe to merge with
                        // timed karaoke spans. Treat them as a boundary.
                        flushPending()
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

                    if hasLeadingWhitespace {
                        flushPending()
                    }

                    // Remove only boundary whitespace. Internal visible
                    // whitespace is handled below so "foo bar" cannot become
                    // the single logical word "foobar".
                    let pieces = raw.split(whereSeparator: { $0.isWhitespace })

                    if pieces.isEmpty {
                        flushPending()
                        continue
                    }

                    for (index, piece) in pieces.enumerated() {
                        if piece.isEmpty { continue }

                        // If the span itself contains an internal whitespace
                        // boundary, every piece after it starts a new word.
                        if index > 0 {
                            flushPending()
                        }

                        if pendingStart == nil {
                            pendingStart = start
                        }

                        pendingText += piece
                        pendingEnd = max(pendingEnd ?? end, end)

                        // If this is not the last piece, there was whitespace
                        // inside this span, so finalize before continuing.
                        if index < pieces.count - 1 {
                            flushPending()
                        }
                    }

                    if hasTrailingWhitespace {
                        flushPending()
                    }
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

            // The timedWords array already contains real word boundaries.
            // Joining with one visual space is therefore correct: it does not
            // split syllable fragments, and it does not collapse actual words.
            let text = timedWords.isEmpty
                ? fallbackText
                : timedWords.map(\.text).joined(separator: " ")

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
