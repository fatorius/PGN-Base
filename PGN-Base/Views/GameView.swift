import SwiftUI

/// Shows one game: its header, the board at the current move, navigation controls, annotation
/// editing, and the move list.
struct GameView: View {
    let game: PGNGame
    let database: GameDatabase

    @Environment(\.undoManager) private var undoManager
    @State private var replay: GameReplay?
    /// The number of half-moves played; 0 is the starting position.
    @State private var ply = 0
    @State private var isFlipped = false
    @FocusState private var isEditingComment: Bool

    var body: some View {
        Group {
            if let replay {
                content(for: replay)
            } else {
                ProgressView()
            }
        }
        .task {
            replay = game.replay()
        }
        .navigationSubtitle(game.title)
        .toolbar {
            Button("Flip Board", systemImage: "arrow.up.arrow.down") {
                isFlipped.toggle()
            }
            .help("Flip Board")
        }
    }

    private func content(for replay: GameReplay) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                GameHeaderView(game: game)
                BoardView(
                    position: replay.positions[ply],
                    lastMove: ply > 0 ? replay.moves[ply - 1] : nil,
                    isFlipped: isFlipped
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                navigationControls(lastPly: replay.moves.count)
                annotationEditor
            }
            .padding()
            .frame(minWidth: 360)

            Divider()

            MoveListView(game: game, replay: replay, ply: $ply)
                .frame(width: 240)
        }
    }

    private func navigationControls(lastPly: Int) -> some View {
        HStack(spacing: 16) {
            Button("First Move", systemImage: "chevron.backward.to.line") { ply = 0 }
                .keyboardShortcut(navigationShortcut(.leftArrow, modifiers: .command))
                .disabled(ply == 0)
            Button("Previous Move", systemImage: "chevron.backward") { ply -= 1 }
                .keyboardShortcut(navigationShortcut(.leftArrow))
                .disabled(ply == 0)
            Button("Next Move", systemImage: "chevron.forward") { ply += 1 }
                .keyboardShortcut(navigationShortcut(.rightArrow))
                .disabled(ply == lastPly)
            Button("Last Move", systemImage: "chevron.forward.to.line") { ply = lastPly }
                .keyboardShortcut(navigationShortcut(.rightArrow, modifiers: .command))
                .disabled(ply == lastPly)
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    /// Arrow-key shortcuts for moving through the game, turned off while typing a comment
    /// so the arrow keys move the text cursor instead.
    private func navigationShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> KeyboardShortcut? {
        isEditingComment ? nil : KeyboardShortcut(key, modifiers: modifiers)
    }

    /// Edits the current move's annotation and comment, or the opening comment at the start.
    private var annotationEditor: some View {
        let moveIndex = ply > 0 ? ply - 1 : nil
        let move = moveIndex.map { game.moves[$0] }
        let gameIndex = game.id
        return AnnotationEditor(
            comment: move?.comment ?? (moveIndex == nil ? game.initialComment : nil),
            annotation: move?.annotation,
            isMove: moveIndex != nil,
            isEditingComment: $isEditingComment,
            onCommentChange: { comment in
                database.setComment(comment, forMoveAt: moveIndex, inGameAt: gameIndex, undoManager: undoManager)
            },
            onAnnotationChange: { symbol in
                guard let moveIndex else { return }
                database.setAnnotation(symbol, forMoveAt: moveIndex, inGameAt: gameIndex, undoManager: undoManager)
            }
        )
        // A fresh editor per move, so a pending comment is committed to the move it was typed for.
        .id(ply)
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

    1.e4 e5 2.Nf3 d6 3.d4 Bg4 {This pin is dubious.} 4.dxe5 Bxf3 5.Qxf3 dxe5 6.Bc4 Nf6
    7.Qb3 Qe7 8.Nc3 c6 9.Bg5 b5 10.Nxb5! cxb5 11.Bxb5+ Nbd7 12.O-O-O Rd8 13.Rxd7 Rxd7
    14.Rd1 Qe6 15.Bxd7+ Nxd7 16.Qb8+!! Nxb8 17.Rd8# 1-0
    """
    GameView(
        game: PGNParser.parseGames(from: pgn)[0],
        database: GameDatabase(storage: PGNStorage(original: Data(pgn.utf8)))
    )
    .frame(width: 900, height: 700)
}
