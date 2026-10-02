import AppKit
import SwiftUI

struct GameFormView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State var game: Game
    let isNew: Bool
    @State private var showSources = false
    @State private var wizard: GamePlatform?
    @State private var fetching = false
    @State private var picker: PickerKind?
    @State private var showNewCategory = false
    @State private var newCategory = ""

    private var categoryOptions: [String] {
        let all = Set(library.allCategories + GamePlatform.allCases.map(\.label) + [game.category].compactMap { $0 })
        return all.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private func list(_ keyPath: WritableKeyPath<Game, [String]>) -> Binding<String> {
        Binding(
            get: { game[keyPath: keyPath].joined(separator: ", ") },
            set: { game[keyPath: keyPath] = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
    }

    private func pick(allowFolders: Bool = false, completion: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowFolders
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Game") {
                    TextField("Title", text: $game.title)
                    Picker("Platform", selection: $game.platform) {
                        ForEach(GamePlatform.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Category") {
                        HStack {
                            Picker("Category", selection: $game.category) {
                                Text("Default (\(game.platform.label))").tag(String?.none)
                                ForEach(categoryOptions, id: \.self) { Text($0).tag(Optional($0)) }
                            }
                            .labelsHidden()
                            Button("New…") { newCategory = ""; showNewCategory = true }
                        }
                    }
                    switch game.platform {
                    case .steam:
                        TextField("Steam App ID", value: $game.steamAppID, format: .number.grouping(.never))
                        wizardButton
                    case .epic:
                        TextField("Epic App Name", text: Binding(get: { game.epicAppName ?? "" }, set: { game.epicAppName = $0 }))
                        wizardButton
                    case .crossover:
                        TextField("Bottle", text: Binding(get: { game.crossoverBottle ?? "" }, set: { game.crossoverBottle = $0 }))
                        fileRow("Executable", game.launchPath) { game.launchPath = $0 }
                        wizardButton
                    case .emulator:
                        fileRow("Emulator", game.launchPath) { game.launchPath = $0 }
                        fileRow("ROM / Disc", game.romPath) { game.romPath = $0 }
                    default:
                        fileRow("App / Executable", game.launchPath) { game.launchPath = $0 }
                        if game.platform == .gog { wizardButton }
                    }
                }
                Section {
                    choosable(.summary) { TextField("Summary", text: $game.summary, axis: .vertical).lineLimit(3...6) }
                    choosable(.genres) { TextField("Genres", text: list(\.genres)) }
                    choosable(.developers) { TextField("Developers", text: list(\.developers)) }
                    choosable(.publishers) { TextField("Publishers", text: list(\.publishers)) }
                    TextField("Collections (tags)", text: list(\.tags))
                    choosable(.cover) { TextField("Cover URL", text: urlBinding(\.coverURL)) }
                    choosable(.hero) { TextField("Background URL", text: urlBinding(\.heroURL)) }
                } header: {
                    HStack {
                        Text("Metadata")
                        Spacer()
                        Button(fetching ? "Fetching…" : "Fetch") { fetch() }
                            .disabled(fetching || game.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Sources…") { showSources = true }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Remove", role: .destructive) { library.remove(game.id); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    if isNew { library.add(game) } else { library.update(game) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(game.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
        .sheet(isPresented: $showSources) { MetadataSourcesSheet() }
        .alert("New Category", isPresented: $showNewCategory) {
            TextField("Name", text: $newCategory)
            Button("Create") {
                let name = newCategory.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { game.category = name }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $picker) { kind in
            MetadataPickerSheet(game: game, kind: kind) { apply($0, to: kind) }
        }
        .sheet(item: $wizard) { p in
            if p == .crossover { CrossOverWizard { dismiss() } } else { StoreWizard(platform: p) { dismiss() } }
        }
        .onChange(of: game.platform) { _, new in
            if isNew && [.steam, .epic, .gog, .crossover].contains(new) { wizard = new }
        }
    }

    private var wizardButton: some View {
        Group {
            if isNew { Button("Add from \(game.platform.label)…") { wizard = game.platform } }
        }
    }

    private func choosable<Content: View>(_ kind: PickerKind, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
            Button("Choose…") { picker = kind }.disabled(game.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func apply(_ value: PickerValue, to kind: PickerKind) {
        switch (kind, value) {
        case (.cover, .image(let url)): game.coverURL = url
        case (.hero, .image(let url)): game.heroURL = url
        case (.summary, .text(let s)): game.summary = s
        case (.genres, .list(let l)): game.genres = l
        case (.developers, .list(let l)): game.developers = l
        case (.publishers, .list(let l)): game.publishers = l
        default: break
        }
    }

    private func fetch() {
        fetching = true
        Task {
            let meta = await MetadataService.fetch(for: game)
            game.apply(meta, overwrite: true)
            fetching = false
        }
    }

    private func urlBinding(_ keyPath: WritableKeyPath<Game, URL?>) -> Binding<String> {
        Binding(
            get: { game[keyPath: keyPath]?.absoluteString ?? "" },
            set: { game[keyPath: keyPath] = URL(string: $0) }
        )
    }

    private func fileRow(_ label: String, _ value: String?, set: @escaping (String) -> Void) -> some View {
        LabeledContent(label) {
            HStack {
                Text(value.map { ($0 as NSString).lastPathComponent } ?? "None")
                    .foregroundStyle(.secondary).lineLimit(1)
                Button("Choose…") { pick(completion: set) }
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("igdbClientID") private var igdbID = ""
    @AppStorage("igdbClientSecret") private var igdbSecret = ""
    @AppStorage("sgdbAPIKey") private var sgdbKey = ""
    @AppStorage("igdbProxyURL") private var igdbProxy = ""
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("navigationStyle") private var navStyle: NavigationStyle = .sidebar
    @EnvironmentObject private var library: Library

    var body: some View {
        TabView {
            keysForm.tabItem { Label("Services", systemImage: "key") }
            MetadataSourcesView().tabItem { Label("Metadata Sources", systemImage: "line.3.horizontal.decrease.circle") }
        }
        .frame(width: 500, height: 680)
    }

    private var keysForm: some View {
        Form {
            Section("Navigation") {
                Picker("Layout", selection: $navStyle) {
                    ForEach(NavigationStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Menu Bar") {
                Toggle("Show Shelf in the menu bar", isOn: $showMenuBarIcon)
                if showMenuBarIcon {
                    Toggle("Hide Dock icon", isOn: $hideDockIcon)
                }
            }
            Section {
                Label("Steam Store: active (no key needed)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Section {
                TextField("Client ID", text: $igdbID)
                SecureField("Client Secret", text: $igdbSecret)
                Link("Get free credentials (Twitch developer console)",
                     destination: URL(string: "https://dev.twitch.tv/console/apps")!)
                Link("How to set it up",
                     destination: URL(string: "https://api-docs.igdb.com/#account-creation")!)
            } header: {
                Text("IGDB — descriptions, genres, ratings")
            } footer: {
                Text("Register an app (OAuth Redirect URL: http://localhost, Category: Application Integration), then copy its Client ID and a new secret.")
            }
            Section {
                SecureField("API Key", text: $sgdbKey)
                Link("Get API key (SteamGridDB preferences)",
                     destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
            } header: {
                Text("SteamGridDB — artwork")
            }
            Section {
                Button("Fetch Missing Metadata") { Task { await library.refreshAll(missingOnly: true) } }
                Button("Re-fetch All Metadata") { Task { await library.refreshAll(missingOnly: false) } }
            } footer: {
                Text("Keys are stored in app preferences.")
            }
        }
        .formStyle(.grouped)
    }
}
