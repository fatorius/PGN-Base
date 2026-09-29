import Foundation

/// Edits comments and move-quality annotations in a game's PGN text.
///
/// Edits replace only the affected characters, so everything else in the game —
/// variations, other annotations, clock and engine data, formatting — is kept exactly as written.
nonisolated enum PGNEditor {
    /// The move-quality annotations people can choose from, with their spoken names.
    static let annotations: [(symbol: String, name: String)] = [
        ("!!", "Brilliant move"),
        ("!", "Good move"),
        ("!?", "Interesting move"),
        ("?!", "Dubious move"),
        ("?", "Mistake"),
        ("??", "Blunder"),
    ]

    /// Returns `text` with the comment after the move at `moveIndex` replaced by `comment`,
    /// or with the game's opening comment replaced when `moveIndex` is `nil`.
    /// An empty comment removes it.
    static func settingComment(_ comment: String, forMoveAt moveIndex: Int?, in text: String) -> String {
        guard let game = PGNParser.parseGames(from: text).first else { return text }
        let scalars = Array(text.unicodeScalars)
        let cleaned = sanitizedComment(comment)

        let existing: [Range<Int>]
        let insertion: (position: Int, text: String)
        if let moveIndex {
            guard game.moves.indices.contains(moveIndex) else { return text }
            let source = game.moves[moveIndex].source
            existing = source.comments
            insertion = (source.annotatedEnd, " {\(cleaned)}")
        } else {
            existing = game.initialCommentSources
            insertion = (game.movetextStart ?? scalars.count, "{\(cleaned)} ")
        }

        var edits: [(range: Range<Int>, replacement: String)] = []
        if let first = existing.first {
            // Merge any separate comments into one.
            edits.append((first, cleaned.isEmpty ? "" : "{\(cleaned)}"))
            edits += existing.dropFirst().map { ($0, "") }
        } else if !cleaned.isEmpty {
            edits.append((insertion.position..<insertion.position, insertion.text))
        }
        return apply(edits, to: scalars)
    }

    /// Returns `text` with the move-quality annotation of the move at `moveIndex` set to `symbol`,
    /// such as `!?`, or removed when `symbol` is `nil`.
    static func settingAnnotation(_ symbol: String?, forMoveAt moveIndex: Int, in text: String) -> String {
        guard let game = PGNParser.parseGames(from: text).first, game.moves.indices.contains(moveIndex) else { return text }
        let source = game.moves[moveIndex].source

        // Written as a suffix on the move (`Nf3!?`), replacing any existing suffix or NAG.
        var edits = source.separateAnnotations.map { (range: $0, replacement: "") }
        edits.append((source.sanEnd..<source.token.upperBound, symbol ?? ""))
        return apply(edits, to: Array(text.unicodeScalars))
    }

    /// The comment as it will be stored: whitespace collapsed, and without `}`, which would end the comment early.
    static func sanitizedComment(_ comment: String) -> String {
        comment
            .replacingOccurrences(of: "}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Applies non-overlapping replacements, working backward so earlier offsets stay valid.
    private static func apply(_ edits: [(range: Range<Int>, replacement: String)], to original: [Unicode.Scalar]) -> String {
        var scalars = original
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            var range = edit.range
            if range.isEmpty && edit.replacement.isEmpty { continue }
            // When deleting, also remove the space before, so no double spaces are left behind.
            if edit.replacement.isEmpty, !range.isEmpty, range.lowerBound > 0, scalars[range.lowerBound - 1] == " " {
                range = (range.lowerBound - 1)..<range.upperBound
            }
            scalars.replaceSubrange(range, with: edit.replacement.unicodeScalars)
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
