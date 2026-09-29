import AppKit
import SwiftUI

/// The window for an open PGN file: a list of its games and the selected game.
struct ContentView: View {
    let database: GameDatabase
    /// The file on disk, used to save edits promptly. `nil` for a new, unsaved document.
    let fileURL: URL?

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedGameIndex: Int?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    init(document: PGNDocument, fileURL: URL?) {
        database = document.database
        self.fileURL = fileURL
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            GameListTable(database: database, gameCount: database.gameCount, selection: $selectedGameIndex)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            detail
        }
        // Keyed by the database, so a reverted document (a new instance) gets indexed too.
        .task(id: ObjectIdentifier(database)) {
            await database.buildIndex()
            selectedGameIndex = database.gameCount > 0 ? 0 : nil
            // Only show the game list when there's more than one game to choose from.
            columnVisibility = database.gameCount > 1 ? .all : .detailOnly
        }
        .task(id: database.revision) {
            guard database.revision > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                saveSoon()
            } catch {}
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
            GameView(game: database.game(at: selectedGameIndex), database: database)
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

    /// Asks the system to autosave now, rather than at its next opportunity, so edits reach the
    /// file within about a second. The document is autosaved in place either way.
    private func saveSoon() {
        guard let fileURL, let document = NSDocumentController.shared.document(for: fileURL) else { return }
        document.autosave(withImplicitCancellability: false) { error in
            if let error {
                document.presentError(error)
            }
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
    ContentView(document: PGNDocument(data: Data(pgn.utf8)), fileURL: nil)
        .frame(width: 1100, height: 720)
}
