import AppKit
import SwiftUI
import Combine

/// What every window of one showing shares.
final class SaverSession: ObservableObject {
    /// When the owner went idle. "Done" in the footer counts from here.
    let idleSince: Date
    init(idleSince: Date) { self.idleSince = idleSince }
}

/// A borderless window can't become key unless it says so. Key is how the app gets the key press that dismisses.
final class SaverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// AppKit keeps a window clear of the menu bar. This one covers the whole display.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Opens one full-screen window on every display, and closes them all at the first sign of the owner.
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

    var isShowing: Bool { !windows.isEmpty }

    init(store: StatusStore) { self.store = store }

    func show(idleSince: Date) {
        guard !isShowing else { return }
        shownAt = Date()
        moved = 0
        previousApp = NSWorkspace.shared.frontmostApplication
        let session = SaverSession(idleSince: idleSince)
        store.startPolling()

        for (index, screen) in NSScreen.screens.enumerated() {
            let window = SaverWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
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
            let host = NSHostingView(rootView: root)
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

    func dismiss() {
        guard isShowing else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        pollTimer?.invalidate()
        pollTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        store.stopPolling()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
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
        // 1. Events that reach this app: any key, click, scroll or mouse move.
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .scrollWheel, .mouseMoved, .leftMouseDragged]
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.saw(event)
            return nil
        }) { monitors.append(local) }

        // 2. The HID idle clock, in case an event goes to another app or another display.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let showing = Date().timeIntervalSince(self.shownAt)
            if showing > 1.2, Idle.seconds() < showing - 0.6 { self.dismiss() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // 3. The displays changed, or the Mac sleeps: close, and let the idle clock start over.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.dismiss() })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
        }
    }

    private func saw(_ event: NSEvent) {
        // The click on "Preview now" is still in the air for a moment: ignore the first instant.
        guard Date().timeIntervalSince(shownAt) > 0.6 else { return }
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            // A desk bump moves the mouse a pixel. A hand moves it more.
            moved += abs(event.deltaX) + abs(event.deltaY)
            if moved < 4 { return }
        }
        dismiss()
    }
}
