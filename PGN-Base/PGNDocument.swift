import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Portable Game Notation, as declared by the system's Chess app.
    nonisolated static var pgn: UTType { UTType(importedAs: "com.apple.chess.pgn") }
}

/// A PGN file, which may contain any number of games.
///
/// Reading only captures the file's bytes; `GameDatabase` finds and parses the games afterward,
/// so even very large files open without blocking.
nonisolated struct PGNDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pgn]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        // File wrappers memory-map regular files by default, so this doesn't copy the whole file.
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // The app only views PGN files for now.
        throw CocoaError(.fileWriteNoPermission)
    }
}
