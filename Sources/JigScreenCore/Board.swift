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
                return Worker(name: agent.name, task: item?.title ?? "—", since: item?.startedAt, stalled: stalled)
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
