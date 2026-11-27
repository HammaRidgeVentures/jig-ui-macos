import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let store = StatusStore()
    private lazy var saver = SaverController(store: store)
    private let monitor = IdleMonitor()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 {
            Snapshot.run(to: arguments[flag + 1], arguments: arguments, store: store)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.inset.bottomright.filled",
                                     accessibilityDescription: "Jig Screen")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        if arguments.contains("--check-menu") {
            // A smoke test: build the menu once, print its rows, and quit.
            menuNeedsUpdate(menu)
            for row in menu.items { print(row.isSeparatorItem ? "---" : row.title, row.submenu.map { "(\($0.items.count) choices)" } ?? "") }
            exit(0)
        }

        monitor.isShowing = { [weak self] in self?.saver.isShowing ?? false }
        monitor.onAlmostIdle = { [weak self] in self?.store.refresh() }
        monitor.onIdle = { [weak self] since in self?.saver.show(idleSince: since) }
        monitor.start()

        if arguments.contains("--preview") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.preview() } }
    }

    // MARK: The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(action("Preview now", #selector(preview)))
        menu.addItem(.separator())

        let idle = NSMenu()
        for minutes in Settings.idleChoices {
            let item = action(minutes == 1 ? "1 minute" : "\(minutes) minutes", #selector(pickIdle(_:)))
            item.tag = minutes
            item.state = settings.idleMinutes == minutes ? .on : .off
            idle.addItem(item)
        }
        menu.addItem(submenu("Start after", idle, detail: "\(settings.idleMinutes) min"))

        let source = NSMenu()
        let sample = action("Sample data", #selector(pickSample))
        sample.state = settings.source == .sample ? .on : .off
        source.addItem(sample)
        let jig = action("Jig on this Mac", #selector(pickJig))
        jig.state = settings.source == .jig ? .on : .off
        source.addItem(jig)
        var fileTitle = "A file…", urlTitle = "A web address…"
        var fileOn = false, urlOn = false
        if case .file(let path) = settings.source { fileTitle = "File: \((path as NSString).abbreviatingWithTildeInPath)…"; fileOn = true }
        if case .url(let url) = settings.source { urlTitle = "Address: \(url)…"; urlOn = true }
        let file = action(fileTitle, #selector(pickFile))
        file.state = fileOn ? .on : .off
        source.addItem(file)
        let url = action(urlTitle, #selector(pickURL))
        url.state = urlOn ? .on : .off
        source.addItem(url)
        menu.addItem(submenu("Data source", source, detail: settings.source.label))

        let background = NSMenu()
        for color in Settings.colors {
            let item = action(color.name, #selector(pickColor(_:)))
            item.representedObject = color.hex
            item.state = settings.background == .solid && settings.solidColor == color.hex ? .on : .off
            background.addItem(item)
        }
        background.addItem(.separator())
        let photos = action("Photo slideshow", #selector(pickSlideshow))
        photos.state = settings.background == .slideshow ? .on : .off
        background.addItem(photos)
        let folderName = settings.photoFolder.map { ($0 as NSString).lastPathComponent }
        background.addItem(action(folderName.map { "Photo folder: \($0)…" } ?? "Choose a photo folder…", #selector(pickFolder)))
        let pace = NSMenu()
        for seconds in Settings.photoChoices {
            let item = action("\(seconds) seconds", #selector(pickPace(_:)))
            item.tag = seconds
            item.state = settings.secondsPerPhoto == seconds ? .on : .off
            pace.addItem(item)
        }
        background.addItem(submenu("Each photo stays", pace, detail: "\(settings.secondsPerPhoto) s"))
        menu.addItem(submenu("Background", background, detail: settings.background == .slideshow ? "Photos" : "Color"))

        menu.addItem(.separator())
        let login = action("Launch at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jig Screen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu, detail: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        // The current choice, shown at the right of the row.
        if #available(macOS 14.4, *) { item.subtitle = detail } else { item.title = "\(title): \(detail)" }
        return item
    }

    // MARK: Actions

    @objc private func preview() {
        // As if the Mac had just reached the idle time.
        store.refresh()
        saver.show(idleSince: Date().addingTimeInterval(-TimeInterval(settings.idleMinutes * 60)))
    }

    @objc private func pickIdle(_ sender: NSMenuItem) { settings.idleMinutes = sender.tag }
    @objc private func pickSample() { settings.source = .sample; store.refresh() }
    @objc private func pickJig() { settings.source = .jig; store.refresh() }

    @objc private func pickFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose the status file (status.json)."
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: ("~/.claude/jig" as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            settings.source = .file(url.path)
            store.refresh()
        }
    }

    @objc private func pickURL() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Where is the status?"
        alert.informativeText = "A web address that answers with the status JSON. For a Mac on your tailnet: http://mac-mini:8787/status.json"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        if case .url(let current) = settings.source { field.stringValue = current }
        field.placeholderString = "http://mac-mini:8787/status.json"
        alert.accessoryView = field
        alert.addButton(withTitle: "Use it")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else {
            tell("That is not a web address.", "It starts with http:// or https://.")
            return
        }
        settings.source = .url(text)
        store.refresh()
    }

    @objc private func pickColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        settings.solidColor = hex
        settings.background = .solid
    }

    @objc private func pickSlideshow() {
        if settings.photoFolder == nil { pickFolder() } else { settings.background = .slideshow }
    }

    @objc private func pickFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose a folder of photos."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            settings.photoFolder = url.path
            settings.background = .slideshow
        }
    }

    @objc private func pickPace(_ sender: NSMenuItem) { settings.secondsPerPhoto = sender.tag }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            tell("Launch at login could not be changed.",
                 "Move Jig Screen to the Applications folder, open it from there, and try again. (\(error.localizedDescription))")
        }
    }

    private func tell(_ message: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
