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
            // Everything grows and shrinks with the display's height, so the panel takes the same
            // share of any screen: a full panel fits a small laptop, and a big display reads from far off.
            let scale = min(1.6, max(0.85, geo.size.height / 980))
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
                        StatusPanel(board: store.status.map { Board($0, now: now) },
                                    log: store.log, problem: store.problem, now: now, scale: scale, backed: background.needsBacking,
                                    room: Board.Layout.room(height: geo.size.height, scale: scale),
                                    desk: store.status?.desk, open: session.open)
                            .offset(x: -drift.width, y: -drift.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .padding(44 * scale)
                    .animation(.easeInOut(duration: 4), value: drift)
                }
                if session.pointerShown {
                    CloseHint(desk: store.status?.desk != nil, scale: scale, backed: background.needsBacking)
                        .padding(44 * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: session.pointerShown)
            .frame(width: geo.size.width, height: geo.size.height)
            // A click on any place that is not a link closes the screen.
            .contentShape(Rectangle())
            .onTapGesture { session.close() }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

/// Bottom left, while the pointer shows: how to close the screen, and what a click opens.
struct CloseHint: View {
    let desk: Bool
    let scale: CGFloat
    let backed: Bool

    var body: some View {
        Text(desk ? "Click Decisions to open the desk · click anywhere else or press a key to close"
                  : "Click anywhere or press a key to close")
            .font(.system(size: 15 * scale, weight: .medium))
            .foregroundStyle(Ink.secondary)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 9 * scale)
            .modifier(Backing(backed: backed, scale: scale))
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

/// The colors of the screen. It is white on dark. The three session colors are the three session
/// lights: red is blocked on the owner, blue is working, green is done. Amber marks an issue that
/// waits on the owner. A count of zero has no color.
enum Ink {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.74)
    static let label = Color.white.opacity(0.66)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.0)
    static let blocked = Color(red: 1.0, green: 0.36, blue: 0.32)
    static let working = Color(red: 0.42, green: 0.72, blue: 1.0)
    static let done = Color(red: 0.36, green: 0.86, blue: 0.52)
    static let stalled = blocked
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
