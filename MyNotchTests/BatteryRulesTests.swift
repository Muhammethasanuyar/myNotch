import XCTest
@testable import MyNotch

final class BatteryRulesTests: XCTestCase {
    private let thresholds = BatteryThresholds(low: 0.20, critical: 0.10)

    private func source(charging: Bool, ac: Bool, capacity: Int, toFull: Int? = nil, toEmpty: Int? = nil, type: String = "InternalBattery") -> [String: Any] {
        var dictionary: [String: Any] = [
            "Type": type, "Is Present": true, "Is Charging": charging,
            "Current Capacity": capacity, "Max Capacity": 100,
            "Power Source State": ac ? "AC Power" : "Battery Power"
        ]
        if let toFull { dictionary["Time to Full Charge"] = toFull }
        if let toEmpty { dictionary["Time to Empty"] = toEmpty }
        return dictionary
    }

    func testParsesAChargingBattery() {
        let snapshot = BatteryRules.parse(powerSource: source(charging: true, ac: true, capacity: 62, toFull: 80), lowPowerMode: false)
        XCTAssertEqual(snapshot, BatterySnapshot(isCharging: true, isPluggedIn: true, percentage: 62, timeToFull: 80 * 60, timeToEmpty: nil, isLowPowerMode: false))
    }

    func testParsesABatteryInUseAndTreatsMinusOneAsUnknown() {
        let estimating = BatteryRules.parse(powerSource: source(charging: false, ac: false, capacity: 40, toEmpty: -1), lowPowerMode: true)
        XCTAssertEqual(estimating?.timeToEmpty, nil, "-1 means macOS is still estimating")
        XCTAssertEqual(estimating?.isLowPowerMode, true)
        let known = BatteryRules.parse(powerSource: source(charging: false, ac: false, capacity: 40, toEmpty: 250), lowPowerMode: false)
        XCTAssertEqual(known?.timeToEmpty, 250 * 60)
        XCTAssertFalse(known?.isPluggedIn ?? true)
    }

    func testMissingKeysAndOtherSourcesAreTolerated() {
        XCTAssertNil(BatteryRules.parse(powerSource: source(charging: false, ac: true, capacity: 100, type: "UPS"), lowPowerMode: false), "a UPS is not the internal battery")
        XCTAssertNil(BatteryRules.parse(powerSource: [:], lowPowerMode: false), "a desktop has no internal battery")
        let sparse = BatteryRules.parse(powerSource: ["Type": "InternalBattery", "Current Capacity": 55], lowPowerMode: false)
        XCTAssertEqual(sparse?.percentage, 55)
        XCTAssertEqual(sparse?.isCharging, false)
    }

    func testScalesCapacityWhenMaxIsNotAHundred() {
        var dictionary = source(charging: false, ac: false, capacity: 4000)
        dictionary["Max Capacity"] = 5000
        XCTAssertEqual(BatteryRules.parse(powerSource: dictionary, lowPowerMode: false)?.percentage, 80)
    }

    func testActivityOnlyWhileChargingOrLow() {
        XCTAssertEqual(BatteryRules.activity(nil, thresholds: thresholds), .idle)
        XCTAssertEqual(BatteryRules.activity(snapshot(percent: 62, charging: true, ac: true), thresholds: thresholds), .live)
        XCTAssertEqual(BatteryRules.activity(snapshot(percent: 100, charging: false, ac: true), thresholds: thresholds), .idle, "full on mains has nothing to say")
        XCTAssertEqual(BatteryRules.activity(snapshot(percent: 62, charging: false, ac: false), thresholds: thresholds), .idle)
        XCTAssertEqual(BatteryRules.activity(snapshot(percent: 18, charging: false, ac: false), thresholds: thresholds), .live)
    }

    func testLevelsFollowTheThresholdsOnlyOnBattery() {
        XCTAssertEqual(BatteryRules.level(snapshot(percent: 50, charging: false, ac: false), thresholds: thresholds), 0)
        XCTAssertEqual(BatteryRules.level(snapshot(percent: 20, charging: false, ac: false), thresholds: thresholds), 1)
        XCTAssertEqual(BatteryRules.level(snapshot(percent: 9, charging: false, ac: false), thresholds: thresholds), 2)
        XCTAssertEqual(BatteryRules.level(snapshot(percent: 9, charging: true, ac: true), thresholds: thresholds), 0, "charging is never alarming")
    }

    func testPlugEventsFireOnTransitionsOnly() {
        let onBattery = snapshot(percent: 60, charging: false, ac: false)
        let charging = snapshot(percent: 60, charging: true, ac: true)
        XCTAssertEqual(BatteryRules.alerts(previous: nil, current: charging, thresholds: thresholds, memory: .init()).alerts, [], "the first reading announces nothing")
        XCTAssertEqual(BatteryRules.alerts(previous: onBattery, current: charging, thresholds: thresholds, memory: .init()).alerts, [.pluggedIn])
        XCTAssertEqual(BatteryRules.alerts(previous: charging, current: onBattery, thresholds: thresholds, memory: .init()).alerts, [.unplugged])
        XCTAssertEqual(BatteryRules.alerts(previous: charging, current: charging, thresholds: thresholds, memory: .init()).alerts, [])
    }

