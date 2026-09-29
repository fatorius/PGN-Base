import SwiftUI

/// The window for an open PGN file: a list of its games and the selected game.
struct ContentView: View {
    @State private var database: GameDatabase

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedGameIndex: Int?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    init(document: PGNDocument) {
        _database = State(initialValue: GameDatabase(data: document.data))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            GameListTable(database: database, gameCount: database.gameCount, selection: $selectedGameIndex)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            detail
        }
        .task {
            await database.buildIndex()
            selectedGameIndex = database.gameCount > 0 ? 0 : nil
            // Only show the game list when there's more than one game to choose from.
            columnVisibility = database.gameCount > 1 ? .all : .detailOnly
        }
        .onAppear {
            // Once a file is open, the welcome window has done its job.
            dismissWindow(id: welcomeWindowID)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let progress = database.indexingProgress {
            ProgressView(value: progress) {
                Text("Reading games…")
            } currentValueLabel: {
                Text(progress, format: .percent.precision(.fractionLength(0)))
            }
            .frame(width: 280)
        } else if let selectedGameIndex, selectedGameIndex < database.gameCount {
            // A new identity per game resets the current move and board orientation.
            GameView(game: database.game(at: selectedGameIndex))
                .id(selectedGameIndex)
        } else if database.gameCount == 0 {
            ContentUnavailableView(
                "No Games",
                systemImage: "doc.questionmark",
                description: Text("This file doesn't contain any PGN games.")
            )
        } else {
            ContentUnavailableView("No Game Selected", systemImage: "checkerboard.rectangle")
        }
    }
}

#Preview {
    let pgn = """
    [White "Morphy, Paul"] [Black "Duke Karl / Count Isouard"] [Event "Paris Opera"] [Result "1-0"]
    1.e4 e5 2.Nf3 d6 3.d4 Bg4 4.dxe5 Bxf3 5.Qxf3 dxe5 6.Bc4 Nf6 7.Qb3 Qe7 1-0
    [White "Anderssen, Adolf"] [Black "Kieseritzky, Lionel"] [Event "London"] [Result "1-0"]
    1.e4 e5 2.f4 exf4 3.Bc4 Qh4+ 4.Kf1 b5 5.Bxb5 Nf6 1-0
    """
    ContentView(document: PGNDocument(data: Data(pgn.utf8)))
        .frame(width: 1100, height: 680)
}
