import Foundation
import IOKit

/// Best effort. `AppleDeviceManagementHIDEventService` is public IOKit and needs no entitlement; the
/// battery keys on its entries are undocumented, so every field is optional and a miss is normal.
/// Nothing is written to the registry. Verified on this Mac: the class exists and the built-in
/// keyboard/trackpad is one entry (`Transport = FIFO`, no battery keys), so the built-in filter matters.
nonisolated enum AirPodsBatteryReader {
    static let serviceClass = "AppleDeviceManagementHIDEventService"

    /// Every entry of the class, parsed. Runs a registry sweep of a few milliseconds.
    static func entries() -> [AirPodsRegistryEntry] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [AirPodsRegistryEntry] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let parsed = AudioDeviceRules.parseRegistry(dictionary) else { continue }
            result.append(parsed)
        }
        return result
    }
}
