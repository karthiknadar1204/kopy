import AppKit
import KopyCore
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    let model: KopyModel

    @State private var query = ""
    @State private var filter: ClipboardFilter = .all
    @State private var previewID: UUID?
    @State private var expandedStackID: UUID?
    @State private var emojiOpen = false
    @State private var confirmClear = false
    @State private var scrollID: UUID?
    @State private var scrollAnchor: UnitPoint?
    @State private var scrollMarks = ShelfScrollMarks()
    @State private var filterPositions: [ClipboardFilter: ShelfScrollMarks.Location] = [:]
    @State private var lastClosed: ClosedPosition?
    @State private var priorPosition: ShelfScrollMarks.Location?
    @State private var returnHovered = false
    @State private var splitHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var searchFocused: Bool

    private var horizontal: Bool { model.preferences.edge == .top }
    private var scrollEdge: ShelfScrollMarks.Edge {
        horizontal ? (layoutDirection == .leftToRight ? .left : .right) : .top
    }
    private var matchingItems: [ClipboardItem] { model.items.filter { $0.matches(query, filter: filter) } }
    private var pinnedFolded: Bool { !model.expandedPinnedFilters.contains(filter.rawValue) }
    private var newestActivity: Date? { model.items.max { $0.activityAt < $1.activityAt }?.activityAt }
    private var headID: UUID? {
        let matches = matchingItems
        if !pinnedFolded, let firstPinned = matches.first(where: \.pinned) { return firstPinned.id }
        return matches.first { !$0.pinned }?.id
    }

    var body: some View {
        let matches = matchingItems
        VStack(alignment: .leading, spacing: 0) {
            if let id = model.noteDraft?.itemID, let item = model.items.first(where: { $0.id == id }) {
                header()
                ClipNoteEditor(item: item, model: model, horizontal: horizontal)
                    .id(id)
            } else if let id = previewID, let item = model.items.first(where: { $0.id == id }) {
                header()
                ClipPreview(item: item, model: model, horizontal: horizontal, onClose: { closePreview() })
                    .id(id)
            } else if emojiOpen {
                header()
                EmojiShelfView(model: model, onClose: { emojiOpen = false })
            } else {
                historyHeader(matches)
                history(matches)
            }
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(ShelfTheme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(ShelfTheme.highlight)
                    .accessibilityIdentifier("shelf-status")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ShelfTheme.background)
        .clipShape(.rect(cornerRadius: ShelfTheme.radius))
        .overlay {
            RoundedRectangle(cornerRadius: ShelfTheme.radius)
                .strokeBorder(ShelfTheme.line)
                .allowsHitTesting(false)
        }
        .foregroundStyle(ShelfTheme.ink)
        .tint(ShelfTheme.accent)
        .overlay(alignment: .bottom) {
            if model.isDropTargeted {
                Label("Drop to add to Kopy", systemImage: "arrow.down.to.line")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(ShelfTheme.highlight, in: .capsule)
                    .overlay { Capsule().strokeBorder(ShelfTheme.accent.opacity(0.5)) }
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: searchFocused) { _, active in
            if model.noteDraft == nil { model.setKeyboardEntry(active) }
        }
        .onChange(of: model.isShelfOpen) { _, isOpen in shelfVisibilityChanged(isOpen) }
        .onChange(of: model.importRevision) { _, _ in
            scrollAnchor = nil
            closeSubview(savingNote: true)
            searchFocused = false
            query = ""
            filter = .all
            expandedStackID = nil
            filterPositions[.all] = nil
            scrollID = model.items.first?.id
        }
        .onChange(of: filter) { _, next in
            let location = filterPositions[next]
            scrollAnchor = location?.edge == scrollEdge ? location?.anchor : nil
            scrollID = location?.id ?? headID
            priorPosition = nil
            expandedStackID = nil
        }
        .onChange(of: newestActivity) { previous, next in
            guard model.isShelfOpen, let next, previous.map({ next > $0 }) ?? true else { return }
            scrollAnchor = nil
            scrollID = matchingItems.first { !$0.pinned }?.id ?? headID
            filterPositions[filter] = nil
        }
        .onExitCommand(perform: escape)
    }

    private func historyHeader(_ matches: [ClipboardItem]) -> some View {
        VStack(spacing: 0) {
            header(inlineSearch: horizontal)
            if !horizontal { searchBar.padding(.horizontal, 14) }
            filterBar(matches)
        }
        .background(ShelfTheme.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ShelfTheme.line).frame(height: 1).allowsHitTesting(false)
        }
    }

    private func header(inlineSearch: Bool = false) -> some View {
        HStack(spacing: 9) {
            if emojiOpen || previewID != nil || model.noteDraft != nil {
                ShelfIconButton(title: "Back to history", symbol: "chevron.backward") { closeSubview(savingNote: true) }
            }
            KopyBadge()
            Text(verbatim: "Kopy")
                .font(.system(size: 18, weight: .semibold))
            if model.preferences.incognito {
                Image(systemName: "pause.circle")
                    .foregroundStyle(ShelfTheme.accent)
                    .accessibilityLabel("Paused")
                    .help("Paused")
            } else if model.automaticCaptureDenied {
                Image(systemName: "info.circle")
                    .foregroundStyle(ShelfTheme.muted)
                    .accessibilityLabel("macOS has blocked automatic clipboard capture.")
                    .help("macOS has blocked automatic clipboard capture.")
            }
            Spacer(minLength: 0)
            if inlineSearch {
                searchBar.frame(idealWidth: 270, maxWidth: 360)
                Spacer(minLength: 0)
            }
            toolbarActions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var toolbarActions: some View {
        HStack(spacing: 1) {
#if !KOPY_APP_STORE
            switch model.updater.state {
            case .available, .ready:
                ShelfIconButton(title: "Update available", symbol: "arrow.down.circle.fill") {
                    closeSubview(savingNote: true)
                    model.openSettings()
                }
            default:
                EmptyView()
            }
#endif
            ShelfIconButton(title: "Import clipboard", symbol: "document.on.clipboard") { model.importClipboard() }
            ShelfIconButton(title: "Emoji", symbol: "face.smiling") {
                searchFocused = false
                previewID = nil
                expandedStackID = nil
                model.finishNote(saving: true)
                model.play(.click)
                emojiOpen.toggle()
            }
            ShelfIconButton(title: "Settings", symbol: "gearshape") {
                closeSubview(savingNote: true)
                model.openSettings()
            }
        }
        .padding(2)
        .background(ShelfTheme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(ShelfTheme.line).allowsHitTesting(false)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .accessibilityHidden(true)
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(ShelfTheme.ink)
                .simultaneousGesture(TapGesture().onEnded {
                    guard !searchFocused else { return }
                    model.setKeyboardEntry(true)
                    Task { @MainActor in
                        await Task.yield()
                        searchFocused = true
                    }
                })
                .onSubmit {
                    if let item = matchingItems.first {
                        model.paste(item, plain: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
                    }
                }
            if !query.isEmpty {
                ShelfIconButton(title: "Clear search", symbol: "xmark.circle.fill", size: 24) { query = "" }
            } else if searchFocused && !matchingItems.isEmpty {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 19, height: 19)
                    .background(ShelfTheme.inset, in: .rect(cornerRadius: 5))
                    .help("Paste into the current app")
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline)
        .foregroundStyle(ShelfTheme.muted)
        .shelfField(isFocused: searchFocused)
    }

    private func filterBar(_ matches: [ClipboardItem]) -> some View {
        HStack(spacing: 5) {
            ViewThatFits(in: .horizontal) {
                filterButtons(showTitles: true)
                    .fixedSize(horizontal: true, vertical: false)
                filterButtons(showTitles: false)
            }
            Spacer(minLength: 0)
            clearMenu(matches)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }

    private func filterButtons(showTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(ClipboardFilter.allCases) { option in
                Button {
                    selectFilter(option)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.shelfSymbol)
                            .font(.system(size: 12, weight: .medium))
                        if showTitles && (horizontal || filter == option) {
                            Text(option.shelfTitle)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption.weight(filter == option ? .semibold : .medium))
                    .padding(.horizontal, 9)
                    .frame(minWidth: 29, minHeight: 28)
                    .background(filter == option ? ShelfTheme.highlight : .clear, in: .rect(cornerRadius: 7))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(filter == option ? ShelfTheme.accent : ShelfTheme.muted)
                .accessibilityLabel(Text(option.shelfTitle))
                .accessibilityAddTraits(filter == option ? .isSelected : [])
                .help(Text(option.shelfTitle))
            }
        }
    }

    private func selectFilter(_ option: ClipboardFilter) {
        if filter != option {
            filterPositions[filter] = scrollID.map { scrollMarks.capture(id: $0, edge: scrollEdge) }
        }
        filter = option
        model.play(.click)
        searchFocused = false
    }

    private func clearMenu(_ matches: [ClipboardItem]) -> some View {
        Menu {
            Button("Last hour", systemImage: "clock") { model.clear(matches, since: .now.addingTimeInterval(-3_600)) }
            Button("Last 6 hours", systemImage: "clock") { model.clear(matches, since: .now.addingTimeInterval(-21_600)) }
            Button("Last 24 hours", systemImage: "clock") { model.clear(matches, since: .now.addingTimeInterval(-86_400)) }
            Divider()
            Button("Clear shown history", systemImage: "trash", role: .destructive) { confirmClear = true }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 26, height: 26)
                .accessibilityLabel("History actions")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(.titleAndIcon)
        .menuOrder(.fixed)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(ShelfTheme.muted)
        .disabled(!matches.contains { !$0.isProtected })
        .help("Clear history")
        .confirmationDialog("Clear shown history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { model.clear(matchingItems) }
        } message: {
            Text("Pinned items and items with notes will be kept.")
        }
    }

    private func history(_ matches: [ClipboardItem]) -> some View {
        let pinned = matches.filter(\.pinned)
        let recent = matches.filter { !$0.pinned }
        return VStack(alignment: .leading, spacing: 0) {
            if model.isLoadingHistory && matches.isEmpty {
                ProgressView("Loading clipboard history…")
                    .controlSize(.small)
                    .foregroundStyle(ShelfTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.isEmpty {
                emptyHistory
            } else {
                if let priorPosition {
                    Button("Back to previous position", systemImage: "arrow.uturn.backward") {
                        self.priorPosition = nil
                        scrollAnchor = priorPosition.edge == scrollEdge ? priorPosition.anchor : nil
                        scrollID = priorPosition.id
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShelfTheme.accent)
                    .onHover { returnHovered = $0 }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
                if horizontal {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            horizontalSection("Pinned", items: pinned, isPinned: true)
                            horizontalSection("Recent", items: recent, isPinned: false)
                        }
                        .scrollTargetLayout()
                        .padding(12)
                    }
                    .scrollPosition(id: $scrollID, anchor: scrollAnchor ?? .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            verticalSection("Pinned", items: pinned, isPinned: true)
                            verticalSection("Recent", items: recent, isPinned: false)
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .scrollPosition(id: $scrollID, anchor: scrollAnchor ?? .top)
                }
            }
            if splitHovered {
                Label("Drop here to separate the item", systemImage: "rectangle.split.2x1")
                    .font(.caption)
                    .padding(7)
                    .frame(maxWidth: .infinity)
                    .background(ShelfTheme.highlight)
            }
        }
        .frame(maxHeight: .infinity)
        .onDrop(of: [ShelfTheme.internalDrag], isTargeted: $splitHovered) { providers in
            model.acceptInternalDrop(providers)
        }
        .onChange(of: query) { _, _ in
            scrollAnchor = nil
            priorPosition = nil
            expandedStackID = nil
        }
        .task(id: ReturnTimer(position: priorPosition?.id, hovering: returnHovered)) {
            guard priorPosition != nil, !returnHovered else { return }
            do {
                try await Task.sleep(for: .seconds(6))
                priorPosition = nil
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private struct ReturnTimer: Equatable {
        let position: UUID?
        let hovering: Bool
    }

    private struct ClosedPosition {
        let at: Date
        let newestActivity: Date?
        let anchor: ShelfScrollMarks.Location?
    }

    private func shelfVisibilityChanged(_ isOpen: Bool) {
        if isOpen {
            if let lastClosed,
               Date.now.timeIntervalSince(lastClosed.at) >= 60 || lastClosed.newestActivity != newestActivity {
                filterPositions.removeAll()
                priorPosition = lastClosed.anchor.flatMap { anchor in
                    matchingItems.contains { $0.id == anchor.id } ? anchor : nil
                }
                scrollAnchor = nil
                scrollID = headID
            }
            lastClosed = nil
        } else {
            let candidates = matchingItems.filter { !pinnedFolded || !$0.pinned }
            let anchor = scrollID.flatMap { id in
                candidates.firstIndex { $0.id == id }.map { $0 >= (horizontal ? 2 : 4) } == true
                    ? scrollMarks.capture(id: id, edge: scrollEdge) : nil
            }
            lastClosed = ClosedPosition(at: .now, newestActivity: newestActivity, anchor: anchor)
            priorPosition = nil
            searchFocused = false
            previewID = nil
            expandedStackID = nil
        }
    }

    @ViewBuilder
    private var emptyHistory: some View {
        if model.items.isEmpty {
            ShelfEmptyState(
                symbol: model.preferences.incognito ? "pause" : "tray",
                title: model.preferences.incognito ? "Paused" : "Nothing copied yet",
                detail: model.preferences.incognito ? "Drop to add to Kopy" : "Copy an item or drop a file here."
            ) {
                Button("Import clipboard", systemImage: "document.on.clipboard", action: model.importClipboard)
            }
        } else {
            let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ShelfEmptyState(
                symbol: hasQuery ? "magnifyingglass" : filter.shelfSymbol,
                title: "No matching items",
                detail: "Try a different filter or search."
            ) {
                if hasQuery {
                    Button("Clear search", systemImage: "xmark.circle") { query = "" }
                } else {
                    Button("All", systemImage: ClipboardFilter.all.shelfSymbol) { selectFilter(.all) }
                }
            }
        }
    }

    @ViewBuilder
    private func verticalSection(_ title: LocalizedStringKey, items: [ClipboardItem], isPinned: Bool) -> some View {
        if !items.isEmpty {
            HStack {
                if isPinned {
                    pinnedGroupButton(title)
                } else {
                    Text(title)
                }
                Spacer()
                Text(items.count.formatted()).monospacedDigit().fontWeight(.regular)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ShelfTheme.muted)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)
            if !isPinned || !pinnedFolded {
                ForEach(items) { item in
                    card(item)
                }
            }
        }
    }

    @ViewBuilder
    private func horizontalSection(_ title: LocalizedStringKey, items: [ClipboardItem], isPinned: Bool) -> some View {
        if isPinned && pinnedFolded && !items.isEmpty {
            pinnedGroupButton(title)
        } else {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    if item.id == items.first?.id {
                        if isPinned {
                            pinnedGroupButton(title)
                        } else {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ShelfTheme.muted)
                                .accessibilityAddTraits(.isHeader)
                        }
                    } else {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .hidden()
                            .accessibilityHidden(true)
                    }
                    card(item)
                }
                .frame(width: 206)
            }
        }
    }

    private func pinnedGroupButton(_ title: LocalizedStringKey) -> some View {
        Button {
            model.togglePinnedSection(filter)
        } label: {
            Label(title, systemImage: pinnedFolded ? "chevron.right" : "chevron.down")
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(ShelfTheme.muted)
        .help(pinnedFolded ? "Expand pinned items" : "Collapse pinned items")
    }

    private func card(_ item: ClipboardItem) -> some View {
        ClipCard(item: item, model: model, horizontal: horizontal, expanded: expandedStackID == item.id) {
            let closing = expandedStackID == item.id
            withAnimation(reduceMotion || model.preferences.reduceMotion ? nil : .easeOut(duration: 0.17)) {
                expandedStackID = closing ? nil : item.id
            }
            model.play(closing ? .collapse : .expand)
        } preview: {
            previewID = item.id
            searchFocused = false
        } editNote: {
            searchFocused = false
            model.editNote(item)
        }
        .background(ShelfScrollMarker(id: item.id, marks: scrollMarks).allowsHitTesting(false))
        .id(item.id)
    }

    private func escape() {
        if emojiOpen || previewID != nil || model.noteDraft != nil {
            closeSubview(savingNote: false)
        } else if !query.isEmpty {
            query = ""
        } else {
            searchFocused = false
        }
    }

    private func closeSubview(savingNote: Bool) {
        emojiOpen = false
        closePreview()
        model.finishNote(saving: savingNote)
    }

    private func closePreview() {
        if previewID != nil {
            previewID = nil
            model.keepShelfOpen?(.milliseconds(2_500))
        }
    }
}
