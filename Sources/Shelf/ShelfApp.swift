import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActivationPolicy()
        }
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func updateActivationPolicy() {
        let defaults = UserDefaults.standard
        let hideDockIcon = defaults.bool(forKey: "hideDockIcon")
        let showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        let policy: NSApplication.ActivationPolicy = hideDockIcon && showMenuBarIcon ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
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
            CommandGroup(after: .sidebar) { NavigationStyleCommands() }
        }

        Settings {
            SettingsView().environmentObject(library)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ShelfMenuBarMenu()
                .environmentObject(library)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Shelf")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Joystick outline drawn as a vector (same geometry as Resources/MenuBarIcon.svg), so it
/// works whether or not the app runs from a bundle and stays sharp at any scale.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let box = NSRect(x: -14, y: -12, width: 388, height: 388)
            let transform = NSAffineTransform()
            transform.scaleX(by: rect.width / box.width, yBy: rect.height / box.height)
            transform.translateX(by: -box.minX, yBy: -box.minY)
            transform.concat()
            NSColor.black.setStroke()

            let stroke = { (path: NSBezierPath) in
                path.lineWidth = 22
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                path.stroke()
            }

            stroke(NSBezierPath(ovalIn: NSRect(x: 217.5 - 51.5, y: 62.5 - 51.5, width: 103, height: 103)))

            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: NSRect(x: 0, y: -20, width: 361, height: 253))
            clip.append(NSBezierPath(ovalIn: NSRect(x: 217.5 - 72, y: 62.5 - 72, width: 144, height: 144)))
            clip.windingRule = .evenOdd
            clip.addClip()
            let lever = NSBezierPath()
            lever.move(to: NSPoint(x: 151.275, y: 278.695))
            lever.curve(to: NSPoint(x: 137.411, y: 254.681), controlPoint1: NSPoint(x: 140.815, y: 275.893), controlPoint2: NSPoint(x: 134.608, y: 265.141))
            lever.line(to: NSPoint(x: 182.503, y: 86.393))
            lever.curve(to: NSPoint(x: 206.517, y: 72.529), controlPoint1: NSPoint(x: 185.306, y: 75.933), controlPoint2: NSPoint(x: 196.058, y: 69.726))
            lever.line(to: NSPoint(x: 221.795, y: 76.622))
            lever.curve(to: NSPoint(x: 235.660, y: 100.636), controlPoint1: NSPoint(x: 232.255, y: 79.425), controlPoint2: NSPoint(x: 238.463, y: 90.177))
            lever.line(to: NSPoint(x: 190.567, y: 268.925))
            lever.curve(to: NSPoint(x: 166.553, y: 282.789), controlPoint1: NSPoint(x: 187.764, y: 279.385), controlPoint2: NSPoint(x: 177.013, y: 285.592))
            lever.close()
            stroke(lever)
            NSGraphicsContext.restoreGraphicsState()

            let base = NSBezierPath()
            base.move(to: NSPoint(x: 359.469, y: 336.594))
            base.line(to: NSPoint(x: 359.469, y: 279.953))
            base.curve(to: NSPoint(x: 339.861, y: 260.342), controlPoint1: NSPoint(x: 359.468, y: 269.120), controlPoint2: NSPoint(x: 350.689, y: 260.342))
            base.line(to: NSPoint(x: 286.484, y: 260.344))
            base.line(to: NSPoint(x: 285.932, y: 254.854))
            base.curve(to: NSPoint(x: 259.253, y: 233.109), controlPoint1: NSPoint(x: 283.392, y: 242.444), controlPoint2: NSPoint(x: 272.413, y: 233.109))
            base.line(to: NSPoint(x: 100.219, y: 233.109))
            base.curve(to: NSPoint(x: 72.983, y: 260.342), controlPoint1: NSPoint(x: 85.175, y: 233.109), controlPoint2: NSPoint(x: 72.983, y: 245.302))
            base.line(to: NSPoint(x: 19.609, y: 260.344))
            base.curve(to: NSPoint(x: 0, y: 279.949), controlPoint1: NSPoint(x: 8.779, y: 260.342), controlPoint2: NSPoint(x: 0, y: 269.120))
            base.line(to: NSPoint(x: 0, y: 336.594))
            base.curve(to: NSPoint(x: 19.607, y: 356.200), controlPoint1: NSPoint(x: 0, y: 347.422), controlPoint2: NSPoint(x: 8.779, y: 356.200))
            base.line(to: NSPoint(x: 339.859, y: 356.203))
            base.curve(to: NSPoint(x: 359.469, y: 336.594), controlPoint1: NSPoint(x: 350.689, y: 356.200), controlPoint2: NSPoint(x: 359.468, y: 347.422))
            base.close()
            stroke(base)
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
