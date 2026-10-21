import Foundation

public struct Library: Codable, Sendable {
    public var favorites: [Station] = []
    public var recent: [Station] = []
    public var lastStation: Station?
    public init() {}

    public mutating func toggleFavorite(_ station: Station) {
        if favorites.contains(where: { $0.id == station.id }) { favorites.removeAll { $0.id == station.id } }
        else { favorites.insert(station, at: 0) }
    }

    public mutating func recordSuccessfulPlayback(_ station: Station) {
        recent.removeAll { $0.id == station.id }
        recent.insert(station, at: 0)
        recent = Array(recent.prefix(50))
        lastStation = station
    }
}

public struct LibraryStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var libraryURL: URL { directory.appendingPathComponent("library.json") }

    public func load() throws -> Library {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return Library() }
        return try JSONDecoder().decode(Library.self, from: Data(contentsOf: libraryURL))
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: libraryURL, options: .atomic)
    }
}

public struct StationQuery: Hashable, Codable, Sendable {
    public var name: String
    public var countrycode: String
    public var language: String
    public var tag: String
    public init(name: String = "", countrycode: String = "", language: String = "", tag: String = "") {
        self.name = name; self.countrycode = countrycode; self.language = language; self.tag = tag
    }
    public func items(offset: Int, limit: Int) -> [URLQueryItem] {
        var result = [URLQueryItem(name: "hidebroken", value: "true"),
                      URLQueryItem(name: "order", value: "clickcount"), URLQueryItem(name: "reverse", value: "true"),
                      URLQueryItem(name: "offset", value: String(max(0, offset))),
                      URLQueryItem(name: "limit", value: String(max(1, min(100, limit))))]
        for (key, value) in [("name", name), ("countrycode", countrycode), ("language", language), ("tag", tag)] {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(URLQueryItem(name: key, value: text)) }
        }
        return result
    }
}

public struct DirectorySnapshot: Codable, Sendable {
    public let query: StationQuery
    public let stations: [Station]
    public let date: Date
    public init(query: StationQuery, stations: [Station], date: Date = Date()) {
        self.query = query; self.stations = stations; self.date = date
    }
}
