import Foundation

nonisolated enum SANError: Error, Sendable {
    case malformed
    case illegal
    case ambiguous

    var reason: String {
        switch self {
        case .malformed: "the move notation isn't valid"
        case .illegal: "the move isn't legal in this position"
        case .ambiguous: "more than one piece can make this move"
        }
    }
}

extension Position {
    /// Writes a legal move in Standard Algebraic Notation, such as `Nbd7`, `exd6`, `O-O`, or `e8=Q#`.
    nonisolated func san(for move: Move) -> String {
        guard let piece = self[move.from] else { return "" }
        var san: String
        if piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            san = move.to.file == 6 ? "O-O" : "O-O-O"
        } else {
            let isCapture = self[move.to] != nil || (piece.kind == .pawn && move.to == enPassantTarget)
            if piece.kind == .pawn {
                san = isCapture ? "\(move.from.fileLetter)x\(move.to.name)" : move.to.name
                if let promotion = move.promotion {
                    san += "=\(promotion.letter)"
                }
            } else {
                // Name the source file, rank, or both only when another piece of the same kind can also move there.
                let rivals = legalMoves.filter { other in
                    other.to == move.to && other.from != move.from && self[other.from] == piece
                }
                var disambiguation = ""
                if !rivals.isEmpty {
                    if !rivals.contains(where: { $0.from.file == move.from.file }) {
                        disambiguation = String(move.from.fileLetter)
                    } else if !rivals.contains(where: { $0.from.rank == move.from.rank }) {
                        disambiguation = String(move.from.rank + 1)
                    } else {
                        disambiguation = move.from.name
                    }
                }
                san = "\(piece.kind.letter)\(disambiguation)\(isCapture ? "x" : "")\(move.to.name)"
            }
        }

        let after = applying(move)
        if after.isInCheck {
            san += after.legalMoves.isEmpty ? "#" : "+"
        }
        return san
    }

    /// Resolves a move written in Standard Algebraic Notation (such as `Nbd7`, `exd6`, `O-O-O`, or `e8=Q+`)
    /// to a legal move in this position. Also accepts common variants like `0-0` and `e2-e4`.
    nonisolated func move(fromSAN san: String) throws(SANError) -> Move {
        var text = Substring(san)
        while let last = text.last, "+#!?".contains(last) { text.removeLast() }
        let legal = legalMoves

        if ["O-O", "0-0", "O-O-O", "0-0-0"].contains(text) {
            let targetFile = text.count == 3 ? 6 : 2
            let castle = legal.first { move in
                self[move.from]?.kind == .king && move.from.file == 4 && move.to.file == targetFile
            }
            guard let castle else { throw .illegal }
            return castle
        }

        var promotion: PieceKind?
        if let last = text.last, !last.isNumber {
            guard let kind = PieceKind(letter: last), kind != .pawn, kind != .king else { throw .malformed }
            promotion = kind
            text.removeLast()
            if text.last == "=" { text.removeLast() }
        }

        guard text.count >= 2, let target = Square(text.suffix(2)) else { throw .malformed }
        text.removeLast(2)

        // Piece letters are uppercase; a lowercase letter here is a pawn's file (so `b` is never a bishop).
        var kind = PieceKind.pawn
        if let first = text.first, first.isUppercase {
            guard let pieceKind = PieceKind(letter: first) else { throw .malformed }
            kind = pieceKind
            text.removeFirst()
        }

        // What's left is optional disambiguation plus capture/separator marks.
        var fromFile: Int?
        var fromRank: Int?
        for character in text where !"x:-".contains(character) {
            if let ascii = character.asciiValue, (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(ascii) {
                fromFile = Int(ascii - UInt8(ascii: "a"))
            } else if let digit = character.wholeNumberValue, (1...8).contains(digit) {
                fromRank = digit - 1
            } else {
                throw .malformed
            }
        }

        if kind == .pawn {
            // A pawn move without a source file (like `e4`) is a push along the same file.
            if fromFile == nil { fromFile = target.file }
            // Be lenient with files that omit the promotion piece.
            if promotion == nil, target.rank == 0 || target.rank == 7 { promotion = .queen }
        }

        let candidates = legal.filter { move in
            self[move.from]?.kind == kind
                && move.to == target
                && move.promotion == promotion
                && (fromFile == nil || move.from.file == fromFile)
                && (fromRank == nil || move.from.rank == fromRank)
        }
        guard let move = candidates.first else { throw .illegal }
        guard candidates.count == 1 else { throw .ambiguous }
        return move
    }
}
