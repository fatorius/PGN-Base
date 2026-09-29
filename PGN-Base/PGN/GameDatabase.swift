import Foundation
import Observation

/// The games in a PGN file, parsed on demand.
///
/// Opening a file only records where each game is (see `PGNIndexer`). Headers are parsed when a
/// row needs them, and a game's moves only when it's selected, so files with hundreds of
/// thousands of games open quickly and use little memory.
@MainActor
@Observable
final class GameDatabase {
    private let data: Data
    private(set) var gameRanges: [Range<Int>] = []
    /// The fraction of the file indexed so far, or `nil` once indexing is complete.
    private(set) var indexingProgress: Double? = 0

    /// Header-only games for list rows. Bounded, because people can scroll through huge files.
    @ObservationIgnored private var headerCache: [Int: PGNGame] = [:]
    private static let headerCacheLimit = 5_000

    init(data: Data) {
        self.data = data
    }

    var gameCount: Int { gameRanges.count }

    /// Scans the file for games, publishing progress as it goes.
    func buildIndex() async {
        guard indexingProgress != nil else { return }
        let (updates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        async let ranges = Self.indexGames(in: data, reportingTo: continuation)
        for await fraction in updates {
            indexingProgress = fraction
        }
        let result = await ranges
        guard !Task.isCancelled else { return }
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

    /// The complete game, including its moves.
    func game(at index: Int) -> PGNGame {
        var game = PGNParser.parseGames(from: text(ofGameAt: index)).first ?? PGNGame(id: index)
        game.id = index
        return game
    }

    /// The game's header tags only, without its moves.
    func header(at index: Int) -> PGNGame {
        if let cached = headerCache[index] { return cached }
        let header = PGNGame(id: index, tags: PGNParser.parseTags(from: text(ofGameAt: index)))
        if headerCache.count >= Self.headerCacheLimit {
            headerCache.removeAll(keepingCapacity: true)
        }
        headerCache[index] = header
        return header
    }

    private func text(ofGameAt index: Int) -> String {
        let range = gameRanges[index]
        let bytes = data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)]
        // PGN is usually UTF-8, but older files are often Latin-1.
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
    }
}
