import SwiftUI

struct CoverView: View {
    let game: Game

    private var gradient: LinearGradient {
        // String.hashValue is re-seeded each launch, which would reshuffle colors.
        let hue = Double(game.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.55, brightness: 0.75), Color(hue: hue, saturation: 0.7, brightness: 0.45)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(gradient)
            Text(String(game.title.prefix(1)).uppercased())
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            if let url = game.coverURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GameCard: View {
    @EnvironmentObject private var library: Library
    let game: Game
    @State private var hovering = false

    var body: some View {
        NavigationLink(value: game.id) {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(game: game)
                    .overlay(alignment: .bottomTrailing) {
                        Button { library.launch(game.id) } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.55), in: Circle())
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .opacity(hovering ? 1 : 0)
                    }
                    .shadow(color: .black.opacity(hovering ? 0.35 : 0.18), radius: hovering ? 18 : 8, y: hovering ? 10 : 4)
                    .scaleEffect(hovering ? 1.04 : 1)
                Text(game.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .contextMenu {
            Button("Play") { library.launch(game.id) }
            Button(game.isFavorite ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(game.id) }
            Button("Refresh Metadata") { Task { await library.refreshMetadata(game.id) } }
            Divider()
            Button("Remove from Library", role: .destructive) { library.remove(game.id) }
        }
    }
}

struct GameGrid: View {
    let games: [Game]
    let title: String

    var body: some View {
        ScrollView {
            if games.isEmpty {
                ContentUnavailableView("No Games", systemImage: "gamecontroller",
                                       description: Text("Add a game or import your libraries from the toolbar."))
                    .padding(.top, 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 24)], spacing: 28) {
                    ForEach(games) { GameCard(game: $0) }
                }
                .padding(28)
            }
        }
        .navigationTitle(title)
    }
}
