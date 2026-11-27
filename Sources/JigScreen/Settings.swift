import AppKit
import Combine

/// Where the status comes from.
enum DataSource: Equatable {
    /// The sample file that ships with the app.
    case sample
    /// This Mac's own Jig: the app runs `jig status --json`.
    case jig
    case file(String)
    case url(String)

    var label: String {
        switch self {
        case .sample: return "Sample data"
        case .jig: return "Jig on this Mac"
        case .file(let path): return (path as NSString).lastPathComponent
        case .url(let url): return url
        }
    }
}

enum BackgroundKind: String {
    case solid, slideshow
}

/// The app's settings, kept in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    /// A snapshot run (`--snapshot`) keeps its settings apart, so it never changes the real ones.
    private let defaults: UserDefaults = {
        guard CommandLine.arguments.contains("--snapshot") else { return .standard }
        let name = "jig-screen-snapshot"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }()

    @Published var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: "idleMinutes") } }
    @Published var source: DataSource { didSet { saveSource() } }
    @Published var background: BackgroundKind { didSet { defaults.set(background.rawValue, forKey: "background") } }
    @Published var solidColor: String { didSet { defaults.set(solidColor, forKey: "solidColor") } }
    @Published var photoFolder: String? { didSet { defaults.set(photoFolder, forKey: "photoFolder") } }
    @Published var secondsPerPhoto: Int { didSet { defaults.set(secondsPerPhoto, forKey: "secondsPerPhoto") } }

    @Published var hotKey: HotKey? { didSet { saveHotKey() } }
    @Published var hotCorner: Corner { didSet { defaults.set(hotCorner.rawValue, forKey: "hotCorner") } }

    static let idleChoices = [1, 2, 5, 10, 15, 30]
    static let photoChoices = [8, 12, 20, 30, 60]
    /// The solid colors on offer: a name and its hex value.
    static let colors: [(name: String, hex: String)] = [
        ("Black", "000000"), ("Charcoal", "15171A"), ("Midnight blue", "0B1220"), ("Forest", "0C1712"),
    ]

    private init() {
        let minutes = defaults.integer(forKey: "idleMinutes")
        idleMinutes = minutes > 0 ? minutes : 5
        switch (defaults.string(forKey: "sourceKind"), defaults.string(forKey: "sourceValue")) {
        case ("jig", _): source = .jig
        case ("file", let path?): source = .file(path)
        case ("url", let url?): source = .url(url)
        default: source = .sample
        }
        background = BackgroundKind(rawValue: defaults.string(forKey: "background") ?? "") ?? .solid
        solidColor = defaults.string(forKey: "solidColor") ?? "000000"
        photoFolder = defaults.string(forKey: "photoFolder")
        let seconds = defaults.integer(forKey: "secondsPerPhoto")
        secondsPerPhoto = seconds > 0 ? seconds : 12
        if let label = defaults.string(forKey: "hotKeyLabel") {
            hotKey = HotKey(keyCode: UInt32(defaults.integer(forKey: "hotKeyCode")),
                            modifiers: UInt32(defaults.integer(forKey: "hotKeyModifiers")), label: label)
        } else {
            hotKey = nil
        }
        hotCorner = Corner(rawValue: defaults.string(forKey: "hotCorner") ?? "") ?? .off
    }

    private func saveHotKey() {
        guard let hotKey else {
            ["hotKeyCode", "hotKeyModifiers", "hotKeyLabel"].forEach { defaults.removeObject(forKey: $0) }
            return
        }
        defaults.set(Int(hotKey.keyCode), forKey: "hotKeyCode")
        defaults.set(Int(hotKey.modifiers), forKey: "hotKeyModifiers")
        defaults.set(hotKey.label, forKey: "hotKeyLabel")
    }

    private func saveSource() {
        switch source {
        case .sample: defaults.set("sample", forKey: "sourceKind"); defaults.removeObject(forKey: "sourceValue")
        case .jig: defaults.set("jig", forKey: "sourceKind"); defaults.removeObject(forKey: "sourceValue")
        case .file(let path): defaults.set("file", forKey: "sourceKind"); defaults.set(path, forKey: "sourceValue")
        case .url(let url): defaults.set("url", forKey: "sourceKind"); defaults.set(url, forKey: "sourceValue")
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
