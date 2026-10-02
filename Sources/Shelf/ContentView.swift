import SwiftUI

enum SidebarItem: Hashable {
    case all, favorites, recent
    case category(String)
    case tag(String)
}

enum SortOrder: String, CaseIterable, Identifiable {
    case title = "Title", added = "Recently Added", played = "Last Played", rating = "Rating", released = "Release Date"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @State private var selection: SidebarItem? = .all
    @State private var search = ""
    @State private var sort: SortOrder = .title
    @State private var showAdd = false
    @State private var importWizard: GamePlatform?
    @State private var path = NavigationPath()

    private var title: String {
        switch selection ?? .all {
        case .all: "Library"
        case .favorites: "Favorites"
        case .recent: "Recently Played"
        case .category(let c): c
        case .tag(let t): t
        }
    }

    private var filtered: [Game] {
        var list = library.games
        switch selection ?? .all {
        case .all: break
        case .favorites: list = list.filter(\.isFavorite)
        case .recent: list = list.filter { $0.lastPlayed != nil }
        case .category(let c): list = list.filter { $0.effectiveCategory == c }
        case .tag(let t): list = list.filter { $0.tags.contains(t) }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                ([$0.title] + $0.genres + $0.tags + $0.developers).contains { $0.lowercased().contains(q) }
            }
        }
        if selection == .recent { return list.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) } }
        switch sort {
        case .title: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .added: return list.sorted { $0.dateAdded > $1.dateAdded }
        case .played: return list.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .rating: return list.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .released: return list.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                GameGrid(games: filtered, title: title)
                    .navigationDestination(for: UUID.self) { DetailView(id: $0) }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Search games")
            .toolbar { toolbar }
        }
        .onChange(of: selection) { path = NavigationPath() }
        .sheet(isPresented: $showAdd) {
            GameFormView(game: Game(title: "", platform: .mac), isNew: true)
        }
        .sheet(item: $importWizard) { p in
            if p == .crossover { CrossOverWizard {} } else { StoreWizard(platform: p) }
        }
        .overlay(alignment: .bottom) {
            if let status = library.status {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status).font(.callout)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 12, y: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: library.status)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Library", systemImage: "square.grid.2x2").tag(SidebarItem.all)
                Label("Favorites", systemImage: "heart").tag(SidebarItem.favorites)
                Label("Recently Played", systemImage: "clock").tag(SidebarItem.recent)
            }
            Section("Categories") {
                ForEach(library.allCategories, id: \.self) { c in
                    let platform = GamePlatform.allCases.first { $0.label == c }
                    Label(c, systemImage: platform?.symbol ?? "folder.fill").tag(SidebarItem.category(c))
                }
            }
            if !library.allTags.isEmpty {
                Section("Collections") {
                    ForEach(library.allTags, id: \.self) { Label($0, systemImage: "folder").tag(SidebarItem.tag($0)) }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("Sort", selection: $sort) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Menu {
                Button("Import from Steam…") { importWizard = .steam }
                Button("Import from Epic Games…") { importWizard = .epic }
                Button("Import from GOG…") { importWizard = .gog }
                Button("Import from CrossOver…") { importWizard = .crossover }
                Button("Import Mac Games") { library.importMacGames() }
                Divider()
                Button("Refresh All Metadata") { Task { await library.refreshAll(missingOnly: false) } }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItem {
            Button { Task { await library.refreshAll(missingOnly: true) } } label: {
                Label("Fetch Metadata", systemImage: "sparkles")
            }
            .help("Fetch metadata for games that don't have any yet")
        }
        ToolbarItem {
            Button { showAdd = true } label: { Label("Add Game", systemImage: "plus") }
        }
    }
}
