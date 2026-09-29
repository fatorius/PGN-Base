import SwiftUI

/// Edits the current move's quality annotation and comment, or the game's opening comment
/// at the starting position.
///
/// Comments are committed shortly after typing pauses, and when moving to another move,
/// so each pause becomes one undoable edit rather than one per keystroke.
struct AnnotationEditor: View {
    let comment: String?
    let annotation: String?
    /// Whether there's a move to annotate; the starting position only has a comment.
    let isMove: Bool
    var isEditingComment: FocusState<Bool>.Binding
    let onCommentChange: (String) -> Void
    let onAnnotationChange: (String?) -> Void

    @State private var draft: String

    init(
        comment: String?,
        annotation: String?,
        isMove: Bool,
        isEditingComment: FocusState<Bool>.Binding,
        onCommentChange: @escaping (String) -> Void,
        onAnnotationChange: @escaping (String?) -> Void
    ) {
        self.comment = comment
        self.annotation = annotation
        self.isMove = isMove
        self.isEditingComment = isEditingComment
        self.onCommentChange = onCommentChange
        self.onAnnotationChange = onAnnotationChange
        _draft = State(initialValue: comment ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isMove {
                HStack(spacing: 6) {
                    ForEach(PGNEditor.annotations, id: \.symbol) { option in
                        Toggle(option.symbol, isOn: Binding(
                            get: { annotation == option.symbol },
                            set: { onAnnotationChange($0 ? option.symbol : nil) }
                        ))
                        .toggleStyle(.button)
                        .help(option.name)
                        .accessibilityLabel(option.name)
                    }
                }
            }

            TextEditor(text: $draft)
                .focused(isEditingComment)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 72)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(isMove ? "Add a comment about this move…" : "Add a comment about the game…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .onKeyPress(.escape) {
                    isEditingComment.wrappedValue = false
                    return .handled
                }
                .accessibilityLabel(isMove ? "Move comment" : "Game comment")
        }
        .task(id: draft) {
            // Commit once typing pauses.
            do {
                try await Task.sleep(for: .milliseconds(400))
                commit()
            } catch {}
        }
        .onDisappear {
            commit()
        }
        .onChange(of: comment) {
            // Pick up changes from elsewhere, like Undo, but never rewrite what's being typed.
            if !isEditingComment.wrappedValue {
                draft = comment ?? ""
            }
        }
    }

    private func commit() {
        if PGNEditor.sanitizedComment(draft) != (comment ?? "") {
            onCommentChange(draft)
        }
    }
}

#Preview {
    @Previewable @FocusState var isEditing: Bool
    AnnotationEditor(
        comment: "A daring knight sacrifice.",
        annotation: "!",
        isMove: true,
        isEditingComment: $isEditing,
        onCommentChange: { _ in },
        onAnnotationChange: { _ in }
    )
    .padding()
    .frame(width: 520)
}
