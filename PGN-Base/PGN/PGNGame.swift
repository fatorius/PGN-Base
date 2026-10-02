import Foundation

nonisolated struct PGNTag: Sendable, Hashable {
    let name: String
    let value: String
}

/// A move in a game's tree of moves. The root node stands for the starting position and has no move.
///
/// A node's first child continues its line; any further children are variations — alternatives
/// to that continuation, written in parentheses after it in PGN.
nonisolated struct PGNNode: Sendable, Hashable {
    /// The move in Standard Algebraic Notation, without annotation symbols. Empty for the root.
    var san = ""
    /// A move-quality annotation such as `!`, `?`, or `!?`.
    var annotation: String?
    /// The comment after the move. For the root, the comment before the first move.
    var comment: String?
    /// A comment written before the move, such as one opening a variation. Shown, but not yet editable.
    var leadingComment: String?
    /// Where the move and its annotations appear in the game's text, for editing.
    var source = MoveSource()
    var parent: Int?
    var children: [Int] = []
}

/// Locations in a game's text, as offsets in Unicode scalars from the start of the game.
nonisolated struct MoveSource: Sendable, Hashable {
    /// The move token, including any attached suffix such as the `!?` in `Nf3!?`.
    var token: Range<Int> = 0..<0
    /// Where the move itself ends and an attached suffix would begin.
    var sanEnd = 0
    /// Move-quality annotations written separately, like a standalone `!` or the NAGs `$1`–`$6`.
    var separateAnnotations: [Range<Int>] = []
    /// Comments after the move, including their braces.
    var comments: [Range<Int>] = []
    /// The end of everything that belongs after this move — its annotations, comments, and the
    /// variations that follow it — which is where the line's next move is written.
    var blockEnd = 0
    /// Where the move number written before the move starts, like the `12.` in `12. Nf3`.
    var numberStart: Int?
    /// For the first move of a variation, the whole variation including its parentheses.
    var variationRange: Range<Int>?

    /// The end of the move and its annotations, where a new comment belongs.
    var annotatedEnd: Int {
        max(token.upperBound, separateAnnotations.map(\.upperBound).max() ?? 0)
    }
}

/// A path from the root to a node: the child index to take at each step. Unlike node indices,
/// paths stay valid when moves are added, because new moves are always added as the last child.
typealias MovePath = [Int]

/// One game from a PGN file: its header tags and tree of moves.
nonisolated struct PGNGame: Identifiable, Sendable, Hashable {
    /// The game's position within its file.
    var id: Int
    var tags: [PGNTag] = []
    /// The move tree; `nodes[0]` is the root.
    var nodes = [PGNNode()]
    /// Where the movetext starts in the game's text, if there is any.
    var movetextStart: Int?
    /// Where the result token starts in the game's text, if there is one.
    var resultStart: Int?
    var result = "*"

    /// The comment before the first move.
    var initialComment: String? { nodes[0].comment }

    /// The main line's nodes, following each node's first child from the root.
    var mainLine: [Int] { line(continuingFrom: 0) }

    /// The nodes that continue from `node` by always taking the first child, excluding `node` itself.
    func line(continuingFrom node: Int) -> [Int] {
        var line: [Int] = []
        var current = node
        while let next = nodes[current].children.first {
            line.append(next)
            current = next
        }
        return line
    }

    /// Whether the game branches after `node`, so there's more than one move to choose from.
    func isBranchPoint(_ node: Int) -> Bool {
        nodes[node].children.count > 1
    }

    /// The nearest move before `node` where the game branches, or `nil` if there's none.
    func previousBranchPoint(before node: Int) -> Int? {
        var ancestor = nodes[node].parent
        while let current = ancestor {
            if isBranchPoint(current) { return current }
            ancestor = nodes[current].parent
        }
        return nil
    }

    func node(at path: MovePath) -> Int? {
        var current = 0
        for step in path {
            guard nodes[current].children.indices.contains(step) else { return nil }
            current = nodes[current].children[step]
        }
        return current
    }

    /// The first move of the variation `node` is in — `node` itself or its nearest ancestor that
    /// isn't its parent's main continuation. `nil` for moves on the main line.
    func variationStart(containing node: Int) -> Int? {
        var current = node
        while let parent = nodes[current].parent {
            if nodes[parent].children.first != current { return current }
            current = parent
        }
        return nil
    }

    /// The node at `path`, or the deepest node along it if the path goes further than the tree does.
    func deepestNode(along path: MovePath) -> Int {
        var current = 0
        for step in path {
            guard nodes[current].children.indices.contains(step) else { break }
            current = nodes[current].children[step]
        }
        return current
    }

    func path(to node: Int) -> MovePath {
        var path: MovePath = []
        var current = node
        while let parent = nodes[current].parent, let index = nodes[parent].children.firstIndex(of: current) {
            path.append(index)
            current = parent
        }
        return path.reversed()
    }

    /// The value of a header tag, or `nil` if it's missing or an "unknown" placeholder like `?` or `????.??.??`.
    func tag(_ name: String) -> String? {
        guard let value = tags.first(where: { $0.name == name })?.value,
              !value.allSatisfy({ $0 == "?" || $0 == "." || $0 == " " }) else { return nil }
        return value
    }

    var white: String { tag("White") ?? "White" }
    var black: String { tag("Black") ?? "Black" }
    var title: String { "\(white) – \(black)" }

    /// The date with unknown parts dropped, so `1858.??.??` becomes `1858`.
    var date: String? {
        tag("Date").map { date in
            date.split(separator: ".").prefix { !$0.contains("?") }.joined(separator: ".")
        }
    }

    /// Plays through every line of the game. A move that can't be played cuts off its line,
    /// but the rest of the game is still replayed.
    func replay() -> GameReplay {
        var positions = [Position?](repeating: nil, count: nodes.count)
        var moves = [Move?](repeating: nil, count: nodes.count)
        var firstError: String?

        if let fen = tag("FEN") {
            guard let custom = Position(fen: fen) else {
                positions[0] = .standard
                return GameReplay(positions: positions, moves: moves, error: "The game's FEN tag isn't valid.")
            }
            positions[0] = custom
        } else {
            positions[0] = .standard
        }

        // Nodes are created in text order, so every parent comes before its children.
        for index in nodes.indices.dropFirst() {
            guard let parent = nodes[index].parent, let before = positions[parent] else { continue }
            do {
                let move = try before.move(fromSAN: nodes[index].san)
                moves[index] = move
                positions[index] = before.applying(move)
            } catch {
                if firstError == nil {
                    firstError = "Stopped at \(before.moveNumberLabel) \(nodes[index].san): \(error.reason)."
                }
            }
        }
        return GameReplay(positions: positions, moves: moves, error: firstError)
    }
}

/// The positions reached by playing through a game's move tree.
nonisolated struct GameReplay: Sendable {
    /// The position after each node's move, indexed like `PGNGame.nodes`; the root's is the
    /// starting position. `nil` for moves that can't be reached because a move before them is illegal.
    let positions: [Position?]
    /// The move each node plays, or `nil` for the root and unplayable moves.
    let moves: [Move?]
    /// Describes the first move that couldn't be played, if any.
    let error: String?
}

extension Position {
    /// The move number as written before this position's move, like `12.` for White or `12...` for Black.
    nonisolated var moveNumberLabel: String {
        "\(fullmoveNumber)\(sideToMove == .white ? "." : "...")"
    }
}
