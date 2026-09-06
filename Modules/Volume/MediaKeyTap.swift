import AppKit
import CoreGraphics
import os

/// A CoreGraphics event tap that takes the sound keys (volume up, volume down, mute) before macOS
/// does, so the system HUD never appears and the notch shows the level instead. Needs the
/// Accessibility permission; without it `start()` fails and the keys keep their system behaviour.
///
/// The tap runs on a thread of its own: an event tap that does not answer within the system's
/// deadline is switched off, and this app's main run loop is busy with SwiftUI animation. The
/// callback does only pure decoding and hands the press to the main actor. Brightness and other
/// keys are returned untouched.
nonisolated final class MediaKeyTap: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case notTrusted
        case tapCreationFailed
    }

    /// A sound key was pressed or released while the tap was swallowing. Called on the tap thread.
    var onPress: (@Sendable (MediaKeyPress, MediaKeyFlags) -> Void)?
    /// The system disabled the tap (it was re-enabled at once). Called on the tap thread.
    var onDisabled: (@Sendable () -> Void)?

    private var lock = os_unfair_lock()
    private var swallowing = false
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private static let log = Logger(subsystem: "com.emre.mynotch", category: "media-keys")
    /// NX_SYSDEFINED: the event type media keys arrive as. Sound and brightness keys are subtype 8.
    private static let systemDefined = CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))!
    private static let auxiliaryControlSubtype: Int16 = 8

    /// Whether sound keys are taken (the default output has a volume) or passed through.
    func setSwallowing(_ on: Bool) {
        os_unfair_lock_lock(&lock)
        swallowing = on
        os_unfair_lock_unlock(&lock)
    }

    var isSwallowing: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return swallowing
    }

    func start() throws {
        guard AXIsProcessTrusted() else { throw Failure.notTrusted }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefined.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw Failure.tapCreationFailed
        }
        self.port = port
        let thread = Thread { [weak self] in
            guard let self, let port = self.port else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            let loop = CFRunLoopGetCurrent()
            os_unfair_lock_lock(&self.lock)
            self.source = source
            self.runLoop = loop
            os_unfair_lock_unlock(&self.lock)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.emre.mynotch.mediakeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        let port = self.port
        let source = self.source
        let loop = self.runLoop
        self.port = nil
        self.source = nil
        self.runLoop = nil
        os_unfair_lock_unlock(&lock)
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let loop, let source {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopStop(loop)
        }
        if let port { CFMachPortInvalidate(port) }
        thread = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system switched us off; switch back on and tell the owner so it can count it.
            os_unfair_lock_lock(&tap.lock)
            let port = tap.port
            os_unfair_lock_unlock(&tap.lock)
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            tap.onDisabled?()
            return Unmanaged.passUnretained(event)
        }
        guard type == systemDefined,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == auxiliaryControlSubtype,
              let press = VolumeRules.mediaKey(data1: nsEvent.data1),
              tap.isSwallowing else {
            return Unmanaged.passUnretained(event)
        }
        let flags = MediaKeyFlags(shift: event.flags.contains(.maskShift), option: event.flags.contains(.maskAlternate))
        tap.onPress?(press, flags)
        // Both the press and the release are ours: the system must not see half a key.
        return nil
    }
}
