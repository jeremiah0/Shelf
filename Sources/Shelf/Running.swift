import AppKit
import Foundation

/// Finds and stops the processes belonging to a game by matching their command lines.
enum ProcessScanner {
    struct Entry { let pid: pid_t; let command: String }

    static func snapshot() -> [Entry] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let me = ProcessInfo.processInfo.processIdentifier
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let t = line.drop { $0 == " " }
            guard let space = t.firstIndex(of: " "), let pid = pid_t(t[..<space]), pid != me else { return nil }
            return Entry(pid: pid, command: String(t[space...].drop { $0 == " " }))
        }
    }

    /// Lowercased substrings that identify a game's processes; Windows separators are normalized to "/".
    static func patterns(for g: Game, installDir: String?) -> [String] {
        func lower(_ s: String) -> String { s.lowercased() }
        switch g.platform {
        case .steam:
            return installDir.map { [lower("/steamapps/common/\($0)/")] } ?? []
        case .crossover:
            if g.steamAppID != nil { return installDir.map { [lower("/steamapps/common/\($0)/")] } ?? [] }
            guard let exe = g.launchPath else { return [] }
            return [lower("/" + URL(fileURLWithPath: exe).lastPathComponent)]
        case .emulator, .gog, .mac, .other:
            guard let path = g.launchPath else { return [] }
            return [lower(path.hasSuffix(".app") ? path + "/Contents/" : path)]
        case .epic:
            return []
        }
    }

    static func matches(_ entries: [Entry], patterns: [String]) -> [pid_t] {
        guard !patterns.isEmpty else { return [] }
        return entries.filter { e in
            let c = e.command.lowercased().replacingOccurrences(of: "\\", with: "/")
            return patterns.contains { c.contains($0) }
        }.map(\.pid)
    }

    /// The `installdir` of a Steam game, read from its app manifest in the given steamapps folders.
    static func steamInstallDir(appID: Int, steamapps: [URL]) -> String? {
        for dir in steamapps {
            let url = dir.appendingPathComponent("appmanifest_\(appID).acf")
            if let text = try? String(contentsOf: url, encoding: .utf8), let d = Importers.value(for: "installdir", in: text) {
                return d
            }
        }
        return nil
    }

    static func steamappsFolders(for g: Game) -> [URL] {
        let main: URL
        if g.platform == .crossover, let bottle = g.crossoverBottle, let s = CrossOver.steamInstall(in: bottle) {
            main = s.steamapps
        } else {
            main = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam/steamapps")
        }
        var dirs = [main]
        if let text = try? String(contentsOf: main.appendingPathComponent("libraryfolders.vdf"), encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: "\"path\"\\s+\"([^\"]+)\"") {
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var path = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "\\\\", with: "/")
                if g.platform == .crossover, let bottle = g.crossoverBottle {
                    guard path.lowercased().hasPrefix("c:") else { continue }
                    path = CrossOver.bottlesDir.appendingPathComponent(bottle).appendingPathComponent("drive_c").path + path.dropFirst(2)
                }
                dirs.append(URL(fileURLWithPath: path).appendingPathComponent("steamapps"))
            }
        }
        return dirs
    }

    static func terminate(_ pids: [pid_t]) {
        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid) { app.terminate() } else { kill(pid, SIGTERM) }
        }
        // Escalate for anything that ignores the polite request.
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            let alive = Set(snapshot().map(\.pid))
            for pid in pids where alive.contains(pid) { kill(pid, SIGKILL) }
        }
    }
}

extension Library {
    /// Whether the game's process is up, or it was just launched and may still be starting.
    func isRunning(_ id: UUID) -> Bool { running.contains(id) }

    func toggleRunning(_ id: UUID) {
        if isRunning(id) { stop(id) } else { launch(id) }
    }

    func stop(_ id: UUID) {
        guard let g = game(id) else { return }
        launching[id] = nil
        Task {
            let pids = await Task.detached { () -> [pid_t] in
                let dir = g.steamAppID.flatMap { ProcessScanner.steamInstallDir(appID: $0, steamapps: ProcessScanner.steamappsFolders(for: g)) }
                return ProcessScanner.matches(ProcessScanner.snapshot(), patterns: ProcessScanner.patterns(for: g, installDir: dir))
            }.value
            ProcessScanner.terminate(pids)
            refreshRunning()
        }
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshRunning()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refreshRunning() {
        let games = self.games
        let launching = self.launching
        Task {
            let result = await Task.detached { () -> Set<UUID> in
                let entries = ProcessScanner.snapshot()
                var found = Set<UUID>()
                for g in games where g.platform != .epic {
                    let dir = g.steamAppID.flatMap { ProcessScanner.steamInstallDir(appID: $0, steamapps: ProcessScanner.steamappsFolders(for: g)) }
                    if !ProcessScanner.matches(entries, patterns: ProcessScanner.patterns(for: g, installDir: dir)).isEmpty {
                        found.insert(g.id)
                    }
                }
                return found
            }.value
            // Keep a freshly launched game "running" while it starts, until it appears or the grace period lapses.
            var next = result
            for (id, date) in launching where Date().timeIntervalSince(date) < 30 && !result.contains(id) { next.insert(id) }
            for id in result { self.launching[id] = nil }
            if next != self.running { self.running = next }
        }
    }
}
