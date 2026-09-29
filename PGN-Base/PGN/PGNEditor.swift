import Foundation

/// Edits comments, move-quality annotations, and moves in a game's PGN text.
///
/// Edits replace only the affected characters, so everything else in the game —
/// other variations, other annotations, clock and engine data, formatting — is kept exactly as written.
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

    /// Returns `text` with the comment after the move at `path` replaced by `comment`. The root
    /// path (`[]`) edits the game's opening comment. An empty comment removes it.
    static func settingComment(_ comment: String, forMoveAt path: MovePath, in text: String) -> String {
        guard let game = PGNParser.parseGames(from: text).first, let node = game.node(at: path) else { return text }
        let scalars = Array(text.unicodeScalars)
        let cleaned = sanitizedComment(comment)
        let source = game.nodes[node].source

        var edits: [(range: Range<Int>, replacement: String)] = []
        if let first = source.comments.first {
            // Merge any separate comments into one.
            edits.append((first, cleaned.isEmpty ? "" : "{\(cleaned)}"))
            edits += source.comments.dropFirst().map { ($0, "") }
        } else if !cleaned.isEmpty {
            if node == 0 {
                let position = game.movetextStart ?? scalars.count
                edits.append((position..<position, "{\(cleaned)} "))
            } else {
                edits.append((source.annotatedEnd..<source.annotatedEnd, " {\(cleaned)}"))
            }
        }
        return apply(edits, to: scalars)
    }

    /// Returns `text` with the move-quality annotation of the move at `path` set to `symbol`,
    /// such as `!?`, or removed when `symbol` is `nil`.
    static func settingAnnotation(_ symbol: String?, forMoveAt path: MovePath, in text: String) -> String {
        guard let game = PGNParser.parseGames(from: text).first, let node = game.node(at: path), node != 0 else { return text }
        let source = game.nodes[node].source

        // Written as a suffix on the move (`Nf3!?`), replacing any existing suffix or NAG.
        var edits = source.separateAnnotations.map { (range: $0, replacement: "") }
        edits.append((source.sanEnd..<source.token.upperBound, symbol ?? ""))
        return apply(edits, to: Array(text.unicodeScalars))
    }

    /// Returns `text` with a move added after the move at `path`, and the path of the new move.
    ///
    /// If the line ends there, the move extends it. Otherwise it starts a new variation, written
    /// after the existing continuation and any variations already there.
    /// - Parameter moveNumber: The move number label for the position before the move, like `12.` or `12...`.
    static func addingMove(
        _ san: String,
        moveNumber: String,
        after path: MovePath,
        in text: String
    ) -> (text: String, path: MovePath)? {
        guard let game = PGNParser.parseGames(from: text).first, let parent = game.node(at: path) else { return nil }
        let scalars = Array(text.unicodeScalars)
        let parentNode = game.nodes[parent]
        let isWhiteMove = !moveNumber.hasSuffix("...")

        let insertion: (position: Int, text: String)
        if let continuation = parentNode.children.first {
            // A new alternative to the continuation, after the variations it already has.
            insertion = (game.nodes[continuation].source.blockEnd, " (\(moveNumber) \(san))")
        } else if parent == 0 {
            // The first move of a game without any.
            let position = game.resultStart ?? scalars.count
            insertion = (position, "\(moveNumber) \(san) ")
        } else {
            // Extending the line. Black's moves only need a number after a comment or variation.
            let source = parentNode.source
            let needsNumber = isWhiteMove || source.blockEnd > source.annotatedEnd
            insertion = (source.blockEnd, " \(needsNumber ? "\(moveNumber) " : "")\(san)")
        }

        let newText = apply([(insertion.position..<insertion.position, insertion.text)], to: scalars)
        return (newText, path + [parentNode.children.count])
    }

    // MARK: - Variations

    enum VariationEdit: Sendable {
        /// Makes the variation containing the move its parent's main continuation, one level up.
        case promote
        /// Removes the variation containing the move.
        case delete
        /// Removes every move after the move.
        case deleteRemainingMoves

        var actionName: String {
            switch self {
            case .promote: "Promote Variation"
            case .delete: "Delete Variation"
            case .deleteRemainingMoves: "Delete Remaining Moves"
            }
        }
    }

    /// Whether `edit` can be applied at `node`.
    static func canApply(_ edit: VariationEdit, at node: Int, in game: PGNGame) -> Bool {
        switch edit {
        case .promote, .delete: game.variationStart(containing: node) != nil
        case .deleteRemainingMoves: !game.nodes[node].children.isEmpty
        }
    }

    /// Returns `text` with a variation promoted or deleted, or the moves after a move deleted.
    ///
    /// Only the text after the branch point is rewritten, by writing its lines again in their new
    /// order. Each move keeps its own text — annotations, comments, and anything else written with
    /// it — while move numbers and parentheses are regenerated.
    static func applying(_ edit: VariationEdit, at path: MovePath, in text: String) -> String? {
        guard let game = PGNParser.parseGames(from: text).first, let node = game.node(at: path),
              canApply(edit, at: node, in: game) else { return nil }

        let branch: Int
        let newChildren: [Int]
        switch edit {
        case .deleteRemainingMoves:
            branch = node
            newChildren = []
        case .promote, .delete:
            guard let variation = game.variationStart(containing: node), let parent = game.nodes[variation].parent else { return nil }
            branch = parent
            let others = game.nodes[parent].children.filter { $0 != variation }
            newChildren = edit == .promote ? [variation] + others : others
        }

        let scalars = Array(text.unicodeScalars)
        guard var region = continuationRange(after: branch, in: game, textLength: scalars.count) else { return nil }
        let writer = LineWriter(game: game, replay: game.replay(), scalars: scalars)
        let replacement = writer.continuation(of: branch, children: newChildren, numberFirst: writer.needsNumberAfter(branch))

        // Trim the region to its content, and when nothing replaces it, take the space before it too.
        while region.upperBound > region.lowerBound, scalars[region.upperBound - 1].properties.isWhitespace {
            region = region.lowerBound..<(region.upperBound - 1)
        }
        if replacement.isEmpty {
            while region.lowerBound > 0, scalars[region.lowerBound - 1] == " " {
                region = (region.lowerBound - 1)..<region.upperBound
            }
        }
        return apply([(region, replacement)], to: scalars)
    }

    /// Where the current move goes after `edit` — adjusted for moves that moved or were removed.
    static func path(_ current: MovePath, after edit: VariationEdit, at editPath: MovePath, in game: PGNGame) -> MovePath {
        guard let node = game.node(at: editPath) else { return current }
        switch edit {
        case .deleteRemainingMoves:
            return current.starts(with: editPath) ? Array(current.prefix(editPath.count)) : current
        case .promote, .delete:
            guard let variation = game.variationStart(containing: node) else { return current }
            let variationPath = game.path(to: variation)
            let parentPath = Array(variationPath.dropLast())
            guard let index = variationPath.last, current.count > parentPath.count, current.starts(with: parentPath) else { return current }
            var result = current
            let step = current[parentPath.count]
            if edit == .delete {
                if step == index { return parentPath }
                if step > index { result[parentPath.count] = step - 1 }
            } else {
                if step == index { result[parentPath.count] = 0 } else if step < index { result[parentPath.count] = step + 1 }
            }
            return result
        }
    }

    /// The text after `branch`'s own block that holds its continuation and variations, up to the
    /// end of its line: the result for the main line, or the closing parenthesis for a variation.
    private static func continuationRange(after branch: Int, in game: PGNGame, textLength: Int) -> Range<Int>? {
        guard let first = game.nodes[branch].children.first else { return nil }
        let start = game.nodes[first].source.numberStart ?? game.nodes[first].source.token.lowerBound
        let end: Int
        if let variation = game.variationStart(containing: branch) {
            guard let range = game.nodes[variation].source.variationRange else { return nil }
            end = range.upperBound - 1
        } else {
            end = game.resultStart ?? textLength
        }
        return start <= end ? start..<end : nil
    }

    /// Writes lines of a game's move tree as PGN, reusing each move's original text.
    private struct LineWriter {
        let game: PGNGame
        let replay: GameReplay
        let scalars: [Unicode.Scalar]

        /// The moves after `parent`: the first child and its line, with the other children as variations.
        func continuation(of parent: Int, children: [Int], numberFirst: Bool) -> String {
            guard let main = children.first else { return "" }
            var parts = [write(main, forceNumber: numberFirst)]
            let alternatives = children.dropFirst()
            for alternative in alternatives {
                let rest = continuation(of: alternative, children: game.nodes[alternative].children, numberFirst: needsNumberAfter(alternative))
                parts.append("(" + [write(alternative, forceNumber: true), rest].filter { !$0.isEmpty }.joined(separator: " ") + ")")
            }
            let rest = continuation(
                of: main,
                children: game.nodes[main].children,
                numberFirst: !alternatives.isEmpty || needsNumberAfter(main)
            )
            if !rest.isEmpty { parts.append(rest) }
            return parts.joined(separator: " ")
        }

        /// Whether a Black move after `node` needs its number, because a comment comes between them.
        func needsNumberAfter(_ node: Int) -> Bool {
            !game.nodes[node].source.comments.isEmpty
        }

        /// One move with its number, if needed, and its own text.
        private func write(_ node: Int, forceNumber: Bool) -> String {
            let before = game.nodes[node].parent.flatMap { replay.positions[$0] }
            let isWhite = before?.sideToMove != .black
            let number = (isWhite || forceNumber) ? before.map { "\($0.moveNumberLabel) " } ?? "" : ""
            let leading = game.nodes[node].leadingComment.map { "{\($0)} " } ?? ""
            return leading + number + ownText(of: node)
        }

        /// The move and what's written with it — annotations, comments, other NAGs — without the
        /// variations that follow it, which are written separately.
        private func ownText(of node: Int) -> String {
            let source = game.nodes[node].source
            var excluded: [Range<Int>] = []
            if let parent = game.nodes[node].parent {
                excluded = game.nodes[parent].children
                    .filter { $0 != node }
                    .compactMap { game.nodes[$0].source.variationRange }
            }
            var result = String.UnicodeScalarView()
            var index = source.token.lowerBound
            while index < source.blockEnd {
                if let skip = excluded.first(where: { $0.contains(index) }) {
                    index = skip.upperBound
                    continue
                }
                result.append(scalars[index])
                index += 1
            }
            return String(result).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
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
