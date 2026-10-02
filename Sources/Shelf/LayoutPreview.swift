import SwiftUI

/// Lightweight mock of the library in each navigation style, using placeholder boxes.
struct LayoutPreview: View {
    let style: NavigationStyle

    private let colors: [Color] = [.indigo, .pink, .teal, .orange, .blue, .green]

    var body: some View {
        HStack(spacing: 0) {
            if style == .sidebar { sidebar }
            VStack(spacing: 0) {
                if style == .top { topBar }
                grid
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 170)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Library", "square.grid.2x2", active: true)
            row("Favorites", "heart")
            row("Recent", "clock")
            Text("Categories").font(.system(size: 7, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
            row("Steam", "cloud.fill")
            row("Epic Games", "e.square.fill")
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 90, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary.opacity(0.5))
    }

    private func row(_ title: String, _ symbol: String, active: Bool = false) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 8))
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2")
                Image(systemName: "heart")
                Image(systemName: "clock")
                Image(systemName: "square.stack")
            }
            .font(.system(size: 8))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassSurface(in: Capsule())
            Spacer(minLength: 0)
            Color.clear.frame(width: 40, height: 14)
                .glassSurface(in: Capsule())
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.arrow.down")
                Image(systemName: "plus")
            }
            .font(.system(size: 8))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassSurface(in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { col in
                        let color = colors[row * 3 + col]
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                            Capsule().fill(.quaternary).frame(height: 4).padding(.trailing, 10)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
