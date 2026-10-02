import SwiftUI

enum PickerKind: String, Identifiable {
    case cover, hero, summary, genres, developers, publishers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cover: "Cover Art"
        case .hero: "Background Art"
        case .summary: "Summary"
        case .genres: "Genres"
        case .developers: "Developers"
        case .publishers: "Publishers"
        }
    }
    var isImage: Bool { self == .cover || self == .hero }
}

enum PickerValue: Hashable {
    case image(URL)
    case text(String)
    case list([String])
}

private struct PickerOption: Identifiable {
    let id = UUID()
    let source: MetadataSource
    let value: PickerValue
}

/// Shows what each source offers for one field so the user can choose.
struct MetadataPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let kind: PickerKind
    let onPick: (PickerValue) -> Void

    @State private var options: [PickerOption] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose \(kind.title)").font(.title3.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            if loading {
                ProgressView("Fetching options…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if options.isEmpty {
                ContentUnavailableView("No options found", systemImage: "square.grid.2x2",
                                       description: Text("Check that a source is enabled and configured in Settings."))
            } else {
                ScrollView {
                    if kind.isImage { collage } else { textList }
                }
            }
        }
        .frame(width: 640, height: 560)
        .task { await load() }
    }

    private var collage: some View {
        let cols = kind == .cover
            ? [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]
            : [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(options) { option in
                Button { choose(option) } label: {
                    VStack(spacing: 4) {
                        if case .image(let url) = option.value {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
                                default: ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(kind == .cover ? 2.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(option.source.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var textList: some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                Button { choose(option) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.source.label).font(.caption.bold()).foregroundStyle(.secondary)
                        switch option.value {
                        case .text(let s): Text(s).lineLimit(8)
                        case .list(let l): Text(l.joined(separator: ", "))
                        case .image: EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func choose(_ option: PickerOption) {
        onPick(option.value)
        dismiss()
    }

    private func load() async {
        let prefs = MetadataPreferences.load()
        let bySource = await MetadataService.fetchBySource(for: game, preferences: prefs)
        var found: [PickerOption] = []

        if kind.isImage, !prefs.disabled.contains(.steamGridDB),
           let key = UserDefaults.standard.string(forKey: "sgdbAPIKey"), !key.isEmpty,
           let art = try? await SteamGridDBClient.artwork(title: game.title, steamAppID: game.steamAppID, key: key) {
            for url in kind == .cover ? art.covers : art.heroes { found.append(.init(source: .steamGridDB, value: .image(url))) }
        }
        for source in MetadataSource.allCases where source != .steamGridDB {
            guard let m = bySource[source] else { continue }
            switch kind {
            case .cover: m.coverURL.map { found.append(.init(source: source, value: .image($0))) }
            case .hero: m.heroURL.map { found.append(.init(source: source, value: .image($0))) }
            case .summary: if let s = m.summary, !s.isEmpty { found.append(.init(source: source, value: .text(s))) }
            case .genres: if !m.genres.isEmpty { found.append(.init(source: source, value: .list(m.genres))) }
            case .developers: if !m.developers.isEmpty { found.append(.init(source: source, value: .list(m.developers))) }
            case .publishers: if !m.publishers.isEmpty { found.append(.init(source: source, value: .list(m.publishers))) }
            }
        }
        options = found
        loading = false
    }
}
