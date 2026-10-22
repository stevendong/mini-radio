import XCTest

final class MiniRadioUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MINIRADIO_UI_TEST_RUN"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["station-ui-jazz"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways
        add(image)
    }

    func testDiscoveryLayout() {
        XCTAssertTrue(app.buttons["discover-shuffle"].exists)
        XCTAssertTrue(app.buttons["compact-play"].exists)
        capture("Discovery")
        app.buttons["open-player"].tap()
        XCTAssertTrue(app.buttons["player-play"].waitForExistence(timeout: 5))
        capture("NowPlaying-empty")
    }

    func testSyncSettingsOfferPrivateKeySetup() {
        let more = app.buttons["更多选项"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        // SwiftUI Menu can reject XCTest's scroll-to-visible action on an already visible toolbar.
        more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["library-sync"].tap()
        XCTAssertTrue(app.textFields["sync-server"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["sync-key"].exists)
        let management = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "生成或管理同步密钥")).firstMatch
        XCTAssertTrue(management.waitForExistence(timeout: 5))
        capture("Sync-settings")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["station-ui-jazz"].waitForExistence(timeout: 5))
    }

    func testPlaybackPauseAndStopUseRealPlayer() {
        app.buttons["station-ui-jazz"].tap()
        app.buttons["open-player"].tap()
        let status = app.descendants(matching: .any)["player-status"].firstMatch
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "正在直播"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 25), .completed, "AVPlayer status: \(status.label)")
        capture("NowPlaying-local-audio")
        app.buttons["player-play"].tap()
        XCTAssertTrue(app.staticTexts["已暂停"].waitForExistence(timeout: 5))
        app.buttons["player-stop"].tap()
        XCTAssertTrue(app.staticTexts["准备收听"].waitForExistence(timeout: 5))
    }

    func testFavoritesPersistAcrossRelaunch() {
        app.buttons["favorite-ui-jazz"].tap()
        app.tabBars.buttons["收藏"].tap()
        XCTAssertTrue(app.buttons["station-ui-jazz"].waitForExistence(timeout: 5))
        capture("Favorites")
        app.terminate(); app.launch()
        app.tabBars.buttons["收藏"].tap()
        XCTAssertTrue(app.buttons["station-ui-jazz"].waitForExistence(timeout: 5))
    }

    func testManualValidationAndSleepTimer() {
        app.buttons["add-station"].tap()
        let address = app.textFields["manual-url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap(); address.typeText("invalid-address")
        app.buttons["manual-save"].tap()
        XCTAssertTrue(app.staticTexts["manual-error"].waitForExistence(timeout: 5))
        address.tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "invalid-address".count))
        address.typeText("http://127.0.0.1:18767/tone.wav")
        app.textFields["manual-name"].tap(); app.textFields["manual-name"].typeText("My Radio")
        app.buttons["manual-save"].tap()
        XCTAssertTrue(app.buttons["open-player"].waitForExistence(timeout: 5))
        app.buttons["open-player"].tap()
        XCTAssertTrue(app.staticTexts["My Radio"].waitForExistence(timeout: 5))
        app.buttons["sleep-timer"].tap()
        app.buttons["15 分钟后停止"].tap()
        capture("Sleep-timer")
        app.buttons["player-stop"].tap()
        XCTAssertTrue(app.staticTexts["准备收听"].waitForExistence(timeout: 5))
    }

    func testCarPlaySharesPlaybackWhenConnected() throws {
        let car = XCUIApplication(bundleIdentifier: "com.apple.CarPlayTemplateUIHost")
        let home = XCUIApplication(bundleIdentifier: "com.apple.CarPlayApp")
        guard home.state != .notRunning else {
            throw XCTSkip("Connect the CarPlay simulator display before running this test")
        }
        if home.icons["Mini Radio"].exists { home.icons["Mini Radio"].tap() }
        let discover = car.buttons["发现"]
        if discover.exists { discover.tap() }
        let jazz = car.buttons["Jazz Window"].firstMatch
        XCTAssertTrue(jazz.waitForExistence(timeout: 10), car.debugDescription + "\n" + home.debugDescription)
        jazz.tap()
        let name = car.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Jazz Window")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), car.debugDescription)
        app.buttons["open-player"].tap()
        let status = app.descendants(matching: .any)["player-status"].firstMatch
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "正在直播"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 25), .completed, "AVPlayer status: \(status.label)")
        capture("CarPlay-shared-phone-player")
        app.buttons["player-play"].tap()
        XCTAssertTrue(app.staticTexts["已暂停"].waitForExistence(timeout: 5))
        app.buttons["player-stop"].tap()
        XCTAssertTrue(app.staticTexts["准备收听"].waitForExistence(timeout: 5))
    }
}
