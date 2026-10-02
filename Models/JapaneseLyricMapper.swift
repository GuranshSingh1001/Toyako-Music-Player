import Foundation
import CoreFoundation

/// Builds character/mora-sized karaoke units for Japanese timed spans.
///
/// TTML timing remains authoritative, but romanization is resolved from the
/// largest available Japanese context. This is important for kanji: a timed
/// span containing only `美` cannot reliably be romanized in isolation because
/// its reading depends on the surrounding word (`美しい` -> `utsukushii`).
enum JapaneseLyricMapper {

    static func units(
        for text: String,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> [LyricUnit] {
        let duration = max(0, endTime - startTime)
        let pieces = tokenize(text)

        guard !pieces.isEmpty else {
            return [LyricUnit(text: text, startTime: startTime, endTime: endTime)]
        }

        let romanized = text.toJapaneseRomaji()
        let romanizationParts = allocateRomanization(romanized, to: pieces)
        return makeUnits(pieces, romanizationParts: romanizationParts, startTime: startTime, endTime: endTime)
    }

    /// Rebuilds the timed words using paragraph-level Japanese romanization.
    /// This fixes TTML where a single Japanese word is split across several
    /// timed spans. Each span keeps its original begin/end interval.
    static func contextualizedWords(
        _ words: [LyricWord],
        lineText: String
    ) -> [LyricWord] {
        guard !words.isEmpty, containsJapaneseCharacters(lineText) else { return words }

        let tokens = japaneseWordTokens(lineText)
        guard !tokens.isEmpty else { return words }

        var output = words
        var wordIndex = 0

        for token in tokens {
            guard wordIndex < words.count else { break }

            var group: [Int] = []
            var combined = ""

            while wordIndex < words.count {
                let candidate = words[wordIndex].text
                if candidate.isEmpty { wordIndex += 1; continue }

                let next = combined + candidate
                if token.source.hasPrefix(next) {
                    combined = next
                    group.append(wordIndex)
                    wordIndex += 1
                    if combined == token.source { break }
                } else {
                    break
                }
            }

            guard combined == token.source, !group.isEmpty else { continue }

            let romanizedParts = allocateTokenRomanization(
                source: token.source,
                romanized: token.romanized,
                words: group.map { words[$0].text }
            )

            for (offset, index) in group.enumerated() {
                let word = words[index]
                let parts = romanizedParts[offset]
                let rebuiltUnits = units(
                    for: word.text,
                    startTime: word.startTime,
                    endTime: word.endTime,
                    romanizationOverride: parts
                )

                output[index] = LyricWord(
                    text: word.text,
                    startTime: word.startTime,
                    endTime: word.endTime,
                    units: rebuiltUnits
                )
            }
        }

        return output
    }

    private struct Piece {
        let text: String
        let isAtomicWord: Bool
    }

    private struct RomanizationToken {
        let source: String
        let romanized: String
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
                result[last].append(contentsOf: string)
            } else {
                result.append(string)
            }
        }
        return result
    }

    private static func japaneseWordTokens(_ text: String) -> [RomanizationToken] {
        JapaneseRomajiTokenizerLock.lock.lock()
        defer { JapaneseRomajiTokenizerLock.lock.unlock() }

        let cfText = text as CFString
        let length = CFStringGetLength(cfText)
        guard length > 0 else { return [] }

        let localeIdentifier = CFLocaleCreateCanonicalLanguageIdentifierFromString(
            kCFAllocatorDefault, "ja" as CFString
        )
        guard let locale = CFLocaleCreate(kCFAllocatorDefault, localeIdentifier),
              let tokenizer = CFStringTokenizerCreate(
                kCFAllocatorDefault,
                cfText,
                CFRangeMake(0, length),
                kCFStringTokenizerUnitWordBoundary,
                locale
              ) else { return [] }

        var result: [RomanizationToken] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)

        while !tokenType.isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let source = (CFStringCreateWithSubstring(kCFAllocatorDefault, cfText, range) as String)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if !source.isEmpty,
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                    tokenizer,
                    kCFStringTokenizerAttributeLatinTranscription
               ) as? String {
                let romanized = latin.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !romanized.isEmpty && romanized != source {
                    result.append(RomanizationToken(source: source, romanized: romanized))
                }
            }

            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        return result
    }

    private static func allocateTokenRomanization(
        source: String,
        romanized: String,
        words: [String]
    ) -> [[String?]] {
        let pieces = words.map { tokenize($0) }
        let flatPieces = pieces.flatMap { $0 }
        guard !flatPieces.isEmpty else {
            return words.map { _ in [romanized] }
        }

        // Kana can be romanized independently. For mixed kanji/kana words,
        // reserve the reading of the visible kana suffix first, leaving the
        // context-dependent kanji reading for the kanji portion. Example:
        // 溢して -> kobo + shite, 欲しい -> ho + shii.
        let characters = Array(source)
        var kanaSuffixStart = characters.count
        while kanaSuffixStart > 0 {
            let scalar = characters[kanaSuffixStart - 1].unicodeScalars.first?.value ?? 0
            if isKana(scalar) {
                kanaSuffixStart -= 1
            } else {
                break
            }
        }

        let suffix = String(characters[kanaSuffixStart...])
        let suffixRomanized = suffix.toJapaneseRomaji() ?? ""
        var kanjiRomanized = romanized

        if !suffix.isEmpty, !suffixRomanized.isEmpty {
            kanjiRomanized = removeRomanizedSuffix(romanized, suffixRomanized)
        }

        var result = words.map { _ in [String?]() }
        var remainingKanjiReading = kanjiRomanized

        for (wordIndex, word) in words.enumerated() {
            let wordChars = Array(word)
            let wordIsAllKana = wordChars.allSatisfy {
                isKana($0.unicodeScalars.first?.value ?? 0)
            }

            if wordIsAllKana {
                result[wordIndex] = [word.toJapaneseRomaji() ?? word]
                continue
            }

            // The first non-kana unit in a mixed token owns the contextual
            // kanji reading. This preserves the full reading instead of
            // dropping kanji that cannot be romanized in isolation.
            if !remainingKanjiReading.isEmpty {
                result[wordIndex] = [remainingKanjiReading]
                remainingKanjiReading = ""
            } else {
                result[wordIndex] = [word.toJapaneseRomaji() ?? word]
            }
        }

        // If the word sequence is mora-sized, split a suffix such as しい over
        // the corresponding timed units so the visual timing remains useful.
        let assignedSuffix = suffixRomanized
        if !assignedSuffix.isEmpty {
            var suffixWordIndices: [Int] = []
            for index in words.indices.reversed() {
                let chars = Array(words[index])
                if chars.allSatisfy({ isKana($0.unicodeScalars.first?.value ?? 0) }) {
                    suffixWordIndices.insert(index, at: 0)
                } else {
                    break
                }
            }

            if suffixWordIndices.count > 1 {
                let suffixPieces = suffixWordIndices.map { words[$0] }
                let allocated = allocateRomanization(assignedSuffix, to: suffixPieces.map {
                    Piece(text: $0, isAtomicWord: false)
                })
                for (offset, index) in suffixWordIndices.enumerated() {
                    result[index] = [allocated[offset] ?? words[index]]
                }
            }
        }

        return result
    }

    private static func removeRomanizedSuffix(_ full: String, _ suffix: String) -> String {
        let normalizedFull = full.lowercased().replacingOccurrences(of: " ", with: "")
        let normalizedSuffix = suffix.lowercased().replacingOccurrences(of: " ", with: "")
        guard normalizedFull.hasSuffix(normalizedSuffix) else { return full }
        let end = full.index(full.endIndex, offsetBy: -suffix.count)
        return String(full[..<end]).trimmingCharacters(in: .whitespaces)
    }

    private static func makeUnits(
        _ pieces: [Piece],
        romanizationParts: [String?],
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> [LyricUnit] {
        let duration = max(0, endTime - startTime)
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

    private static func units(
        for text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        romanizationOverride: [String?]
    ) -> [LyricUnit] {
        let pieces = tokenize(text)
        guard !pieces.isEmpty else {
            return [LyricUnit(text: text, startTime: startTime, endTime: endTime)]
        }
        let parts: [String?]
        if romanizationOverride.count == pieces.count {
            parts = romanizationOverride
        } else if romanizationOverride.count == 1 {
            parts = allocateRomanization(romanizationOverride[0], to: pieces)
        } else {
            parts = allocateRomanization(text.toJapaneseRomaji(), to: pieces)
        }
        return makeUnits(pieces, romanizationParts: parts, startTime: startTime, endTime: endTime)
    }

    private static func allocateRomanization(_ romanized: String?, to pieces: [Piece]) -> [String?] {
        guard let romanized, !romanized.isEmpty else {
            return Array(repeating: nil, count: pieces.count)
        }
        guard pieces.count > 1 else { return [romanized] }

        let latinPieces = romanized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if latinPieces.count == pieces.count { return latinPieces }

        let graphemes = Array(romanized.replacingOccurrences(of: " ", with: ""))
        let weights = pieces.map { max(1, $0.text.count) }
        let totalWeight = max(1, weights.reduce(0, +))
        var output = Array<String?>(repeating: nil, count: pieces.count)
        var cursor = 0

        for index in pieces.indices {
            let remainingPieces = pieces.count - index - 1
            let remainingCharacters = graphemes.count - cursor
            let ideal = Double(graphemes.count) * Double(weights[index]) / Double(totalWeight)
            let take = min(max(1, Int(ideal.rounded())), max(0, remainingCharacters - remainingPieces))
            if take > 0 {
                output[index] = String(graphemes[cursor..<min(cursor + take, graphemes.count)])
                cursor += take
            }
        }

        if cursor < graphemes.count {
            output[output.count - 1] = (output[output.count - 1] ?? "") + String(graphemes[cursor...])
        }
        return output
    }

    private static func isKana(_ value: UInt32) -> Bool {
        (0x3040...0x309F).contains(value) || (0x30A0...0x30FF).contains(value)
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
        case 0x0030...0x0039, 0x0041...0x005A, 0x0061...0x007A,
             0xFF10...0xFF19, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return true
        default:
            return false
        }
    }
}
