import SwiftUI

/// The game's moves in numbered pairs. Clicking a move jumps to the position after it.
struct MoveListView: View {
    let game: PGNGame
    let replay: GameReplay
    /// The number of half-moves played; 0 is the starting position.
    @Binding var ply: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(replay.rows) { row in
                        HStack(spacing: 4) {
                            Text("\(row.number).")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                            moveButton(for: row.whiteMoveIndex, placeholder: "…")
                            moveButton(for: row.blackMoveIndex, placeholder: "")
                        }
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
            .onChange(of: ply) {
                guard let rowID = rowID(forPly: ply) else { return }
                withAnimation { proxy.scrollTo(rowID) }
            }
        }
    }

    @ViewBuilder
    private func moveButton(for moveIndex: Int?, placeholder: String) -> some View {
        if let moveIndex {
            let move = game.moves[moveIndex]
            let isCurrent = ply == moveIndex + 1
            Button {
                ply = moveIndex + 1
            } label: {
                HStack(spacing: 2) {
                    Text(move.san + (move.annotation ?? ""))
                    if move.comment != nil {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has comment")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isCurrent ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 4))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        } else {
            Text(placeholder)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
    }

    private func rowID(forPly ply: Int) -> MoveRow.ID? {
        guard ply > 0 else { return replay.rows.first?.id }
        let moveIndex = ply - 1
        return replay.rows.first { $0.whiteMoveIndex == moveIndex || $0.blackMoveIndex == moveIndex }?.id
    }
}
