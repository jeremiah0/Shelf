import Foundation

private func fetchJSON<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(T.self, from: data)
}

// MARK: - IGDB

struct IGDBConfig {
    var clientID = ""
    var secret = ""
    /// Optional proxy that holds the Twitch secret and forwards IGDB queries.
    var proxy = ""

    var isUsable: Bool { !proxy.isEmpty || (!clientID.isEmpty && !secret.isEmpty) }
}

actor IGDBClient {
    static let shared = IGDBClient()
    private var token: String?
    private var expiry = Date.distantPast

    private struct Token: Decodable { let access_token: String; let expires_in: Double }
    private struct Named: Decodable { let name: String }
    private struct Img: Decodable { let image_id: String }
    private struct Video: Decodable { let video_id: String }
    private struct Website: Decodable { let url: URL; let category: Int? }
    private struct Company: Decodable { let developer: Bool?; let publisher: Bool?; let company: Named? }
    private struct Row: Decodable {
        let name: String
        let summary: String?
        let genres: [Named]?
        let game_modes: [Named]?
        let involved_companies: [Company]?
        let first_release_date: TimeInterval?
        let total_rating: Double?
        let cover: Img?
        let artworks: [Img]?
        let screenshots: [Img]?
        let videos: [Video]?
        let websites: [Website]?
    }

    private func accessToken(id: String, secret: String) async throws -> String {
        if let token, expiry > Date() { return token }
        var comps = URLComponents(string: "https://id.twitch.tv/oauth2/token")!
        comps.queryItems = [
            .init(name: "client_id", value: id),
            .init(name: "client_secret", value: secret),
            .init(name: "grant_type", value: "client_credentials"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        let t = try await fetchJSON(req, as: Token.self)
        token = t.access_token
        expiry = Date().addingTimeInterval(t.expires_in - 60)
        return t.access_token
    }

    func lookup(title: String, config: IGDBConfig) async throws -> GameMetadata? {
        var req: URLRequest
        if let proxy = URL(string: config.proxy), !config.proxy.isEmpty {
            req = URLRequest(url: proxy)
        } else {
            req = URLRequest(url: URL(string: "https://api.igdb.com/v4/games")!)
            let tok = try await accessToken(id: config.clientID, secret: config.secret)
            req.setValue(config.clientID, forHTTPHeaderField: "Client-ID")
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        req.httpMethod = "POST"
        let safe = title.replacingOccurrences(of: "\"", with: "")
        let fields = "name,summary,genres.name,game_modes.name,involved_companies.developer,involved_companies.publisher,involved_companies.company.name,first_release_date,total_rating,cover.image_id,artworks.image_id,screenshots.image_id,videos.video_id,websites.url,websites.category"
        req.httpBody = Data("search \"\(safe)\"; fields \(fields); limit 5;".utf8)

        let rows = try await fetchJSON(req, as: [Row].self)
        let key = title.lowercased()
        guard let row = rows.first(where: { $0.name.lowercased() == key }) ?? rows.first else { return nil }

        func image(_ id: String, _ size: String) -> URL? {
            URL(string: "https://images.igdb.com/igdb/image/upload/t_\(size)/\(id).jpg")
        }
        let companies = row.involved_companies ?? []
        let heroID = row.artworks?.first?.image_id ?? row.screenshots?.first?.image_id
        return GameMetadata(
            summary: row.summary,
            genres: row.genres?.map(\.name) ?? [],
            features: row.game_modes?.map(\.name) ?? [],
            developers: companies.filter { $0.developer == true }.compactMap { $0.company?.name },
            publishers: companies.filter { $0.publisher == true }.compactMap { $0.company?.name },
            releaseDate: row.first_release_date.map { Date(timeIntervalSince1970: $0) },
            rating: row.total_rating,
            coverURL: row.cover.flatMap { image($0.image_id, "cover_big_2x") },
            heroURL: heroID.flatMap { image($0, "1080p") },
            screenshots: (row.screenshots ?? []).prefix(8).compactMap { image($0.image_id, "screenshot_big") },
            trailerURL: row.videos?.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.video_id)") },
            websiteURL: (row.websites?.first { $0.category == 1 } ?? row.websites?.first)?.url
        )
    }
}

// MARK: - Steam Store (public API; SteamDB has no official API)

enum SteamClient {
    private struct Search: Decodable {
        struct Item: Decodable { let id: Int; let name: String }
        let items: [Item]
    }
    private struct Entry: Decodable {
        struct Payload: Decodable {
            struct Described: Decodable { let description: String }
            struct Release: Decodable { let date: String? }
            struct Meta: Decodable { let score: Double? }
            struct Shot: Decodable { let path_full: URL }
            struct Movie: Decodable {
                struct Files: Decodable { let max: String? }
                let mp4: Files?
            }
            let short_description: String?
            let about_the_game: String?
            let developers: [String]?
            let publishers: [String]?
            let genres: [Described]?
            let categories: [Described]?
            let release_date: Release?
            let metacritic: Meta?
            let screenshots: [Shot]?
            let movies: [Movie]?
            let website: String?
        }
        let success: Bool
        let data: Payload?
    }

    static func findAppID(title: String) async -> Int? {
        var comps = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        comps.queryItems = [.init(name: "term", value: title), .init(name: "l", value: "english"), .init(name: "cc", value: "us")]
        guard let result = try? await fetchJSON(URLRequest(url: comps.url!), as: Search.self) else { return nil }
        let key = title.lowercased()
        return result.items.first { $0.name.lowercased() == key }?.id
            ?? result.items.first { $0.name.lowercased().contains(key) }?.id
    }

    static func lookup(title: String, appID: Int?) async throws -> GameMetadata? {
        let found: Int?
        if let appID { found = appID } else { found = await findAppID(title: title) }
        guard let id = found else { return nil }
        let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(id)&l=english")!
        let map = try await fetchJSON(URLRequest(url: url), as: [String: Entry].self)
        guard let entry = map["\(id)"], entry.success, let d = entry.data else { return nil }

        let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)"
        return GameMetadata(
            summary: d.short_description,
            about: d.about_the_game.map(stripHTML),
            genres: d.genres?.map(\.description) ?? [],
            features: d.categories?.map(\.description) ?? [],
            developers: d.developers ?? [],
            publishers: d.publishers ?? [],
            releaseDate: d.release_date?.date.flatMap(parseDate),
            rating: d.metacritic?.score,
            coverURL: URL(string: "\(cdn)/library_600x900_2x.jpg"),
            heroURL: URL(string: "\(cdn)/library_hero.jpg"),
            screenshots: (d.screenshots ?? []).prefix(8).map(\.path_full),
            trailerURL: d.movies?.first?.mp4?.max.flatMap { URL(string: $0) },
            websiteURL: d.website.flatMap { URL(string: $0) }
        )
    }

    private static func parseDate(_ s: String) -> Date? {
        // DateFormatter isn't thread-safe, and lookups run concurrently.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["d MMM, yyyy", "MMM d, yyyy", "MMM yyyy", "yyyy"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func stripHTML(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&quot;", "\""), ("&amp;", "&"), ("&#39;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - SteamGridDB (artwork)

enum SteamGridDBClient {
    private struct Response<T: Decodable>: Decodable { let data: [T] }
    private struct Game: Decodable { let id: Int }
    private struct Asset: Decodable { let url: URL }

    private static func request(_ path: String, key: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://www.steamgriddb.com/api/v2/\(path)")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return req
    }

    static func lookup(title: String, steamAppID: Int?, key: String) async throws -> GameMetadata? {
        let art = try await artwork(title: title, steamAppID: steamAppID, key: key)
        guard art.covers.first != nil || art.heroes.first != nil else { return nil }
        return GameMetadata(coverURL: art.covers.first, heroURL: art.heroes.first)
    }

    static func artwork(title: String, steamAppID: Int?, key: String, limit: Int = 12) async throws -> (covers: [URL], heroes: [URL]) {
        let gridPath: String
        let heroPath: String
        if let steamAppID {
            gridPath = "grids/steam/\(steamAppID)?dimensions=600x900"
            heroPath = "heroes/steam/\(steamAppID)"
        } else {
            let term = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            let found = try await fetchJSON(request("search/autocomplete/\(term)", key: key), as: Response<Game>.self)
            guard let id = found.data.first?.id else { return ([], []) }
            gridPath = "grids/game/\(id)?dimensions=600x900"
            heroPath = "heroes/game/\(id)"
        }
        async let grids = try? fetchJSON(request(gridPath, key: key), as: Response<Asset>.self)
        async let heroes = try? fetchJSON(request(heroPath, key: key), as: Response<Asset>.self)
        let cover = await grids?.data.prefix(limit).map(\.url) ?? []
        let hero = await heroes?.data.prefix(limit).map(\.url) ?? []
        return (cover, hero)
    }
}

// MARK: - Aggregator

enum MetadataSource: String, Codable, CaseIterable, Identifiable {
    case igdb, steam, steamGridDB

    var id: String { rawValue }
    var label: String {
        switch self {
        case .igdb: "IGDB"
        case .steam: "Steam Store"
        case .steamGridDB: "SteamGridDB"
        }
    }
}

enum MetadataField: String, CaseIterable, Identifiable {
    case summary, about, genres, features, developers, publishers, releaseDate, rating
    case cover, hero, screenshots, trailer, website

    var id: String { rawValue }
    var label: String {
        switch self {
        case .summary: "Summary"
        case .about: "Long Description"
        case .genres: "Genres"
        case .features: "Features"
        case .developers: "Developers"
        case .publishers: "Publishers"
        case .releaseDate: "Release Date"
        case .rating: "Rating"
        case .cover: "Cover Art"
        case .hero: "Background Art"
        case .screenshots: "Screenshots"
        case .trailer: "Trailer"
        case .website: "Website"
        }
    }

    /// Order used when no source is chosen. Steam trailers are direct video files that play inline; IGDB's are YouTube links.
    var defaultOrder: [MetadataSource] {
        switch self {
        case .cover, .hero: [.steamGridDB, .igdb, .steam]
        case .trailer: [.steam, .igdb]
        default: [.igdb, .steam, .steamGridDB]
        }
    }
}

struct MetadataPreferences: Codable, Equatable {
    var disabled: Set<MetadataSource> = []
    /// Field raw value -> source raw value; absent means automatic.
    var preferred: [String: String] = [:]

    private static let key = "metadataPreferences"

    static func load() -> MetadataPreferences {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(MetadataPreferences.self, from: $0) } ?? MetadataPreferences()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func source(for field: MetadataField) -> MetadataSource? {
        preferred[field.rawValue].flatMap(MetadataSource.init(rawValue:))
    }

    mutating func setSource(_ source: MetadataSource?, for field: MetadataField) {
        preferred[field.rawValue] = source?.rawValue
    }

    /// A chosen source is tried first, then the defaults act as fallback.
    func order(for field: MetadataField) -> [MetadataSource] {
        var list = field.defaultOrder
        if let chosen = source(for: field) { list.removeAll { $0 == chosen }; list.insert(chosen, at: 0) }
        return list.filter { !disabled.contains($0) }
    }
}

enum MetadataService {
    static func fetch(for game: Game, preferences: MetadataPreferences = .load()) async -> GameMetadata {
        let results = await fetchBySource(for: game, preferences: preferences)

        func pick<T>(_ field: MetadataField, _ get: (GameMetadata) -> T?) -> T? {
            for source in preferences.order(for: field) {
                if let meta = results[source], let value = get(meta) { return value }
            }
            return nil
        }
        func nonEmpty(_ s: String?) -> String? { s?.isEmpty == false ? s : nil }
        func nonEmpty<T>(_ a: [T]) -> [T]? { a.isEmpty ? nil : a }

        return GameMetadata(
            summary: pick(.summary) { nonEmpty($0.summary) },
            about: pick(.about) { nonEmpty($0.about) },
            genres: pick(.genres) { nonEmpty($0.genres) } ?? [],
            features: pick(.features) { nonEmpty($0.features) } ?? [],
            developers: pick(.developers) { nonEmpty($0.developers) } ?? [],
            publishers: pick(.publishers) { nonEmpty($0.publishers) } ?? [],
            releaseDate: pick(.releaseDate) { $0.releaseDate },
            rating: pick(.rating) { $0.rating },
            coverURL: pick(.cover) { $0.coverURL },
            heroURL: pick(.hero) { $0.heroURL },
            screenshots: pick(.screenshots) { nonEmpty($0.screenshots) } ?? [],
            trailerURL: pick(.trailer) { $0.trailerURL },
            websiteURL: pick(.website) { $0.websiteURL }
        )
    }

    static func fetchBySource(for game: Game, preferences: MetadataPreferences = .load()) async -> [MetadataSource: GameMetadata] {
        let defaults = UserDefaults.standard
        let igdbConfig = IGDBConfig(
            clientID: defaults.string(forKey: "igdbClientID") ?? "",
            secret: defaults.string(forKey: "igdbClientSecret") ?? "",
            proxy: defaults.string(forKey: "igdbProxyURL") ?? ""
        )
        let sgdbKey = defaults.string(forKey: "sgdbAPIKey") ?? ""
        let off = preferences.disabled

        async let igdb: GameMetadata? = {
            guard !off.contains(.igdb), igdbConfig.isUsable else { return nil }
            return try? await IGDBClient.shared.lookup(title: game.title, config: igdbConfig)
        }()
        async let steam: GameMetadata? = {
            guard !off.contains(.steam) else { return nil }
            return try? await SteamClient.lookup(title: game.title, appID: game.steamAppID)
        }()
        async let grid: GameMetadata? = {
            guard !off.contains(.steamGridDB), !sgdbKey.isEmpty else { return nil }
            return try? await SteamGridDBClient.lookup(title: game.title, steamAppID: game.steamAppID, key: sgdbKey)
        }()

        let (i, s, g) = await (igdb, steam, grid)
        return [.igdb: i, .steam: s, .steamGridDB: g].compactMapValues { $0 }
    }
}
