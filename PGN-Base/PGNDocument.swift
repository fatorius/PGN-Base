import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Portable Game Notation, as declared by the system's Chess app.
    nonisolated static var pgn: UTType { UTType(importedAs: "com.apple.chess.pgn") }
}

/// A PGN file, which may contain any number of games.
nonisolated struct PGNDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pgn]

    var games: [PGNGame]

    init(games: [PGNGame] = []) {
        self.games = games
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // PGN is usually UTF-8, but older files are often Latin-1.
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        games = PGNParser.parseGames(from: text)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // The app only views PGN files for now.
        throw CocoaError(.fileWriteNoPermission)
    }
}
