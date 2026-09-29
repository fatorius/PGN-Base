import Foundation
import Synchronization

/// The bytes of a PGN file plus any edited games, shared between the UI and background saving.
///
/// The original file stays memory-mapped and is never modified; edited games are kept
/// separately and spliced in when the file is written.
nonisolated final class PGNStorage: Sendable {
    let original: Data

    private struct State {
        var gameRanges: [Range<Int>] = []
        var edits: [Int: Data] = [:]
    }

    private let state = Mutex(State())

    init(original: Data) {
        self.original = original
    }

    func setGameRanges(_ ranges: [Range<Int>]) {
        state.withLock { $0.gameRanges = ranges }
    }

    /// The game's current bytes: the edited version if there is one, otherwise the original.
    func bytes(ofGameAt index: Int) -> Data {
        state.withLock { state in
            if let edited = state.edits[index] { return edited }
            guard state.gameRanges.indices.contains(index) else { return Data() }
            return original.subdata(in: state.gameRanges[index].offset(by: original.startIndex))
        }
    }

    /// Replaces the game's bytes, or restores the original with `nil`. Returns the previous edit, if any.
    @discardableResult
    func setBytes(_ bytes: Data?, ofGameAt index: Int) -> Data? {
        state.withLock { state in
            let previous = state.edits[index]
            state.edits[index] = bytes
            return previous
        }
    }

    func snapshot() -> PGNSnapshot {
        state.withLock { PGNSnapshot(original: original, gameRanges: $0.gameRanges, edits: $0.edits) }
    }
}

/// The file's contents at a moment in time, ready to be written.
nonisolated struct PGNSnapshot: Sendable {
    let original: Data
    let gameRanges: [Range<Int>]
    let edits: [Int: Data]

    /// Streams the file to `url`, copying unchanged stretches straight from the original,
    /// so even very large files are written without being loaded into memory.
    func write(to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var unchangedStart = 0
        for index in edits.keys.sorted() where gameRanges.indices.contains(index) {
            let range = gameRanges[index]
            try handle.write(contentsOf: original[(unchangedStart..<range.lowerBound).offset(by: original.startIndex)])
            try handle.write(contentsOf: edits[index] ?? Data())
            unchangedStart = range.upperBound
        }
        try handle.write(contentsOf: original[(unchangedStart..<original.count).offset(by: original.startIndex)])
    }
}

private extension Range<Int> {
    nonisolated func offset(by amount: Int) -> Range<Int> {
        (lowerBound + amount)..<(upperBound + amount)
    }
}
