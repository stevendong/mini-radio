import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RadioCore

final class StubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var callback: ((URLRequest) throws -> (Int, Data))?
    static func setHandler(_ handler: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }; callback = handler
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.callback; Self.lock.unlock()
        do {
            let (code, data) = try handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class DirectoryTests: XCTestCase {
    func client() -> RadioDirectory {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return RadioDirectory(session: URLSession(configuration: config))
    }

    func testDiscoveredServerSearchAndRawPagination() async throws {
        StubProtocol.setHandler { request in
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")!.contains("MiniRadio"))
            if request.url!.path == "/json/servers" {
                return (200, Data(#"[{"name":"test.api.radio-browser.info"},{"name":"evil.example"}]"#.utf8))
            }
            XCTAssertEqual(request.url!.host, "test.api.radio-browser.info")
            XCTAssertEqual(request.url!.path, "/json/stations/search")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(items.first { $0.name == "name" }?.value, "Jazz & Soul")
            return (200, Data(#"[{"stationuuid":"a","url":"https://example.com/a"},{"stationuuid":"a","url":"https://example.com/a"},{"stationuuid":"b","url":"file:///etc/passwd"}]"#.utf8))
        }
        let page = try await client().search(StationQuery(name: "Jazz & Soul"), offset: 6, limit: 3)
        XCTAssertEqual(page.stations.map(\.id), ["a"])
        XCTAssertEqual(page.nextOffset, 9)
        XCTAssertTrue(page.hasMore, "Filtering invalid records must not end pagination early")
    }

    func testDiscoveryFailureStillTriesDNSPoolAndFallback() async throws {
        StubProtocol.setHandler { request in
            if request.url!.host == "de1.api.radio-browser.info" {
                return (200, Data(#"[{"stationuuid":"ok","url":"https://example.com/live"}]"#.utf8))
            }
            return (503, Data())
        }
        let page = try await client().search(StationQuery())
        XCTAssertEqual(page.stations.first?.id, "ok")
        XCTAssertFalse(page.hasMore)
    }

    func testServerNameValidation() {
        for bad in ["evil.example", "x.api.radio-browser.info.evil.com", "x.api.radio-browser.info/path", "../x.api.radio-browser.info", "a..api.radio-browser.info"] {
            XCTAssertNil(RadioDirectory.validatedServer(bad))
        }
        XCTAssertEqual(RadioDirectory.validatedServer("DE1.api.radio-browser.info")?.host, "de1.api.radio-browser.info")
    }

    func testRealDirectoryWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MINIRADIO_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set MINIRADIO_LIVE_TEST=1 for a live directory request")
        }
        let page = try await RadioDirectory().search(StationQuery(countrycode: "CN"), limit: 5)
        XCTAssertFalse(page.stations.isEmpty)
        XCTAssertTrue(page.stations.allSatisfy { !$0.streamURLs.isEmpty })
        print("LIVE_DIRECTORY: \(page.stations.map { $0.name + " [" + $0.codec + "]" }.joined(separator: ", "))")
    }
}
