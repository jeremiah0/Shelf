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
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("navigationStyle") private var navStyle: NavigationStyle = .sidebar
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
        Group {
            if hasCompletedWelcome {
                libraryView
            } else {
                WelcomeView {
                    hasCompletedWelcome = true
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var libraryView: some View {
        Group {
            if navStyle == .top { topNavLayout } else { sidebarLayout }
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
                .glassSurface(in: Capsule())
                .shadow(radius: 12, y: 4)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: library.status)
    }

    // MARK: Layouts

    private var gameDetail: some View {
        NavigationStack(path: $path) {
            GameGrid(games: filtered, title: title)
                .navigationDestination(for: UUID.self) { DetailView(id: $0) }
        }
        // Without a backing, covers scroll underneath the toolbar and make its controls unreadable.
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }

    private var sidebarLayout: some View {
        // Toolbar and search live on the split view (not the detail column) so the
        // items keep their position when the sidebar collapses or reappears.
        NavigationSplitView {
            sidebar
        } detail: {
            gameDetail
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search games")
        .toolbar { toolbar }
    }

    private var topNavLayout: some View {
        gameDetail
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
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
                    Label(c, systemImage: categorySymbol(c)).tag(SidebarItem.category(c))
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

    private func categorySymbol(_ category: String) -> String {
        GamePlatform.allCases.first { $0.label == category }?.symbol ?? "folder.fill"
    }

    // MARK: Overhead navigation

    /// Falls back to icon-only controls when the window is too narrow for labels.
    private var topBar: some View {
        GlassContainer {
            ViewThatFits(in: .horizontal) {
                topBarContent(compact: false)
                topBarContent(compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, ignoresSafeAreaEdges: .top)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func topBarContent(compact: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                navButton("Library", "square.grid.2x2", .all, compact: compact)
                navButton("Favorites", "heart", .favorites, compact: compact)
                navButton("Recent", "clock", .recent, compact: compact)
                if !library.allCategories.isEmpty { categoryMenu(compact: compact) }
                if !library.allTags.isEmpty { collectionMenu(compact: compact) }
            }
            .padding(4)
            .glassSurface(in: Capsule())

            Spacer(minLength: 0)

            searchField
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(width: compact ? 150 : 210)
                .glassSurface(in: Capsule())

            HStack(spacing: 6) { actionControls(compact: compact) }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassSurface(in: Capsule())
        }
        .lineLimit(1)
    }

    private func pill(_ title: String, _ symbol: String, active: Bool, compact: Bool) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(BarLabelStyle(compact: compact))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? Color.accentColor.opacity(0.28) : .clear, in: Capsule())
            .contentShape(Capsule())
    }

    private func navButton(_ title: String, _ symbol: String, _ item: SidebarItem, compact: Bool) -> some View {
        Button { selection = item } label: { pill(title, symbol, active: selection == item, compact: compact) }
            .buttonStyle(.plain)
            .help(title)
    }

    private func categoryMenu(compact: Bool) -> some View {
        Menu {
            ForEach(library.allCategories, id: \.self) { c in
                Button { selection = .category(c) } label: { Label(c, systemImage: categorySymbol(c)) }
            }
        } label: {
            pill("Categories", "square.stack", active: isCategorySelected, compact: compact)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize()
        .help("Categories")
    }

    private func collectionMenu(compact: Bool) -> some View {
        Menu {
            ForEach(library.allTags, id: \.self) { t in
                Button { selection = .tag(t) } label: { Label(t, systemImage: "folder") }
            }
        } label: {
            pill("Collections", "folder", active: isTagSelected, compact: compact)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(compact ? .hidden : .visible)
        .fixedSize()
        .help("Collections")
    }

    private var isCategorySelected: Bool {
        if case .category = selection { return true }
        return false
    }

    private var isTagSelected: Bool {
        if case .tag = selection { return true }
        return false
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search games", text: $search).textFieldStyle(.plain)
        }
    }

    // MARK: Shared actions

    @ViewBuilder
    private func actionControls(compact: Bool) -> some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            pill(compact ? "Sort" : "Sort: \(sort.rawValue)", "arrow.up.arrow.down", active: false, compact: compact)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort")

        Menu {
            Button("Import from Steam…") { importWizard = .steam }
            Button("Import from Epic Games…") { importWizard = .epic }
            Button("Import from GOG…") { importWizard = .gog }
            Button("Import from CrossOver…") { importWizard = .crossover }
            Button("Import Mac Games") { library.importMacGames() }
            Divider()
            Button("Refresh All Metadata") { Task { await library.refreshAll(missingOnly: false) } }
        } label: {
            pill("Import", "square.and.arrow.down", active: false, compact: compact)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Import games")

        Button { Task { await library.refreshAll(missingOnly: true) } } label: {
            pill("Fetch Metadata", "sparkles", active: false, compact: true)
        }
        .buttonStyle(.plain)
        .help("Fetch metadata for games that don't have any yet")

        Button { showAdd = true } label: { pill("Add Game", "plus", active: false, compact: true) }
            .buttonStyle(.plain)
            .help("Add Game")
    }

    // Sidebar mode uses the system toolbar, which is Liquid Glass on macOS 26 automatically.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem { Picker("Sort", selection: $sort) {
            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu) }
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

enum NavigationStyle: String, CaseIterable, Identifiable {
    case sidebar, top
    var id: String { rawValue }
    var label: String { self == .sidebar ? "Sidebar" : "Top Bar" }
}

extension View {
    /// Liquid Glass on macOS 26+, falling back to a material on earlier versions.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct GlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

/// Icon plus single-line title, or the icon alone when space is tight.
struct BarLabelStyle: LabelStyle {
    var compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title.lineLimit(1).fixedSize()
            }
        }
    }
}
