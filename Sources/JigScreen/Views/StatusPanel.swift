import SwiftUI
import JigScreenCore

/// The panel, bottom right. Top to bottom, in the owner's order: the three counts of sessions
/// (blocked, working, done), a list for each, then the issues outside the sessions.
struct StatusPanel: View {
    let board: Board?
    let log: ActivityLog
    let problem: String?
    let now: Date
    let scale: CGFloat
    let backed: Bool
    /// The room for the three lists, in points before scaling.
    var room: Double = Board.Layout.room
    /// The Decision Desk's link. "Decisions" opens it on a click. Nil: no desk, no link.
    var desk: URL? = nil
    var open: (URL) -> Void = { _ in }

    private func size(_ points: CGFloat) -> CGFloat { points * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: size(16)) {
            if let board {
                let layout = board.layout(room: room)
                counts(board)
                if layout.blocked > 0 { blocked(board, show: layout.blocked) }
                rule
                working(board, layout: layout)
                if layout.finished > 0 {
                    rule
                    finished(board, show: layout.finished)
                }
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

    private func heading(_ text: String, _ color: Color = Ink.label) -> some View {
        Text(text.uppercased())
            .font(.system(size: size(13), weight: .bold))
            .tracking(size(1.4))
            .foregroundStyle(color)
    }

    private func more(_ count: Int) -> some View {
        Text("+ \(count) more")
            .font(.system(size: size(15), weight: .medium))
            .foregroundStyle(Ink.secondary)
    }

    // MARK: The three counts

    private func counts(_ board: Board) -> some View {
        HStack(spacing: size(8)) {
            CountTile(count: board.blocked.count, label: "Blocked", color: Ink.blocked, breathes: true, scale: scale)
            CountTile(count: board.workers.count, label: "Working", color: Ink.working, breathes: false, scale: scale)
            CountTile(count: board.finished.count, label: "Done", color: Ink.done, breathes: false, scale: scale)
        }
    }

    // MARK: Blocked on you

    private func blocked(_ board: Board, show: Int) -> some View {
        VStack(alignment: .leading, spacing: size(9)) {
            heading("Blocked on you", Ink.blocked)
            ForEach(board.blocked.prefix(show)) { wait in
                HStack(alignment: .firstTextBaseline, spacing: size(8)) {
                    Image(systemName: wait.kind == .approval ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .font(.system(size: size(15), weight: .semibold))
                        .foregroundStyle(Ink.blocked)
                    VStack(alignment: .leading, spacing: size(2)) {
                        Text(wait.title)
                            .font(.system(size: size(17), weight: .semibold))
                            .foregroundStyle(Ink.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !wait.origin.isEmpty {
                            Text(wait.origin)
                                .font(.system(size: size(14)))
                                .foregroundStyle(Ink.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: size(6))
                    Text(Elapsed.short(from: wait.since, to: now))
                        .font(.system(size: size(17), weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Ink.blocked)
                        .fixedSize()
                }
            }
            if board.blocked.count > show { more(board.blocked.count - show) }
        }
    }

    // MARK: Working

    @ViewBuilder
    private func working(_ board: Board, layout: Board.Layout) -> some View {
        // More agents, less room each: full rows, then two-line rows, then a grid of cells.
        let density = layout.density
        let shown = Array(board.workers.prefix(layout.workers))
        let rate = log.rate(at: now)
        VStack(alignment: .leading, spacing: size(density == .full ? 12 : 10)) {
            HStack(alignment: .firstTextBaseline) {
                heading("Working", Ink.working)
                Spacer()
                if rate > 0 {
                    Text("\(rate) tool calls a min")
                        .font(.system(size: size(13), weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Ink.label)
                }
            }
            if board.workers.isEmpty {
                Text("No agent is working")
                    .font(.system(size: size(16)))
                    .foregroundStyle(Ink.secondary)
            }
            if density == .compact {
                let columns = [GridItem(.flexible(), spacing: size(16), alignment: .leading),
                               GridItem(.flexible(), alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: size(11)) {
                    ForEach(shown) { worker in
                        WorkerRow(worker: worker, bars: log.bars(for: worker.name, at: now), now: now, scale: scale, density: density)
                    }
                }
            } else {
                ForEach(shown) { worker in
                    WorkerRow(worker: worker, bars: log.bars(for: worker.name, at: now), now: now, scale: scale, density: density)
                }
            }
            if board.workers.count > shown.count { more(board.workers.count - shown.count) }
        }
    }

    // MARK: Done

    private func finished(_ board: Board, show: Int) -> some View {
        VStack(alignment: .leading, spacing: size(8)) {
            heading("Done · ready to archive", Ink.done)
            ForEach(board.finished.prefix(show)) { session in
                HStack(alignment: .firstTextBaseline, spacing: size(8)) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: size(14), weight: .semibold))
                        .foregroundStyle(Ink.done)
                    Text(session.title)
                        .font(.system(size: size(15)))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                    Spacer(minLength: size(6))
                    Text(Elapsed.short(from: session.since, to: now))
                        .font(.system(size: size(14), weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Ink.label)
                        .fixedSize()
                }
            }
            if board.finished.count > show { more(board.finished.count - show) }
        }
    }

    // MARK: Footer: the issues outside the sessions

    private func footer(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: size(8)) {
            HStack(alignment: .top, spacing: size(8)) {
                let decisions = stat(board.decisions, board.decisions == 1 ? "Decision" : "Decisions", board.decisions > 0 ? Ink.amber : nil)
                if let desk {
                    decisions
                        .contentShape(Rectangle())
                        .onTapGesture { open(desk) }
                        .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
                } else {
                    decisions
                }
                stat(board.queued, "To do", nil)
                stat(board.shipped, "Shipped today", nil)
            }
            Text("updated \(Elapsed.short(from: board.updatedAt, to: now)) ago" + (board.failed > 0 ? " · \(board.failed) failed" : ""))
                .font(.system(size: size(14)))
                .monospacedDigit()
                .foregroundStyle(Ink.label)
        }
    }

    /// One number of the footer with its label under it. A zero is dim. `color` marks a number that asks for the owner:
    /// "Decisions" are the issues that wait on the owner, in amber.
    private func stat(_ count: Int, _ label: String, _ color: Color?) -> some View {
        VStack(alignment: .leading, spacing: size(1)) {
            Text("\(count)")
                .font(.system(size: size(24), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(count == 0 ? Color.white.opacity(0.4) : (color ?? Ink.primary))
            Text(label)
                .font(.system(size: size(13), weight: .medium))
                .foregroundStyle(count == 0 ? Ink.label : (color ?? Ink.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
