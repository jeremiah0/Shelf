import Foundation

enum GamePlatform: String, Codable, CaseIterable, Identifiable {
    case steam, epic, gog, mac, crossover, emulator, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steam: "Steam"
        case .epic: "Epic Games"
        case .gog: "GOG"
        case .mac: "Mac"
        case .crossover: "CrossOver"
        case .emulator: "Emulator"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .steam: "cloud.fill"
        case .epic: "e.square.fill"
        case .gog: "g.square.fill"
        case .mac: "macwindow"
        case .crossover: "wineglass.fill"
        case .emulator: "gamecontroller.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

struct Game: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var platform: GamePlatform
    var steamAppID: Int?
    var epicAppName: String?
    /// App/executable path (emulator app for `.emulator`).
    var launchPath: String?
    var romPath: String?
    /// CrossOver bottle name; `launchPath` is the .exe on the Mac filesystem.
    var crossoverBottle: String?
    /// User-chosen sidebar category; nil groups the game under its platform.
    var category: String?

    var summary = ""
    var genres: [String] = []
    var developers: [String] = []
    var publishers: [String] = []
    var tags: [String] = []
    var releaseDate: Date?
    var rating: Double?
    var coverURL: URL?
    var heroURL: URL?
    // Optional so libraries saved before these fields existed still decode.
    var about: String?
    var features: [String]?
    var screenshots: [URL]?
    var trailerURL: URL?
    var websiteURL: URL?

    var isFavorite = false
    var playCount = 0
    var lastPlayed: Date?
    var dateAdded = Date()
    var metadataVersion: Int?

    static let currentMetadataVersion = 2
    var needsMetadata: Bool { (metadataVersion ?? 0) < Game.currentMetadataVersion }

    var effectiveCategory: String {
        let custom = category?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? platform.label : custom
    }
}

/// Partial metadata returned by a single source.
struct GameMetadata {
    var summary: String?
    var about: String?
    var genres: [String] = []
    var features: [String] = []
    var developers: [String] = []
    var publishers: [String] = []
    var releaseDate: Date?
    var rating: Double?
    var coverURL: URL?
    var heroURL: URL?
    var screenshots: [URL] = []
    var trailerURL: URL?
    var websiteURL: URL?

    /// Keeps values from `self`, filling gaps from `other`.
    func merged(with other: GameMetadata) -> GameMetadata {
        GameMetadata(
            summary: summary?.isEmpty == false ? summary : other.summary,
            about: about?.isEmpty == false ? about : other.about,
            genres: genres.isEmpty ? other.genres : genres,
            features: features.isEmpty ? other.features : features,
            developers: developers.isEmpty ? other.developers : developers,
            publishers: publishers.isEmpty ? other.publishers : publishers,
            releaseDate: releaseDate ?? other.releaseDate,
            rating: rating ?? other.rating,
            coverURL: coverURL ?? other.coverURL,
            heroURL: heroURL ?? other.heroURL,
            screenshots: screenshots.isEmpty ? other.screenshots : screenshots,
            trailerURL: trailerURL ?? other.trailerURL,
            websiteURL: websiteURL ?? other.websiteURL
        )
    }
}

extension Game {
    mutating func apply(_ m: GameMetadata, overwrite: Bool) {
        if let s = m.summary, overwrite || summary.isEmpty { summary = s }
        if !m.genres.isEmpty, overwrite || genres.isEmpty { genres = m.genres }
        if !m.developers.isEmpty, overwrite || developers.isEmpty { developers = m.developers }
        if !m.publishers.isEmpty, overwrite || publishers.isEmpty { publishers = m.publishers }
        if let d = m.releaseDate, overwrite || releaseDate == nil { releaseDate = d }
        if let r = m.rating, overwrite || rating == nil { rating = r }
        if let c = m.coverURL, overwrite || coverURL == nil { coverURL = c }
        if let h = m.heroURL, overwrite || heroURL == nil { heroURL = h }
        if let a = m.about, overwrite || about == nil { about = a }
        if !m.features.isEmpty, overwrite || features == nil { features = m.features }
        if !m.screenshots.isEmpty, overwrite || screenshots == nil { screenshots = m.screenshots }
        if let t = m.trailerURL, overwrite || trailerURL == nil { trailerURL = t }
        if let w = m.websiteURL, overwrite || websiteURL == nil { websiteURL = w }
    }
}
