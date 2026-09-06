import AppKit
import IOKit.ps
import Observation

/// Listens to the power source: IOKit calls back whenever the battery state changes and the
/// system posts a notification when Low Power Mode flips. Nothing polls.
@MainActor
@Observable
final class BatteryService {
    private(set) var snapshot: BatterySnapshot?
    /// False on a Mac without an internal battery, so the module stays out of the way.
    private(set) var hasBattery = false
    var thresholds = BatteryThresholds()

    /// Called after every change with the previous reading.
    var onChange: ((BatterySnapshot?, BatterySnapshot) -> Void)?

    @ObservationIgnored private var observer: PowerSourceObserver?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var powerStateObserver: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        let observer = PowerSourceObserver { [weak self] in self?.refresh() }
        self.observer = observer
        if let source = IOPSNotificationCreateRunLoopSource(PowerSourceObserver.fire, observer.opaque)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            assertionFailure("IOPSNotificationCreateRunLoopSource failed")
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        observer = nil
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
        powerStateObserver = nil
    }

    /// Reads the internal battery, if there is one.
    func refresh() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let current = Self.readInternalBattery(lowPowerMode: lowPower)
        hasBattery = current != nil
        guard current != snapshot else { return }
        let previous = snapshot
        snapshot = current
        if let current {
            onChange?(previous, current)
        }
    }

    private static func readInternalBattery(lowPowerMode: Bool) -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let snapshot = BatteryRules.parse(powerSource: description, lowPowerMode: lowPowerMode) {
                return snapshot
            }
        }
        return nil
    }
}

/// Crosses the C callback boundary: IOKit hands back an opaque pointer, we hop to the main actor.
private final class PowerSourceObserver: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    var opaque: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    static let fire: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        let observer = Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue()
        // IOKit delivers on the run loop the source was added to — the main one.
        MainActor.assumeIsolated { observer.handler() }
    }
}
