import Combine  // Provides ObservableObject's default publisher, which ReferenceFileDocument requires.
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Portable Game Notation, as declared by the system's Chess app.
    nonisolated static var pgn: UTType { UTType(importedAs: "com.apple.chess.pgn") }
}

/// A PGN file, which may contain any number of games.
///
/// Reading only captures the file's bytes; `GameDatabase` finds and parses the games afterward,
/// so even very large files open without blocking. Edits are autosaved in place by the system.
nonisolated final class PGNDocument: ReferenceFileDocument {
    static let readableContentTypes: [UTType] = [.pgn]

    let storage: PGNStorage
    let database: GameDatabase

    init(data: Data = Data()) {
        storage = PGNStorage(original: data)
        database = GameDatabase(storage: storage)
    }

    init(configuration: ReadConfiguration) throws {
        // File wrappers memory-map regular files by default, so this doesn't copy the whole file.
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        storage = PGNStorage(original: data)
        database = GameDatabase(storage: storage)
    }

    func snapshot(contentType: UTType) throws -> PGNSnapshot {
        storage.snapshot()
    }

    func fileWrapper(snapshot: PGNSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        // Stream to a temporary file instead of building the whole file in memory.
        let temporaryURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pgn")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try snapshot.write(to: temporaryURL)
        let wrapper = try FileWrapper(url: temporaryURL)
        // Load (memory-map) the contents now, while the temporary file still exists.
        _ = wrapper.regularFileContents
        return wrapper
    }
}
