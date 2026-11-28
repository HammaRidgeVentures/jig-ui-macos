import Foundation

/// What the panel shows, worked out from a status file at one moment.
///
/// It sorts every session into one of three: blocked on the owner, working, or done. Then it
/// counts the issues outside the sessions: the ones that wait on the owner, the ones to do,
/// and the ones shipped today.
public struct Board: Equatable {
    /// A session that is blocked on the owner: at a question, a plan or a permission prompt,
    /// or stopped with an ask.
    public struct Wait: Equatable, Identifiable {
        public var id: String
        public var title: String
        public var kind: StatusFile.Kind
        public var since: Date?
        /// The session's name. Nil: not known.
        public var agent: String?
        /// The issue the session works on, short: "#42". Nil: none.
        public var issue: String?

        /// The small line under the title: "shop · #42".
        public var origin: String { [agent, issue].compactMap { $0 }.joined(separator: " · ") }
    }

    /// A session that is done and waits to be archived.
    public struct Finished: Equatable, Identifiable {
        public var id: String
        public var title: String
        public var agent: String?
        public var since: Date?
    }

    public struct Worker: Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        public var task: String
        public var since: Date?
        public var stalled: Bool
        public var heartbeat: Date?
        /// What the agent is doing now, in plain words: "running a command". Nil: not known.
        public var action: String?
        /// The issue the agent works on, short: "#42". Nil: the session has no issue.
        public var issue: String?
        /// Its turn ended and work it started still runs. It calls no tool, so it has no heartbeat.
        public var background: Bool = false

        /// The task with its issue in front: "#42 · Fix the cart total".
        public var line: String { issue.map { "\($0) · \(task)" } ?? task }

