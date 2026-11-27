import SwiftUI

struct ClockView: View {
    let now: Date
    let scale: CGFloat
    let backed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 88 * scale, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Ink.primary)
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 22 * scale, weight: .medium))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, backed ? 26 * scale : 0)
        .padding(.vertical, backed ? 16 * scale : 0)
        .modifier(ClockBacking(backed: backed, scale: scale))
    }
}

/// The clock has a backing only over a photo.
private struct ClockBacking: ViewModifier {
    let backed: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        if backed { content.modifier(Backing(backed: true, scale: scale)) } else { content }
    }
}
