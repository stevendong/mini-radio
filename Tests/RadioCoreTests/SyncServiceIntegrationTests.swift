import XCTest
@testable import RadioCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SyncServiceIntegrationTests: XCTestCase {
    func testRealServiceTwoDeviceMergeRevocationAndIsolation() async throws {
        guard let address = ProcessInfo.processInfo.environment["MINIRADIO_SYNC_TEST_URL"], let url = URL(string: address) else {
            throw XCTSkip("Set MINIRADIO_SYNC_TEST_URL for a real two-device service test")
        }
        guard let invitationFile = ProcessInfo.processInfo.environment["MINIRADIO_SYNC_TEST_INVITES_FILE"],
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: invitationFile))) as? [String: Any],
              let invitations = object["invitations"] as? [[String: Any]], invitations.count >= 2,
              let firstInvite = invitations[0]["code"] as? String, let secondInvite = invitations[1]["code"] as? String else {
            throw SyncServiceError.unavailable
        }
        let session = URLSession(configuration: .ephemeral)
        func create(invitation: String) async throws -> String {
            var request = URLRequest(url: url.appendingPathComponent("v1/keys"))
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: ["invitation": invitation])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 201,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: String], let key = object["key"] else {
                throw SyncServiceError.unavailable
            }
            return key
        }
        func revoke(_ key: String) async throws {
            var request = URLRequest(url: url.appendingPathComponent("v1/library"))
            request.httpMethod = "DELETE"; request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
        let key = try await create(invitation: firstInvite), otherKey = try await create(invitation: secondInvite)
        let phone = LibrarySyncClient(server: url, key: key), mac = LibrarySyncClient(server: url, key: key)
        let other = LibrarySyncClient(server: url, key: otherKey)
        do {
            let jazz = Station(id: "integration-jazz", name: "Integration fixture", url: "https://example.com/jazz")
            let news = Station(id: "integration-news", name: "Integration fixture", url: "https://example.com/news")
            var a = Library(), b = Library()
            a.setFavorite(jazz, enabled: true, at: Date(timeIntervalSince1970: 100))
            b.merge(try await phone.synchronize(LibrarySyncDocument(library: a)))
            XCTAssertEqual(b.favorites, [jazz])
            a.setFavorite(jazz, enabled: false, at: Date(timeIntervalSince1970: 200))
            b.setFavorite(news, enabled: true, at: Date(timeIntervalSince1970: 300))
            b.recordSuccessfulPlayback(news, at: Date(timeIntervalSince1970: 400))
            _ = try await phone.synchronize(LibrarySyncDocument(library: a))
            a.merge(try await mac.synchronize(LibrarySyncDocument(library: b)))
            XCTAssertEqual(a.favorites, [news]); XCTAssertEqual(a.recent, [news])
            b.merge(try await mac.synchronize(LibrarySyncDocument(library: b)))
            XCTAssertEqual(a.syncState, b.syncState)
            let isolated = try await other.synchronize(LibrarySyncDocument(library: Library()))
            XCTAssertTrue(isolated.state.favorites.isEmpty)
        } catch {
            try? await revoke(key); try? await revoke(otherKey)
            throw error
        }
        try await revoke(key); try await revoke(otherKey)
        do { _ = try await phone.synchronize(LibrarySyncDocument(library: Library())); XCTFail("Revoked key must fail") }
        catch SyncServiceError.unauthorized {}
    }
}
