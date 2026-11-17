import SwiftUI

struct EmojiShelfView: View {
    let model: KopyModel
    let onClose: () -> Void

    @AppStorage("emojiRecents") private var recentStorage = ""
    @AppStorage("emojiTone") private var tone = EmojiTone.standard
    @State private var category: EmojiCategory = .faces
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var recent: [String] {
        recentStorage.split(separator: "|").map(String.init)
    }

    private var searchTerm: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var entries: [EmojiEntry] {
        let catalog = EmojiCatalog.shared
        if !searchTerm.isEmpty { return catalog.search(searchTerm) }
        if category == .recent {
            return recent.map { EmojiEntry(glyph: $0, name: catalog.names[$0] ?? $0, variants: nil) }
        }
        return catalog.groups[category.rawValue] ?? []
    }

    var body: some View {
        let entries = entries
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Emoji").font(.headline)
                Spacer()
                if category == .recent && searchTerm.isEmpty && !recent.isEmpty {
                    ShelfIconButton(title: "Clear recent emoji", symbol: "trash", size: 26) {
                        recentStorage = ""
                    }
                }
                Menu {
                    Picker("Skin tone", selection: $tone) {
                        ForEach(EmojiTone.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Text("Skin tone")
                }
                .controlSize(.small)
            }
            .padding(.top, 6)
            searchBar(results: entries)
            categoryBar
            if entries.isEmpty {
                emptyEmoji
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 3)], spacing: 3) {
                        ForEach(entries) { entry in
                            tile(entry)
                        }
                    }
                }
                .id(searchTerm.isEmpty ? category.rawValue : searchTerm)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .onAppear { if !recent.isEmpty { category = .recent } }
        .onChange(of: searchFocused) { _, active in model.setKeyboardEntry(active) }
        .onDisappear { model.setKeyboardEntry(false) }
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var emptyEmoji: some View {
        if !searchTerm.isEmpty {
            ShelfEmptyState(symbol: "magnifyingglass", title: "No matching emoji") {
                Button("Clear search", systemImage: "xmark.circle") { query = "" }
            }
        } else if category == .recent {
            ShelfEmptyState(symbol: "clock", title: "No recent emoji") {
                Button("Faces", systemImage: EmojiCategory.faces.symbol) { category = .faces }
            }
        } else {
            ShelfEmptyState(symbol: "face.smiling", title: "Emoji unavailable") { EmptyView() }
        }
    }

    private func searchBar(results: [EmojiEntry]) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Search emoji", text: $query)
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
                    if let result = results.first { insert(result.displaying(tone).glyph) }
                }
            if !query.isEmpty {
                ShelfIconButton(title: "Clear search", symbol: "xmark.circle.fill", size: 24) { query = "" }
            }
        }
        .font(.subheadline)
        .foregroundStyle(ShelfTheme.muted)
        .shelfField(isFocused: searchFocused)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                ForEach(EmojiCategory.allCases) { group in
                    let selected = group == category && searchTerm.isEmpty
                    ShelfIconButton(
                        title: group.title, symbol: group.symbol,
                        tint: selected ? ShelfTheme.accent : ShelfTheme.muted, size: 28
                    ) {
                        category = group
                        query = ""
                        searchFocused = false
                    }
                    .background(selected ? ShelfTheme.highlight : .clear, in: .rect(cornerRadius: 8))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ entry: EmojiEntry) -> some View {
        let displayed = entry.displaying(tone)
        let variants = entry.variants ?? []
        return Button {
            insert(displayed.glyph)
        } label: {
            Text(displayed.glyph)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 33)
                .background(ShelfTheme.surface, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(displayed.name))
        .help(variants.isEmpty ? Text(displayed.name) : Text("\(displayed.name) · Control-click for skin tones"))
        .contextMenu {
            if !variants.isEmpty {
                Button("\(entry.glyph) \(entry.name)") { insert(entry.glyph) }
                ForEach(variants) { option in
                    Button("\(option.glyph) \(option.name)") { insert(option.glyph) }
                }
            }
        }
    }

    private func insert(_ emoji: String) {
        recentStorage = ([emoji] + recent.filter { $0 != emoji }).prefix(77).joined(separator: "|")
        onClose()
        model.pasteEmoji(emoji)
    }
}

private enum EmojiCategory: String, CaseIterable, Identifiable {
    case recent, faces, people, animals, foods, travel, activities, objects, symbols, flags

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .recent: "Recent emoji"
        case .faces: "Faces"
        case .people: "People and body"
        case .animals: "Animals and nature"
        case .foods: "Food and drink"
        case .travel: "Travel and places"
        case .activities: "Activities"
        case .objects: "Objects"
        case .symbols: "Symbols"
        case .flags: "Flags"
        }
    }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .faces: "face.smiling"
        case .people: "hand.raised"
        case .animals: "pawprint"
        case .foods: "fork.knife"
        case .travel: "airplane"
        case .activities: "sportscourt"
        case .objects: "lightbulb"
        case .symbols: "heart"
        case .flags: "flag"
        }
    }
}

private enum EmojiTone: String, CaseIterable, Decodable, Identifiable {
    case standard = ""
    case light = "🏻"
    case mediumLight = "🏼"
    case medium = "🏽"
    case mediumDark = "🏾"
    case dark = "🏿"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "Default"
        case .light: "Light"
        case .mediumLight: "Medium light"
        case .medium: "Medium"
        case .mediumDark: "Medium dark"
        case .dark: "Dark"
        }
    }
}

private struct EmojiEntry: Decodable, Identifiable {
    let glyph: String
    let name: String
    let variants: [EmojiVariant]?

    var id: String { glyph }

    func displaying(_ tone: EmojiTone) -> EmojiVariant {
        variants?.first(where: { $0.tone == tone }) ?? EmojiVariant(glyph: glyph, name: name, tone: nil)
    }
}

private struct EmojiVariant: Decodable, Identifiable {
    let glyph: String
    let name: String
    let tone: EmojiTone?

    var id: String { glyph }
}

private struct EmojiCatalog {
    static let shared = EmojiCatalog()

    let groups: [String: [EmojiEntry]]
    let names: [String: String]
    private let all: [EmojiEntry]

    init(bundle: Bundle = .main) {
        let groups: [String: [EmojiEntry]]
        let url = bundle.url(forResource: "emoji-16", withExtension: "json", subdirectory: "Emoji")
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [EmojiEntry]].self, from: data) {
            groups = decoded
        } else {
            groups = ["faces": [
                EmojiEntry(glyph: "😀", name: "grinning face", variants: nil),
                EmojiEntry(glyph: "😉", name: "winking face", variants: nil),
                EmojiEntry(glyph: "😊", name: "smiling face with smiling eyes", variants: nil)
            ]]
        }
        all = EmojiCategory.allCases.flatMap { groups[$0.rawValue] ?? [] }
        self.groups = groups
        names = all.reduce(into: [:]) { names, entry in
            names[entry.glyph] = entry.name
            for variant in entry.variants ?? [] { names[variant.glyph] = variant.name }
        }
    }

    func search(_ query: String) -> [EmojiEntry] {
        if let name = names[query] { return [EmojiEntry(glyph: query, name: name, variants: nil)] }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return all.filter { entry in
            words.allSatisfy { entry.name.localizedStandardContains($0) }
        }
    }
}
