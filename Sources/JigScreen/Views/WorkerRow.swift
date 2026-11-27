import SwiftUI
import JigScreenCore

/// One agent under "Working": a live pulse, its name and time, its task, and a strip of its last 12 minutes.
struct WorkerRow: View {
    let worker: Board.Worker
    /// Tool calls a minute, oldest first.
    let bars: [Int]
    let now: Date
    let scale: CGFloat

    private func size(_ points: CGFloat) -> CGFloat { points * scale }

    var body: some View {
        let pulse = worker.pulse(at: now)
        HStack(alignment: .top, spacing: size(10)) {
            PulseOrb(pulse: pulse, scale: scale, offset: PulseOrb.offset(for: worker.name))
                .padding(.top, size(-1))
            VStack(alignment: .leading, spacing: size(2)) {
                HStack(alignment: .firstTextBaseline, spacing: size(8)) {
                    Text(worker.name)
                        .font(.system(size: size(17), weight: .semibold))
                        .foregroundStyle(pulse == .quiet ? Ink.secondary : Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: size(6))
                    if pulse == .stalled {
                        Text("stalled")
                            .font(.system(size: size(15), weight: .heavy))
                            .foregroundStyle(Ink.stalled)
                    }
                    Text(Elapsed.short(from: worker.since, to: now))
                        .font(.system(size: size(16), weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Ink.secondary)
                }
                Text(worker.task)
                    .font(.system(size: size(15)))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                HStack(alignment: .center, spacing: size(9)) {
                    ActivityStrip(bars: bars, pulse: pulse, scale: scale)
                    Text(doing(pulse))
                        .font(.system(size: size(14), weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Ink.label)
                        .lineLimit(1)
                }
                .padding(.top, size(3))
            }
        }
    }

    /// The words beside the strip: what the agent does now, or how long it has been still.
    private func doing(_ pulse: Board.Pulse) -> String {
        switch pulse {
        case .active: return worker.action ?? "working"
        // A long gap after a tool call is a long step, or the model at work on its answer.
        case .steady: return worker.action.map { $0 == "thinking" ? $0 : "\($0) · \(Elapsed.short(from: worker.heartbeat, to: now))" } ?? "working"
        case .quiet: return "quiet for \(Elapsed.short(from: worker.heartbeat, to: now))"
        case .stalled: return "silent for \(Elapsed.short(from: worker.heartbeat, to: now))"
        }
    }
}

/// The live dot beside an agent. Its rhythm says how long ago the agent last called a tool:
/// a quick ping when it just did, a slow breath while it thinks, still when it is quiet, a red ring when stalled.
struct PulseOrb: View {
    let pulse: Board.Pulse
    let scale: CGFloat
    /// A share of a beat, so two agents don't pulse in step.
    let offset: Double
    @Environment(\.accessibilityReduceMotion) private var still

    static func offset(for name: String) -> Double {
        Double(name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 997 }) / 997
    }

    var body: some View {
        let moving = (pulse == .active || pulse == .steady) && !still
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                PulseOrb.draw(pulse, in: &context, size: size, time: time, offset: offset, moving: moving)
            }
        }
        .frame(width: 24 * scale, height: 24 * scale)
        .accessibilityHidden(true)
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    static func draw(_ pulse: Board.Pulse, in context: inout GraphicsContext, size: CGSize, time: Double, offset: Double, moving: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = size.width / 24
        switch pulse {
        case .active:
            // A ring leaves the dot about once a second and fades as it grows.
            let phase = moving ? (time / 1.15 + offset).truncatingRemainder(dividingBy: 1) : 0.45
            let eased = 1 - pow(1 - phase, 3)
            context.fill(circle(center, 8 * unit), with: .color(.white.opacity(0.10)))
            context.stroke(circle(center, (4.6 + 6.6 * eased) * unit),
                           with: .color(.white.opacity(0.75 * (1 - phase))), lineWidth: (1.8 - 0.8 * phase) * unit)
            let beat = moving ? sin(2 * .pi * phase) : 0
            context.fill(circle(center, (4.5 + 0.55 * beat) * unit), with: .color(.white))
        case .steady:
            // A slow breath: alive, with nothing new to report.
            let breath = moving ? 0.5 + 0.5 * sin(2 * .pi * (time / 2.8 + offset)) : 0.7
            context.fill(circle(center, (6.5 + 1.2 * breath) * unit), with: .color(.white.opacity(0.06 + 0.10 * breath)))
            context.fill(circle(center, 4.1 * unit), with: .color(.white.opacity(0.5 + 0.42 * breath)))
        case .quiet:
            context.fill(circle(center, 3.5 * unit), with: .color(.white.opacity(0.38)))
        case .stalled:
            context.stroke(circle(center, 4.4 * unit), with: .color(Ink.stalled), lineWidth: 1.9 * unit)
        }
    }
}

/// Twelve bars: the agent's tool calls in each of the last 12 minutes. The newest is on the right.
struct ActivityStrip: View {
    let bars: [Int]
    let pulse: Board.Pulse
    let scale: CGFloat

    var body: some View {
        // At least 4, so a single call is a small bar and not a full one.
        let top = Double(max(4, bars.max() ?? 0))
        HStack(alignment: .bottom, spacing: 2.5 * scale) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                // The square root lifts small counts, so one call still shows.
                let share = value == 0 ? 0 : (Double(value) / top).squareRoot()
                let recent = Double(index) / Double(max(1, bars.count - 1))
                RoundedRectangle(cornerRadius: 1.5 * scale, style: .continuous)
                    .fill(Color.white.opacity(value == 0 || pulse == .stalled ? 0.20 : 0.34 + 0.66 * recent))
                    .frame(width: 4 * scale, height: (2 + 14 * share) * scale)
            }
        }
        .frame(height: 16 * scale, alignment: .bottom)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: bars)
        .accessibilityHidden(true)
    }
}

/// The big count under "Waiting on you". Above zero it is amber and breathes slowly, to catch the eye from far off.
struct WaitingCount: View {
    let count: Int
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let some = count > 0
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !some || still)) { timeline in
            let breath = some && !still ? 0.5 + 0.5 * sin(2 * .pi * timeline.date.timeIntervalSinceReferenceDate / 3.2) : 1
            Text("\(count)")
                .font(.system(size: 84 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(some ? Ink.amber.opacity(0.82 + 0.18 * breath) : Color.white.opacity(0.4))
                .shadow(color: some ? Ink.amber.opacity(0.10 + 0.30 * breath) : .clear, radius: 22 * scale)
                .frame(height: 84 * scale)
        }
    }
}
