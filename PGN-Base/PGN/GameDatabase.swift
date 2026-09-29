import Foundation
import Observation

/// The games in a PGN file, parsed on demand, with support for editing them.
///
/// Opening a file only records where each game is (see `PGNIndexer`). Headers are parsed when a
/// row needs them, and a game's moves only when it's selected, so files with hundreds of
/// thousands of games open quickly and use little memory.
@MainActor
@Observable
final class GameDatabase {
    @ObservationIgnored let storage: PGNStorage
    private(set) var gameRanges: [Range<Int>] = []
    /// The fraction of the file indexed so far, or `nil` once indexing is complete.
    private(set) var indexingProgress: Double? = 0
    /// Increases with every edit, so views showing game contents refresh.
    private(set) var revision = 0

    /// Header-only games for list rows. Bounded, because people can scroll through huge files.
    @ObservationIgnored private var headerCache: [Int: PGNGame] = [:]
    private static let headerCacheLimit = 5_000
    /// The most recently parsed full game and its replay, since the selected game is requested on every update.
    @ObservationIgnored private var gameCache: PGNGame?
    @ObservationIgnored private var replayCache: (gameIndex: Int, replay: GameReplay)?

    nonisolated init(storage: PGNStorage) {
        self.storage = storage
    }

    var gameCount: Int { gameRanges.count }

    /// Scans the file for games, publishing progress as it goes.
    func buildIndex() async {
        guard indexingProgress != nil else { return }
        let (updates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        async let ranges = Self.indexGames(in: storage.original, reportingTo: continuation)
        for await fraction in updates {
            indexingProgress = fraction
        }
        let result = await ranges
        guard !Task.isCancelled else { return }
        storage.setGameRanges(result)
        gameRanges = result
        indexingProgress = nil
    }

    @concurrent
    nonisolated private static func indexGames(
        in data: Data,
        reportingTo continuation: AsyncStream<Double>.Continuation
    ) async -> [Range<Int>] {
        defer { continuation.finish() }
        return PGNIndexer.gameRanges(in: data) { continuation.yield($0) }
    }

    // MARK: - Reading

    /// The complete game, including its moves.
    func game(at index: Int) -> PGNGame {
        _ = revision  // Views that show a game depend on its edits.
        if let gameCache, gameCache.id == index { return gameCache }
        var game = PGNParser.parseGames(from: text(ofGameAt: index).text).first ?? PGNGame(id: index)
        game.id = index
        gameCache = game
        return game
    }

    /// The positions reached in every line of the game.
    func replay(at index: Int) -> GameReplay {
        let game = game(at: index)
        if let replayCache, replayCache.gameIndex == index { return replayCache.replay }
        let replay = game.replay()
        replayCache = (index, replay)
        return replay
    }

    /// The game's header tags only, without its moves.
    func header(at index: Int) -> PGNGame {
        if let cached = headerCache[index] { return cached }
        let header = PGNGame(id: index, tags: PGNParser.parseTags(from: text(ofGameAt: index).text))
        if headerCache.count >= Self.headerCacheLimit {
            headerCache.removeAll(keepingCapacity: true)
        }
        headerCache[index] = header
        return header
    }

    private func text(ofGameAt index: Int) -> (text: String, encoding: String.Encoding) {
        let bytes = storage.bytes(ofGameAt: index)
        // PGN is usually UTF-8, but older files are often Latin-1.
        if let text = String(data: bytes, encoding: .utf8) { return (text, .utf8) }
        return (String(data: bytes, encoding: .isoLatin1) ?? "", .isoLatin1)
    }

    // MARK: - Editing

    /// Sets the comment after a move, or the game's opening comment for the root path.
    func setComment(_ comment: String, forMoveAt path: MovePath, inGameAt gameIndex: Int, undoManager: UndoManager?) {
        editGame(at: gameIndex, actionName: "Edit Comment", undoManager: undoManager) { text in
            PGNEditor.settingComment(comment, forMoveAt: path, in: text)
        }
    }

    /// Sets a move's quality annotation, such as `!?`, or removes it with `nil`.
    func setAnnotation(_ symbol: String?, forMoveAt path: MovePath, inGameAt gameIndex: Int, undoManager: UndoManager?) {
        editGame(at: gameIndex, actionName: symbol == nil ? "Remove Annotation" : "Annotate Move", undoManager: undoManager) { text in
            PGNEditor.settingAnnotation(symbol, forMoveAt: path, in: text)
        }
    }

    /// Adds a move after the move at `path`, extending the line or starting a new variation.
    /// Returns the new move's path.
    func addMove(
        _ san: String,
        moveNumber: String,
        after path: MovePath,
        inGameAt gameIndex: Int,
        undoManager: UndoManager?
    ) -> MovePath? {
        var newPath: MovePath?
        editGame(at: gameIndex, actionName: "Add Move", undoManager: undoManager) { text in
            guard let result = PGNEditor.addingMove(san, moveNumber: moveNumber, after: path, in: text) else { return text }
            newPath = result.path
            return result.text
        }
        return newPath
    }

    /// Promotes or deletes the variation containing the move at `path`, or deletes the moves after it.
    /// Returns where `currentPath` ends up afterward.
    func apply(
        _ edit: PGNEditor.VariationEdit,
        at path: MovePath,
        inGameAt gameIndex: Int,
        currentPath: MovePath,
        undoManager: UndoManager?
    ) -> MovePath {
        let newPath = PGNEditor.path(currentPath, after: edit, at: path, in: game(at: gameIndex))
        editGame(at: gameIndex, actionName: edit.actionName, undoManager: undoManager) { text in
            PGNEditor.applying(edit, at: path, in: text) ?? text
        }
        return newPath
    }

    private func editGame(at index: Int, actionName: String, undoManager: UndoManager?, _ edit: (String) -> String) {
        let (text, encoding) = text(ofGameAt: index)
        let newText = edit(text)
        // Latin-1 files stay Latin-1; characters it can't represent are replaced.
        guard newText != text, let bytes = newText.data(using: encoding, allowLossyConversion: true) else { return }
        replaceBytes(ofGameAt: index, with: bytes, actionName: actionName, undoManager: undoManager)
    }

    /// Swaps in new bytes for a game and registers the reverse swap, which also marks the
    /// document as changed so it gets saved.
    private func replaceBytes(ofGameAt index: Int, with bytes: Data?, actionName: String, undoManager: UndoManager?) {
        let previous = storage.setBytes(bytes, ofGameAt: index)
        gameCache = nil
        replayCache = nil
        revision += 1
        undoManager?.registerUndo(withTarget: self) { database in
            MainActor.assumeIsolated {
                database.replaceBytes(ofGameAt: index, with: previous, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(actionName)
    }
}
