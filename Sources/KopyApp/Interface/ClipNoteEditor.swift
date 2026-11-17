import KopyCore
import SwiftUI

struct ClipNoteEditor: View {
    let item: ClipboardItem
    let model: KopyModel
    let horizontal: Bool

    @FocusState private var editing: Bool

    private var draft: Binding<String> {
        Binding(get: { model.noteDraft?.text ?? "" }, set: { model.updateNoteDraft($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ClipBadge(item: item, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Item note")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    item.shelfTitle
                        .font(.caption)
                        .foregroundStyle(ShelfTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.shelfTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("Find this item by its note", text: draft)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($editing)
                .shelfField(isFocused: editing)
                .onSubmit(save)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    count
                    Spacer(minLength: 4)
                    actions
                }
                VStack(alignment: .trailing, spacing: 8) {
                    count
                    actions
                }
            }
        }
        .padding(14)
        .background(ShelfTheme.surface, in: .rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13).strokeBorder(ShelfTheme.line).allowsHitTesting(false)
        }
        .frame(maxWidth: 430)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: horizontal ? .center : .top)
        .task {
            model.setKeyboardEntry(true)
            await Task.yield()
            editing = true
        }
        .onDisappear { model.setKeyboardEntry(false) }
        .onExitCommand(perform: cancel)
    }

    private var count: some View {
        Text(verbatim: "\(draft.wrappedValue.unicodeScalars.count)/120")
            .font(.caption.monospacedDigit())
            .foregroundStyle(ShelfTheme.muted)
            .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Cancel", action: cancel).buttonStyle(ShelfSecondaryButtonStyle())
            Button("Save note", action: save).buttonStyle(ShelfPrimaryButtonStyle())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func save() { model.finishNote(saving: true) }
    private func cancel() { model.finishNote(saving: false) }
}
