import Foundation

/// The status file: what every agent is doing. `jig status --json` writes this shape.
public struct StatusFile: Decodable, Equatable {
    public var updatedAt: Date
    public var items: [Item]
    public var agents: [Agent]

    public struct Item: Decodable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var kind: Kind
        public var state: State
        public var agent: String?
        public var startedAt: Date?
        public var waitingSince: Date?
        public var completedAt: Date?
    }

    public struct Agent: Decodable, Equatable {
        public var name: String
        public var currentItemId: String?
        public var lastHeartbeat: Date?
    }

    /// A word this app doesn't know reads as `.other`, so a newer writer never breaks the screen.
    public enum Kind: String, Decodable {
        case question, approval, task, other
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
        }
    }

    public enum State: String, Decodable {
        case queued, working, waitingUser = "waiting_user", done, failed, other
        public init(from decoder: Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
        }
    }

    public enum ReadError: Error, LocalizedError {
        case badDate(String)
        public var errorDescription: String? {
            switch self { case .badDate(let s): return "not a date: \(s)" }
        }
    }

    /// Reads the JSON. A time is ISO 8601, with or without fractions of a second.
    public static func decode(_ data: Data) throws -> StatusFile {
        let decoder = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            if let date = plain.date(from: text) ?? fractional.date(from: text) { return date }
            throw ReadError.badDate(text)
        }
        return try decoder.decode(StatusFile.self, from: data)
    }

    /// The same file with every time moved, so `updatedAt` is `now`. The sample data uses it.
    public func moved(to now: Date) -> StatusFile {
        let by = now.timeIntervalSince(updatedAt)
        var copy = self
        copy.updatedAt = now
        copy.items = items.map { item in
            var i = item
            i.startedAt = item.startedAt?.addingTimeInterval(by)
            i.waitingSince = item.waitingSince?.addingTimeInterval(by)
            i.completedAt = item.completedAt?.addingTimeInterval(by)
            return i
        }
        copy.agents = agents.map { agent in
            var a = agent
            a.lastHeartbeat = agent.lastHeartbeat?.addingTimeInterval(by)
            return a
        }
        return copy
    }
}
