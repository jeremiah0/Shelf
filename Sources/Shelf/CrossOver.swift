import AppKit
import SwiftUI

enum CrossOver {
    static let bottlesDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CrossOver/Bottles")

    static let appURL: URL? = [
        URL(fileURLWithPath: "/Applications/CrossOver.app"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/CrossOver.app"),
    ].first { FileManager.default.fileExists(atPath: $0.path) }

    static var wineURL: URL? {
        appURL?.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
    }

    static func bottles() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: bottlesDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { $0.hasDirectoryPath }.map(\.lastPathComponent).sorted()
    }

    private static let ignored = [
        "unins", "uninstall", "setup", "install", "redist", "vcredist", "dxsetup", "dotnet", "crashreport",
        "crashhandler", "updater", "helper", "unitycrashhandler", "directx", "ndp", "vc_redist",
    ]
    private static let ignoredFolders = ["windows", "common files", "windowsapps", "internet explorer", "windows nt",
                                          "microsoft", "windows media player", "windows defender", "_commonredist"]

    private static func driveC(_ bottle: String) -> URL {
        bottlesDir.appendingPathComponent(bottle).appendingPathComponent("drive_c")
    }

    /// Steam.exe and its steamapps folder when Steam is installed in the bottle.
    static func steamInstall(in bottle: String) -> (exe: URL, steamapps: URL)? {
        let fm = FileManager.default
        for root in ["Program Files (x86)", "Program Files"] {
            let dir = driveC(bottle).appendingPathComponent(root).appendingPathComponent("Steam")
            let exe = dir.appendingPathComponent("steam.exe")
            if fm.fileExists(atPath: exe.path) { return (exe, dir.appendingPathComponent("steamapps")) }
        }
        return nil
    }

    /// Installed Steam games in the bottle, launched through the bottle's Steam client.
    static func steamGames(in bottle: String) -> [Game] {
        guard let steam = steamInstall(in: bottle) else { return [] }
        return Importers.steamGames(steamapps: steam.steamapps, driveC: driveC(bottle), platform: .crossover).map {
            var g = $0
            g.launchPath = steam.exe.path
            g.crossoverBottle = bottle
            return g
        }
    }

