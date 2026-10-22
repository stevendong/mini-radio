import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DirectoryError: LocalizedError {
    case unavailable
    public var errorDescription: String? { "暂时无法连接电台目录。可以播放收藏或手动添加直播地址。" }
}

public struct StationPage: Sendable {
    public let stations: [Station]
    public let nextOffset: Int
    public let hasMore: Bool
}

public actor RadioDirectory {
    #if os(iOS)
    private static let userAgent = "MiniRadio/0.1.0 (iOS; github.com/stevendong/mini-radio)"
    #elseif os(macOS)
    private static let userAgent = "MiniRadio/0.1.0 (macOS; github.com/stevendong/mini-radio)"
    #else
    private static let userAgent = "MiniRadio/0.1.0 (github.com/stevendong/mini-radio)"
    #endif
    private let session: URLSession
    private var servers: [URL] = []
    private var discoveredAt = Date.distantPast
    private let discoveryURL = URL(string: "https://all.api.radio-browser.info/json/servers")!

    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 12
            config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: config)
        }
    }

    public static func validatedServer(_ name: String) -> URL? {
        let host = name.lowercased()
        guard host.hasSuffix(".api.radio-browser.info"),
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }),
              !host.contains("..") else { return nil }
        return URL(string: "https://" + host)
    }

    private func discover() async {
        guard servers.isEmpty || Date().timeIntervalSince(discoveredAt) > 3600 else { return }
        struct Server: Decodable { let name: String }
        if let data = try? await request(discoveryURL),
           let found = try? JSONDecoder().decode([Server].self, from: data) {
            let valid = Array(Set(found.compactMap { Self.validatedServer($0.name) })).shuffled()
            if !valid.isEmpty { servers = valid; discoveredAt = Date(); return }
        }
        // DNS pool first; the last-resort seed is not the only directory dependency.
        if servers.isEmpty { servers = [URL(string: "https://all.api.radio-browser.info")!,
                                        URL(string: "https://de1.api.radio-browser.info")!] }
    }

    private func request(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 8_000_000 else { throw DirectoryError.unavailable }
        return data
    }

    public func search(_ query: StationQuery, offset: Int = 0, limit: Int = 60) async throws -> StationPage {
        await discover()
        for server in servers {
            try Task.checkCancellation()
            var components = URLComponents(url: server.appendingPathComponent("json/stations/search"), resolvingAgainstBaseURL: false)!
            components.queryItems = query.items(offset: offset, limit: limit)
            do {
                let data = try await request(components.url!)
                let stations = try JSONDecoder().decode([Station].self, from: data)
                var seen = Set<String>()
                return StationPage(stations: stations.filter { !$0.streamURLs.isEmpty && seen.insert($0.id).inserted },
                                   nextOffset: max(0, offset) + stations.count,
                                   hasMore: stations.count >= max(1, min(100, limit)))
            } catch {
                if Task.isCancelled { throw CancellationError() }
            }
        }
        discoveredAt = .distantPast
        throw DirectoryError.unavailable
    }

    public func recordSelection(_ station: Station) async {
        guard station.isDirectoryStation else { return }
        await discover()
        guard let server = servers.first else { return }
        _ = try? await request(server.appendingPathComponent("json/url/" + station.id))
    }
}
