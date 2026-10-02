import SwiftUI

/// The game's moves as a tree of lines. Each row is a run of moves up to where the game branches,
/// and each move that can follow there starts a row one level in. Rows fold to hide what follows them;
/// the rows leading to the current move are always unfolded. Clicking a move jumps to it.
struct MoveListView: View {
    let game: PGNGame
    let replay: GameReplay
    /// The node whose position is on the board.
    let currentNode: Int
    let onSelect: (Int) -> Void
    /// Reorganizes variations from a move's context menu.
    let onEdit: (PGNEditor.VariationEdit, Int) -> Void

    /// The unfolded rows, by the path of their first move. Paths are used rather than nodes
    /// because they stay valid when moves are added.
    @State private var expanded: Set<MovePath> = []

    private static let indent: CGFloat = 14

    var body: some View {
        let model = MoveTreeModel(game: game)
        let rows = model.rows(expanded: expanded)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                            .id(row.id)
                    }

                    if let error = replay.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    }

                    Text(game.result)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding()
            }
            .onAppear {
                // Start by showing the moves that can follow each top-level line.
                expanded.formUnion(model.roots.map(\.path))
                expanded.formUnion(model.segmentPaths(showing: game.path(to: currentNode)))
            }
            .onChange(of: currentNode) { oldNode, newNode in
                // Expand only when the current move goes into another row, so that stepping
                // through a row's moves keeps the rows the user collapsed, like the main line, collapsed.
                let newPath = game.path(to: newNode)
                guard oldNode < game.nodes.count,
                      model.segment(containing: game.path(to: oldNode))?.path != model.segment(containing: newPath)?.path
                else { return }
                let unfolded = expanded.union(model.segmentPaths(showing: newPath))
                expanded = unfolded
                if let rowID = model.rows(expanded: unfolded).first(where: { $0.segment.nodes.contains(newNode) })?.id {
                    withAnimation { proxy.scrollTo(rowID) }
                }
            }
        }
    }

    private func rowView(_ row: MoveTreeModel.Row) -> some View {
        let segment = row.segment
        return HStack(alignment: .top, spacing: 2) {
            if segment.isCollapsible {
                Button {
                    toggle(row)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.indent, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(row.isExpanded ? "Collapse this line to its first move" : "Show this line")
                .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
            } else {
                Color.clear.frame(width: Self.indent, height: 1)
            }

            // The line written first in the PGN, the one Promote Variation moves others into. Every row
            // keeps the space for it, so sibling lines start at the same place.
            Image(systemName: "star.fill")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .frame(width: 10, height: 20)
                .opacity(segment.isFirstAlternative ? 1 : 0)
                .help(segment.isFirstAlternative ? "Main line" : "")
                .accessibilityLabel("Main line")
                .accessibilityHidden(!segment.isFirstAlternative)

            FlowLayout(spacing: 1, lineSpacing: 1) {
                // A collapsed line shows only its first move.
                let shown = row.isExpanded ? segment.nodes : [segment.nodes[0]]
                ForEach(Array(shown.enumerated()), id: \.element) { offset, node in
                    moveButton(for: node, label: label(for: node, numbered: offset == 0))
                }
                if !row.isExpanded, segment.isCollapsible {
                    Button("…") { toggle(row) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .frame(height: 20)
                        .help("Show this line")
                        .accessibilityLabel("Show line")
                    if !segment.children.isEmpty {
                        Text(segment.lineCount == 1 ? "1 line" : "\(segment.lineCount) lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .frame(height: 20)
                    }
                }
            }
        }
        .padding(.vertical, 1)
        .padding(.leading, CGFloat(row.depth) * Self.indent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            // A guide line for each level, so sibling lines are easy to line up by eye.
            HStack(spacing: 0) {
                ForEach(0..<row.depth, id: \.self) { _ in
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                        .frame(width: Self.indent)
                }
            }
        }
    }

    /// Collapses the line to its first move, hiding the lines that follow it, or shows it again.
    private func toggle(_ row: MoveTreeModel.Row) {
        withAnimation(.snappy) {
            if row.isExpanded {
                expanded.remove(row.segment.path)
            } else {
                expanded.insert(row.segment.path)
            }
        }
    }

    private func moveButton(for node: Int, label: String) -> some View {
        let isCurrent = node == currentNode
        let isPlayable = replay.positions[node] != nil
        return Button {
            onSelect(node)
        } label: {
            HStack(spacing: 2) {
                Text(label)
                if game.nodes[node].comment != nil {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Has comment")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isCurrent ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 4))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isPlayable)
        .contextMenu {
            VariationCommands(game: game, node: node) { edit in
                onEdit(edit, node)
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The move as shown in the tree. White's moves are always numbered; Black's only when `numbered`,
    /// where a row starts.
    private func label(for node: Int, numbered: Bool) -> String {
        let before = game.nodes[node].parent.flatMap { replay.positions[$0] }
        let san = game.nodes[node].san + (game.nodes[node].annotation ?? "")
        let isWhite = before?.sideToMove != .black
        return (isWhite || numbered) ? "\(before?.moveNumberLabel ?? "")\(san)" : san
    }
}

/// A game's move tree grouped into segments: runs of moves that end where the game branches.
///
/// Every move that can follow a branch point starts its own segment, including the main
/// continuation, so all the alternatives there are siblings of equal standing.
struct MoveTreeModel {
    struct Segment {
        /// The path of the segment's first move.
        let path: MovePath
        /// The segment's moves in order; each but the last has exactly one move following it.
        let nodes: [Int]
        /// The segments that start with each move following the last one, when there are two or more.
        let children: [Segment]
        /// Whether this is the first of several alternatives — the main line in PGN terms.
        let isFirstAlternative: Bool
        /// How many lines end below this segment, counting itself when nothing follows.
        let lineCount: Int

        /// Whether collapsing to the first move would hide anything.
        var isCollapsible: Bool { nodes.count > 1 || !children.isEmpty }
    }

    struct Row: Identifiable {
        let segment: Segment
        let depth: Int
        let isExpanded: Bool

        /// The segment's first node, unique because each node is in one segment.
        var id: Int { segment.nodes[0] }
    }

    /// The segments starting with the game's first moves; usually just one.
    let roots: [Segment]

    init(game: PGNGame) {
        roots = Self.segments(following: 0, at: [], in: game)
    }

    /// The segments starting with each move after `node`, whose path is `path`.
    private static func segments(following node: Int, at path: MovePath, in game: PGNGame) -> [Segment] {
        let children = game.nodes[node].children
        return children.enumerated().map { index, child in
            segment(startingAt: child, path: path + [index], isFirstAlternative: index == 0 && children.count > 1, in: game)
        }
    }

    private static func segment(startingAt start: Int, path: MovePath, isFirstAlternative: Bool, in game: PGNGame) -> Segment {
        var nodes = [start]
        var last = start
        while game.nodes[last].children.count == 1 {
            last = game.nodes[last].children[0]
            nodes.append(last)
        }
        let lastPath = path + Array(repeating: 0, count: nodes.count - 1)
        let children = game.isBranchPoint(last) ? segments(following: last, at: lastPath, in: game) : []
        return Segment(
            path: path,
            nodes: nodes,
            children: children,
            isFirstAlternative: isFirstAlternative,
            lineCount: children.isEmpty ? 1 : children.reduce(0) { $0 + $1.lineCount }
        )
    }

    /// The visible rows, in order. Segments in `expanded` show all their moves with their children
    /// below; the others show only their first move.
    func rows(expanded: Set<MovePath>) -> [Row] {
        var rows: [Row] = []
        func append(_ segments: [Segment], depth: Int) {
            for segment in segments {
                let isExpanded = expanded.contains(segment.path)
                rows.append(Row(segment: segment, depth: depth, isExpanded: isExpanded))
                if isExpanded {
                    append(segment.children, depth: depth + 1)
                }
            }
        }
        append(roots, depth: 0)
        return rows
    }

    /// The paths of the segments that must be expanded for the move at `nodePath` to be visible:
    /// the one holding it and those above it.
    func segmentPaths(showing nodePath: MovePath) -> [MovePath] {
        segments(along: nodePath).map(\.path)
    }

    /// The segment holding the move at `nodePath`, or `nil` for the starting position.
    func segment(containing nodePath: MovePath) -> Segment? {
        segments(along: nodePath).last
    }

    /// The segments from the top level down to the one holding the move at `nodePath`.
    private func segments(along nodePath: MovePath) -> [Segment] {
        var result: [Segment] = []
        var level = roots
        // Sibling segments' paths differ only in their last step, so at most one is a prefix.
        while let segment = level.first(where: { nodePath.starts(with: $0.path) }) {
            result.append(segment)
            if nodePath.count < segment.path.count + segment.nodes.count { break }
            level = segment.children
        }
        return result
    }
}

#Preview {
    let pgn = """
    1. e4 e5 2. Nf3 Nc6 (2... d6 3. d4 exd4 4. Nxd4) (2... Nf6 3. Nxe5 d6 (3... Qe7 4. Nf3) (3... Nxe4 4. Qe2)
    4. Nf3 Nxe4) (2... f5 3. Nxe5) 3. Bb5 a6 (3... Nf6 4. O-O) 4. Ba4 *
    """
    let game = PGNParser.parseGames(from: pgn)[0]
    // The current move is 4. Nf3 in the 2... Nf6 variation, so the rows leading to it are unfolded.
    let current = game.node(at: [0, 0, 0, 2, 0, 0, 0]) ?? 0
    MoveListView(game: game, replay: game.replay(), currentNode: current, onSelect: { _ in }, onEdit: { _, _ in })
        .frame(width: 260, height: 420)
}
