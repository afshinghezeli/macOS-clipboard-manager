import Foundation

/// Normalizes text for search and for one-line display.
///
/// Search compares folded text on both sides: the stored item's and the query. Both must go through
/// ``fold(_:maxUTF8Bytes:)``, or matches silently disappear.
public enum TextFolding {
    /// The size of the folded text stored per item, in UTF-8 bytes. Searching beyond it would need
    /// the full payload, which lives outside the search index.
    public static let searchTextLimit = 2048

    /// Folds case, diacritics and character width, drops invisible characters, and collapses runs of
    /// whitespace to a single space, so that "Crème  Brûlée" and "creme brulee" compare equal.
    ///
    /// The result never exceeds `maxUTF8Bytes` and never ends in a partial character.
    public static func fold(_ text: String, maxUTF8Bytes: Int = searchTextLimit) -> String {
        // Folding a 16 MB copy would be wasted work; the result is capped anyway. A character is at
        // least one UTF-8 byte, so this prefix is always long enough.
        let head = String(text.prefix(maxUTF8Bytes))
        let folded = head.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let cleaned = normalizeWhitespace(folded)
        return truncate(cleaned, maxUTF8Bytes: maxUTF8Bytes)
    }

    /// A single line that is safe to show in the history list: invisible characters removed, line
    /// breaks and tabs turned into spaces, and at most `maxCharacters` characters, ending in "…" when
    /// shortened.
    ///
    /// macOS 26 CoreText can spin forever truncating single-line text that contains U+FFFC (the
    /// attachment placeholder in rich text), so every string shown in a list goes through here.
    public static func preview(of text: String, maxCharacters: Int = 300) -> String {
        precondition(maxCharacters > 1)
        // Bound the work for huge copies. Four times the limit leaves room for stripped characters.
        let head = String(text.prefix(maxCharacters * 4))
        let line = normalizeWhitespace(head)
        guard line.count > maxCharacters else { return line }
        let kept = line.prefix(maxCharacters - 1)
        return kept.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Helpers

    private static func normalizeWhitespace(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if isStripped(scalar) { continue }
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Invisible characters that carry no meaning in a one-line preview or a search key.
    ///
    /// Zero-width joiner (U+200D) and non-joiner (U+200C) are kept: emoji sequences and scripts such
    /// as Persian depend on them.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xFFFC, 0xFFFD: true  // object replacement, replacement character
        case 0x200B, 0x2060, 0xFEFF: true  // zero-width space, word joiner, byte order mark
        case 0x202A...0x202E, 0x2066...0x2069: true  // bidi embeddings, overrides and isolates
        default: false
        }
    }

    private static func truncate(_ text: String, maxUTF8Bytes: Int) -> String {
        guard text.utf8.count > maxUTF8Bytes else { return text }
        var result = ""
        var bytes = 0
        for character in text {
            let size = character.utf8.count
            if bytes + size > maxUTF8Bytes { break }
            result.append(character)
            bytes += size
        }
        return result
    }
}
