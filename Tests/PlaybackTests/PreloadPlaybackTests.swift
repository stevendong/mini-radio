#if os(macOS)
import XCTest
import AVFoundation
import RadioCore
@testable import RoamRadio

final class PreloadPlaybackTests: XCTestCase {
    @MainActor
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(condition(), message)
        if !condition() { throw NSError(domain: "PlaybackTestTimeout", code: 1) }
    }

    @MainActor
    func testRealPlayerHandoffPowerWiFiCancellationAndHistory() async throws {
        guard let stream = ProcessInfo.processInfo.environment["MINIRADIO_PLAYBACK_TEST_URL"] else {
            throw XCTSkip("Set MINIRADIO_PLAYBACK_TEST_URL to the local audio fixture")
        }
        let environment = PreloadEnvironment(monitoring: false)
        let playback = PlaybackController(environment: environment)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { playback.shutdown(); try? FileManager.default.removeItem(at: folder) }
        let model = RadioModel(automaticallyLoad: false, storageDirectory: folder, playback: playback)
        let a = Station(id: "test-a", name: "A", url: stream)
        let b = Station(id: "test-b", name: "B", url: stream)
        model.stations = [a, b]
        model.select(a)
        try await waitFor("Primary starts", { playback.status == .playing && model.library.recent.first?.id == a.id })
        for conditions in [PreloadConditions(), PreloadConditions(externalPower: true), PreloadConditions(wifi: true)] {
            environment.update(conditions)
            playback.prepare(b)
            XCTAssertNil(playback.preparedPlayer)
            XCTAssertEqual(playback.status, .playing)
        }
        environment.update(PreloadConditions(externalPower: true, wifi: true))
        try await waitFor("Standby really plays muted", { playback.preparedPlayer?.timeControlStatus == .playing })
        let standby = try XCTUnwrap(playback.preparedPlayer)
        XCTAssertTrue(standby.isMuted)
        XCTAssertEqual(model.library.recent.map(\.id), [a.id], "Preparation must not record listening history")
        model.randomNext()
        XCTAssertTrue(playback.player === standby, "Promote the buffered player without reconnecting")
        XCTAssertFalse(standby.isMuted)
        try await waitFor("Promotion records successful playback", { model.library.recent.first?.id == b.id })

        try await waitFor("Prepare another station", { playback.preparedPlayer?.timeControlStatus == .playing })
        let unplugged = try XCTUnwrap(playback.preparedPlayer)
        environment.update(PreloadConditions(externalPower: false, wifi: true))
        XCTAssertNil(playback.preparedPlayer)
        XCTAssertNil(unplugged.currentItem)
        XCTAssertTrue(playback.player === standby)
        XCTAssertEqual(playback.status, .playing)

        environment.update(PreloadConditions(externalPower: true, wifi: true))
        try await waitFor("Plugging back in prepares again", { playback.preparedPlayer?.timeControlStatus == .playing })
        let lostWiFi = try XCTUnwrap(playback.preparedPlayer)
        environment.update(PreloadConditions(externalPower: true, wifi: false))
        XCTAssertNil(playback.preparedPlayer)
        XCTAssertNil(lostWiFi.currentItem)
        XCTAssertEqual(playback.status, .playing)

        environment.update(PreloadConditions(externalPower: true, wifi: true))
        try await waitFor("Ready before filter change", { playback.preparedPlayer?.timeControlStatus == .playing })
        let filtered = try XCTUnwrap(playback.preparedPlayer)
        model.query = StationQuery(name: "no matching station")
        XCTAssertNil(playback.preparedPlayer)
        XCTAssertNil(filtered.currentItem)
        model.query = StationQuery()
        try await waitFor("Clearing a filter can prepare the same candidate again", { playback.preparedPlayer?.timeControlStatus == .playing })

        let bad = Station(id: "test-bad", name: "Unavailable", url: stream.replacingOccurrences(of: "tone.wav", with: "missing.wav"))
        model.stations = [b, bad]
        try await waitFor("Failed preload is released", { playback.preparedPlayer == nil })
        XCTAssertEqual(playback.station?.id, b.id)
        XCTAssertEqual(playback.status, .playing)
        model.stations = [a, b]
        try await waitFor("Ready before pause", { playback.preparedPlayer?.timeControlStatus == .playing })
        let paused = try XCTUnwrap(playback.preparedPlayer)
        playback.pause()
        XCTAssertNil(playback.preparedPlayer)
        XCTAssertNil(paused.currentItem)
        XCTAssertNil(playback.player)
        XCTAssertEqual(playback.status, .paused)
        playback.resume()
        try await waitFor("Resume prepares again", { playback.preparedPlayer?.timeControlStatus == .playing })
        model.randomNext()
        model.randomNext()
        try await waitFor("Rapid skips keep the last selection", { playback.station?.id == b.id && playback.status == .playing })
        playback.stop()
        XCTAssertNil(playback.player)
        XCTAssertNil(playback.preparedPlayer)
        XCTAssertEqual(playback.status, .idle)
    }
}
#endif
