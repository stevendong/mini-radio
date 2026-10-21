import Foundation

public struct Station: Codable, Identifiable, Equatable, Sendable {
    public var stationuuid: String
    public var name: String
    public var url: String
    public var urlResolved: String
    public var countrycode: String
    public var state: String
    public var language: String
    public var tags: String
    public var codec: String
    public var bitrate: Int
    public var id: String { stationuuid }
    public var isDirectoryStation: Bool { UUID(uuidString: id) != nil }

    public init(id: String, name: String, url: String, resolved: String = "",
                countrycode: String = "", state: String = "", language: String = "",
                tags: String = "", codec: String = "", bitrate: Int = 0) {
        self.stationuuid = id; self.name = name; self.url = url; self.urlResolved = resolved
        self.countrycode = countrycode; self.state = state; self.language = language
        self.tags = tags; self.codec = codec; self.bitrate = bitrate
    }

    enum CodingKeys: String, CodingKey {
        case stationuuid, name, url, countrycode, state, language, tags, codec, bitrate
        case urlResolved = "url_resolved"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stationuuid = try c.decode(String.self, forKey: .stationuuid)
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名电台"
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        urlResolved = (try? c.decode(String.self, forKey: .urlResolved)) ?? ""
        countrycode = (try? c.decode(String.self, forKey: .countrycode)) ?? ""
        state = (try? c.decode(String.self, forKey: .state)) ?? ""
        language = (try? c.decode(String.self, forKey: .language)) ?? ""
        tags = (try? c.decode(String.self, forKey: .tags)) ?? ""
        codec = (try? c.decode(String.self, forKey: .codec)) ?? ""
        bitrate = (try? c.decode(Int.self, forKey: .bitrate))
            ?? Int((try? c.decode(String.self, forKey: .bitrate)) ?? "") ?? 0
    }

    public var streamURLs: [URL] {
        var seen = Set<URL>()
        return [urlResolved, url].compactMap(Self.streamURL).filter { seen.insert($0).inserted }
    }

    public static func streamURL(_ value: String) -> URL? {
        guard let u = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = u.host, !host.isEmpty, u.user == nil, u.password == nil else { return nil }
        return u
    }

    public var location: String {
        let country = Locale(identifier: "zh_Hans").localizedString(forRegionCode: countrycode) ?? countrycode
        let parts = [state, country].filter { !$0.isEmpty }
        return parts.isEmpty ? "地点未知" : parts.joined(separator: " · ")
    }

    public var detail: String {
        let firstTag = tags.split(separator: ",").first.map(String.init) ?? ""
        return [location, firstTag].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public static func manual(name: String, address: String) -> Station? {
        guard let u = streamURL(address) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Station(id: "manual-" + UUID().uuidString, name: trimmed.isEmpty ? (u.host ?? "自定义电台") : trimmed,
                       url: u.absoluteString)
    }
}
