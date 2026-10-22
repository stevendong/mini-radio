import XCTest
@testable import RadioCore

final class LibrarySyncTests: XCTestCase {
    private func station(_ index: Int) -> Station {
        Station(id: String(index), name: "Radio \(index)", url: "https://example.com/\(index)")
    }

    private func time(_ value: Double) -> Date { Date(timeIntervalSince1970: value) }

    func testExistingLibraryLoadsAndMigratesWithoutLosingOrder() throws {
        var original = Library()
        original.favorites = [station(3), station(1)]
        original.recent = [station(2), station(1)]
        original.lastStation = station(2)
        let data = try JSONEncoder().encode(original)
        var migrated = try JSONDecoder().decode(Library.self, from: data)
        XCTAssertNil(migrated.syncState)
        migrated.merge(LibrarySyncDocument(library: migrated))
        XCTAssertEqual(migrated.favorites, original.favorites)
        XCTAssertEqual(migrated.recent, original.recent)
        XCTAssertEqual(migrated.lastStation, original.lastStation)
    }

    func testOfflineAdditionsFromBothDevicesArePreserved() {
        var phone = Library(), mac = Library()
        phone.setFavorite(station(1), enabled: true, at: time(100))
        mac.setFavorite(station(2), enabled: true, at: time(200))
        let snapshot = LibrarySyncDocument(library: phone)
        phone.merge(LibrarySyncDocument(library: mac))
        mac.merge(snapshot)
        XCTAssertEqual(phone.favorites, [station(2), station(1)])
        XCTAssertEqual(phone.syncState, mac.syncState)
    }

    func testRemovingFavoriteSurvivesStaleAndLegacyDevices() {
        var phone = Library()
        phone.setFavorite(station(1), enabled: true, at: time(100))
        let stale = LibrarySyncDocument(library: phone)
        phone.toggleFavorite(station(1), at: time(200))
        phone.merge(stale)
        XCTAssertTrue(phone.favorites.isEmpty)
        var legacy = Library()
        legacy.favorites = [station(1)]
        phone.merge(LibrarySyncDocument(library: legacy))
        XCTAssertTrue(phone.favorites.isEmpty)
        legacy.merge(LibrarySyncDocument(library: phone))
        XCTAssertTrue(legacy.favorites.isEmpty)
        legacy.setFavorite(station(1), enabled: true, at: time(300))
        phone.merge(LibrarySyncDocument(library: legacy))
        XCTAssertEqual(phone.favorites, [station(1)])
    }

    func testSimultaneousConflictsConvergeAndRemovalWinsTies() {
        var phone = Library(), mac = Library()
        phone.setFavorite(station(1), enabled: true, at: time(100))
        mac.setFavorite(station(1), enabled: false, at: time(100))
        let snapshot = LibrarySyncDocument(library: phone)
        phone.merge(LibrarySyncDocument(library: mac))
        mac.merge(snapshot)
        XCTAssertTrue(phone.favorites.isEmpty)
        XCTAssertEqual(phone.syncState, mac.syncState)
        let repeated = phone.syncState
        phone.merge(LibrarySyncDocument(library: mac))
        XCTAssertEqual(phone.syncState, repeated)
    }

    func testListeningHistoryDeduplicatesKeepsLatestAndCapsAtFifty() {
        var phone = Library(), mac = Library()
        for index in 0..<40 { phone.recordSuccessfulPlayback(station(index), at: time(Double(index))) }
        for index in 20..<70 { mac.recordSuccessfulPlayback(station(index), at: time(Double(index))) }
        phone.recordSuccessfulPlayback(station(25), at: time(100))
        let snapshot = LibrarySyncDocument(library: phone)
        phone.merge(LibrarySyncDocument(library: mac))
        mac.merge(snapshot)
        XCTAssertEqual(phone.recent.count, 50)
        XCTAssertEqual(phone.recent.first, station(25))
        XCTAssertEqual(phone.lastStation, station(25))
        XCTAssertEqual(Set(phone.recent.map(\.id)).count, 50)
        XCTAssertEqual(phone.syncState, mac.syncState)
    }

    func testSyncDocumentRoundTripsAndRejectsUnsupportedOrInvalidData() throws {
        var library = Library()
        library.toggleFavorite(station(1), at: time(100))
        library.recordSuccessfulPlayback(station(2), at: time(200))
        let encoded = try LibrarySyncDocument(library: library).encoded()
        let decoded = try LibrarySyncDocument.decode(encoded)
        var restored = Library()
        restored.merge(decoded)
        XCTAssertEqual(restored.syncState, library.syncState)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 99
        XCTAssertThrowsError(try LibrarySyncDocument.decode(JSONSerialization.data(withJSONObject: object)))
        var invalid = Library()
        invalid.setFavorite(Station(id: "bad", name: "Bad", url: "file:///tmp/radio"), enabled: true)
        XCTAssertThrowsError(try LibrarySyncDocument.decode(LibrarySyncDocument(library: invalid).encoded()))
        XCTAssertThrowsError(try LibrarySyncDocument.decode(Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1)))
        XCTAssertThrowsError(try LibrarySyncDocument.decode(Data("invalid".utf8)))
    }
}
