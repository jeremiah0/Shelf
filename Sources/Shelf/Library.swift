import AppKit
import Foundation

@MainActor
final class Library: ObservableObject {
    @Published var games: [Game] = [] { didSet { scheduleSave() } }
    @Published var status: String?
    @Published var running: Set<UUID> = []
    var launching: [UUID: Date] = [:]
    var monitorTask: Task<Void, Never>?

    private var saveTask: Task<Void, Never>?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Game].self, from: data) {
            games = decoded
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        let enc = JSONEncoder()
        if let data = try? enc.encode(games) { try? data.write(to: fileURL, options: .atomic) }
    }

    // Coalesces rapid edits (e.g. bulk metadata updates) into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    var allTags: [String] { Array(Set(games.flatMap(\.tags))).sorted() }

    var allCategories: [String] {
        Array(Set(games.map(\.effectiveCategory))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func game(_ id: UUID) -> Game? { games.first { $0.id == id } }

    func update(_ game: Game) {
        if let i = games.firstIndex(where: { $0.id == game.id }) { games[i] = game }
    }

    func remove(_ id: UUID) { games.removeAll { $0.id == id } }

    func toggleFavorite(_ id: UUID) {
        if var g = game(id) { g.isFavorite.toggle(); update(g) }
    }

    func add(_ game: Game) {
        games.append(game)
        Task { await refreshMetadata(game.id) }
    }

    // MARK: Launching

    func launch(_ id: UUID) {
        guard var g = game(id) else { return }
        let ws = NSWorkspace.shared
        switch g.platform {
        case .steam:
            if let appID = g.steamAppID, let url = URL(string: "steam://rungameid/\(appID)") { ws.open(url) }
        case .epic:
            if let name = g.epicAppName,
               let url = URL(string: "com.epicgames.launcher://apps/\(name)?action=launch&silent=true") { ws.open(url) }
        case .crossover:
            if let exe = g.launchPath, let bottle = g.crossoverBottle {
                CrossOver.launch(exe: exe, bottle: bottle, args: g.steamAppID.map { ["-applaunch", "\($0)"] } ?? [])
            }
        case .emulator:
            if let app = g.launchPath, let rom = g.romPath {
                ws.open([URL(fileURLWithPath: rom)], withApplicationAt: URL(fileURLWithPath: app),
                        configuration: NSWorkspace.OpenConfiguration())
            }
        default:
            guard let path = g.launchPath else { return }
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "app" {
                ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                let p = Process()
                p.executableURL = url
                p.currentDirectoryURL = url.deletingLastPathComponent()
                try? p.run()
            }
        }
        g.playCount += 1
        g.lastPlayed = Date()
        update(g)
        if g.platform != .epic {
            launching[id] = Date()
            running.insert(id)
        }
    }

    // MARK: Metadata

    func refreshMetadata(_ id: UUID) async {
        guard let g = game(id) else { return }
        status = "Fetching \(g.title)…"
        applyMetadata(await MetadataService.fetch(for: g), to: id)
        status = nil
    }

    private func applyMetadata(_ meta: GameMetadata, to id: UUID) {
        guard var g = game(id) else { return }
        g.apply(meta, overwrite: true)
        g.metadataVersion = Game.currentMetadataVersion
        update(g)
    }

    func refreshAll(missingOnly: Bool) async {
        let targets = games.filter { !missingOnly || $0.needsMetadata }
        guard !targets.isEmpty else { return }
        var done = 0
        await withTaskGroup(of: (UUID, GameMetadata).self) { group in
            var running = 0
            for g in targets {
                if running == 4, let r = await group.next() {
                    applyMetadata(r.1, to: r.0)
                    done += 1
                    status = "Updated \(done) of \(targets.count)"
                    running -= 1
                }
                group.addTask { (g.id, await MetadataService.fetch(for: g)) }
                running += 1
            }
            for await r in group {
                applyMetadata(r.1, to: r.0)
                done += 1
                status = "Updated \(done) of \(targets.count)"
            }
        }
        status = nil
    }

    // MARK: Importing

    func isDuplicate(_ new: Game) -> Bool {
        games.contains {
            if new.steamAppID != nil {
                return $0.steamAppID == new.steamAppID && $0.platform == new.platform && $0.crossoverBottle == new.crossoverBottle
            }
            return ($0.epicAppName != nil && $0.epicAppName == new.epicAppName)
                || ($0.launchPath != nil && $0.launchPath == new.launchPath && $0.romPath == new.romPath)
        }
    }

    private func merge(_ incoming: [Game], source: String) {
        let fresh = incoming.filter { !isDuplicate($0) }
        games.append(contentsOf: fresh)
        status = "Imported \(fresh.count) from \(source)"
        Task { await refreshAll(missingOnly: true) }
    }

    func importSteam() { merge(Importers.steam(), source: "Steam") }
    func importEpic() { merge(Importers.epic(), source: "Epic Games") }
    func importMacGames() { merge(Importers.macGames(), source: "Applications") }
}

enum Importers {
    private static let steamIgnored = ["Steamworks", "Proton", "Steam Linux Runtime", "Steam Client"]

    static func steam() -> [Game] {
        let main = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam/steamapps")
        return steamGames(steamapps: main, driveC: nil, platform: .steam)
    }

    /// Reads Steam manifests; with `driveC` set, library paths are Windows paths inside that bottle.
    static func steamGames(steamapps main: URL, driveC: URL?, platform: GamePlatform) -> [Game] {
        let fm = FileManager.default
        var dirs = [main]
        if let text = try? String(contentsOf: main.appendingPathComponent("libraryfolders.vdf"), encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: "\"path\"\\s+\"([^\"]+)\"") {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var path = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "\\\\", with: "/")
                if let driveC {
                    guard path.lowercased().hasPrefix("c:") else { continue }
                    path = driveC.path + path.dropFirst(2)
                }
                let dir = URL(fileURLWithPath: path).appendingPathComponent("steamapps")
                if !dirs.contains(dir) { dirs.append(dir) }
            }
        }
        let files = dirs.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        return files.filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      let idStr = value(for: "appid", in: text), let id = Int(idStr),
                      let name = value(for: "name", in: text),
                      !steamIgnored.contains(where: name.contains) else { return nil }
                return Game(title: name, platform: platform, steamAppID: id)
            }
    }

    static func epic() -> [Game] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "item" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["DisplayName"] as? String,
                  let app = json["AppName"] as? String else { return nil }
            return Game(title: name, platform: .epic, epicAppName: app)
        }
    }

    static func gog() -> [Game] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent("GOG Games"), URL(fileURLWithPath: "/Applications/GOG Games"),
                     URL(fileURLWithPath: "/Users/Shared/GOG.com")]
        var apps: [URL] = []
        for root in roots {
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "app" { apps.append(item) }
                else if item.hasDirectoryPath {
                    apps += ((try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [])
                        .filter { $0.pathExtension == "app" }
                }
            }
        }
        for dir in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            apps += ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter {
                $0.pathExtension == "app" && (Bundle(url: $0)?.bundleIdentifier ?? "").lowercased().contains("gog")
                    && !$0.lastPathComponent.contains("Galaxy")
            }
        }
        return apps.map { Game(title: $0.deletingPathExtension().lastPathComponent, platform: .gog, launchPath: $0.path) }
    }

    static func macGames() -> [Game] {
        let dir = URL(fileURLWithPath: "/Applications")
        let apps = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return apps.filter { $0.pathExtension == "app" }.compactMap { url in
            guard let info = Bundle(url: url)?.infoDictionary,
                  let category = info["LSApplicationCategoryType"] as? String,
                  category.contains("games") else { return nil }
            return Game(title: url.deletingPathExtension().lastPathComponent, platform: .mac, launchPath: url.path)
        }
    }

    /// Reads a `"key"  "value"` pair from Valve KeyValues text.
    static func value(for key: String, in text: String) -> String? {
        let pattern = "\"\(key)\"\\s+\"([^\"]*)\""
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(text[range])
        return match.split(separator: "\"").last.map(String.init)
    }
}
