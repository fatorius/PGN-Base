import Foundation

nonisolated struct CastlingRights: OptionSet, Sendable, Hashable {
    let rawValue: Int

    static let whiteKingside = CastlingRights(rawValue: 1 << 0)
    static let whiteQueenside = CastlingRights(rawValue: 1 << 1)
    static let blackKingside = CastlingRights(rawValue: 1 << 2)
    static let blackQueenside = CastlingRights(rawValue: 1 << 3)
}

/// A complete chess position: piece placement plus the state needed to know which moves are legal.
nonisolated struct Position: Sendable, Hashable {
    private(set) var board: [Piece?]
    private(set) var sideToMove: PieceColor
    private(set) var castlingRights: CastlingRights
    private(set) var enPassantTarget: Square?
    private(set) var halfmoveClock: Int
    private(set) var fullmoveNumber: Int

    static let standardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    // The standard FEN is a constant, so parsing it can't fail.
    static let standard = Position(fen: standardFEN)!

    subscript(square: Square) -> Piece? { board[square.index] }

    /// Creates a position from Forsyth–Edwards Notation. Returns `nil` if the FEN is malformed.
    init?(fen: String) {
        let fields = fen.split(separator: " ")
        guard fields.count >= 4 else { return nil }

        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        var board = [Piece?](repeating: nil, count: 64)
        for (rowIndex, row) in rows.enumerated() {
            let rank = 7 - rowIndex
            var file = 0
            for character in row {
                if let emptySquares = character.wholeNumberValue {
                    file += emptySquares
                } else {
                    guard file < 8, let kind = PieceKind(letter: character) else { return nil }
                    board[rank * 8 + file] = Piece(color: character.isUppercase ? .white : .black, kind: kind)
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }
        self.board = board

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: return nil
        }

        var rights: CastlingRights = []
        for character in fields[2] {
            switch character {
            case "K": rights.insert(.whiteKingside)
            case "Q": rights.insert(.whiteQueenside)
            case "k": rights.insert(.blackKingside)
            case "q": rights.insert(.blackQueenside)
            case "-": break
            default: return nil
            }
        }
        castlingRights = rights
        enPassantTarget = Square(fields[3])
        halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        fullmoveNumber = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
    }

    // MARK: - Attacks

    private static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingOffsets = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    func kingSquare(of color: PieceColor) -> Square? {
        Square.all.first { self[$0] == Piece(color: color, kind: .king) }
    }

    /// Whether the side to move is in check.
    var isInCheck: Bool {
        guard let king = kingSquare(of: sideToMove) else { return false }
        return isSquare(king, attackedBy: sideToMove.opponent)
    }

    func isSquare(_ square: Square, attackedBy attacker: PieceColor) -> Bool {
        // An attacking pawn sits one rank behind the square, from the attacker's point of view.
        let pawnRankOffset = attacker == .white ? -1 : 1
        for fileOffset in [-1, 1] {
            if let source = square.offset(file: fileOffset, rank: pawnRankOffset),
               self[source] == Piece(color: attacker, kind: .pawn) {
                return true
            }
        }
        for (fileOffset, rankOffset) in Self.knightOffsets {
            if let source = square.offset(file: fileOffset, rank: rankOffset),
               self[source] == Piece(color: attacker, kind: .knight) {
                return true
            }
        }
        for (fileOffset, rankOffset) in Self.kingOffsets {
            if let source = square.offset(file: fileOffset, rank: rankOffset),
               self[source] == Piece(color: attacker, kind: .king) {
                return true
            }
        }
        for direction in Self.rookDirections {
            if let piece = firstPiece(from: square, direction: direction), piece.color == attacker,
               piece.kind == .rook || piece.kind == .queen {
                return true
            }
        }
        for direction in Self.bishopDirections {
            if let piece = firstPiece(from: square, direction: direction), piece.color == attacker,
               piece.kind == .bishop || piece.kind == .queen {
                return true
            }
        }
        return false
    }

    /// The first piece found walking from `square` (exclusive) in `direction`.
    private func firstPiece(from square: Square, direction: (Int, Int)) -> Piece? {
        var current = square
        while let next = current.offset(file: direction.0, rank: direction.1) {
            if let piece = self[next] { return piece }
            current = next
        }
        return nil
    }

    // MARK: - Move generation

    /// Every legal move for the side to move.
    var legalMoves: [Move] {
        pseudoLegalMoves().filter { move in
            let after = applying(move)
            guard let king = after.kingSquare(of: sideToMove) else { return true }
            return !after.isSquare(king, attackedBy: sideToMove.opponent)
        }
    }

    /// Moves that follow piece movement rules but may leave the mover's own king in check.
    private func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        for from in Square.all {
            guard let piece = self[from], piece.color == sideToMove else { continue }
            switch piece.kind {
            case .pawn:
                appendPawnMoves(from: from, into: &moves)
            case .knight:
                appendSteps(from: from, offsets: Self.knightOffsets, into: &moves)
            case .bishop:
                appendSlides(from: from, directions: Self.bishopDirections, into: &moves)
            case .rook:
                appendSlides(from: from, directions: Self.rookDirections, into: &moves)
            case .queen:
                appendSlides(from: from, directions: Self.rookDirections + Self.bishopDirections, into: &moves)
            case .king:
                appendSteps(from: from, offsets: Self.kingOffsets, into: &moves)
                appendCastlingMoves(into: &moves)
            }
        }
        return moves
    }

    private func appendSteps(from: Square, offsets: [(Int, Int)], into moves: inout [Move]) {
        for (fileOffset, rankOffset) in offsets {
            guard let to = from.offset(file: fileOffset, rank: rankOffset), self[to]?.color != sideToMove else { continue }
            moves.append(Move(from: from, to: to))
        }
    }

    private func appendSlides(from: Square, directions: [(Int, Int)], into moves: inout [Move]) {
        for (fileOffset, rankOffset) in directions {
            var current = from
            while let to = current.offset(file: fileOffset, rank: rankOffset) {
                if let occupant = self[to] {
                    if occupant.color != sideToMove { moves.append(Move(from: from, to: to)) }
                    break
                }
                moves.append(Move(from: from, to: to))
                current = to
            }
        }
    }

    private func appendPawnMoves(from: Square, into moves: inout [Move]) {
        let direction = sideToMove == .white ? 1 : -1
        let startRank = sideToMove == .white ? 1 : 6
        let promotionRank = sideToMove == .white ? 7 : 0

        func append(to: Square) {
            if to.rank == promotionRank {
                for kind in [PieceKind.queen, .rook, .bishop, .knight] {
                    moves.append(Move(from: from, to: to, promotion: kind))
                }
            } else {
                moves.append(Move(from: from, to: to))
            }
        }

        if let oneStep = from.offset(file: 0, rank: direction), self[oneStep] == nil {
            append(to: oneStep)
            if from.rank == startRank, let twoSteps = oneStep.offset(file: 0, rank: direction), self[twoSteps] == nil {
                moves.append(Move(from: from, to: twoSteps))
            }
        }
        for fileOffset in [-1, 1] {
            guard let to = from.offset(file: fileOffset, rank: direction) else { continue }
            if let target = self[to] {
                if target.color != sideToMove { append(to: to) }
            } else if to == enPassantTarget {
                append(to: to)
            }
        }
    }

    /// Adds castling moves. The king's destination square is checked later by the legality filter.
    private func appendCastlingMoves(into moves: inout [Move]) {
        let rank = sideToMove == .white ? 0 : 7
        let king = Square(file: 4, rank: rank)
        let ownRook = Piece(color: sideToMove, kind: .rook)
        let opponent = sideToMove.opponent
        guard self[king] == Piece(color: sideToMove, kind: .king), !isSquare(king, attackedBy: opponent) else { return }

        let kingside: CastlingRights = sideToMove == .white ? .whiteKingside : .blackKingside
        if castlingRights.contains(kingside),
           self[Square(file: 7, rank: rank)] == ownRook,
           self[Square(file: 5, rank: rank)] == nil,
           self[Square(file: 6, rank: rank)] == nil,
           !isSquare(Square(file: 5, rank: rank), attackedBy: opponent) {
            moves.append(Move(from: king, to: Square(file: 6, rank: rank)))
        }

        let queenside: CastlingRights = sideToMove == .white ? .whiteQueenside : .blackQueenside
        if castlingRights.contains(queenside),
           self[Square(file: 0, rank: rank)] == ownRook,
           self[Square(file: 1, rank: rank)] == nil,
           self[Square(file: 2, rank: rank)] == nil,
           self[Square(file: 3, rank: rank)] == nil,
           !isSquare(Square(file: 3, rank: rank), attackedBy: opponent) {
            moves.append(Move(from: king, to: Square(file: 2, rank: rank)))
        }
    }

    // MARK: - Making moves

    /// The position after playing `move`. The move is assumed to be legal.
    func applying(_ move: Move) -> Position {
        var next = self
        guard let piece = self[move.from] else { return next }
        let captured = self[move.to]

        next.board[move.from.index] = nil
        // En passant: the captured pawn is beside the moving pawn, not on the destination square.
        if piece.kind == .pawn, move.to == enPassantTarget, move.from.file != move.to.file {
            next.board[Square(file: move.to.file, rank: move.from.rank).index] = nil
        }
        next.board[move.to.index] = move.promotion.map { Piece(color: piece.color, kind: $0) } ?? piece

        // Castling is encoded as a two-square king move; bring the rook across too.
        if piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let (rookFromFile, rookToFile) = move.to.file == 6 ? (7, 5) : (0, 3)
            let rookFrom = Square(file: rookFromFile, rank: move.from.rank)
            let rookTo = Square(file: rookToFile, rank: move.from.rank)
            next.board[rookTo.index] = next.board[rookFrom.index]
            next.board[rookFrom.index] = nil
        }

        if piece.kind == .king {
            next.castlingRights.subtract(piece.color == .white
                ? [.whiteKingside, .whiteQueenside]
                : [.blackKingside, .blackQueenside])
        }
        // Moving from or capturing on a rook's home square removes that side's right.
        for square in [move.from, move.to] {
            switch (square.file, square.rank) {
            case (0, 0): next.castlingRights.remove(.whiteQueenside)
            case (7, 0): next.castlingRights.remove(.whiteKingside)
            case (0, 7): next.castlingRights.remove(.blackQueenside)
            case (7, 7): next.castlingRights.remove(.blackKingside)
            default: break
            }
        }

        if piece.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassantTarget = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        } else {
            next.enPassantTarget = nil
        }
        next.halfmoveClock = piece.kind == .pawn || captured != nil ? 0 : halfmoveClock + 1
        if sideToMove == .black { next.fullmoveNumber += 1 }
        next.sideToMove = sideToMove.opponent
        return next
    }
}
