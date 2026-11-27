import AppKit
import SwiftUI
import JigScreenCore

/// Draws the screen into a PNG with no display and no permission. For the README and for checks.
///
///   JigScreen --snapshot out.png [--size 1440x900] [--source status.json] [--photos <folder>] [--clear]
///
/// `--clear` empties the waiting list, to show the screen with nothing waiting.
enum Snapshot {
    private static var window: NSWindow?

    static func run(to path: String, arguments: [String], store: StatusStore) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.count > i + 1 else { return nil }
            return arguments[i + 1]
        }
        var size = CGSize(width: 1440, height: 900)
        if let parts = value("--size")?.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
            size = CGSize(width: parts[0], height: parts[1])
        }
        let settings = Settings.shared
        if let photos = value("--photos") {
            settings.photoFolder = photos
            settings.background = .slideshow
        } else {
            settings.background = .solid
        }
        do {
            var file = try StatusStore.load(value("--source").map { DataSource.file($0) } ?? .sample)
            if value("--source") != nil { file = file.moved(to: Date()) }
            if arguments.contains("--clear") {
                let gone = Set(file.items.filter { $0.state == .waitingUser }.map(\.id))
                file.items.removeAll { gone.contains($0.id) }
                file.agents.removeAll { $0.currentItemId.map(gone.contains) ?? false }
            }
            store.set(file)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        let root = SaverRootView(screenIndex: 0)
            .environmentObject(store)
            .environmentObject(SaverSession(idleSince: Date().addingTimeInterval(-300)))
            .environmentObject(settings)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let frame = NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        Snapshot.window = window

        // Give a photo time to load and fade in.
        DispatchQueue.main.asyncAfter(deadline: .now() + (value("--photos") == nil ? 1.0 : 4.0)) {
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { exit(1) }
            exit(0)
        }
    }
}
