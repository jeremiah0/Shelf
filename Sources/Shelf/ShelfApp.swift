import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library = Library()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = false

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(library)
                .onAppear { library.startMonitoring() }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Shelf") { AboutPanel.show() }
            }
        }

        Settings {
            SettingsView().environmentObject(library)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ShelfMenuBarMenu()
                .environmentObject(library)
        } label: {
            Image(nsImage: NSApp.applicationIconImage)
                .renderingMode(.template)
                .accessibilityLabel("Shelf")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct ShelfMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var library: Library

    private var recentlyPlayedGames: [Game] {
        library.games
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    var body: some View {
        Section("Recently Played") {
            if recentlyPlayedGames.isEmpty {
                Text("No recently played games")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentlyPlayedGames) { game in
                    Button {
                        library.launch(game.id)
                    } label: {
                        Label(game.title, systemImage: game.platform.symbol)
                    }
                }
            }
        }
        Divider()
        Button("Open Shelf") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        SettingsLink()
        Button("Quit Shelf") {
            NSApp.terminate(nil)
        }
    }
}
