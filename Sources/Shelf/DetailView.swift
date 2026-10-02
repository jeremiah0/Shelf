import AVKit
import SwiftUI

struct TrailerView: View {
    let url: URL
    @State private var player: AVPlayer?

    private var isYouTube: Bool { url.host?.contains("youtube") == true }

    var body: some View {
        if isYouTube {
            Link(destination: url) { Label("Watch Trailer", systemImage: "play.rectangle.fill") }
                .font(.callout)
        } else {
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: 640)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear { if player == nil { player = AVPlayer(url: url) } }
                .onDisappear { player?.pause() }
        }
    }
}

struct ScreenshotStrip: View {
    let urls: [URL]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(urls, id: \.self) { url in
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                    }
                    .frame(width: 284, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: 640, maxHeight: 160)
    }
}

struct DetailView: View {
    @EnvironmentObject private var library: Library
    let id: UUID
    @State private var editing = false

    var body: some View {
        if let game = library.game(id) {
            ScrollView {
                VStack(spacing: 0) {
                    hero(game)
                    HStack(alignment: .top, spacing: 28) {
                        CoverView(game: game)
                            .frame(width: 200)
                            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                        info(game)
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, -110)
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle(game.title)
            .toolbar {
                ToolbarItem {
                    Button { library.toggleFavorite(id) } label: {
                        Label("Favorite", systemImage: game.isFavorite ? "heart.fill" : "heart")
                    }
                }
                ToolbarItem {
                    Button { Task { await library.refreshMetadata(id) } } label: {
                        Label("Refresh Metadata", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { GameFormView(game: game, isNew: false) }
        }
    }

    private func hero(_ game: Game) -> some View {
        Color.clear
            .frame(height: 360)
            .background {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.6), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let url = game.heroURL ?? game.coverURL {
                        AsyncImage(url: url) { $0.image?.resizable().scaledToFill() }
                    }
                }
            }
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom)
            }
    }

    private func info(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 100)
            Text(game.title).font(.system(size: 38, weight: .bold, design: .rounded))
            HStack(spacing: 10) {
                Label(game.platform.label, systemImage: game.platform.symbol)
                if let d = game.releaseDate { Text("·"); Text(d, format: .dateTime.year()) }
                if let r = game.rating { Text("·"); Label("\(Int(r))", systemImage: "star.fill") }
            }
            .font(.callout).foregroundStyle(.secondary)

            Button { library.toggleRunning(id) } label: {
                Label(library.isRunning(id) ? "Stop" : "Play", systemImage: library.isRunning(id) ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 26).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(library.isRunning(id) ? .red : .accentColor)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            if !game.genres.isEmpty || !game.tags.isEmpty {
                FlowChips(items: game.genres + game.tags)
            }
            if !game.summary.isEmpty {
                Text(game.summary).font(.body).lineSpacing(4).frame(maxWidth: 640, alignment: .leading)
            }
            if let trailer = game.trailerURL { TrailerView(url: trailer) }
            if let shots = game.screenshots, !shots.isEmpty { ScreenshotStrip(urls: shots) }
            if let about = game.about, !about.isEmpty, about != game.summary {
                DisclosureGroup("About") {
                    Text(about).lineSpacing(4).frame(maxWidth: 640, alignment: .leading).padding(.top, 6)
                }
                .frame(maxWidth: 640)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                row("Released", game.releaseDate?.formatted(date: .long, time: .omitted) ?? "")
                row("Developer", game.developers.joined(separator: ", "))
                row("Publisher", game.publishers.joined(separator: ", "))
                row("Features", (game.features ?? []).prefix(6).joined(separator: ", "))
                row("Played", game.playCount == 0 ? "" : "\(game.playCount)×")
                row("Last Played", game.lastPlayed.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
            }
            if let site = game.websiteURL { Link("Official Website", destination: site).font(.callout) }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value)
            }
            .font(.callout)
        }
    }
}

struct FlowChips: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(8), id: \.self) {
                Text($0)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
