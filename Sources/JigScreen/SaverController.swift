import AppKit
import SwiftUI
import Combine

/// What every window of one showing shares.
final class SaverSession: ObservableObject {
    /// When the owner went idle. "Done" in the footer counts from here.
    let idleSince: Date
    /// True while the pointer shows: the owner moved the mouse. The screen then says how to close it.
    @Published var pointerShown = false
    /// Closes the screen. A click on any place that is not a link calls it.
    var close: () -> Void = {}
    /// Closes the screen and opens a link in the browser.
    var open: (URL) -> Void = { _ in }
    init(idleSince: Date) { self.idleSince = idleSince }
}

/// The first click on a display that is not the key one must reach the view, not only make the window key.
final class SaverHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless window can't become key unless it says so. Key is how the app gets the key press that dismisses.
/// It is a panel that does not activate the app: macOS may refuse to bring the app to the front, and a
/// non-activating panel still takes the keyboard and the mouse moves, as Spotlight does.
final class SaverWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// AppKit keeps a window clear of the menu bar. This one covers the whole display.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Opens one full-screen window on every display, and closes them all at a key press or a click.
/// A mouse move only shows the pointer, so the owner can click a link on the screen.
final class SaverController {
    private let store: StatusStore
    private var windows: [SaverWindow] = []
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var shownAt = Date.distantPast
    private var moved: CGFloat = 0
    private var previousApp: NSRunningApplication?
    private var cursorHidden = false
    private var session: SaverSession?
    private var rehide: DispatchWorkItem?
    private var modifiers: NSEvent.ModifierFlags = []
    /// When the screen last closed. A hot key press that closed it must not open it again.
    private(set) var lastDismissed = Date.distantPast

    var isShowing: Bool { !windows.isEmpty }

    init(store: StatusStore) { self.store = store }

    func show(idleSince: Date) {
        guard !isShowing else { return }
        shownAt = Date()
        moved = 0
        previousApp = NSWorkspace.shared.frontmostApplication
        let session = SaverSession(idleSince: idleSince)
        session.close = { [weak self] in self?.closeByClick() }
        session.open = { [weak self] url in
            self?.dismiss()
            NSWorkspace.shared.open(url)
        }
        self.session = session
        modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        store.startPolling(showing: true)

        for (index, screen) in NSScreen.screens.enumerated() {
            let window = SaverWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            window.isFloatingPanel = true
            window.becomesKeyOnlyIfNeeded = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.acceptsMouseMovedEvents = true
            window.animationBehavior = .none
            let root = SaverRootView(screenIndex: index)
                .environmentObject(store)
                .environmentObject(session)
                .environmentObject(Settings.shared)
            let host = SaverHostingView(rootView: root)
            // The window sets the size, not the view's own ideal size.
            host.sizingOptions = []
            window.contentView = host
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        // Take the keyboard, so the key that dismisses is not typed into the app behind.
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        NSCursor.hide()
        cursorHidden = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        // An animation does not run while the display is off. Never leave a window that can't be seen.
        let opened = windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { opened.forEach { if $0.isVisible { $0.alphaValue = 1 } } }
        watchForTheOwner()
    }

    func dismiss(_ why: String = "asked") {
        guard isShowing else { return }
        NSLog("Jig Screen closes: %@", why)
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        pollTimer?.invalidate()
        pollTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        lastDismissed = Date()
        store.startPolling(showing: false)
        rehide?.cancel()
        rehide = nil
        session = nil
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        // A pointing hand from a link must not stay after the screen goes.
        NSCursor.arrow.set()
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil); $0.contentView = nil }
        })
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private func watchForTheOwner() {
        // 1. Events that reach this app: any key, click or mouse move. A scroll does nothing.
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .mouseMoved, .leftMouseDragged]
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // A left click goes on to the screen: a link opens, and any other place closes it.
            if event.type == .leftMouseDown { return event }
            self?.saw(event)
            return nil
        }) { monitors.append(local) }
        // A mouse move that goes to another app still shows the pointer. Watching the mouse needs no permission.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.saw(event)
        }) { monitors.append(global) }

        // 2. The HID key clock, in case a key press goes to another app.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let showing = Date().timeIntervalSince(self.shownAt)
            // The start is slack: the hand that pressed the hot key is still letting go.
            if showing > 1.5, Idle.secondsSinceKey() < showing - 1.0 { self.dismiss("a key, from the HID clock") }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // 3. The displays changed, or the Mac sleeps: close, and let the idle clock start over.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.dismiss("the displays changed") })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.dismiss(name.rawValue) })
        }
    }

    private func saw(_ event: NSEvent) {
        // The click on "Preview now" is still in the air for a moment: ignore the first instant.
        guard Date().timeIntervalSince(shownAt) > 0.6 else { return }
        if event.type == .flagsChanged {
            // A modifier going down is a key press. One coming up is the hot key being let go.
            let now = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let pressed = !now.subtracting(modifiers).isEmpty
            modifiers = now
            if !pressed { return }
        }
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            // A desk bump moves the mouse a pixel. A hand moves it more.
            moved += abs(event.deltaX) + abs(event.deltaY)
            if moved >= 4 { showPointer() }
            return
        }
        dismiss("event \(event.type.rawValue)")
    }

    /// A click on a place that is not a link. The click on "Preview now" can land here too: ignore the first instant.
    private func closeByClick() {
        guard Date().timeIntervalSince(shownAt) > 0.6 else { return }
        dismiss("a click")
    }

    /// Shows the pointer while the mouse moves, and hides it again after 3 still seconds.
    private func showPointer() {
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        if session?.pointerShown == false { session?.pointerShown = true }
        rehide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isShowing else { return }
            if !self.cursorHidden { NSCursor.hide(); self.cursorHidden = true }
            self.session?.pointerShown = false
            self.moved = 0
        }
        rehide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
