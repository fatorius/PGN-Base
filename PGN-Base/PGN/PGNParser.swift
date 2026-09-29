import Foundation

/// Reads the games out of PGN text, including variations, into a tree of moves.
nonisolated enum PGNParser {
    static func parseGames(from text: String) -> [PGNGame] {
        var reader = ScalarReader(text)
        var games: [PGNGame] = []
        var game = PGNGame(id: 0)
        var hasMovetext = false

        /// The node the next move follows.
        var cursor = 0
        /// The last move in the current line, which comments, annotations, and variations attach to.
        var lastMove: Int?
        /// The enclosing lines, saved when a variation opens and restored when it closes, with
        /// where the variation opened and its first move.
        var lineStack: [(cursor: Int, lastMove: Int?, open: Int, firstMove: Int?)] = []
        /// A comment written before a move, such as at the start of a variation.
        var leadingComment: String?
        /// Where the move number before the next move starts.
        var numberStart: Int?

        func finishGame() {
            if hasMovetext || !game.tags.isEmpty {
                games.append(game)
            }
            game = PGNGame(id: games.count)
            hasMovetext = false
            cursor = 0
            lastMove = nil
            lineStack = []
            leadingComment = nil
            numberStart = nil
        }

        func extendBlock(of node: Int, to end: Int) {
            game.nodes[node].source.blockEnd = max(game.nodes[node].source.blockEnd, end)
        }

        func attach(comment: String, source: Range<Int>) {
            // A comment before the first move belongs to the root; one opening a variation leads its first move.
            let node: Int
            if let lastMove {
                node = lastMove
            } else if lineStack.isEmpty {
                node = 0
            } else {
                if !comment.isEmpty { leadingComment = [leadingComment, comment].compactMap(\.self).joined(separator: " ") }
                return
            }
            // Empty comments are still recorded, so that editing replaces them.
            game.nodes[node].source.comments.append(source)
            extendBlock(of: node, to: source.upperBound)
            if !comment.isEmpty {
                game.nodes[node].comment = [game.nodes[node].comment, comment].compactMap(\.self).joined(separator: " ")
            }
        }

        func attach(annotation: String, source: Range<Int>) {
            guard !annotation.isEmpty, let lastMove else { return }
            game.nodes[lastMove].annotation = annotation
            game.nodes[lastMove].source.separateAnnotations.append(source)
            extendBlock(of: lastMove, to: source.upperBound)
        }

        func markMovetextStart(at position: Int) {
            if game.movetextStart == nil { game.movetextStart = position }
        }

        func finishGame(withResult result: String, at position: Int) {
            game.result = result
            game.resultStart = position
            finishGame()
        }

        while let scalar = reader.peek() {
            let start = reader.position
            switch scalar {
            case "[":
                // A tag after moves means the previous game ended without a result token.
                if hasMovetext { finishGame() }
                if let tag = reader.readTag() { game.tags.append(tag) }

            case "{":
                reader.advance()
                let comment = reader.read(until: "}")
                reader.advance()
                attach(comment: Self.normalizeWhitespace(comment), source: start..<reader.position)

            case ";":
                reader.advance()
                let comment = reader.read(until: "\n")
                attach(comment: Self.normalizeWhitespace(comment), source: start..<reader.position)

            case "%" where reader.isAtLineStart:
                // Escape mechanism: the whole line is ignored.
                _ = reader.read(until: "\n")

            case "(":
                // A variation is an alternative to the last move, so it branches from that move's parent.
                reader.advance()
                markMovetextStart(at: start)
                lineStack.append((cursor, lastMove, start, nil))
                if let lastMove {
                    cursor = game.nodes[lastMove].parent ?? 0
                }
                lastMove = nil
                numberStart = nil

            case ")":
                reader.advance()
                numberStart = nil
                if let saved = lineStack.popLast() {
                    if let firstMove = saved.firstMove {
                        game.nodes[firstMove].source.variationRange = saved.open..<reader.position
                    }
                    cursor = saved.cursor
                    lastMove = saved.lastMove
                    leadingComment = nil
                    if let lastMove {
                        extendBlock(of: lastMove, to: reader.position)
                    }
                }

            case "$":
                reader.advance()
                let digits = reader.read(while: { $0.properties.numericType != nil })
                // Other NAGs aren't shown yet, and aren't recorded as annotations, so editing leaves them
                // alone; they still belong to the move's text, so they move with it.
                if let nag = Int(digits), let symbol = Self.nagSymbols[nag] {
                    attach(annotation: symbol, source: start..<reader.position)
                } else if let lastMove {
                    extendBlock(of: lastMove, to: reader.position)
                }

            case "*":
                reader.advance()
                if lineStack.isEmpty {
                    markMovetextStart(at: start)
                    finishGame(withResult: "*", at: start)
                }

            case _ where Self.isSymbolCharacter(scalar):
                let token = reader.read(while: Self.isSymbolCharacter)
                markMovetextStart(at: start)
                if ["1-0", "0-1", "1/2-1/2"].contains(token) {
                    if lineStack.isEmpty { finishGame(withResult: token, at: start) }
                } else if token.allSatisfy(\.isNumber) {
                    // Move number, such as the "12" in "12." or "12...".
                    numberStart = start
                    continue
                } else {
                    // Split "Nf3!?" into the move and its annotation.
                    let san = String(token.prefix { $0 != "!" && $0 != "?" })
                    let annotation = String(token.dropFirst(san.count))
                    if san.isEmpty {
                        attach(annotation: annotation, source: start..<reader.position)
                    } else {
                        var node = PGNNode(san: san, annotation: annotation.isEmpty ? nil : annotation, parent: cursor)
                        node.leadingComment = leadingComment
                        node.source.token = start..<reader.position
                        node.source.sanEnd = start + san.unicodeScalars.count
                        node.source.blockEnd = reader.position
                        node.source.numberStart = numberStart
                        leadingComment = nil
                        numberStart = nil
                        game.nodes.append(node)
                        let index = game.nodes.count - 1
                        if let last = lineStack.indices.last, lineStack[last].firstMove == nil {
                            lineStack[last].firstMove = index
                        }
                        game.nodes[cursor].children.append(index)
                        cursor = index
                        lastMove = index
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

    /// Reads only the tag pairs at the start of a game, stopping where the movetext begins.
    static func parseTags(from text: String) -> [PGNTag] {
        var reader = ScalarReader(text)
        var tags: [PGNTag] = []
        while true {
            _ = reader.read(while: \.properties.isWhitespace)
            switch reader.peek() {
            case "[":
                if let tag = reader.readTag() { tags.append(tag) }
            case "{":
                // Comments can appear before or between tags, such as a note at the top of a file.
                _ = reader.read(until: "}")
                reader.advance()
            case ";":
                _ = reader.read(until: "\n")
            default:
                return tags
            }
        }
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

    /// The current offset, in Unicode scalars from the start of the text.
    var position: Int { index }

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
