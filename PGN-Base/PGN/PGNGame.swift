import Foundation

nonisolated struct PGNTag: Sendable, Hashable {
    let name: String
    let value: String
}

nonisolated struct PGNMove: Sendable, Hashable {
    /// The move in Standard Algebraic Notation, without annotation symbols.
    var san: String
    /// A move-quality annotation such as `!`, `?`, or `!?`.
    var annotation: String?
    /// The comment that follows the move in the file.
    var comment: String?
    /// Where the move and its annotations appear in the game's text, for editing.
    var source = MoveSource()
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

    /// The end of the move and its annotations, where a new comment belongs.
    var annotatedEnd: Int {
        max(token.upperBound, separateAnnotations.map(\.upperBound).max() ?? 0)
    }
}

/// One game from a PGN file: its header tags and main-line moves.
nonisolated struct PGNGame: Identifiable, Sendable, Hashable {
    /// The game's position within its file.
    var id: Int
    var tags: [PGNTag] = []
    var moves: [PGNMove] = []
    /// A comment that appears before the first move.
    var initialComment: String?
    /// Where the comments before the first move appear in the game's text.
    var initialCommentSources: [Range<Int>] = []
    /// Where the movetext starts in the game's text, if there is any.
    var movetextStart: Int?
    var result = "*"

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

    /// Replays the moves from the starting position, stopping at the first move that can't be played.
    func replay() -> GameReplay {
        var position: Position
        if let fen = tag("FEN") {
            guard let custom = Position(fen: fen) else {
                return GameReplay(positions: [.standard], moves: [], error: "The game's FEN tag isn't valid.")
            }
            position = custom
        } else {
            position = .standard
        }

        var positions = [position]
        var resolvedMoves: [Move] = []
        var failure: String?
        for pgnMove in moves {
            do {
                let move = try position.move(fromSAN: pgnMove.san)
                position = position.applying(move)
                positions.append(position)
                resolvedMoves.append(move)
            } catch {
                let number = "\(position.fullmoveNumber)\(position.sideToMove == .white ? "." : "…")"
                failure = "Stopped at \(number) \(pgnMove.san): \(error.reason)."
                break
            }
        }
        return GameReplay(positions: positions, moves: resolvedMoves, error: failure)
    }
}

/// A row in a move list, pairing White's move with Black's reply.
nonisolated struct MoveRow: Identifiable, Sendable, Hashable {
    let number: Int
    /// Index into the game's moves, or `nil` if the row has no White move (a game starting with Black to move).
    var whiteMoveIndex: Int?
    var blackMoveIndex: Int?

    var id: Int { number }
}

/// The positions reached by playing through a game.
nonisolated struct GameReplay: Sendable {
    /// `positions[0]` is the starting position; `positions[n]` is the position after `n` half-moves.
    let positions: [Position]
    /// `moves[n]` leads from `positions[n]` to `positions[n + 1]`.
    let moves: [Move]
    /// Describes the first move that couldn't be played, if any.
    let error: String?
    let rows: [MoveRow]

    init(positions: [Position], moves: [Move], error: String?) {
        self.positions = positions
        self.moves = moves
        self.error = error

        var rows: [MoveRow] = []
        for index in moves.indices {
            let before = positions[index]
            if before.sideToMove == .white {
                rows.append(MoveRow(number: before.fullmoveNumber, whiteMoveIndex: index))
            } else if rows.isEmpty {
                rows.append(MoveRow(number: before.fullmoveNumber, blackMoveIndex: index))
            } else {
                rows[rows.count - 1].blackMoveIndex = index
            }
        }
        self.rows = rows
    }
}
