import SwiftUI

/// How the board responds to clicks and drags.
struct BoardInteraction {
    /// Whether the piece on the square can be picked up.
    var canPickUp: (Square) -> Bool
    var tap: (Square) -> Void
    /// A piece started being dragged from the square.
    var beginDrag: (Square) -> Void
    /// A dragged piece was dropped; `to` is `nil` when it's dropped off the board.
    var drop: (_ from: Square, _ to: Square?) -> Void
}

/// Draws a chess position, highlighting the last move and a king in check. With an `interaction`,
/// pieces can be clicked or dragged, and a selected piece's legal destinations are marked.
struct BoardView: View {
    let position: Position
    var lastMove: Move?
    var isFlipped = false
    var selectedSquare: Square?
    var targetSquares: Set<Square> = []
    var interaction: BoardInteraction?

    private struct Drag {
        let from: Square
        var location: CGPoint
    }

    @State private var drag: Drag?

    /// Ranks from top to bottom, as seen by the viewer.
    private var ranks: [Int] { isFlipped ? Array(0..<8) : Array((0..<8).reversed()) }
    /// Files from left to right, as seen by the viewer.
    private var files: [Int] { isFlipped ? Array((0..<8).reversed()) : Array(0..<8) }

    var body: some View {
        GeometryReader { proxy in
            let squareSize = min(proxy.size.width, proxy.size.height) / 8
            let checkedKing = position.isInCheck ? position.kingSquare(of: position.sideToMove) : nil
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(ranks, id: \.self) { rank in
                    GridRow {
                        ForEach(files, id: \.self) { file in
                            let square = Square(file: file, rank: rank)
                            BoardSquareView(
                                square: square,
                                piece: position[square],
                                isHighlighted: square == lastMove?.from || square == lastMove?.to,
                                isInCheck: square == checkedKing,
                                isSelected: square == selectedSquare,
                                isTarget: targetSquares.contains(square),
                                isLifted: square == drag?.from,
                                showsFileLabel: rank == ranks.last,
                                showsRankLabel: file == files.first,
                                size: squareSize,
                                onTap: interaction.map { interaction in { interaction.tap(square) } }
                            )
                        }
                    }
                }
            }
            .gesture(boardGesture(squareSize: squareSize))
            .clipShape(.rect(cornerRadius: 4))
            .shadow(radius: 3, y: 1)
            .overlay(alignment: .topLeading) {
                // The dragged piece follows the pointer, slightly enlarged, and may go past the edge.
                if let drag, let piece = position[drag.from] {
                    PieceView(piece: piece, size: squareSize * 1.15)
                        .position(drag.location)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chessboard")
    }

    /// One gesture for both clicks and drags: moving a few points turns a press on a movable piece into a drag.
    private func boardGesture(squareSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let interaction else { return }
                if drag != nil {
                    drag?.location = value.location
                } else if hypot(value.translation.width, value.translation.height) > 3,
                          let from = square(at: value.startLocation, squareSize: squareSize),
                          interaction.canPickUp(from) {
                    drag = Drag(from: from, location: value.location)
                    interaction.beginDrag(from)
                }
            }
            .onEnded { value in
                guard let interaction else { return }
                if let drag {
                    interaction.drop(drag.from, square(at: value.location, squareSize: squareSize))
                    self.drag = nil
                } else if let square = square(at: value.startLocation, squareSize: squareSize) {
                    interaction.tap(square)
                }
            }
    }

    /// The square under a point in the board's own coordinates.
    private func square(at point: CGPoint, squareSize: CGFloat) -> Square? {
        guard squareSize > 0, point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / squareSize)
        let row = Int(point.y / squareSize)
        guard files.indices.contains(column), ranks.indices.contains(row) else { return nil }
        return Square(file: files[column], rank: ranks[row])
    }
}

private struct BoardSquareView: View {
    let square: Square
    let piece: Piece?
    let isHighlighted: Bool
    let isInCheck: Bool
    let isSelected: Bool
    let isTarget: Bool
    /// Whether this square's piece is being dragged.
    let isLifted: Bool
    let showsFileLabel: Bool
    let showsRankLabel: Bool
    let size: CGFloat
    /// Used for the accessibility action; the board handles pointer input itself.
    let onTap: (() -> Void)?

