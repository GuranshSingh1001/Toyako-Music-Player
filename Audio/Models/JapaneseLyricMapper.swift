import Foundation

/// Builds character/mora-sized karaoke units for Japanese timed spans.
///
/// TTML timing is authoritative. When a TTML span contains several Japanese
/// characters but only one begin/end interval, the interval is subdivided
/// deterministically so the UI can still provide a smooth character-level
/// effect. Latin words are deliberately kept atomic.
enum JapaneseLyricMapper {

    static func units(
        for text: String,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> [LyricUnit] {
        let duration = max(0, endTime - startTime)
        let pieces = tokenize(text)

        guard !pieces.isEmpty else {
            return [LyricUnit(
                text: text,
                startTime: startTime,
                endTime: endTime
            )]
        }

        let romanized = text.toJapaneseRomaji()
        let romanizationParts = allocateRomanization(
            romanized,
            to: pieces
        )

        let count = pieces.count
        return pieces.enumerated().map { index, piece in
            let unitStart = startTime + duration * Double(index) / Double(count)
            let unitEnd = startTime + duration * Double(index + 1) / Double(count)

            return LyricUnit(
                text: piece.text,
                romanized: romanizationParts[index],
                startTime: unitStart,
                endTime: unitEnd,
                isAtomicWord: piece.isAtomicWord
            )
        }
    }

    private struct Piece {
        let text: String
        let isAtomicWord: Bool
    }

    private static func tokenize(_ text: String) -> [Piece] {
        var result: [Piece] = []
        var japaneseBuffer = ""
        var latinBuffer = ""

        func flushJapanese() {
            guard !japaneseBuffer.isEmpty else { return }
            result.append(contentsOf: japaneseMorae(japaneseBuffer).map {
                Piece(text: $0, isAtomicWord: false)
            })
            japaneseBuffer = ""
        }

        func flushLatin() {
            guard !latinBuffer.isEmpty else { return }
            result.append(Piece(text: latinBuffer, isAtomicWord: true))
            latinBuffer = ""
        }

        for character in text {
            let value = character.unicodeScalars.first?.value ?? 0

            if isLatinOrNumber(value) {
                flushJapanese()
                latinBuffer.append(character)
                continue
            }

            flushLatin()

            if containsJapaneseCharacters(String(character)) {
                japaneseBuffer.append(character)
            } else {
                flushJapanese()
                result.append(Piece(text: String(character), isAtomicWord: true))
            }
        }

        flushJapanese()
        flushLatin()
        return result
    }

    private static func japaneseMorae(_ text: String) -> [String] {
        var result: [String] = []

        for character in text {
            let value = character.unicodeScalars.first?.value ?? 0
            let string = String(character)

            if isSmallKana(value), let last = result.indices.last {
                result[last].append(contentsOf: string)
            } else if value == 0x30FC, let last = result.indices.last {
                // Long-vowel mark belongs visually to the preceding mora.
                result[last].append(contentsOf: string)
            } else {
                result.append(string)
            }
        }

        return result
    }

    private static func isSmallKana(_ value: UInt32) -> Bool {
        switch value {
        case 0x3041...0x3047, 0x3049, 0x304C...0x3063,
             0x3083...0x3087, 0x308E,
             0x30A1...0x30E3, 0x30E5...0x30E7,
             0x30EE, 0x30F5...0x30F6:
            return true
        default:
            return false
        }
    }

    private static func isLatinOrNumber(_ value: UInt32) -> Bool {
        switch value {
        case 0x0030...0x0039, // ASCII digits
             0x0041...0x005A, // A-Z
             0x0061...0x007A, // a-z
             0xFF10...0xFF19, // full-width digits
             0xFF21...0xFF3A, // full-width A-Z
             0xFF41...0xFF5A: // full-width a-z
            return true
        default:
            return false
        }
    }

    private static func allocateRomanization(
        _ romanized: String?,
        to pieces: [Piece]
    ) -> [String?] {
        guard let romanized, !romanized.isEmpty else {
            return Array(repeating: nil, count: pieces.count)
        }

        let latinPieces = romanized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard pieces.count > 1 else {
            return [romanized]
        }

        // If the transliterator gives one token per logical Japanese word,
        // map tokens to the corresponding piece whenever possible.
        if latinPieces.count == pieces.count {
            return latinPieces
        }

        // Latin words are atomic and should display their complete spelling.
        if pieces.allSatisfy(\.isAtomicWord) {
            return [romanized] + Array(repeating: nil, count: max(0, pieces.count - 1))
        }

        // Otherwise allocate the transliteration across Japanese units by
        // grapheme count. This is intentionally a display mapping rather than
        // a claim about phonetic timing; the TTML begin/end values remain the
        // timing authority.
        let graphemes = Array(romanized)
        let weights = pieces.map { max(1, $0.text.count) }
        let totalWeight = max(1, weights.reduce(0, +))

        var output = Array<String?>(repeating: nil, count: pieces.count)
        var cursor = 0

        for index in pieces.indices {
            let remainingPieces = pieces.count - index - 1
            let remainingCharacters = graphemes.count - cursor
            let ideal = Double(graphemes.count) * Double(weights[index]) / Double(totalWeight)
            var take = max(1, Int(ideal.rounded()))
            take = min(take, max(0, remainingCharacters - remainingPieces))

            if take > 0 {
                output[index] = String(graphemes[cursor..<min(cursor + take, graphemes.count)])
                cursor += take
            }
        }

        if cursor < graphemes.count, let last = output.last {
            output[output.count - 1] = (last ?? "") + String(graphemes[cursor...])
        }

        return output
    }
}
