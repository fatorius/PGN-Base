import SwiftUI

/// Chooses which line to follow when stepping forward into a move with variations, in the
/// style of ChessBase: the line last followed is highlighted first; ↑ and ↓ pick, Return or → follows,
/// and Esc or ← cancels. Clicking a move follows it too.
struct VariationPicker: View {
    /// The moves to choose from, in order; the first is the main line.
    let options: [String]
    let onChoose: (Int) -> Void
    let onCancel: () -> Void

    @State private var highlighted: Int
    @FocusState private var isFocused: Bool

    /// - Parameter initialSelection: The option highlighted first, such as the line last followed here.
    init(options: [String], initialSelection: Int = 0, onChoose: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.options = options
        self.onChoose = onChoose
        self.onCancel = onCancel
        _highlighted = State(initialValue: options.indices.contains(initialSelection) ? initialSelection : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let isHighlighted = index == highlighted
                Text(options[index])
                    .fontWeight(index == 0 ? .semibold : .regular)
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isHighlighted ? Color.accentColor : .clear, in: .rect(cornerRadius: 4))
                    .contentShape(.rect)
                    .onTapGesture { onChoose(index) }
                    .onHover { if $0 { highlighted = index } }
                    .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onChoose(index) }
            }
        }
        .padding(6)
        .frame(minWidth: 160)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) {
            highlighted = max(0, highlighted - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            highlighted = min(options.count - 1, highlighted + 1)
            return .handled
        }
        .onKeyPress(keys: [.return, .rightArrow]) { _ in
            onChoose(highlighted)
            return .handled
        }
        .onKeyPress(keys: [.escape, .leftArrow]) { _ in
            onCancel()
            return .handled
        }
        .accessibilityLabel("Choose a variation")
    }
}

/// The commands for reorganizing variations, for the toolbar and for a move's context menu.
struct VariationCommands: View {
    let game: PGNGame
    /// The move the commands act on.
    let node: Int
    let perform: (PGNEditor.VariationEdit) -> Void

    var body: some View {
        Button("Promote Variation", systemImage: "arrow.up.to.line") { perform(.promote) }
            .disabled(!PGNEditor.canApply(.promote, at: node, in: game))
        Button("Delete Variation", systemImage: "trash") { perform(.delete) }
            .disabled(!PGNEditor.canApply(.delete, at: node, in: game))
        Divider()
        Button("Delete Remaining Moves", systemImage: "scissors") { perform(.deleteRemainingMoves) }
            .disabled(!PGNEditor.canApply(.deleteRemainingMoves, at: node, in: game))
    }
}

#Preview {
    VariationPicker(options: ["12. Nf3", "12. d4", "12. Bb5+"], onChoose: { _ in }, onCancel: {})
        .padding()
}