    private static let lightColor = Color(red: 0.94, green: 0.85, blue: 0.71)
    private static let darkColor = Color(red: 0.71, green: 0.53, blue: 0.39)
    private static let markerColor = Color(red: 0.08, green: 0.33, blue: 0.1)

    // a1 is a dark square.
    private var isLight: Bool { (square.file + square.rank) % 2 == 1 }

    var body: some View {
        ZStack {
            Rectangle().fill(isLight ? Self.lightColor : Self.darkColor)
            if isHighlighted {
                Rectangle().fill(Color.yellow.opacity(0.4))
            }
            if isSelected {
                Rectangle().fill(Self.markerColor.opacity(0.45))
            }
            if isInCheck {
                RadialGradient(colors: [.red, .red.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.6)
            }
            if let piece {
                PieceView(piece: piece, size: size)
                    .opacity(isLifted ? 0.3 : 1)
            }
            if isTarget {
                // A dot on an empty square, a ring around a piece that can be captured.
                if piece == nil {
                    Circle()
                        .fill(Self.markerColor.opacity(0.45))
                        .frame(width: size * 0.3, height: size * 0.3)
                } else {
                    Circle()
                        .strokeBorder(Self.markerColor.opacity(0.45), lineWidth: size * 0.08)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showsFileLabel { coordinateLabel(String(square.fileLetter)) }
        }
        .overlay(alignment: .topLeading) {
            if showsRankLabel { coordinateLabel(String(square.rank + 1)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(isSelected ? "Selected" : isTarget ? "Legal move" : "")
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction {
            onTap?()
        }
    }

    private func coordinateLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size * 0.16, weight: .semibold))
            .foregroundStyle(isLight ? Self.darkColor : Self.lightColor)
            .padding(size * 0.04)
            .accessibilityHidden(true)
    }

    private var accessibilityDescription: String {
        guard let piece else { return square.name }
        return "\(square.name), \(piece.accessibilityName)"
    }
}

/// Draws a piece using the filled Unicode chess glyph for both colors, so the shapes match.
/// White pieces get a black outline so they stand out on light squares.
private struct PieceView: View {
    let piece: Piece
    let size: CGFloat

    var body: some View {
        let glyph = Text(piece.kind.filledGlyph).font(.system(size: size * 0.8))
        if piece.color == .white {
            let width = max(1, size * 0.02)
            // Chained hard shadows in four directions trace an outline around the glyph.
            glyph
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 0, x: width)
                .shadow(color: .black, radius: 0, x: -width)
                .shadow(color: .black, radius: 0, y: width)
                .shadow(color: .black, radius: 0, y: -width)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        } else {
            glyph
                .foregroundStyle(.black)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        }
    }
}

private extension PieceKind {
    // U+FE0E asks for the text presentation, so the pawn isn't drawn as an emoji.
    var filledGlyph: String {
        switch self {
        case .king: "\u{265A}\u{FE0E}"
        case .queen: "\u{265B}\u{FE0E}"
        case .rook: "\u{265C}\u{FE0E}"
        case .bishop: "\u{265D}\u{FE0E}"
        case .knight: "\u{265E}\u{FE0E}"
        case .pawn: "\u{265F}\u{FE0E}"
        }
    }
}

private extension Piece {
    var accessibilityName: String {
        let colorName = color == .white ? "white" : "black"
        let kindName = switch kind {
        case .pawn: "pawn"
        case .knight: "knight"
        case .bishop: "bishop"
        case .rook: "rook"
        case .queen: "queen"
        case .king: "king"
        }
        return "\(colorName) \(kindName)"
    }
}

#Preview {
    let position = Position(fen: "r1bqkbnr/pppp1Qpp/2n5/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4")!
    BoardView(position: position, lastMove: Move(from: Square("h5")!, to: Square("f7")!))
        .frame(width: 480, height: 480)
        .padding()
}
