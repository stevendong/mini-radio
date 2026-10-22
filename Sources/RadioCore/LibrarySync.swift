import Foundation

public struct FavoriteChange: Codable, Equatable, Sendable {
    public var station: Station
    public var modifiedAt: Date
    public var removed: Bool
    public var revision: String = UUID().uuidString
}

public struct ListeningRecord: Codable, Equatable, Sendable {
    public var station: Station
    public var listenedAt: Date
    public var revision: String = UUID().uuidString
}

public struct LibrarySyncState: Codable, Equatable, Sendable {
    public var favorites: [String: FavoriteChange] = [:]
    public var history: [String: ListeningRecord] = [:]
    public init() {}
}

public struct LibrarySyncDocument: Codable, Sendable {
    public let format: String
    public let version: Int
    public let state: LibrarySyncState

    public init(library: Library) {
        var prepared = library
        prepared.prepareForSync()
        format = "mini-radio-library"
        version = 1
        state = prepared.syncState ?? LibrarySyncState()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LibrarySyncDocument {
        guard data.count <= 8 * 1_024 * 1_024 else { throw LibrarySyncError.tooLarge }
        let document = try JSONDecoder().decode(Self.self, from: data)
        guard document.format == "mini-radio-library", document.version == 1 else {
            throw LibrarySyncError.unsupportedFormat
        }
        let favoritesValid = document.state.favorites.allSatisfy {
            $0.key == $0.value.station.id && !$0.key.isEmpty && !$0.value.station.streamURLs.isEmpty
        }
        let historyValid = document.state.history.allSatisfy {
            $0.key == $0.value.station.id && !$0.key.isEmpty && !$0.value.station.streamURLs.isEmpty
        }
        guard favoritesValid, historyValid else { throw LibrarySyncError.invalidStation }
        return document
    }
}

public enum LibrarySyncError: LocalizedError {
    case tooLarge, unsupportedFormat, invalidStation

    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "同步文件超过 8 MB，未修改本机数据。"
        case .unsupportedFormat: return "暂不支持此同步文件格式，请更新应用后重试。"
        case .invalidStation: return "同步文件包含无效电台，未修改本机数据。"
        }
    }
}

extension Library {
    public mutating func prepareForSync() {
        guard syncState == nil else { return }
        var state = LibrarySyncState()
        for (index, station) in favorites.enumerated() {
            state.favorites[station.id] = FavoriteChange(
                station: station, modifiedAt: Date(timeIntervalSince1970: -Double(index)),
                removed: false, revision: "legacy-" + station.id)
        }
        for (index, station) in recent.enumerated() {
            state.history[station.id] = ListeningRecord(
                station: station, listenedAt: Date(timeIntervalSince1970: -Double(index) - 1),
                revision: "legacy-" + station.id)
        }
        if let station = lastStation {
            state.history[station.id] = ListeningRecord(
                station: station, listenedAt: Date(timeIntervalSince1970: 0), revision: "legacy-" + station.id)
        }
        syncState = state
    }

    public mutating func merge(_ document: LibrarySyncDocument) {
        prepareForSync()
        var state = syncState ?? LibrarySyncState()
        for (id, incoming) in document.state.favorites {
            if let current = state.favorites[id] {
                if incoming.modifiedAt < current.modifiedAt { continue }
                if incoming.modifiedAt == current.modifiedAt {
                    if current.removed && !incoming.removed { continue }
                    if incoming.removed == current.removed && incoming.revision <= current.revision { continue }
                }
            }
            state.favorites[id] = incoming
        }
        for (id, incoming) in document.state.history {
            if let current = state.history[id] {
                if incoming.listenedAt < current.listenedAt { continue }
                if incoming.listenedAt == current.listenedAt && incoming.revision <= current.revision { continue }
            }
            state.history[id] = incoming
        }
        favorites = state.favorites.values.filter { !$0.removed }.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.station.id < $1.station.id
        }.map(\.station)
        let history = state.history.values.sorted {
            if $0.listenedAt != $1.listenedAt { return $0.listenedAt > $1.listenedAt }
            return $0.station.id < $1.station.id
        }.prefix(50)
        recent = history.map(\.station)
        lastStation = recent.first
        state.history = Dictionary(uniqueKeysWithValues: history.map { ($0.station.id, $0) })
        syncState = state
    }
}
