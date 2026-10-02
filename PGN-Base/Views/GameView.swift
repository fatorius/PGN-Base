import SwiftUI

/// Shows one game: its header, the board at the current move, navigation controls, annotation
/// editing, and the move list. Moves played on the board are added to the game.
struct GameView: View {
    let game: PGNGame
    let database: GameDatabase

    @Environment(\.undoManager) private var undoManager
    /// The current move, as a path through the move tree; empty for the starting position.
    @State private var path: MovePath = []
    @State private var isFlipped = false
    /// The square of the piece picked up to move, if any.
    @State private var selectedSquare: Square?
    /// A pawn move waiting for the choice of promotion piece.
    @State private var pendingPromotion: Move?
    /// Whether the picker for which variation to follow is showing.
    @State private var isChoosingVariation = false
    /// The line last followed at each branch point: the child index taken, keyed by the branch point's path.
    @State private var lastChoice: [MovePath: Int] = [:]
    @FocusState private var isEditingComment: Bool

    var body: some View {
        let replay = database.replay(at: game.id)
        // If an undo removed the current move, fall back to the deepest move that still exists.
        let node = game.deepestNode(along: path)
        let position = replay.positions[node]

        HStack(spacing: 0) {
            VStack(spacing: 12) {
                GameHeaderView(game: game)
                BoardView(
                    position: position ?? replay.positions[0] ?? .standard,
                    lastMove: replay.moves[node],
                    isFlipped: isFlipped,
                    selectedSquare: selectedSquare,
                    targetSquares: targets(in: position),
                    interaction: position.map { boardInteraction(in: $0, at: node, replay: replay) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                navigationControls(at: node, replay: replay)
                annotationEditor(for: node)
            }
            .padding()
            .frame(minWidth: 360)

            Divider()

            MoveListView(game: game, replay: replay, currentNode: node) { selected in
                path = game.path(to: selected)
            } onEdit: { edit, target in
                apply(edit, at: target, current: node)
            }
            .frame(width: 260)
        }
        .onChange(of: node) {
            selectedSquare = nil
            rememberChoices(toReach: node)
        }
        .confirmationDialog(
            "Promote Pawn",
            isPresented: Binding(get: { pendingPromotion != nil }, set: { if !$0 { pendingPromotion = nil } }),
            presenting: pendingPromotion
        ) { move in
            ForEach(Self.promotionChoices, id: \.kind) { choice in
                Button(choice.name) {
                    if let position {
                        play(Move(from: move.from, to: move.to, promotion: choice.kind), in: position, at: node, replay: replay)
                    }
                }
            }
        }
        .navigationSubtitle(game.title)
        .toolbar {
            Menu("Variation", systemImage: "arrow.triangle.branch") {
                VariationCommands(game: game, node: node) { edit in
                    apply(edit, at: node, current: node)
                }
            }
            .help("Promote or delete variations")

            Button("Flip Board", systemImage: "arrow.up.arrow.down") {
                isFlipped.toggle()
            }
            .help("Flip Board")
        }
    }

    /// Promotes or deletes a variation, or deletes the moves after `target`, keeping the board on
    /// the current move wherever it ends up.
    private func apply(_ edit: PGNEditor.VariationEdit, at target: Int, current: Int) {
        path = database.apply(
            edit,
            at: game.path(to: target),
            inGameAt: game.id,
            currentPath: game.path(to: current),
            undoManager: undoManager
        )
    }

    // MARK: - Playing moves

    private static let promotionChoices: [(kind: PieceKind, name: String)] = [
        (.queen, "Queen"), (.rook, "Rook"), (.bishop, "Bishop"), (.knight, "Knight"),
    ]

    /// Where the selected piece can move.
    private func targets(in position: Position?) -> Set<Square> {
        guard let position, let selectedSquare else { return [] }
        return Set(position.legalMoves.filter { $0.from == selectedSquare }.map(\.to))
    }

    /// Clicking one of your pieces picks it up and clicking a destination plays the move; or drag it there.
    private func boardInteraction(in position: Position, at node: Int, replay: GameReplay) -> BoardInteraction {
        BoardInteraction(
            canPickUp: { square in position[square]?.color == position.sideToMove },
            tap: { square in
                if let selectedSquare, tryMove(from: selectedSquare, to: square, in: position, at: node, replay: replay) {
                    return
                }
                if position[square]?.color == position.sideToMove, square != selectedSquare {
                    selectedSquare = square
                } else {
                    selectedSquare = nil
                }
            },
            beginDrag: { square in
                selectedSquare = square
            },
            drop: { from, to in
                if let to, to != from {
                    _ = tryMove(from: from, to: to, in: position, at: node, replay: replay)
                }
                selectedSquare = nil
            }
        )
    }

    /// Plays the move from `from` to `to` if it's legal, asking for the piece first if it's a promotion.
    private func tryMove(from: Square, to: Square, in position: Position, at node: Int, replay: GameReplay) -> Bool {
        let candidates = position.legalMoves.filter { $0.from == from && $0.to == to }
        guard let move = candidates.first else { return false }
        selectedSquare = nil
        if candidates.count > 1 {
            // Several moves to one square means a promotion; ask which piece.
            pendingPromotion = Move(from: move.from, to: move.to)
        } else {
            play(move, in: position, at: node, replay: replay)
        }
        return true
    }

    /// Goes to the move if the game already has it here; otherwise adds it, extending the
    /// line or starting a new variation.
    private func play(_ move: Move, in position: Position, at node: Int, replay: GameReplay) {
        let nodePath = game.path(to: node)
        if let existing = game.nodes[node].children.firstIndex(where: { replay.moves[$0] == move }) {
            path = nodePath + [existing]
            return
        }
        if let newPath = database.addMove(
            position.san(for: move),
            moveNumber: position.moveNumberLabel,
            after: nodePath,
            inGameAt: game.id,
            undoManager: undoManager
        ) {
            path = newPath
        }
    }

    // MARK: - Navigation

    private func navigationControls(at node: Int, replay: GameReplay) -> some View {
        let nodePath = game.path(to: node)
        let siblings = game.nodes[node].parent.map { game.nodes[$0].children.count } ?? 1
        let children = game.nodes[node].children
        let hasNext = !children.isEmpty
        let previousBranch = game.previousBranchPoint(before: node)
        return HStack(spacing: 16) {
            Button("First Move", systemImage: "chevron.backward.to.line") { path = [] }
                .keyboardShortcut(navigationShortcut(.leftArrow, modifiers: .command))
                .disabled(node == 0)
            Button("Previous Branch", systemImage: "arrow.turn.left.up") {
                if let previousBranch { path = game.path(to: previousBranch) }
            }
            .keyboardShortcut(navigationShortcut(.leftArrow, modifiers: .shift))
            .disabled(previousBranch == nil)
            .help("Go back to where the line branches")
            Button("Previous Move", systemImage: "chevron.backward") { path = Array(nodePath.dropLast()) }
                .keyboardShortcut(navigationShortcut(.leftArrow))
                .disabled(node == 0)
            Button("Next Move", systemImage: "chevron.forward") {
                // Where the game branches, ask which line to follow.
                if children.count > 1 {
                    isChoosingVariation = true
                } else {
                    path = nodePath + [0]
                }
            }
            .keyboardShortcut(navigationShortcut(.rightArrow))
            .disabled(!hasNext)
            .popover(isPresented: $isChoosingVariation, arrowEdge: .bottom) {
                let before = replay.positions[node]
                VariationPicker(
                    options: children.map { child in
                        "\(before?.moveNumberLabel ?? "") \(game.nodes[child].san)\(game.nodes[child].annotation ?? "")"
                    },
                    initialSelection: lastChoice[nodePath] ?? 0,
                    onChoose: { index in
                        isChoosingVariation = false
                        path = nodePath + [index]
                    },
                    onCancel: {
                        isChoosingVariation = false
                    }
                )
            }
            Button("Next Branch", systemImage: "arrow.turn.right.down") {
                path = nodePath + rememberedContinuation(from: node, stoppingAtBranch: true)
            }
            .keyboardShortcut(navigationShortcut(.rightArrow, modifiers: .shift))
            .disabled(!hasNext)
            .help("Go ahead to where the line branches")
            Button("End of Line", systemImage: "chevron.forward.to.line") {
                path = nodePath + rememberedContinuation(from: node, stoppingAtBranch: false)
            }
            .keyboardShortcut(navigationShortcut(.rightArrow, modifiers: .command))
            .disabled(!hasNext)

            Divider()
                .frame(height: 20)

            // Switches to the alternatives to the current move, in the order they're written.
            Button("Previous Variation", systemImage: "chevron.up") { switchVariation(from: nodePath, by: -1, count: siblings) }
                .keyboardShortcut(navigationShortcut(.upArrow, modifiers: .option))
                .disabled(siblings < 2)
            Button("Next Variation", systemImage: "chevron.down") { switchVariation(from: nodePath, by: 1, count: siblings) }
                .keyboardShortcut(navigationShortcut(.downArrow, modifiers: .option))
                .disabled(siblings < 2)
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    /// Records, at each branch point on the way to `node`, which line was taken.
    private func rememberChoices(toReach node: Int) {
        let nodePath = game.path(to: node)
        var current = 0
        for (depth, step) in nodePath.enumerated() {
            if game.isBranchPoint(current) {
                lastChoice[Array(nodePath.prefix(depth))] = step
            }
            current = game.nodes[current].children[step]
        }
    }

    /// The steps from `node` along the lines last followed at each branch point (or the first line
    /// where there's none), to the end of the line or, if `stoppingAtBranch`, the next branch point.
    private func rememberedContinuation(from node: Int, stoppingAtBranch: Bool) -> MovePath {
        var nodePath = game.path(to: node)
        var steps: MovePath = []
        var current = node
        while !game.nodes[current].children.isEmpty {
            let children = game.nodes[current].children
            let remembered = lastChoice[nodePath] ?? 0
            let step = children.indices.contains(remembered) ? remembered : 0
            steps.append(step)
            nodePath.append(step)
            current = children[step]
            if stoppingAtBranch, game.isBranchPoint(current) { break }
        }
        return steps
    }

    private func switchVariation(from nodePath: MovePath, by offset: Int, count: Int) {
        guard let last = nodePath.last else { return }
        path = Array(nodePath.dropLast()) + [(last + offset + count) % count]
    }

    /// Keyboard shortcuts for moving through the game, turned off while typing a comment
    /// so the arrow keys move the text cursor instead.
    private func navigationShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> KeyboardShortcut? {
        isEditingComment ? nil : KeyboardShortcut(key, modifiers: modifiers)
    }

    // MARK: - Annotations

    /// Edits the current move's annotation and comment, or the opening comment at the start.
    private func annotationEditor(for node: Int) -> some View {
        let nodePath = game.path(to: node)
        let gameIndex = game.id
        return AnnotationEditor(
            comment: game.nodes[node].comment,
            annotation: game.nodes[node].annotation,
            isMove: node != 0,
            isEditingComment: $isEditingComment,
            onCommentChange: { comment in
                database.setComment(comment, forMoveAt: nodePath, inGameAt: gameIndex, undoManager: undoManager)
            },
            onAnnotationChange: { symbol in
                database.setAnnotation(symbol, forMoveAt: nodePath, inGameAt: gameIndex, undoManager: undoManager)
            }
        )
        // A fresh editor per move, so a pending comment is committed to the move it was typed for.
        .id(nodePath)
    }
}

private struct GameHeaderView: View {
    let game: PGNGame

    var body: some View {
        VStack(spacing: 2) {
            Text("\(player(game.white, elo: game.tag("WhiteElo"))) vs. \(player(game.black, elo: game.tag("BlackElo")))")
                .font(.headline)
            let details = [game.tag("Event"), game.tag("Site"), game.date].compactMap(\.self)
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func player(_ name: String, elo: String?) -> String {
        elo.map { "\(name) (\($0))" } ?? name
    }
}

#Preview {
    let pgn = """
    [Event "Paris Opera"]
    [Date "1858.??.??"]
    [White "Morphy, Paul"]
    [Black "Duke Karl / Count Isouard"]
    [Result "1-0"]

    1.e4 e5 2.Nf3 d6 3.d4 Bg4 {This pin is dubious.} (3...exd4 4.Qxd4 Nc6 (4...Nf6) 5.Bb5) 4.dxe5 Bxf3
    5.Qxf3 dxe5 6.Bc4 Nf6 7.Qb3 Qe7 (7...Qd7 8.Qxb7) 8.Nc3 c6 9.Bg5 b5 10.Nxb5! cxb5 11.Bxb5+ Nbd7
    12.O-O-O Rd8 13.Rxd7 Rxd7 14.Rd1 Qe6 15.Bxd7+ Nxd7 16.Qb8+!! Nxb8 17.Rd8# 1-0

    """
    let storage = PGNStorage(original: Data(pgn.utf8))
    storage.setGameRanges([0..<pgn.utf8.count])
    let database = GameDatabase(storage: storage)
    return GameView(game: database.game(at: 0), database: database)
        .frame(width: 960, height: 720)
}
