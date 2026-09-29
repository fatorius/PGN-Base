import Foundation

/// Finds where each game starts and ends in PGN data without parsing the games.
///
/// Works directly on bytes, so it's fast on very large files and handles both UTF-8 and Latin-1
/// (every character that matters here is ASCII). A new game starts at a tag (`[`) that follows movetext.
nonisolated enum PGNIndexer {
    /// How often, in bytes, to report progress and check for cancellation.
    private static let progressInterval = 4 * 1_048_576

    /// Returns the byte range of each game, relative to the start of `data`.
    /// Returns an empty array if the task is cancelled.
    static func gameRanges(in data: Data, progress: (Double) -> Void) -> [Range<Int>] {
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let count = bytes.count
            var ranges: [Range<Int>] = []
            var gameStart = 0
            var hasTags = false
            var hasMovetext = false
            var nextProgressReport = progressInterval
            var index = 0

            /// Moves `index` to the next occurrence of `terminator`, or the end of the data.
            func skip(to terminator: UInt8) {
                while index < count, bytes[index] != terminator { index += 1 }
            }

            while index < count {
                if index >= nextProgressReport {
                    if Task.isCancelled { return [] }
                    progress(Double(index) / Double(count))
                    nextProgressReport += progressInterval
                }

                switch bytes[index] {
                case UInt8(ascii: "["):
                    if hasMovetext {
                        ranges.append(gameStart..<index)
                        gameStart = index
                        hasMovetext = false
                    }
                    hasTags = true
                    skipTag(in: bytes, from: &index)

                case UInt8(ascii: "{"):
                    skip(to: UInt8(ascii: "}"))

                case UInt8(ascii: ";"):
                    skip(to: UInt8(ascii: "\n"))

                case UInt8(ascii: "%") where index == 0 || bytes[index - 1] == UInt8(ascii: "\n"):
                    skip(to: UInt8(ascii: "\n"))

                case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                    break

                default:
                    hasMovetext = true
                }
                index += 1
            }

            if hasTags || hasMovetext {
                ranges.append(gameStart..<count)
            }
            progress(1)
            return ranges
        }
    }

    /// Moves `index` from a tag's `[` to its closing `]`, ignoring brackets inside the quoted value.
    /// Stops at the end of the line if the tag is never closed.
    private static func skipTag(in bytes: UnsafeBufferPointer<UInt8>, from index: inout Int) {
        var isInQuotes = false
        index += 1
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\") where isInQuotes:
                index += 1
            case UInt8(ascii: "\""):
                isInQuotes.toggle()
            case UInt8(ascii: "]") where !isInQuotes:
                return
            case UInt8(ascii: "\n"):
                return
            default:
                break
            }
            index += 1
        }
    }
}
