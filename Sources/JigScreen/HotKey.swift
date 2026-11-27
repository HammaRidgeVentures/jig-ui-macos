import AppKit
import Carbon.HIToolbox

/// A key and its modifiers, which show the screen from anywhere.
struct HotKey: Equatable {
    var keyCode: UInt32
    /// Carbon's modifier bits (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32
    /// How the menu shows it: "⌃⌥⌘J".
    var label: String

    /// Reads a key press. Nil when it has no Control, Option or Command: a bare letter can't be a hot key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0, symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        modifiers = carbon
        label = symbols + HotKey.name(of: event)
    }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_ForwardDelete: "Fwd Delete",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "Home", kVK_End: "End",
        kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func name(of event: NSEvent) -> String {
        if let name = named[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// Registers one system-wide hot key. Carbon's hot keys need no Accessibility permission.
final class HotKeyCenter {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    /// Puts `hotKey` in place of the one before it. Nil removes it. False: macOS refused it (another app has it).
    @discardableResult
    func register(_ hotKey: HotKey?) -> Bool {
        if let key { UnregisterEventHotKey(key) }
        key = nil
        guard let hotKey else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4A49_4753), id: 1)   // "JIGS"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, id, GetApplicationEventTarget(), 0, &key)
        return status == noErr && key != nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            if let context { Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}

/// A corner of the display that shows the screen when the pointer rests in it.
enum Corner: String, CaseIterable {
    case off, topLeft, topRight, bottomLeft, bottomRight

    var label: String {
        switch self {
        case .off: return "Off"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    func point(in frame: NSRect) -> NSPoint? {
        switch self {
        case .off: return nil
        case .topLeft: return NSPoint(x: frame.minX, y: frame.maxY)
        case .topRight: return NSPoint(x: frame.maxX, y: frame.maxY)
        case .bottomLeft: return NSPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: return NSPoint(x: frame.maxX, y: frame.minY)
        }
    }
}

/// Watches the pointer for the hot corner. macOS has no way to add an action to its own hot corners,
/// so the app reads the pointer's place itself. That needs no permission.
final class HotCornerWatcher {
    private var timer: Timer?
    private var corner = Corner.off
    private var enteredAt: Date?
    /// False after it fires, until the pointer leaves the corner: one visit shows the screen once.
    private var armed = true
    var onTrigger: (() -> Void)?

    func set(_ corner: Corner) {
        self.corner = corner
        timer?.invalidate()
        timer = nil
        enteredAt = nil
        armed = true
        guard corner != .off else { return }
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let pointer = NSEvent.mouseLocation
        // The nearest matching corner of any display.
        let distance = NSScreen.screens.compactMap { corner.point(in: $0.frame) }
            .map { hypot(pointer.x - $0.x, pointer.y - $0.y) }.min() ?? .infinity
        // A drag that ends in the corner is not a visit.
        if distance > 5 || NSEvent.pressedMouseButtons != 0 {
            enteredAt = nil
            if distance > 40 { armed = true }
            return
        }
        guard armed else { return }
        guard let enteredAt else { self.enteredAt = Date(); return }
        if Date().timeIntervalSince(enteredAt) >= 0.35 {
            armed = false
            self.enteredAt = nil
            onTrigger?()
        }
    }
}
