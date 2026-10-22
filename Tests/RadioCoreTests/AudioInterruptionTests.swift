import XCTest
@testable import RadioCore

final class AudioInterruptionTests: XCTestCase {
    func testOnlyPreviouslyActivePlaybackMayResume() {
        var state = AudioInterruptionState()
        state.begin(wasPlaying: false)
        XCTAssertFalse(state.end(systemAllowsResume: true))
        state.begin(wasPlaying: true)
        XCTAssertTrue(state.end(systemAllowsResume: true))
        XCTAssertFalse(state.end(systemAllowsResume: true))
    }

    func testPauseStopAndRouteDisconnectCancelAutomaticResume() {
        var state = AudioInterruptionState()
        state.begin(wasPlaying: true)
        state.userChangedPlayback()
        XCTAssertFalse(state.end(systemAllowsResume: true))
    }

    func testSystemCanForbidResume() {
        var state = AudioInterruptionState()
        state.begin(wasPlaying: true)
        XCTAssertFalse(state.end(systemAllowsResume: false))
    }

    func testDuplicateBeginDoesNotEraseOriginalPlaybackIntent() {
        var state = AudioInterruptionState()
        state.begin(wasPlaying: true)
        state.begin(wasPlaying: false)
        XCTAssertTrue(state.end(systemAllowsResume: true))
    }
}