        /// How lively the agent is at `now`. The screen's pulse follows it.
        public func pulse(at now: Date) -> Pulse { background ? .steady : Pulse(heartbeat: heartbeat, now: now) }
    }

    /// How long ago an agent last called a tool, as four steps.
    public enum Pulse: Equatable {
        /// A tool call in the last 30 seconds.
        case active
        /// Up to 3 minutes: it is thinking, or one long step runs. Also when no heartbeat is known.
        case steady
        /// Up to 10 minutes with no tool call.
        case quiet
        /// More than 10 minutes.
        case stalled

        public init(heartbeat: Date?, now: Date) {
            guard let heartbeat else { self = .steady; return }
            let age = now.timeIntervalSince(heartbeat)
            if age > Board.stallAfter { self = .stalled }
            else if age > 180 { self = .quiet }
            else if age > 30 { self = .steady }
            else { self = .active }
        }
    }

    /// An agent is stalled when its last heartbeat is older than this.
    public static let stallAfter: TimeInterval = 10 * 60
    /// The panel dims when the data is older than this.
    public static let staleAfter: TimeInterval = 2 * 60

    /// The sessions blocked on the owner, longest wait first.
    public var blocked: [Wait]
    public var workers: [Worker]
    /// The sessions that are done, newest first.
    public var finished: [Finished]
    /// Issues that wait on the owner, outside every session.
    public var decisions: Int
    /// Issues an agent can take.
    public var queued: Int
    /// Issues closed today, by the calendar's day.
    public var shipped: Int
    public var failed: Int
    public var updatedAt: Date

    /// Everything that waits on the owner: the blocked sessions and the issues.
    public var waitingCount: Int { blocked.count + decisions }

    /// "owner/name#42" → "#42". Nil for an id that is no issue.
    public static func shortIssue(_ id: String?) -> String? {
        guard let id, !id.hasPrefix("session:"), let hash = id.lastIndex(of: "#"),
              !id[id.index(after: hash)...].isEmpty, id[id.index(after: hash)...].allSatisfy(\.isNumber) else { return nil }
        return String(id[hash...])
    }

    /// An item that is a session, not an issue: Jig gives it the id "session:<id>", and only a
    /// session's waiting or done item names an agent.
    private static func isSession(_ item: StatusFile.Item) -> Bool {
        item.id.hasPrefix("session:") || item.agent != nil
    }

    public init(_ status: StatusFile, now: Date, calendar: Calendar = .current) {
        let waits = status.items
            .filter { $0.state == .waitingUser }
            .sorted { ($0.waitingSince ?? .distantFuture) < ($1.waitingSince ?? .distantFuture) }
        let sessionWaits = waits.filter(Board.isSession)
        blocked = sessionWaits.map {
            Wait(id: $0.id, title: $0.title, kind: $0.kind, since: $0.waitingSince, agent: $0.agent,
                 issue: Board.shortIssue($0.issue))
        }
        decisions = waits.count - sessionWaits.count

        // An agent that waits on the owner is not working: it shows above, not here.
        let waitingAgents = Set(waits.compactMap(\.agent))
        let byID = Dictionary(status.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        workers = status.agents
            .filter { !waitingAgents.contains($0.name) }
            .map { agent in
                let item = agent.currentItemId.flatMap { byID[$0] }
                let background = agent.background ?? false
                let heartbeat = background ? nil : agent.lastHeartbeat
                let stalled = heartbeat.map { now.timeIntervalSince($0) > Board.stallAfter } ?? false
                return Worker(name: agent.name, task: item?.title ?? "—", since: item?.startedAt, stalled: stalled,
                              heartbeat: heartbeat, action: Activity.words(for: agent.activity),
                              issue: Board.shortIssue(agent.currentItemId), background: background)
            }
            .sorted { a, b in
                if a.stalled != b.stalled { return a.stalled }
                return (a.since ?? .distantFuture) < (b.since ?? .distantFuture)
            }

        let done = status.items.filter { $0.state == .done }
        finished = done.filter(Board.isSession)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .map { Finished(id: $0.id, title: $0.title, agent: $0.agent, since: $0.completedAt) }
        shipped = done.filter { item in
            !Board.isSession(item) && item.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }.count

        queued = status.items.filter { $0.state == .queued }.count
        failed = status.items.filter { $0.state == .failed }.count
        updatedAt = status.updatedAt
    }

    /// How much room one agent gets under "Working". More agents, less room each.
    public enum Density: Equatable {
        /// Three lines: name and time, the task, the strip and what the agent does now.
        case full
        /// Two lines: name and time, then the strip and the task.
        case medium
        /// A cell in a two-column grid: the pulse, the name, the time, and the strip.
        case compact

        /// The most agents the panel shows at this density. The rest are a "+ N more" line.
        public var limit: Int {
            switch self {
            case .full: return 5
            case .medium: return 8
            case .compact: return 16
            }
        }

        /// The height of `count` agents at this density, in points before scaling.
        func height(of count: Int) -> Double {
            switch self {
            case .full: return Double(count) * Layout.fullRow
            case .medium: return Double(count) * Layout.mediumRow
            case .compact: return Double((count + 1) / 2) * Layout.gridRow
            }
        }
    }

    /// How many rows of each list the panel shows, so the whole panel fits the display.
    /// The lists take room in the owner's order: blocked first, then working, then done.
    public struct Layout: Equatable {
        public var blocked: Int
        public var density: Density
        public var workers: Int
        public var finished: Int

        public init(blocked: Int, density: Density, workers: Int, finished: Int) {
            self.blocked = blocked
            self.density = density
            self.workers = workers
            self.finished = finished
        }

        /// The room for the three lists on a display 900 points high, in points before scaling.
        public static let room = 640.0

        /// The room for the three lists on a display of this height, drawn at this scale.
        /// The panel is as tall as the display less its margins (88). The counts on top, the
        /// footer and the padding take 215. 30 more stay free, for a title that runs long.
        /// Every number here and below is measured from a drawn panel.
        public static func room(height: Double, scale: Double) -> Double { height / scale - 333 }
        /// A list's heading, with the gap and the rule above it.
        static let heading = 60.0
        /// The blocked list sits right under the counts, with no rule.
        static let blockedHeading = 41.0
        /// A blocked row at its tallest: a title of two lines, then the session's name.
        static let blockedRow = 68.0
        static let fullRow = 74.0
        static let mediumRow = 50.0
        static let gridRow = 41.0
        static let finishedRow = 29.0
        static let moreLine = 24.0
    }

    public func layout(room: Double = Layout.room) -> Layout {
        let shownBlocked = min(3, blocked.count)
        var room = room
        if shownBlocked > 0 {
            room -= Layout.blockedHeading + Double(shownBlocked) * Layout.blockedRow
            if blocked.count > shownBlocked { room -= Layout.moreLine }
        }
        room -= Layout.heading  // "Working" always shows, with a line when nobody works.

        // Do these agents fit at this density, beside `rows` done rows?
        func fits(_ density: Density, _ rows: Int) -> Bool {
            guard workers.count <= density.limit else { return false }
            var left = room - density.height(of: workers.count)
            if rows > 0 {
                left -= Layout.heading + Double(rows) * Layout.finishedRow
                if finished.count > rows { left -= Layout.moreLine }
            }
            return left >= 0
        }
        // Working comes before done, so the done list gives way first. One step is fair the other
        // way: a two-line agent row beside a done row beats a three-line row and no done row.
        let wanted = min(2, finished.count)
        let order: [(Density, Int)] = [(.full, 2), (.full, 1), (.medium, 2), (.medium, 1), (.full, 0), (.medium, 0),
                                       (.compact, 2), (.compact, 1), (.compact, 0)]
        for (density, rows) in order where rows <= wanted && fits(density, rows) {
            return Layout(blocked: shownBlocked, density: density, workers: workers.count, finished: rows)
        }
        // Too many agents for the room: a grid of what fits, and a "+ N more" line.
        let rows = max(1, Int((room - Layout.moreLine) / Layout.gridRow))
        return Layout(blocked: shownBlocked, density: .compact,
                      workers: min(workers.count, rows * 2, Density.compact.limit), finished: 0)
    }

    /// Agents at work whose heartbeat is fresh.
    public var running: Int { workers.filter { !$0.stalled }.count }

    public func isStale(now: Date) -> Bool { now.timeIntervalSince(updatedAt) > Board.staleAfter }
}

