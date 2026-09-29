import Foundation

/// Reads the games out of PGN text.
///
/// Only the main line is kept for now: variations in parentheses are skipped, along with any
/// comments and annotations inside them.
nonisolated enum PGNParser {
    static func parseGames(from text: String) -> [PGNGame] {
        var reader = ScalarReader(text)
        var games: [PGNGame] = []
        var game = PGNGame(id: 0)
        var hasMovetext = false
        var variationDepth = 0

        func finishGame() {
            if hasMovetext || !game.tags.isEmpty {
                games.append(game)
            }
            game = PGNGame(id: games.count)
            hasMovetext = false
            variationDepth = 0
        }

        func attach(comment: String) {
            guard !comment.isEmpty else { return }
            if game.moves.isEmpty {
                game.initialComment = [game.initialComment, comment].compactMap(\.self).joined(separator: " ")
            } else {
                let last = game.moves.count - 1
                game.moves[last].comment = [game.moves[last].comment, comment].compactMap(\.self).joined(separator: " ")
            }
        }

        func attach(annotation: String) {
            guard !annotation.isEmpty, !game.moves.isEmpty else { return }
            game.moves[game.moves.count - 1].annotation = annotation
        }

        while let scalar = reader.peek() {
            switch scalar {
            case "[":
                // A tag after moves means the previous game ended without a result token.
                if hasMovetext { finishGame() }
                if let tag = reader.readTag() { game.tags.append(tag) }

            case "{":
                reader.advance()
                let comment = reader.read(until: "}")
                reader.advance()
                if variationDepth == 0 { attach(comment: Self.normalizeWhitespace(comment)) }

            case ";":
                reader.advance()
                let comment = reader.read(until: "\n")
                if variationDepth == 0 { attach(comment: Self.normalizeWhitespace(comment)) }

            case "%" where reader.isAtLineStart:
                // Escape mechanism: the whole line is ignored.
                _ = reader.read(until: "\n")

            case "(":
                reader.advance()
                variationDepth += 1

            case ")":
                reader.advance()
                variationDepth = max(0, variationDepth - 1)

            case "$":
                reader.advance()
                let digits = reader.read(while: { $0.properties.numericType != nil })
                if variationDepth == 0, let nag = Int(digits), let symbol = Self.nagSymbols[nag] {
                    attach(annotation: symbol)
                }

            case "*":
                reader.advance()
                if variationDepth == 0 {
                    game.result = "*"
                    finishGame()
                }

            case _ where Self.isSymbolCharacter(scalar):
                let token = reader.read(while: Self.isSymbolCharacter)
                guard variationDepth == 0 else { continue }
                if ["1-0", "0-1", "1/2-1/2"].contains(token) {
                    game.result = token
                    finishGame()
                } else if token.allSatisfy(\.isNumber) {
                    // Move number, such as the "12" in "12." or "12...".
                    continue
                } else {
                    // Split "Nf3!?" into the move and its annotation.
                    let san = String(token.prefix { $0 != "!" && $0 != "?" })
                    let annotation = String(token.dropFirst(san.count))
                    if san.isEmpty {
                        attach(annotation: annotation)
                    } else {
                        game.moves.append(PGNMove(san: san, annotation: annotation.isEmpty ? nil : annotation))
                        hasMovetext = true
                    }
                }

            default:
                // Whitespace, move-number periods, and anything unrecognized.
                reader.advance()
            }
        }
        finishGame()
        return games
    }

    /// Symbols for the standard move-quality numeric annotation glyphs (NAGs).
    private static let nagSymbols = [1: "!", 2: "?", 3: "!!", 4: "??", 5: "!?", 6: "?!"]

    private static func isSymbolCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil || "_+#=:-/!?".unicodeScalars.contains(scalar)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// A cursor over the Unicode scalars of a string.
nonisolated private struct ScalarReader {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    var isAtLineStart: Bool { index == 0 || scalars[index - 1] == "\n" }

    func peek() -> Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    mutating func advance() {
        index += 1
    }

    mutating func read(while predicate: (Unicode.Scalar) -> Bool) -> String {
        var result = String.UnicodeScalarView()
        while let scalar = peek(), predicate(scalar) {
            result.append(scalar)
            index += 1
        }
        return String(result)
    }

    /// Reads up to, but not including, `terminator`.
    mutating func read(until terminator: Unicode.Scalar) -> String {
        read(while: { $0 != terminator })
    }

    /// Reads a tag pair like `[White "Kasparov, Garry"]`, starting at the opening bracket.
    mutating func readTag() -> PGNTag? {
        advance()
        _ = read(while: \.properties.isWhitespace)
        let name = read(while: { !$0.properties.isWhitespace && $0 != "\"" && $0 != "]" })
        _ = read(while: { $0 != "\"" && $0 != "]" })

        var value = String.UnicodeScalarView()
        if peek() == "\"" {
            advance()
            while let scalar = peek(), scalar != "\"" {
                // A backslash escapes a quote or another backslash.
                if scalar == "\\" { advance() }
                if let escaped = peek() { value.append(escaped) }
                advance()
            }
            advance()
        }
        _ = read(until: "]")
        advance()
        return name.isEmpty ? nil : PGNTag(name: name, value: String(value))
    }
}
