import SwiftUI

/// The game's moves: the main line in numbered pairs, with each variation as an indented
/// paragraph below the move it's an alternative to. Clicking a move jumps to it.
struct MoveListView: View {
    let game: PGNGame
    let replay: GameReplay
    /// The node whose position is on the board.
    let currentNode: Int
    let onSelect: (Int) -> Void
    /// Reorganizes variations from a move's context menu.
    let onEdit: (PGNEditor.VariationEdit, Int) -> Void

    var body: some View {
        let model = MoveListModel(game: game, replay: replay)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.items) { item in
                        switch item.kind {
                        case .row(let number, let white, let black):
                            HStack(spacing: 4) {
                                Text("\(number).")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .trailing)
                                mainLineButton(for: white, placeholder: "…")
                                mainLineButton(for: black, placeholder: "")
                            }
                            .id(item.id)
                        case .variation(let tokens):
                            variationBlock(tokens)
                                .id(item.id)
                        }
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
            .onChange(of: currentNode) {
                guard let itemID = model.itemIDs[currentNode] else { return }
                withAnimation { proxy.scrollTo(itemID) }
            }
        }
    }

    @ViewBuilder
    private func mainLineButton(for node: Int?, placeholder: String) -> some View {
        if let node {
            moveButton(for: node, label: game.nodes[node].san + (game.nodes[node].annotation ?? ""))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(placeholder)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
    }

    private func variationBlock(_ tokens: [MoveListModel.Token]) -> some View {
        FlowLayout(spacing: 2, lineSpacing: 1) {
            ForEach(tokens) { token in
                switch token {
                case .move(let node, let label):
                    moveButton(for: node, label: label)
                case .open:
                    Text("(").foregroundStyle(.secondary)
                case .close:
                    Text(")").foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 2)
        }
        .padding(.leading, 30)
        .padding(.vertical, 3)
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
            .padding(.horizontal, 5)
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
}

/// The move list's rows and variation paragraphs, built from a game's move tree.
struct MoveListModel {
    enum Kind {
        /// A numbered main-line row. Either move can be missing, when a variation interrupts the pair.
        case row(number: Int, white: Int?, black: Int?)
        /// A variation branching from the main line, with any nested variations in parentheses.
        case variation([Token])
    }

    struct Item: Identifiable {
        /// The first node shown in the item; unique because each node appears once.
        let id: Int
        var kind: Kind
    }

    enum Token: Identifiable {
        case move(node: Int, label: String)
        case open(Int)
        case close(Int)

        var id: String {
            switch self {
            case .move(let node, _): "m\(node)"
            case .open(let node): "(\(node)"
            case .close(let node): ")\(node)"
            }
        }
    }

    private(set) var items: [Item] = []
    /// The item showing each node, for scrolling to the current move.
    private(set) var itemIDs: [Int: Int] = [:]

    init(game: PGNGame, replay: GameReplay) {
        // Whether the last row has a White move and room for Black's reply.
        var rowAwaitsBlack = false
        for node in game.mainLine {
            guard let parent = game.nodes[node].parent else { continue }
            let before = replay.positions[parent]
            let number = before?.fullmoveNumber ?? 0
            let isWhite = before?.sideToMove != .black

            if !isWhite, rowAwaitsBlack, let last = items.indices.last, case .row(let rowNumber, let white, _) = items[last].kind {
                items[last].kind = .row(number: rowNumber, white: white, black: node)
                itemIDs[node] = items[last].id
            } else {
                items.append(Item(id: node, kind: .row(number: number, white: isWhite ? node : nil, black: isWhite ? nil : node)))
                itemIDs[node] = node
            }
            rowAwaitsBlack = isWhite

            // Variations are alternatives to this move, so they branch from its parent.
            let alternatives = game.nodes[parent].children.dropFirst()
            for alternative in alternatives {
                var tokens: [Token] = []
                Self.appendLine(startingAt: alternative, game: game, replay: replay, item: alternative, tokens: &tokens, itemIDs: &itemIDs)
                items.append(Item(id: alternative, kind: .variation(tokens)))
            }
            if !alternatives.isEmpty {
                rowAwaitsBlack = false
            }
        }
    }

    /// Adds a line's moves as tokens, with the variations inside it in parentheses.
    private static func appendLine(
        startingAt start: Int,
        game: PGNGame,
        replay: GameReplay,
        item: Int,
        tokens: inout [Token],
        itemIDs: inout [Int: Int]
    ) {
        var node: Int? = start
        var needsNumber = true
        while let current = node {
            let parent = game.nodes[current].parent ?? 0
            let before = replay.positions[parent]
            let isWhite = before?.sideToMove != .black
            let san = game.nodes[current].san + (game.nodes[current].annotation ?? "")
            // Number White's moves, and Black's where the line starts or resumes after a nested variation.
            let label = (isWhite || needsNumber) ? "\(before?.moveNumberLabel ?? "")\(san)" : san
            tokens.append(.move(node: current, label: label))
            itemIDs[current] = item
            needsNumber = false

            // Alternatives to this move are nested inside the line, but only where it continues its
            // parent's line; the line's first move has its alternatives shown at the level above.
            if game.nodes[parent].children.first == current {
                for alternative in game.nodes[parent].children.dropFirst() {
                    tokens.append(.open(alternative))
                    appendLine(startingAt: alternative, game: game, replay: replay, item: item, tokens: &tokens, itemIDs: &itemIDs)
                    tokens.append(.close(alternative))
                    needsNumber = true
                }
            }
            node = game.nodes[current].children.first
        }
    }
}
