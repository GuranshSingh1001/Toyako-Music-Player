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
        endTime: TimeInterval,
        generateRomanization: Bool = true,
        romanizationOverride: String? = nil
    ) -> [LyricUnit] {
        let duration = max(0, endTime - startTime)
        let pieces = tokenize(text)

        guard !pieces.isEmpty else {
            return [LyricUnit(text: text, startTime: startTime, endTime: endTime)]
        }

        if !generateRomanization && romanizationOverride == nil {
            return makeUnits(
                pieces,
                romanizationParts: Array(repeating: nil, count: pieces.count),
                startTime: startTime,
                endTime: endTime
            )
        }

        let romanized = romanizationOverride ?? text.toJapaneseRomaji()
        let romanizationParts = allocateRomanization(romanized, to: pieces)
        return makeUnits(pieces, romanizationParts: romanizationParts, startTime: startTime, endTime: endTime)
    }

    /// Applies one paragraph-level romaji result to already-timed words.
    /// The tokenizer is invoked once for the complete lyric line, never once
    /// per TTML span. The original TTML timing remains authoritative.
    static func timedWordsWithRomanization(
        _ words: [LyricWord],
        lineText: String,
        romanized: String?
    ) -> [LyricWord] {
        guard !words.isEmpty, let romanized, !romanized.isEmpty else { return words }
        guard containsJapaneseCharacters(lineText) else { return words }

        let tokens = japaneseWordTokens(lineText)
        var output = words
        var assigned = Array(repeating: false, count: words.count)
        var wordIndex = 0
        var tokenIndex = 0

        while wordIndex < words.count && tokenIndex < tokens.count {
            let wordSource = normalizeJapaneseForMatching(words[wordIndex].text)
            let tokenSource = normalizeJapaneseForMatching(tokens[tokenIndex].source)

            if wordSource.isEmpty {
                wordIndex += 1
                continue
            }
            if tokenSource.isEmpty {
                tokenIndex += 1
                continue
            }

            if wordSource == tokenSource {
                output[wordIndex] = rebuiltWord(
                    words[wordIndex],
                    romanization: [tokens[tokenIndex].romanized]
                )
                assigned[wordIndex] = true
                wordIndex += 1
                tokenIndex += 1
                continue
            }

            // One timed TTML span can contain several Japanese tokenizer words,
            // e.g. "はして" can correspond to "は" + "して". Combine the
            // readings and keep the single TTML time interval intact.
            if wordSource.hasPrefix(tokenSource) {
                var combinedSource = ""
                var combinedRomanization: [String] = []
                var lookahead = tokenIndex

                while lookahead < tokens.count {
                    let candidate = normalizeJapaneseForMatching(tokens[lookahead].source)
                    guard !candidate.isEmpty else {
                        lookahead += 1
                        continue
                    }

                    let next = combinedSource + candidate
                    if !wordSource.hasPrefix(next) { break }

                    combinedSource = next
                    combinedRomanization.append(tokens[lookahead].romanized)
                    lookahead += 1

                    if combinedSource == wordSource { break }
                }

                if combinedSource == wordSource {
                    let joined = combinedRomanization.joined(separator: " ")
                    output[wordIndex] = rebuiltWord(
                        words[wordIndex],
                        romanization: [joined]
                    )
                    assigned[wordIndex] = true
                    wordIndex += 1
                    tokenIndex = lookahead
                    continue
                }
            }

            // One tokenizer word can be split across several timed TTML spans,
            // e.g. "美しい" -> "美" + "しい". Gather timed spans until the
            // complete tokenizer word is covered, then allocate its reading.
            if tokenSource.hasPrefix(wordSource) {
                var combinedSource = ""
                var group: [Int] = []
                var lookahead = wordIndex

                while lookahead < words.count {
                    let candidate = normalizeJapaneseForMatching(words[lookahead].text)
                    guard !candidate.isEmpty else {
                        lookahead += 1
                        continue
                    }

                    let next = combinedSource + candidate
                    if !tokenSource.hasPrefix(next) { break }

                    combinedSource = next
                    group.append(lookahead)
                    lookahead += 1

                    if combinedSource == tokenSource { break }
                }

                if combinedSource == tokenSource, !group.isEmpty {
                    let parts = allocateTokenRomanization(
                        source: tokens[tokenIndex].source,
                        romanized: tokens[tokenIndex].romanized,
                        words: group.map { words[$0].text }
                    )

                    for (offset, index) in group.enumerated() {
                        output[index] = rebuiltWord(
                            words[index],
                            romanization: parts[offset]
                        )
                        assigned[index] = true
                    }

                    wordIndex = lookahead
                    tokenIndex += 1
                    continue
                }
            }

            // The tokenizer and TTML timing sometimes disagree about a boundary.
            // Do not let one mismatch poison all later words: leave this word for
            // the deterministic fallback below and advance the smaller side.
            if wordIndex + 1 < words.count {
                wordIndex += 1
            } else {
                tokenIndex += 1
            }
        }

        // Fill every unmatched timed word. This is deliberately done only for
        // words the contextual tokenizer could not align. It prevents blank
        // romaji while preserving the more accurate contextual readings above.
        let fallbackParts = allocateRomanization(
            romanized,
            to: words.map { Piece(text: $0.text, isAtomicWord: true) }
        )

        for index in words.indices where !assigned[index] {
            if let fallback = fallbackParts[index], !fallback.isEmpty {
                output[index] = rebuiltWord(
                    words[index],
                    romanization: [fallback]
                )
                assigned[index] = true
            }
        }

        return output
    }

    private static func rebuiltWord(
        _ word: LyricWord,
        romanization: [String?]
    ) -> LyricWord {
        let override = romanization.first ?? nil
        let rebuiltUnits = units(
            for: word.text,
            startTime: word.startTime,
            endTime: word.endTime,
            romanizationOverride: override
        )

        return LyricWord(
            text: word.text,
            startTime: word.startTime,
            endTime: word.endTime,
            units: rebuiltUnits,
            generateRomanization: false
        )
    }

    /// Rebuilds the timed words using paragraph-level Japanese romanization.
    /// This fixes TTML where a single Japanese word is split across several
    /// timed spans. Each span keeps its original begin/end interval.
    static func contextualizedWords(
        _ words: [LyricWord],
        lineText: String,
        generateRomanization: Bool = true
    ) -> [LyricWord] {
        guard generateRomanization else { return words }
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
                kCFStringTokenizerUnitWord,
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
        let suffixRomanized = romanizeKana(suffix) ?? ""
        var kanjiRomanized = romanized

        if !suffix.isEmpty, !suffixRomanized.isEmpty {
            kanjiRomanized = removeRomanizedSuffix(romanized, suffixRomanized)
        }

        if words.allSatisfy({
            Array($0).allSatisfy { isKana($0.unicodeScalars.first?.value ?? 0) }
        }) {
            return words.map { [romanizeKana($0) ?? $0] }
        }

        var result = words.map { _ in [String?]() }
        var remainingKanjiReading = kanjiRomanized

        for (wordIndex, word) in words.enumerated() {
            let wordChars = Array(word)
            let wordIsAllKana = wordChars.allSatisfy {
                isKana($0.unicodeScalars.first?.value ?? 0)
            }

            if wordIsAllKana {
                result[wordIndex] = [romanizeKana(word) ?? word]
                continue
            }

            // The first non-kana unit in a mixed token owns the contextual
            // kanji reading. This preserves the full reading instead of
            // dropping kanji that cannot be romanized in isolation.
            if !remainingKanjiReading.isEmpty {
                result[wordIndex] = [remainingKanjiReading]
                remainingKanjiReading = ""
            } else {
                result[wordIndex] = [romanizeKana(word) ?? word]
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

    /// Romanizes kana without invoking CFStringTokenizer. This is used only
    /// for kana-only pieces after the complete Japanese word has already been
    /// read in context. It keeps the context-sensitive kanji reading in the
    /// tokenizer while avoiding extra tokenizer calls for suffixes.
    private static func romanizeKana(_ text: String) -> String? {
        guard !text.isEmpty, Array(text).allSatisfy({
            isKana($0.unicodeScalars.first?.value ?? 0)
        }) else {
            return nil
        }

        let result = text
            .applyingTransform(.toLatin, reverse: false)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result?.isEmpty == false ? result : nil
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
        if pieces.count == romanizationOverride.count {
            parts = romanizationOverride
        } else if romanizationOverride.count == 1,
                  !pieces.isEmpty,
                  !pieces.filter({ containsJapaneseCharacters($0.text) }).isEmpty,
                  pieces.filter({ containsJapaneseCharacters($0.text) }).allSatisfy({
                      Array($0.text).allSatisfy { isKana($0.unicodeScalars.first?.value ?? 0) }
                  }) {
            parts = pieces.map { piece in
                guard containsJapaneseCharacters(piece.text) else { return nil }
                return romanizeKana(piece.text)
            }
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

    private static func normalizeJapaneseForMatching(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
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
