import Foundation

/// One of the two sides in a chess game.
nonisolated enum PieceColor: Sendable, Hashable {
    case white, black

    var opponent: PieceColor { self == .white ? .black : .white }
}

nonisolated enum PieceKind: Sendable, Hashable {
    case pawn, knight, bishop, rook, queen, king

    /// Creates a piece kind from its FEN/SAN letter, ignoring case (`n` and `N` are both knights).
    init?(letter: Character) {
        switch letter {
        case "P", "p": self = .pawn
        case "N", "n": self = .knight
        case "B", "b": self = .bishop
        case "R", "r": self = .rook
        case "Q", "q": self = .queen
        case "K", "k": self = .king
        default: return nil
        }
    }

    /// The uppercase letter used in SAN; empty for pawns.
    var letter: String {
        switch self {
        case .pawn: ""
        case .knight: "N"
        case .bishop: "B"
        case .rook: "R"
        case .queen: "Q"
        case .king: "K"
        }
    }
}

nonisolated struct Piece: Sendable, Hashable {
    let color: PieceColor
    let kind: PieceKind
}

/// A square on the board. Files and ranks are zero-based, so a1 is `(0, 0)` and h8 is `(7, 7)`.
nonisolated struct Square: Sendable, Hashable {
    let file: Int
    let rank: Int

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    /// Creates a square from its algebraic name, such as `e4`.
    init?(_ name: some StringProtocol) {
        let bytes = Array(name.utf8)
        guard bytes.count == 2,
              (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(bytes[0]),
              (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(bytes[1]) else { return nil }
        self.init(file: Int(bytes[0] - UInt8(ascii: "a")), rank: Int(bytes[1] - UInt8(ascii: "1")))
    }

    static let all: [Square] = (0..<64).map { Square(file: $0 % 8, rank: $0 / 8) }

    /// Index into a 64-element board array, with a1 at 0 and h8 at 63.
    var index: Int { rank * 8 + file }

    var fileLetter: Character { Character(Unicode.Scalar(UInt8(ascii: "a") + UInt8(file))) }

    var name: String { "\(fileLetter)\(rank + 1)" }

    /// The square shifted by the given number of files and ranks, or `nil` if that falls off the board.
    func offset(file fileDelta: Int, rank rankDelta: Int) -> Square? {
        let newFile = file + fileDelta
        let newRank = rank + rankDelta
        guard (0..<8).contains(newFile), (0..<8).contains(newRank) else { return nil }
        return Square(file: newFile, rank: newRank)
    }
}

nonisolated struct Move: Sendable, Hashable {
    let from: Square
    let to: Square
    var promotion: PieceKind? = nil
}
