import CoreAudio
import XCTest
@testable import MyNotch

final class AudioDeviceRulesTests: XCTestCase {
    private func device(_ name: String, transport: UInt32, uid: String? = nil) -> AudioOutputInfo {
        AudioOutputInfo(id: 1, uid: uid, name: name, transport: transport)
    }

    func testTransportClassification() {
        XCTAssertFalse(AudioDeviceRules.isExternal(device("MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn)))
        XCTAssertTrue(AudioDeviceRules.isExternal(device("LG TV", transport: kAudioDeviceTransportTypeHDMI)))
        XCTAssertTrue(AudioDeviceRules.isBluetooth(device("AirPods", transport: kAudioDeviceTransportTypeBluetooth)))
        XCTAssertTrue(AudioDeviceRules.isBluetooth(device("Buds", transport: kAudioDeviceTransportTypeBluetoothLE)))
        XCTAssertFalse(AudioDeviceRules.isBluetooth(device("Dock", transport: kAudioDeviceTransportTypeUSB)))
    }

    func testGlyphsFollowTheNameThenTheTransport() {
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("Emre's AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth)), "airpods.pro")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("AirPods Max", transport: kAudioDeviceTransportTypeBluetooth)), "airpodsmax")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("Emre's AirPods", transport: kAudioDeviceTransportTypeBluetooth)), "airpods")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("WH-1000XM5", transport: kAudioDeviceTransportTypeBluetooth)), "headphones")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("22W_LCD_TV", transport: kAudioDeviceTransportTypeHDMI)), "tv.fill")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn)), "speaker.wave.2.fill")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("Some Bluetooth Thing", transport: kAudioDeviceTransportTypeBluetooth)), "headphones", "transport decides when the name says nothing")
        XCTAssertEqual(AudioDeviceRules.symbolName(for: device("Audio Interface", transport: kAudioDeviceTransportTypeUSB)), "hifispeaker.fill")
    }

    func testOnlyRealSwitchesAreAnnounced() {
        let speakers = device("Speakers", transport: kAudioDeviceTransportTypeBuiltIn)
        let airpods = device("AirPods", transport: kAudioDeviceTransportTypeBluetooth)
        let tv = device("TV", transport: kAudioDeviceTransportTypeHDMI)
        XCTAssertNil(AudioDeviceRules.shouldAnnounce(previous: nil, current: airpods, connectPopups: true, disconnectPopups: true), "the first reading is not a connection")
        XCTAssertEqual(AudioDeviceRules.shouldAnnounce(previous: speakers, current: airpods, connectPopups: true, disconnectPopups: true), .connected)
        XCTAssertEqual(AudioDeviceRules.shouldAnnounce(previous: airpods, current: tv, connectPopups: true, disconnectPopups: true), .connected, "switching between externals announces the new one")
        XCTAssertEqual(AudioDeviceRules.shouldAnnounce(previous: airpods, current: speakers, connectPopups: true, disconnectPopups: true), .disconnected)
        XCTAssertNil(AudioDeviceRules.shouldAnnounce(previous: airpods, current: speakers, connectPopups: true, disconnectPopups: false), "disconnect popups are off by default")
        XCTAssertNil(AudioDeviceRules.shouldAnnounce(previous: speakers, current: airpods, connectPopups: false, disconnectPopups: true))
        XCTAssertNil(AudioDeviceRules.shouldAnnounce(previous: speakers, current: speakers, connectPopups: true, disconnectPopups: true))
        XCTAssertNil(AudioDeviceRules.shouldAnnounce(previous: speakers, current: device("Speakers", transport: kAudioDeviceTransportTypeBuiltIn, uid: "x"), connectPopups: true, disconnectPopups: true), "built-in to built-in is never news")
        XCTAssertEqual(AudioDeviceRules.shouldAnnounce(previous: airpods, current: nil, connectPopups: true, disconnectPopups: true), .disconnected, "no device at all counts as the external one leaving")
    }

    func testRegistryParsing() {
        let full = AudioDeviceRules.parseRegistry(["Product": "Emre's AirPods Pro", "DeviceAddress": "aa-bb-cc-dd-ee-ff", "BatteryPercentLeft": 84, "BatteryPercentRight": 82, "BatteryPercentCase": 61, "Transport": "Bluetooth"])
        XCTAssertEqual(full?.battery, AirPodsBattery(left: 84, right: 82, caseLevel: 61))
        XCTAssertEqual(full?.address, "aa-bb-cc-dd-ee-ff")
        XCTAssertFalse(full?.isBuiltIn ?? true)
        let empty = AudioDeviceRules.parseRegistry([:])
        XCTAssertEqual(empty?.battery.isEmpty, true)
        XCTAssertFalse(empty?.isBuiltIn ?? true)
        let bad = AudioDeviceRules.parseRegistry(["BatteryPercentLeft": 250, "BatteryPercentRight": -1, "BatteryPercentCase": "61"])
        XCTAssertEqual(bad?.battery.isEmpty, true, "out-of-range and wrong-typed values read as absent")
        let keyboard = AudioDeviceRules.parseRegistry(["Product": "Apple Internal Keyboard / Trackpad", "Built-In": true, "Transport": "FIFO"])
        XCTAssertTrue(keyboard?.isBuiltIn ?? false)
        XCTAssertTrue(AudioDeviceRules.parseRegistry(["Transport": "FIFO"])?.isBuiltIn ?? false, "FIFO without the flag still means the built-in top case")
    }

    func testBatteryMatchingStrategies() {
        let pro = AirPodsRegistryEntry(product: "Emre's AirPods Pro", address: "aa-bb-cc-dd-ee-ff", isBuiltIn: false, battery: AirPodsBattery(left: 84, right: 82, caseLevel: 61))
        let max = AirPodsRegistryEntry(product: "AirPods Max", address: "11-22-33-44-55-66", isBuiltIn: false, battery: AirPodsBattery(left: 40, right: nil, caseLevel: nil))
        let keyboard = AirPodsRegistryEntry(product: "Apple Internal Keyboard / Trackpad", address: nil, isBuiltIn: true, battery: AirPodsBattery(left: nil, right: nil, caseLevel: nil))
        XCTAssertEqual(AudioDeviceRules.matchBattery(deviceName: "Something", deviceUID: "AABBCCDDEEFF:output", candidates: [pro, max, keyboard]), pro.battery, "the address inside the UID wins")
        XCTAssertEqual(AudioDeviceRules.matchBattery(deviceName: "AirPods Max", deviceUID: nil, candidates: [pro, max]), max.battery, "exact name")
        XCTAssertEqual(AudioDeviceRules.matchBattery(deviceName: "Emre's AirPods Pro (2)", deviceUID: nil, candidates: [pro, max]), pro.battery, "either name containing the other")
        XCTAssertEqual(AudioDeviceRules.matchBattery(deviceName: "Unknown", deviceUID: nil, candidates: [pro, keyboard]), pro.battery, "a single external entry is taken on faith")
        XCTAssertNil(AudioDeviceRules.matchBattery(deviceName: "Unknown", deviceUID: nil, candidates: [pro, max]), "two candidates and no match: say nothing rather than guess")
        XCTAssertNil(AudioDeviceRules.matchBattery(deviceName: "AirPods", deviceUID: nil, candidates: [keyboard]))
        XCTAssertEqual(AudioDeviceRules.normalizedAddress("AA:BB-cc dd"), "aabbccdd")
    }

    func testTexts() {
        let bundle = Bundle(for: AudioDeviceRulesTests.self)
        XCTAssertEqual(AudioDeviceRules.batteryText(AirPodsBattery(left: 84, right: 82, caseLevel: 61), bundle: bundle), "L 84% · R 82% · Case 61%")
        XCTAssertEqual(AudioDeviceRules.batteryText(AirPodsBattery(left: nil, right: 82, caseLevel: nil), bundle: bundle), "R 82%")
        XCTAssertNil(AudioDeviceRules.batteryText(AirPodsBattery(left: nil, right: nil, caseLevel: nil), bundle: bundle))
        let airpods = device("AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth)
        let event = AudioDeviceRules.connectedEvent(airpods, battery: AirPodsBattery(left: 84, right: 82, caseLevel: nil), moduleID: "audioDevice", bundle: bundle)
        XCTAssertEqual(event.title, "Connected: AirPods Pro")
        XCTAssertEqual(event.detail, "L 84% · R 82%")
        XCTAssertEqual(event.symbolName, "airpods.pro")
        XCTAssertEqual(event.duration, 2.5)
        XCTAssertNil(AudioDeviceRules.connectedEvent(airpods, battery: nil, moduleID: "audioDevice", bundle: bundle).detail)
        XCTAssertEqual(AudioDeviceRules.disconnectedEvent(airpods, moduleID: "audioDevice", bundle: bundle).title, "Disconnected: AirPods Pro")
        XCTAssertEqual(AudioDeviceRules.transportName(kAudioDeviceTransportTypeBluetooth, bundle: bundle), "Bluetooth")
        XCTAssertEqual(AudioDeviceRules.transportName(kAudioDeviceTransportTypeBuiltIn, bundle: bundle), "Built-in")
    }
}
