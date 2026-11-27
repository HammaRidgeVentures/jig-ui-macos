import SwiftUI
import JigScreenCore

/// The whole screen on one display: a background, the clock top left, the panel bottom right.
struct SaverRootView: View {
    let screenIndex: Int
    @EnvironmentObject private var store: StatusStore
    @EnvironmentObject private var session: SaverSession
    @EnvironmentObject private var settings: Settings

    var body: some View {
        GeometryReader { geo in
            // A big display is read from further away: grow everything with it.
            let scale = min(1.6, max(1, geo.size.height / 1000))
            let background = Backgrounds.current(settings)
            let someoneWaits = store.status?.items.contains { $0.state == .waitingUser } ?? false
            ZStack {
                background.view(screenIndex: screenIndex, muted: someoneWaits)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let now = timeline.date
                    let drift = Drift.offset(at: now)
                    ZStack {
                        ClockView(now: now, scale: scale, backed: background.needsBacking)
                            .offset(drift)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        StatusPanel(board: store.status.map { Board($0, now: now, idleSince: session.idleSince) },
                                    log: store.log, problem: store.problem, now: now, scale: scale, backed: background.needsBacking)
                            .offset(x: -drift.width, y: -drift.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .padding(44 * scale)
                    .animation(.easeInOut(duration: 4), value: drift)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

/// Burn-in guard: the clock and the panel move a few points every 3 minutes.
enum Drift {
    static let every: TimeInterval = 180

    static func offset(at date: Date) -> CGSize {
        let step = Int(date.timeIntervalSinceReferenceDate / every)
        // Two step sizes that share no factor with their ranges, so the path covers the whole box.
        return CGSize(width: CGFloat((step * 5) % 13) - 6, height: CGFloat((step * 7) % 11) - 5)
    }
}

/// The colors of the screen. It is white on dark. Amber shows only when something waits on the owner.
enum Ink {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.74)
    static let label = Color.white.opacity(0.66)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.0)
    static let stalled = Color(red: 1.0, green: 0.33, blue: 0.29)
}

/// The backing behind text. Over a photo it is dark enough for white text to pass WCAG AA
/// (4.5 to 1) on a pure white picture. Over a solid color it is a faint card.
struct Backing: ViewModifier {
    let backed: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
        content.background(
            shape.fill(backed ? Color.black.opacity(0.72) : Color.white.opacity(0.045))
                .overlay(shape.strokeBorder(Color.white.opacity(backed ? 0.16 : 0.09), lineWidth: 1))
        )
    }
}