    func testLowAndCriticalAnnounceOncePerCrossing() {
        var memory = BatteryAlertMemory()
        var result = BatteryRules.alerts(previous: snapshot(percent: 21, charging: false, ac: false), current: snapshot(percent: 20, charging: false, ac: false), thresholds: thresholds, memory: memory)
        XCTAssertEqual(result.alerts, [.low])
        memory = result.memory
        result = BatteryRules.alerts(previous: snapshot(percent: 20, charging: false, ac: false), current: snapshot(percent: 19, charging: false, ac: false), thresholds: thresholds, memory: memory)
        XCTAssertEqual(result.alerts, [], "still low, already said")
        memory = result.memory
        result = BatteryRules.alerts(previous: snapshot(percent: 11, charging: false, ac: false), current: snapshot(percent: 10, charging: false, ac: false), thresholds: thresholds, memory: memory)
        XCTAssertEqual(result.alerts, [.critical])
        memory = result.memory
        // Plugging in re-arms both.
        result = BatteryRules.alerts(previous: snapshot(percent: 10, charging: false, ac: false), current: snapshot(percent: 10, charging: true, ac: true), thresholds: thresholds, memory: memory)
        XCTAssertEqual(result.alerts, [.pluggedIn])
        XCTAssertFalse(result.memory.announcedLow)
        XCTAssertFalse(result.memory.announcedCritical)
    }

    func testClimbingWellClearReArmsTheLowAlert() {
        let memory = BatteryAlertMemory(announcedLow: true, announcedCritical: false, announcedFull: false)
        let stillClose = BatteryRules.alerts(previous: snapshot(percent: 20, charging: false, ac: false), current: snapshot(percent: 23, charging: false, ac: false), thresholds: thresholds, memory: memory)
        XCTAssertTrue(stillClose.memory.announcedLow, "within five points the alert stays spent")
        let clear = BatteryRules.alerts(previous: snapshot(percent: 23, charging: false, ac: false), current: snapshot(percent: 26, charging: false, ac: false), thresholds: thresholds, memory: memory)
        XCTAssertFalse(clear.memory.announcedLow)
    }

    func testFullAnnouncesOnlyWhenTheChargeFinishesWhileWatched() {
        let charging = snapshot(percent: 99, charging: true, ac: true)
        let full = snapshot(percent: 100, charging: false, ac: true)
        let finished = BatteryRules.alerts(previous: charging, current: full, thresholds: thresholds, memory: .init())
        XCTAssertEqual(finished.alerts, [.full])
        XCTAssertTrue(finished.memory.announcedFull)
        let again = BatteryRules.alerts(previous: full, current: full, thresholds: thresholds, memory: finished.memory)
        XCTAssertEqual(again.alerts, [])
        let pluggedInFull = BatteryRules.alerts(previous: snapshot(percent: 100, charging: false, ac: false), current: full, thresholds: thresholds, memory: .init())
        XCTAssertEqual(pluggedInFull.alerts, [.pluggedIn], "plugging in a full battery is not a charge that finished")
    }

    func testLowPowerModeChangesAreAnnounced() {
        var lowPower = snapshot(percent: 50, charging: false, ac: false)
        lowPower.isLowPowerMode = true
        XCTAssertEqual(BatteryRules.alerts(previous: snapshot(percent: 50, charging: false, ac: false), current: lowPower, thresholds: thresholds, memory: .init()).alerts, [.lowPowerModeOn])
    }

    func testTextInTheSourceLanguage() {
        let bundle = Bundle(for: BatteryRulesTests.self)
        let english = Locale(identifier: "en_US")
        let charging = snapshot(percent: 62, charging: true, ac: true, toFull: 80 * 60)
        XCTAssertEqual(BatteryRules.formatTime(80 * 60, locale: english), "1h 20m")
        XCTAssertEqual(BatteryRules.statusTitle(charging, bundle: bundle), "Charging")
        XCTAssertEqual(BatteryRules.estimate(charging, bundle: bundle, locale: english), "1h 20m to full")
        XCTAssertEqual(BatteryRules.estimate(snapshot(percent: 40, charging: false, ac: false, toEmpty: 250 * 60), bundle: bundle, locale: english), "4h 10m left")
        XCTAssertNil(BatteryRules.estimate(snapshot(percent: 40, charging: false, ac: false), bundle: bundle, locale: english))
        let event = BatteryRules.event(for: .critical, snapshot: snapshot(percent: 9, charging: false, ac: false), moduleID: "battery", bundle: bundle)
        XCTAssertEqual(event.title, "Battery critical")
        XCTAssertEqual(event.detail, "9% — plug in soon")
        XCTAssertEqual(event.duration, 4)
    }

    private func snapshot(percent: Int, charging: Bool, ac: Bool, toFull: TimeInterval? = nil, toEmpty: TimeInterval? = nil) -> BatterySnapshot {
        BatterySnapshot(isCharging: charging, isPluggedIn: ac, percentage: percent, timeToFull: toFull, timeToEmpty: toEmpty, isLowPowerMode: false)
    }
}
