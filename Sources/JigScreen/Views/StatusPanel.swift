import SwiftUI
import JigScreenCore

/// The panel, bottom right: what waits on the owner, who is working, the counts, the data's age.
struct StatusPanel: View {
    let board: Board?
    let problem: String?
    let now: Date
    let scale: CGFloat
    let backed: Bool

    private func size(_ points: CGFloat) -> CGFloat { points * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: size(16)) {
            if let board {
                waiting(board)
                rule
                working(board)
                rule
                footer(board)
            } else {
                Text(problem == nil ? "Reading the status…" : "No status yet")
                    .font(.system(size: size(20), weight: .semibold))
                    .foregroundStyle(Ink.primary)
                if let problem {
                    Text(problem).font(.system(size: size(15))).foregroundStyle(Ink.secondary)
                }
            }
        }
        .padding(size(22))
        .frame(width: size(340), alignment: .leading)
        .modifier(Backing(backed: backed, scale: scale))
        // Old data is dimmed, so nobody trusts it from across the room.
        .opacity(board?.isStale(now: now) == true ? 0.42 : 1)
        .animation(.easeInOut(duration: 0.6), value: board?.isStale(now: now))
    }

    private var rule: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: size(13), weight: .bold))
            .tracking(size(1.4))
            .foregroundStyle(Ink.label)
    }

    // MARK: Waiting on you

    @ViewBuilder
    private func waiting(_ board: Board) -> some View {
        let some = board.waitingCount > 0
        VStack(alignment: .leading, spacing: size(8)) {
            heading("Waiting on you")
            Text("\(board.waitingCount)")
                .font(.system(size: size(84), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(some ? Ink.amber : Color.white.opacity(0.4))
                .frame(height: size(84))
            ForEach(board.waiting) { wait in
                HStack(alignment: .firstTextBaseline, spacing: size(8)) {
                    Image(systemName: wait.kind == .approval ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .font(.system(size: size(15), weight: .semibold))
                        .foregroundStyle(Ink.amber)
                    Text(wait.title)
                        .font(.system(size: size(17), weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: size(6))
                    Text(Elapsed.short(from: wait.since, to: now))
                        .font(.system(size: size(17), weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Ink.amber)
                }
            }
            if board.waitingCount > board.waiting.count {
                Text("+ \(board.waitingCount - board.waiting.count) more")
                    .font(.system(size: size(15), weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
        }
    }

    // MARK: Working

    @ViewBuilder
    private func working(_ board: Board) -> some View {
        let shown = board.workers.prefix(5)
        VStack(alignment: .leading, spacing: size(10)) {
            heading("Working")
            if board.workers.isEmpty {
                Text("No agent is working")
                    .font(.system(size: size(16)))
                    .foregroundStyle(Ink.secondary)
            }
            ForEach(Array(shown)) { worker in
                VStack(alignment: .leading, spacing: size(1)) {
                    HStack(alignment: .firstTextBaseline, spacing: size(8)) {
                        Text(worker.name)
                            .font(.system(size: size(17), weight: .semibold))
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        Spacer(minLength: size(6))
                        if worker.stalled {
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
                }
            }
            if board.workers.count > shown.count {
                Text("+ \(board.workers.count - shown.count) more")
                    .font(.system(size: size(15), weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
        }
    }

    // MARK: Footer

    private func footer(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: size(5)) {
            Text("\(board.queued) queued · \(board.done) done · \(board.failed) failed")
                .font(.system(size: size(16), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.primary)
            Text("updated \(Elapsed.short(from: board.updatedAt, to: now)) ago")
                .font(.system(size: size(14)))
                .monospacedDigit()
                .foregroundStyle(Ink.label)
        }
    }
}