public enum Elapsed {
    /// A short length of time: "45s", "12m", "1h 05m", "2d 3h".
    public static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h \(String(format: "%02d", (s % 3600) / 60))m" }
        return "\(s / 86400)d \((s % 86400) / 3600)h"
    }

    public static func short(from start: Date?, to now: Date) -> String {
        guard let start else { return "" }
        return short(now.timeIntervalSince(start))
    }
}

public enum Activity {
    /// A tool's name as plain words for the screen. Nil stays nil: an older writer sends no tool.
    public static func words(for tool: String?) -> String? {
        guard let tool else { return nil }
        if tool.isEmpty { return "thinking" }
        switch tool {
        case "Bash", "BashOutput", "KillShell": return "running a command"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "editing files"
        case "Read": return "reading files"
        case "Grep", "Glob", "LS", "ToolSearch": return "searching"
        case "WebFetch", "WebSearch": return "reading the web"
        case "Agent", "Task": return "running a helper agent"
        case "TodoWrite": return "planning"
        case "AskUserQuestion", "ExitPlanMode": return "asking you"
        default: break
        }
        let lower = tool.lowercased()
        if lower.contains("browser") || lower.contains("chrome") || lower.contains("playwright") { return "using the browser" }
        if lower.contains("plan") { return "planning" }
        return lower.hasPrefix("mcp__") ? "using a tool" : "working"
    }
}

/// How many tools each agent called, minute by minute. The screen draws it as a strip of bars.
/// A status file holds only the latest count, so the app keeps the history itself.
public struct ActivityLog: Equatable {
    public static let minute: TimeInterval = 60

    private struct Seen: Equatable {
        var calls: Int?
        var beat: Date?
    }

    private var seen: [String: Seen] = [:]
    /// Agent name → minute number → tool calls in that minute.
    private var counts: [String: [Int: Int]] = [:]

    public init() {}

    private static func index(_ date: Date) -> Int { Int(date.timeIntervalSinceReferenceDate / minute) }

    /// Takes one loaded status. The calls since the load before it go into the minute of `now`.
    public mutating func record(_ status: StatusFile, at now: Date) {
        let index = ActivityLog.index(now)
        for agent in status.agents {
            var added = 0
            if let before = seen[agent.name] {
                if let calls = agent.toolCalls, let old = before.calls {
                    added = max(0, calls - old)
                } else if agent.toolCalls == nil, let beat = agent.lastHeartbeat, beat != before.beat {
                    // A writer with no count: a new heartbeat is one sign of work.
                    added = 1
                }
            }
            seen[agent.name] = Seen(calls: agent.toolCalls, beat: agent.lastHeartbeat)
            if added > 0 { counts[agent.name, default: [:]][index, default: 0] += added }
        }
        // Forget an agent that is gone, and minutes too old to draw.
        let names = Set(status.agents.map(\.name))
        seen = seen.filter { names.contains($0.key) }
        counts = counts.filter { names.contains($0.key) }.mapValues { $0.filter { $0.key > index - 30 } }
    }

    /// The last `count` minutes for one agent, oldest first. The last value is the minute of `now`.
    public func bars(for name: String, at now: Date, count: Int = 12) -> [Int] {
        let index = ActivityLog.index(now)
        return (0..<count).map { counts[name]?[index - (count - 1) + $0] ?? 0 }
    }

    /// Tool calls a minute across every agent, over the last 3 minutes.
    public func rate(at now: Date) -> Int {
        let index = ActivityLog.index(now)
        let total = counts.values.reduce(0) { sum, minutes in sum + (0..<3).reduce(0) { $0 + (minutes[index - $1] ?? 0) } }
        return Int((Double(total) / 3).rounded())
    }

    /// Puts a history in place for one agent, oldest first. The sample data uses it.
    public mutating func seed(_ name: String, bars: [Int], at now: Date) {
        let index = ActivityLog.index(now)
        for (offset, value) in bars.enumerated() where value > 0 {
            counts[name, default: [:]][index - (bars.count - 1) + offset] = value
        }
    }
}
