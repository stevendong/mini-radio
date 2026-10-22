import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RadioCore

private final class SyncProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> (Int, Data))?

    static func respond(_ value: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        handler = value
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
        do {
            let (status, data) = try XCTUnwrap(handler)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class LibrarySyncClientTests: XCTestCase {
    private func client() -> LibrarySyncClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncProtocol.self]
        return LibrarySyncClient(server: URL(string: "https://sync.example.com/api")!, key: "test-key",
                                 session: URLSession(configuration: configuration))
    }

    private func station(_ id: String) -> Station {
        Station(id: id, name: id, url: "https://example.com/" + id)
    }

    private func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { break }
            if count < 0 { throw URLError(.cannotDecodeRawData) }
            data.append(buffer, count: count)
        }
        return data
    }

    func testAuthenticatedRequestAndAtomicServerMerge() async throws {
        var local = Library(), remote = Library()
        local.setFavorite(station("phone"), enabled: true)
        remote.setFavorite(station("mac"), enabled: true)
        let remoteDocument = LibrarySyncDocument(library: remote)
        SyncProtocol.respond { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/library/sync")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            var server = Library()
            server.merge(remoteDocument)
            server.merge(try LibrarySyncDocument.decode(self.body(request)))
            return (200, try LibrarySyncDocument(library: server).encoded())
        }
        local.merge(try await client().synchronize(LibrarySyncDocument(library: local)))
        XCTAssertEqual(Set(local.favorites.map(\.id)), ["phone", "mac"])
    }

    func testServerMustRetainClientChangesBeforeReportingSuccess() async throws {
        var local = Library()
        local.toggleFavorite(station("local"))
        SyncProtocol.respond { _ in (200, try LibrarySyncDocument(library: Library()).encoded()) }
        do {
            _ = try await client().synchronize(LibrarySyncDocument(library: local))
            XCTFail("An incomplete merge must not be reported as synchronized")
        } catch let error as SyncServiceError {
            guard case .incompleteMerge = error else { return XCTFail("Unexpected service error") }
        }
        XCTAssertEqual(local.favorites.map(\.id), ["local"])
    }

    func testAuthenticationDeploymentAndServiceErrorsPreserveLocalData() async throws {
        var local = Library()
        local.toggleFavorite(station("local"))
        for status in [401, 403, 404, 413, 429, 500, 302] {
            SyncProtocol.respond { _ in (status, Data("private server response".utf8)) }
            do {
                _ = try await client().synchronize(LibrarySyncDocument(library: local))
                XCTFail("HTTP \(status) must fail")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("private server response"))
                XCTAssertFalse(error.localizedDescription.contains("test-key"))
            }
            XCTAssertEqual(local.favorites.map(\.id), ["local"])
        }
    }

    func testMalformedSuccessResponseFailsWithoutReplacingLibrary() async throws {
        SyncProtocol.respond { _ in (200, Data("not a sync document".utf8)) }
        do {
            _ = try await client().synchronize(LibrarySyncDocument(library: Library()))
            XCTFail("Malformed data must fail")
        } catch let error as SyncServiceError {
            guard case .invalidResponse = error else { return XCTFail("Unexpected service error") }
        }
    }

    func testServerAddressRequiresHTTPSAndKeepsCredentialsOutOfURL() {
        XCTAssertNotNil(LibrarySyncClient.serverURL(" https://sync.example.com/api "))
        for address in ["http://example.com", "file:///tmp/sync", "https://user:pass@example.com", "https://example.com?key=x", "https://example.com#key", "invalid"] {
            XCTAssertNil(LibrarySyncClient.serverURL(address))
        }
    }
}