    /// Finds likely game executables under the bottle's Program Files folders (a few levels deep per app).
    static func executables(in bottle: String) -> [URL] {
        let drive = driveC(bottle)
        var found: [URL] = []
        let fm = FileManager.default
        for root in ["Program Files", "Program Files (x86)", "Games"] {
            let rootURL = drive.appendingPathComponent(root)
            guard let apps = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { continue }
            for app in apps where app.hasDirectoryPath && !ignoredFolders.contains(app.lastPathComponent.lowercased()) {
                // Steam and its games are listed from its manifests instead.
                if app.lastPathComponent.lowercased() == "steam" { continue }
                guard let en = fm.enumerator(at: app, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in en {
                    if en.level > 3 { en.skipDescendants(); continue }
                    guard url.pathExtension.lowercased() == "exe" else { continue }
                    let name = url.deletingPathExtension().lastPathComponent.lowercased()
                    if !ignored.contains(where: name.contains) { found.append(url) }
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    static func launch(exe: String, bottle: String, args: [String] = []) {
        guard let wine = wineURL else { return }
        let url = URL(fileURLWithPath: exe)
        let p = Process()
        p.executableURL = wine
        p.arguments = ["--bottle", bottle, "start", "/unix", exe] + args
        p.currentDirectoryURL = url.deletingLastPathComponent()
        try? p.run()
    }
}

struct CrossOverWizard: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    /// Called after games are added so the presenting form can close.
    var onFinish: () -> Void

    private struct Candidate: Identifiable {
        let id = UUID()
        let url: URL
        var title: String
        var steamAppID: Int?
        var selected = false
    }

    @State private var step = 0
    @State private var bottles: [String] = []
    @State private var bottle: String?
    @State private var candidates: [Candidate] = []
    @State private var scanning = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: bottleStep
                default: appsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Text("Step \(step + 1) of 2").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if step == 1 { Button("Back") { step = 0 } }
                if step == 0 {
                    Button("Next") { scan() }
                        .disabled(bottle == nil)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Add \(candidates.filter(\.selected).count) Game(s)") { finish() }
                        .disabled(!candidates.contains(where: \.selected))
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
        .onAppear {
            bottles = CrossOver.bottles()
            bottle = bottles.first
        }
    }

    private var bottleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add applications from CrossOver").font(.title2.bold())
            if CrossOver.appURL == nil {
                Label("CrossOver.app was not found in Applications; games can be added but won't launch.",
                      systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if bottles.isEmpty {
                ContentUnavailableView("No bottles found", systemImage: "wineglass",
                                       description: Text("Create a bottle and install a game in CrossOver first."))
            } else {
                Text("Choose the bottle that contains your games.").foregroundStyle(.secondary)
                List(bottles, id: \.self, selection: $bottle) { Label($0, systemImage: "shippingbox") }
            }
        }
        .padding(20)
    }

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select applications").font(.title2.bold())
                Spacer()
                Button("Browse…") { browse() }
            }
            if scanning {
                ProgressView("Scanning \(bottle ?? "")…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidates.isEmpty {
                ContentUnavailableView("No executables found", systemImage: "questionmark.folder",
                                       description: Text("Use Browse… to pick an .exe inside the bottle."))
            } else {
                List($candidates) { $c in
                    HStack {
                        Toggle("", isOn: $c.selected).labelsHidden()
                        VStack(alignment: .leading) {
                            TextField("Title", text: $c.title).textFieldStyle(.plain)
                            Text(c.steamAppID.map { "Steam game \u{2022} App ID \($0)" } ?? relativePath(c.url))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func relativePath(_ url: URL) -> String {
        guard let bottle, let r = url.path.range(of: "/\(bottle)/drive_c/") else { return url.path }
        return "C:/" + url.path[r.upperBound...]
    }

    private func candidate(_ url: URL, selected: Bool) -> Candidate {
        Candidate(url: url, title: Self.guessTitle(url), selected: selected)
    }

    // Prefers the install folder name, which is usually the game's title.
    private static func guessTitle(_ url: URL) -> String {
        let folder = url.deletingLastPathComponent().lastPathComponent
        let generic = ["bin", "binaries", "win64", "win32", "x64", "x86", "game"]
        return generic.contains(folder.lowercased()) ? url.deletingPathExtension().lastPathComponent : folder
    }

    private func scan() {
        guard let bottle else { return }
        step = 1
        scanning = true
        candidates = []
        Task {
            let (steam, urls) = await Task.detached { (CrossOver.steamGames(in: bottle), CrossOver.executables(in: bottle)) }.value
            let steamPicks = steam.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }.map {
                Candidate(url: URL(fileURLWithPath: $0.launchPath ?? ""), title: $0.title, steamAppID: $0.steamAppID,
                          selected: !library.isDuplicate($0))
            }
            candidates = steamPicks + urls.map { candidate($0, selected: false) }
            scanning = false
        }
    }

    private func browse() {
        guard let bottle else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = CrossOver.bottlesDir.appendingPathComponent(bottle).appendingPathComponent("drive_c")
        panel.allowedContentTypes = [.init(filenameExtension: "exe")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !candidates.contains(where: { $0.url == url }) {
            candidates.insert(candidate(url, selected: true), at: 0)
        }
    }

    private func finish() {
        guard let bottle else { return }
        for c in candidates where c.selected {
            let title = c.title.trimmingCharacters(in: .whitespaces)
            library.add(Game(title: title.isEmpty ? c.url.deletingPathExtension().lastPathComponent : title,
                             platform: .crossover, steamAppID: c.steamAppID, launchPath: c.url.path, crossoverBottle: bottle))
        }
        dismiss()
        onFinish()
    }
}
