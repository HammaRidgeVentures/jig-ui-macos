import Foundation

/// What the panel shows, worked out from a status file at one moment.
public struct Board: Equatable {
    public struct Wait: Equatable, Identifiable {
        public var id: String
        public var title: String
        public var kind: StatusFile.Kind
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

        /// How lively the agent is at `now`. The screen's pulse follows it.
        public func pulse(at now: Date) -> Pulse { Pulse(heartbeat: heartbeat, now: now) }
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

    public var waitingCount: Int
    /// The three that have waited longest.
    public var waiting: [Wait]
    public var workers: [Worker]
    public var queued: Int
    /// Done since the owner went idle.
    public var done: Int
    public var failed: Int
    public var updatedAt: Date

    public init(_ status: StatusFile, now: Date, idleSince: Date) {
        let waits = status.items
            .filter { $0.state == .waitingUser }
            .sorted { ($0.waitingSince ?? .distantFuture) < ($1.waitingSince ?? .distantFuture) }
        waitingCount = waits.count
        waiting = waits.prefix(3).map { Wait(id: $0.id, title: $0.title, kind: $0.kind, since: $0.waitingSince) }

        // An agent that waits on the owner is not working: it shows above, not here.
        let waitingAgents = Set(waits.compactMap(\.agent))
        let byID = Dictionary(status.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        workers = status.agents
            .filter { !waitingAgents.contains($0.name) }
            .map { agent in
                let item = agent.currentItemId.flatMap { byID[$0] }
                let stalled = agent.lastHeartbeat.map { now.timeIntervalSince($0) > Board.stallAfter } ?? false
                return Worker(name: agent.name, task: item?.title ?? "—", since: item?.startedAt, stalled: stalled,
                              heartbeat: agent.lastHeartbeat, action: Activity.words(for: agent.activity))
            }
            .sorted { a, b in
                if a.stalled != b.stalled { return a.stalled }
                return (a.since ?? .distantFuture) < (b.since ?? .distantFuture)
            }

        queued = status.items.filter { $0.state == .queued }.count
        done = status.items.filter { $0.state == .done && ($0.completedAt ?? .distantPast) >= idleSince }.count
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
    }

    /// The density for this many agents. A waiting list takes room, so each step comes sooner beside one:
    /// full rows for up to 4 agents (5 with nothing waiting), two-line rows up to 6 (8), then the grid.
    public var density: Density {
        let waiting = waitingCount > 0
        if workers.count <= (waiting ? 4 : 5) { return .full }
        return workers.count <= (waiting ? 6 : 8) ? .medium : .compact
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
