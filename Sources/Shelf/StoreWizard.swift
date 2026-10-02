import AppKit
import SwiftUI

/// Two-step import wizard for Steam, Epic Games and GOG.
struct StoreWizard: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    let platform: GamePlatform
    /// Called after games are added so the presenting form can close.
    var onFinish: () -> Void = {}

    private struct Candidate: Identifiable {
        let id = UUID()
        var game: Game
        var duplicate: Bool
        var selected: Bool
    }

    @State private var step = 0
    @State private var candidates: [Candidate] = []

    private var launcherName: String {
        switch platform {
        case .steam: "Steam"
        case .epic: "Epic Games Launcher"
        default: "GOG Galaxy"
        }
    }

    private var launcherInstalled: Bool {
        let paths = platform == .steam ? ["/Applications/Steam.app"]
            : platform == .epic ? ["/Applications/Epic Games Launcher.app"]
            : ["/Applications/GOG Galaxy.app"]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private var hint: String {
        switch platform {
        case .steam: "Shelf reads your installed games from every Steam library folder. Only installed games are listed."
        case .epic: "Shelf reads your installed games from the Epic Games Launcher. Only installed games are listed."
        default: "Shelf looks for GOG games in GOG Games folders and Applications. Use Browse… to add any that aren't found."
        }
    }

    private var selectedCount: Int { candidates.filter(\.selected).count }

    var body: some View {
        VStack(spacing: 0) {
            Group { step == 0 ? AnyView(introStep) : AnyView(gamesStep) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("Step \(step + 1) of 2").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if step == 1 { Button("Back") { step = 0 } }
                if step == 0 {
                    Button("Scan") { scan() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Add \(selectedCount) Game(s)") { finish() }
                        .disabled(selectedCount == 0)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add games from \(platform.label)", systemImage: platform.symbol).font(.title2.bold())
            Text(hint).foregroundStyle(.secondary)
            if launcherInstalled {
                Label("\(launcherName) found", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("\(launcherName) was not found in Applications. Games can still be detected if they are installed.",
                      systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(20)
    }

    private var gamesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select games").font(.title2.bold())
                Spacer()
                if !candidates.isEmpty {
                    Button("Select All") { setAll(true) }
                    Button("None") { setAll(false) }
                }
                if platform == .gog { Button("Browse…") { browse() } }
            }
            if candidates.isEmpty {
                ContentUnavailableView("No games found", systemImage: "questionmark.folder",
                                       description: Text("Install a game in \(launcherName), then scan again."))
            } else {
                List($candidates) { $c in
                    HStack {
                        Toggle("", isOn: $c.selected).labelsHidden().disabled(c.duplicate)
                        TextField("Title", text: $c.game.title).textFieldStyle(.plain).disabled(c.duplicate)
                        if c.duplicate { Text("Already in library").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .padding(20)
    }

    private func setAll(_ on: Bool) {
        for i in candidates.indices where !candidates[i].duplicate { candidates[i].selected = on }
    }

    private func scan() {
        let found: [Game]
        switch platform {
        case .steam: found = Importers.steam()
        case .epic: found = Importers.epic()
        default: found = Importers.gog()
        }
        candidates = found.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }.map {
            let dup = library.isDuplicate($0)
            return Candidate(game: $0, duplicate: dup, selected: !dup)
        }
        step = 1
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !candidates.contains(where: { $0.game.launchPath == url.path }) {
            let game = Game(title: url.deletingPathExtension().lastPathComponent, platform: .gog, launchPath: url.path)
            candidates.insert(Candidate(game: game, duplicate: library.isDuplicate(game), selected: true), at: 0)
        }
    }

    private func finish() {
        for c in candidates where c.selected && !c.duplicate {
            var g = c.game
            g.title = g.title.trimmingCharacters(in: .whitespaces)
            if !g.title.isEmpty { library.add(g) }
        }
        dismiss()
        onFinish()
    }
}
