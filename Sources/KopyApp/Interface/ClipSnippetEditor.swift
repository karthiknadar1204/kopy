import SwiftUI

struct ClipSnippetEditor: View {
    let model: KopyModel
    let horizontal: Bool

    @FocusState private var editing: Bool

    private var draft: Binding<String> {
        Binding(get: { model.snippetDraft ?? "" }, set: { model.updateSnippetDraft($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New snippet", systemImage: "square.and.pencil")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            TextEditor(text: draft)
                .font(.system(size: 13))
                .foregroundStyle(ShelfTheme.ink)
                .scrollContentBackground(.hidden)
                .focused($editing)
                .accessibilityLabel("Snippet text")
                .padding(8)
                .frame(minHeight: 48, maxHeight: .infinity)
                .background(ShelfTheme.background, in: .rect(cornerRadius: 9))
                .overlay(alignment: .topLeading) {
                    if draft.wrappedValue.isEmpty {
                        Text("Write your snippet…")
                            .font(.system(size: 13))
                            .foregroundStyle(ShelfTheme.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(editing ? ShelfTheme.accent.opacity(0.75) : ShelfTheme.line)
                        .allowsHitTesting(false)
                }
                .disabled(model.isSavingSnippet)

            if draft.wrappedValue.count > 500_000 {
                Text("Snippet is too long.")
                    .font(.caption)
                    .foregroundStyle(ShelfTheme.accent)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: model.cancelSnippet)
                    .buttonStyle(ShelfSecondaryButtonStyle())
                    .disabled(model.isSavingSnippet)
                Button("Save snippet", action: model.saveSnippet)
                    .buttonStyle(ShelfPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(Text(verbatim: "⌘↵"))
                    .disabled(!model.canSaveSnippet)
            }
            Text("Saved snippets stay pinned.")
                .font(.caption)
                .foregroundStyle(ShelfTheme.muted)
        }
        .padding(14)
        .background(ShelfTheme.surface, in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13).strokeBorder(ShelfTheme.line).allowsHitTesting(false)
        }
        .frame(maxWidth: horizontal ? 560 : 430)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: horizontal ? .center : .top)
        .task(id: model.isShelfOpen) {
            guard model.isShelfOpen else { editing = false; return }
            model.setKeyboardEntry(true)
            await Task.yield()
            editing = true
        }
        .onExitCommand(perform: model.cancelSnippet)
    }
}
