import AppKit

enum AboutPanel {
    static func show() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        let buildDate = Bundle.main.executableURL
            .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
            .map { $0.formatted(date: .long, time: .omitted) } ?? "Unknown"

        let credits = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 11)
        let bold = NSFont.boldSystemFont(ofSize: 11)

        func heading(_ s: String) {
            credits.append(NSAttributedString(string: s + "\n", attributes: [.font: bold, .foregroundColor: NSColor.labelColor]))
        }
        func text(_ s: String) {
            credits.append(NSAttributedString(string: s + "\n\n", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        func link(_ label: String, _ url: String, trailing: String = "\n\n") {
            credits.append(NSAttributedString(string: label + trailing, attributes: [
                .font: body, .link: URL(string: url)!,
            ]))
        }

        heading("Details")
        text("Developer: Jeremiah Ownby\nVersion \(version) (build \(build))\nBuilt \(buildDate)")

        heading("Data Sources")
        text("Game information is provided by IGDB.com, the Steam Store, and SteamGridDB. Artwork and descriptions belong to their respective owners.")

        heading("Trademarks")
        text("Steam is a trademark of Valve Corporation. Epic Games is a trademark of Epic Games, Inc. GOG and GOG Galaxy are trademarks of GOG sp. z o.o. CrossOver is a trademark of CodeWeavers, Inc. Shelf is an independent app and is not affiliated with or endorsed by any of them.")

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Shelf",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "\u{00A9} \(Calendar.current.component(.year, from: Date())) Jeremiah Ownby",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
