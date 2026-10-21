import XCTest
@testable import RadioCore

final class LibraryTests: XCTestCase {
    func station(_ index: Int) -> Station {
        Station(id: String(index), name: "Station \(index)", url: "https://example.com/\(index)")
    }

    func testAtomicPersistenceKeepsFavoritesLastStationAndHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(directory: folder)
        var library = try store.load()
        library.toggleFavorite(station(1))
        library.recordSuccessfulPlayback(station(2))
        try store.save(library)
        let restored = try store.load()
        XCTAssertEqual(restored.favorites, [station(1)])
        XCTAssertEqual(restored.recent, [station(2)])
        XCTAssertEqual(restored.lastStation, station(2))
        library.toggleFavorite(station(1))
        try store.save(library)
        XCTAssertTrue(try store.load().favorites.isEmpty)
    }

    func testCorruptLibraryIsReportedAndPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = LibraryStore(directory: folder)
        let original = Data("not-json".utf8)
        try original.write(to: store.libraryURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.libraryURL), original)
    }

    func testHistoryDeduplicatesAndCapsAtFifty() {
        var library = Library()
        for n in 0..<70 { library.recordSuccessfulPlayback(station(n)) }
        library.recordSuccessfulPlayback(station(55))
        XCTAssertEqual(library.recent.count, 50)
        XCTAssertEqual(library.recent.first, station(55))
        XCTAssertEqual(library.recent.filter { $0.id == "55" }.count, 1)
    }

    func testTolerantStationDecodeAndStreamValidation() throws {
        let json = #"{"stationuuid":"abc","name":"Radio","url":"http://radio.example/live","url_resolved":"https://radio.example/live","bitrate":"128","tags":null}"#
        let station = try JSONDecoder().decode(Station.self, from: Data(json.utf8))
        XCTAssertEqual(station.bitrate, 128)
        XCTAssertEqual(station.streamURLs.map(\.scheme), ["https", "http"])
        XCTAssertEqual(station.tags, "")
        XCTAssertEqual(station.location, "地点未知")
        for bad in ["file:///tmp/test", "ftp://example.com/radio", "https://user:pass@example.com", "hello", "javascript:alert(1)"] {
            XCTAssertNil(Station.streamURL(bad), bad)
        }
    }

    func testManualStationsAreNotDirectoryClicks() {
        let station = Station.manual(name: "  My Radio  ", address: " https://example.com/live ")!
        XCTAssertFalse(station.isDirectoryStation)
        XCTAssertEqual(station.name, "My Radio")
        XCTAssertEqual(station.streamURLs.count, 1)
        XCTAssertNil(Station.manual(name: "", address: "/etc/passwd"))
    }

    func testQueryEncodingDoesNotTurnSearchIntoExtraParameters() {
        let query = StationQuery(name: "Jazz & news=1", countrycode: "JP")
        var c = URLComponents(string: "https://example.com/search")!
        c.queryItems = query.items(offset: -10, limit: 900)
        XCTAssertEqual(c.queryItems?.first { $0.name == "name" }?.value, "Jazz & news=1")
        XCTAssertEqual(c.queryItems?.first { $0.name == "limit" }?.value, "100")
        XCTAssertEqual(c.queryItems?.first { $0.name == "offset" }?.value, "0")
        XCTAssertFalse(c.queryItems!.contains { $0.name == "news" })
    }
}
