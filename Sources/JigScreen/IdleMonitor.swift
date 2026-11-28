import AppKit
import IOKit
import IOKit.pwr_mgt

/// Reads how long the keyboard and mouse have been still, and whether something holds the display awake.
enum Idle {
    /// Seconds since the last key, click or mouse move, from the HID system in IOKit.
    static func seconds() -> TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber {
                return TimeInterval(value.uint64Value) / 1_000_000_000
            }
        }
        // IOKit gave nothing: ask Quartz, which reads the same clock.
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Seconds since the last key press. A mouse move or click does not count.
    static func secondsSinceKey() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    }

    /// True while an app asks the system to keep the display on: a video, a call, a presentation.
    static func displayIsHeldAwake() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&unmanaged) == kIOReturnSuccess,
              let status = unmanaged?.takeRetainedValue() as? [String: Any] else { return false }
        for key in ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"] {
            if let count = status[key] as? NSNumber, count.intValue > 0 { return true }
        }
        return false
    }

    static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    static func displayIsAsleep() -> Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }
}

/// Watches the idle time and says when to show the screen.
final class IdleMonitor {
    private var timer: Timer?
    private var fetchedEarly = false
    /// Called once the Mac has been idle for the threshold. The value is when the idle time began.
    var onIdle: ((Date) -> Void)?
    /// Called about 20 seconds before `onIdle`, so the data is fresh when the screen opens.
    var onAlmostIdle: (() -> Void)?
    /// The monitor asks this before it fires: true while the screen already shows.
    var isShowing: () -> Bool = { false }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard !isShowing() else { return }
        let idle = Idle.seconds()
        let threshold = TimeInterval(Settings.shared.idleMinutes * 60)
        if idle < threshold - 20 { fetchedEarly = false; return }
        if Idle.displayIsHeldAwake() || Idle.screenIsLocked() || Idle.displayIsAsleep() { return }
        if !fetchedEarly { fetchedEarly = true; onAlmostIdle?() }
        if idle >= threshold { onIdle?(Date().addingTimeInterval(-idle)) }
    }
}
