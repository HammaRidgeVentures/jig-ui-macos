import SwiftUI

/// A background for the screen. To add one: write a type that conforms, and list it in `Backgrounds.all`.
protocol SaverBackground {
    /// The value kept in the settings.
    var kind: BackgroundKind { get }
    /// True when text over it needs a dark backing: a photo can be any color.
    var needsBacking: Bool { get }
    /// `muted`: something waits on the owner, so the background gives up its color and amber is the only one.
    func view(screenIndex: Int, muted: Bool) -> AnyView
}

enum Backgrounds {
    static func all(_ settings: Settings) -> [SaverBackground] {
        [SolidBackground(color: Color(nsColor: NSColor(hex: settings.solidColor))),
         SlideshowBackground(folder: settings.photoFolder, seconds: settings.secondsPerPhoto,
                             fallback: Color(nsColor: NSColor(hex: settings.solidColor)))]
    }

    static func current(_ settings: Settings) -> SaverBackground {
        let all = all(settings)
        return all.first { $0.kind == settings.background } ?? all[0]
    }
}

struct SolidBackground: SaverBackground {
    let color: Color
    var kind: BackgroundKind { .solid }
    var needsBacking: Bool { false }
    func view(screenIndex: Int, muted: Bool) -> AnyView { AnyView(color) }
}
