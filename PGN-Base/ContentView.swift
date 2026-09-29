import SwiftUI

/// The window for an open PGN file: a list of its games and the selected game.
struct ContentView: View {
    let document: PGNDocument

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedGameID: PGNGame.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(document: PGNDocument) {
        self.document = document
        _selectedGameID = State(initialValue: document.games.first?.id)
        // Only show the game list when there's more than one game to choose from.
        _columnVisibility = State(initialValue: document.games.count > 1 ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(document.games, selection: $selectedGameID) { game in
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .lineLimit(1)
                    Text([game.tag("Event"), game.date, game.result].compactMap(\.self).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let selectedGameID, document.games.indices.contains(selectedGameID) {
                // A new identity per game resets the current move and board orientation.
                GameView(game: document.games[selectedGameID])
                    .id(selectedGameID)
            } else if document.games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "doc.questionmark",
                    description: Text("This file doesn't contain any PGN games.")
                )
            } else {
                ContentUnavailableView("No Game Selected", systemImage: "checkerboard.rectangle")
            }
        }
        .onAppear {
            // Once a game is open, the welcome window has done its job.
            dismissWindow(id: welcomeWindowID)
        }
    }
}

#Preview {
    let pgn = """
    [White "Morphy, Paul"] [Black "Duke Karl / Count Isouard"] [Event "Paris Opera"]
    1.e4 e5 2.Nf3 d6 3.d4 Bg4 4.dxe5 Bxf3 5.Qxf3 dxe5 6.Bc4 Nf6 7.Qb3 Qe7 1-0
    [White "Anderssen, Adolf"] [Black "Kieseritzky, Lionel"] [Event "London"]
    1.e4 e5 2.f4 exf4 3.Bc4 Qh4+ 4.Kf1 b5 5.Bxb5 Nf6 1-0
    """
    ContentView(document: PGNDocument(games: PGNParser.parseGames(from: pgn)))
        .frame(width: 1100, height: 680)
}
