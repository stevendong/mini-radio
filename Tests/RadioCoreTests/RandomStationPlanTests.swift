import XCTest
@testable import RadioCore

final class RandomStationPlanTests: XCTestCase {
    private let a = Station(id: "a", name: "A", url: "https://example.com/a")
    private let b = Station(id: "b", name: "B", url: "https://example.com/b")
    private let c = Station(id: "c", name: "C", url: "https://example.com/c")

    func testBothPowerAndWiFiAreRequiredAndUnknownDefaultsOff() {
        XCTAssertFalse(PreloadConditions().allowsPreloading)
        for power in [false, true] {
            for wifi in [false, true] {
                XCTAssertEqual(PreloadConditions(externalPower: power, wifi: wifi).allowsPreloading, power && wifi)
            }
        }
    }

    func testReservationExcludesCurrentAndRecentAndIsConsumedOnce() {
        var plan = RandomStationPlan()
        let source = [a, b, c]
        XCTAssertEqual(plan.prepare(in: source, currentID: a.id, recentIDs: [b.id], context: "discover"), c)
        XCTAssertEqual(plan.prepare(in: source, currentID: a.id, recentIDs: [b.id], context: "discover"), c)
        XCTAssertEqual(plan.next(in: source, currentID: a.id, recentIDs: [b.id], context: "discover"), c)
        XCTAssertNil(plan.reserved)
        XCTAssertEqual(plan.next(in: source, currentID: c.id, recentIDs: [a.id, c.id], context: "discover"), b)
    }

    func testRemovedOrChangedStationCannotUseOldReservation() {
        var plan = RandomStationPlan()
        _ = plan.prepare(in: [a, b], currentID: a.id, recentIDs: [], context: "favorites")
        XCTAssertEqual(plan.next(in: [a, c], currentID: a.id, recentIDs: [], context: "favorites"), c)
        _ = plan.prepare(in: [a, b], currentID: a.id, recentIDs: [], context: "favorites")
        var updated = b
        updated.url = "https://example.com/new-b"
        XCTAssertEqual(plan.next(in: [a, updated], currentID: a.id, recentIDs: [], context: "favorites"), updated)
    }

    func testSwitchingSourcesAndRepeatFallbackPreserveOriginalSelectionRules() {
        var plan = RandomStationPlan()
        _ = plan.prepare(in: [a, b], currentID: a.id, recentIDs: [], context: "discover")
        XCTAssertEqual(plan.next(in: [a, c], currentID: a.id, recentIDs: [], context: "favorites"), c)
        XCTAssertEqual(plan.next(in: [a, b], currentID: a.id, recentIDs: [a.id, b.id], context: "favorites"), b)
        XCTAssertNil(plan.prepare(in: [a], currentID: a.id, recentIDs: [], context: "favorites"))
        XCTAssertEqual(plan.next(in: [a], currentID: a.id, recentIDs: [], context: "favorites"), a)
        XCTAssertNil(plan.next(in: [], currentID: a.id, recentIDs: [], context: "favorites"))
    }

    func testCancellationDiscardsThePendingChoice() {
        var plan = RandomStationPlan()
        _ = plan.prepare(in: [a, b], currentID: a.id, recentIDs: [], context: "discover")
        plan.clear()
        XCTAssertNil(plan.reserved)
        XCTAssertEqual(plan.next(in: [a, c], currentID: a.id, recentIDs: [], context: "discover"), c)
    }
}
