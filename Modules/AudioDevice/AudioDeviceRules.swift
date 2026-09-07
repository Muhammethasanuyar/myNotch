import CoreAudio
import Foundation

/// What the IORegistry knows about a pair of AirPods (or nothing, for most devices).
nonisolated struct AirPodsBattery: Equatable, Sendable {
    let left: Int?
    let right: Int?
    let caseLevel: Int?

    var lowest: Int? { [left, right].compactMap { $0 }.min() }
    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil }
}

/// One `AppleDeviceManagementHIDEventService` entry, reduced to what the module reads.
nonisolated struct AirPodsRegistryEntry: Equatable, Sendable {
    let product: String?
    let address: String?
    let isBuiltIn: Bool
    let battery: AirPodsBattery
}

nonisolated enum AudioDeviceAlert: Equatable, Sendable {
    case connected
    case disconnected
}

/// Pure decisions of the output-device module: what counts as a switch worth announcing, which
/// glyph a device gets, how the registry's battery keys are read and matched.
nonisolated enum AudioDeviceRules {
    static let connectDuration: TimeInterval = 2.5
    static let disconnectDuration: TimeInterval = 2
    /// AirPods report their battery a beat after the route switches; read again at these offsets.
    static let batteryRetryDelays: [TimeInterval] = [2, 5]
    /// Route flapping (a device that appears and vanishes within a moment) is folded before announcing.
    static let settle: Duration = .milliseconds(300)

    static func isExternal(_ info: AudioOutputInfo) -> Bool {
        !info.isBuiltIn
    }

    static func isBluetooth(_ info: AudioOutputInfo) -> Bool {
        info.isBluetooth
    }

    /// The name first (an "AirPods Pro" over any transport), then the transport.
    static func symbolName(for info: AudioOutputInfo) -> String {
        let name = info.name.lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("homepod") { return "homepod.fill" }
        if name.contains("tv") { return "tv.fill" }
        if name.contains("headphone") || name.contains("kulaklık") || name.contains("buds") || name.contains("wh-") { return "headphones" }
        if name.contains("display") || name.contains("monitor") || name.contains("ekran") { return "display" }
        switch info.transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv.fill"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt: return "hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    /// Whether the change from `previous` to `current` deserves a popup. Built-in to built-in never
    /// does; the first reading after launch is not a connection.
    static func shouldAnnounce(previous: AudioOutputInfo?, current: AudioOutputInfo?, connectPopups: Bool, disconnectPopups: Bool) -> AudioDeviceAlert? {
        guard let previous, previous != current else { return nil }
        if let current, isExternal(current) {
            return connectPopups ? .connected : nil
        }
        if isExternal(previous) {
            return disconnectPopups ? .disconnected : nil
        }
        return nil
    }

    static func connectedEvent(_ info: AudioOutputInfo, battery: AirPodsBattery?, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        NotchEvent(
            moduleID: moduleID,
            title: String(localized: "audioDevice.event.connected", defaultValue: "Connected: \(info.name)", bundle: bundle),
            detail: battery.flatMap { batteryText($0, bundle: bundle) },
            symbolName: symbolName(for: info),
            duration: connectDuration
        )
    }

    static func disconnectedEvent(_ info: AudioOutputInfo, moduleID: String, bundle: Bundle = .main) -> NotchEvent {
        NotchEvent(
            moduleID: moduleID,
            title: String(localized: "audioDevice.event.disconnected", defaultValue: "Disconnected: \(info.name)", bundle: bundle),
            symbolName: "speaker.slash",
            duration: disconnectDuration
        )
    }

    // MARK: IORegistry

    /// Reads one registry entry's dictionary. Every key is optional and undocumented; a percentage
    /// outside 0…100 is treated as absent.
    static func parseRegistry(_ properties: [String: Any]) -> AirPodsRegistryEntry? {
        func percent(_ key: String) -> Int? {
            guard let value = (properties[key] as? NSNumber)?.intValue, (0...100).contains(value) else { return nil }
            return value
        }
        let transport = properties["Transport"] as? String
        let builtIn = (properties["Built-In"] as? NSNumber)?.boolValue ?? (transport == "FIFO")
        return AirPodsRegistryEntry(
            product: properties["Product"] as? String,
            address: properties["DeviceAddress"] as? String,
            isBuiltIn: builtIn,
            battery: AirPodsBattery(left: percent("BatteryPercentLeft"), right: percent("BatteryPercentRight"), caseLevel: percent("BatteryPercentCase"))
        )
    }

    /// The registry entry that describes the audio device: by address hidden in the device UID,
    /// then by exact name, then by either name containing the other, then the only external entry.
    static func matchBattery(deviceName: String, deviceUID: String?, candidates: [AirPodsRegistryEntry]) -> AirPodsBattery? {
        let external = candidates.filter { !$0.isBuiltIn && !$0.battery.isEmpty }
        guard !external.isEmpty else { return nil }
        if let uid = deviceUID.map(normalizedAddress), !uid.isEmpty,
           let match = external.first(where: { $0.address.map { uid.contains(normalizedAddress($0)) } ?? false }) {
            return match.battery
        }
        let name = deviceName.lowercased()
        if let exact = external.first(where: { $0.product?.lowercased() == name }) { return exact.battery }
        if let partial = external.first(where: { entry in
            guard let product = entry.product?.lowercased(), !product.isEmpty else { return false }
            return name.contains(product) || product.contains(name)
        }) {
            return partial.battery
        }
        return external.count == 1 ? external[0].battery : nil
    }

    /// "L 84% · R 82% · Case 61%", leaving out what is unknown; `nil` when nothing is.
    static func batteryText(_ battery: AirPodsBattery, bundle: Bundle = .main) -> String? {
        var parts: [String] = []
        if let left = battery.left { parts.append(String(localized: "audioDevice.battery.left", defaultValue: "L \(left)%", bundle: bundle)) }
        if let right = battery.right { parts.append(String(localized: "audioDevice.battery.right", defaultValue: "R \(right)%", bundle: bundle)) }
        if let caseLevel = battery.caseLevel { parts.append(String(localized: "audioDevice.battery.case", defaultValue: "Case \(caseLevel)%", bundle: bundle)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Lower-case hex with separators dropped, so `AA:BB` and `aa-bb` compare equal.
    static func normalizedAddress(_ text: String) -> String {
        text.lowercased().filter { $0.isHexDigit }
    }

    static func transportName(_ transport: UInt32, bundle: Bundle = .main) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: String(localized: "audioDevice.transport.builtIn", defaultValue: "Built-in", bundle: bundle)
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeHDMI: "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: "DisplayPort"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeAggregate: String(localized: "audioDevice.transport.aggregate", defaultValue: "Multi-output", bundle: bundle)
        case kAudioDeviceTransportTypeVirtual: String(localized: "audioDevice.transport.virtual", defaultValue: "Virtual", bundle: bundle)
        default: String(localized: "audioDevice.transport.unknown", defaultValue: "Unknown", bundle: bundle)
        }
    }
}
