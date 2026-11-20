import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowBecameMain(_:)),
                           name: NSWindow.didBecomeMainNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && window.canBecomeMain && window.parent == nil
    }

    @objc private func windowBecameMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isAppWindow(window) else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isAppWindow(window) else { return }
        // AppKit posts willClose before updating the window list.
        DispatchQueue.main.async {
            let hasWindow = NSApp.windows.contains {
                self.isAppWindow($0) && ($0.isVisible || $0.isMiniaturized)
            }
            if !hasWindow && NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library = Library()

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
            CommandGroup(after: .sidebar) { NavigationStyleCommands() }
        }

        Settings {
            SettingsView().environmentObject(library)
        }

        MenuBarExtra {
            ShelfMenuBarMenu()
                .environmentObject(library)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Shelf")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Compact silhouette of the game cases used in the app icon.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height),
                             xRadius: 0.8, yRadius: 0.8).fill()
            }
            bar(1, 6, 3, 7)
            bar(5.5, 2, 4, 11)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: 13, yBy: 13)
            transform.rotate(byDegrees: -17)
            transform.concat()
            bar(0, -9, 3, 9)
            NSGraphicsContext.restoreGraphicsState()
            bar(0.5, 14.5, 17, 2)
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct NavigationStyleCommands: View {
    @AppStorage("navigationStyle") private var navStyle: NavigationStyle = .sidebar

    var body: some View {
        Picker("Navigation Layout", selection: $navStyle) {
            ForEach(NavigationStyle.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.inline)
    }
}

private struct ShelfMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var library: Library

    private var recentlyPlayedGames: [Game] {
        library.games
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(10)
            .map { $0 }
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
