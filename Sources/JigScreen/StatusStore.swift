import Foundation
import Combine
import JigScreenCore

/// Loads the status from the chosen source, and loads it again while the screen shows.
final class StatusStore: ObservableObject {
    @Published private(set) var status: StatusFile?
    /// Why the last load failed, in a few words. Nil after a good load.
    @Published private(set) var problem: String?
    /// Each agent's tool calls, minute by minute, kept from one load to the next.
    @Published private(set) var log = ActivityLog()
    private var logSource: DataSource?

    private var timer: Timer?
    private var loading = false
    private let queue = DispatchQueue(label: "jig-screen.status", qos: .utility)

    /// While the screen shows, every source is read every 15 seconds. `jig status --json` keeps GitHub's
    /// answers for 45 seconds, so that is cheap. While the screen is away, once a minute is enough for the icon.
    private func interval(showing: Bool) -> TimeInterval { showing ? 15 : 60 }

    func startPolling(showing: Bool) {
        stopPolling()
        refresh()
        let t = Timer(timeInterval: interval(showing: showing), repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Puts a status in place by hand. A snapshot run uses it.
    func set(_ file: StatusFile) { took(file, from: .sample) }

    private func took(_ file: StatusFile, from source: DataSource) {
        let now = Date()
        // Another source is another set of agents: start the history over.
        if logSource != source {
            log = ActivityLog()
            logSource = source
            if source == .sample || source == .crowd { StatusStore.seed(&log, for: file, at: now) }
        }
        log.record(file, at: now)
        status = file
        problem = nil
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        let source = Settings.shared.source
        queue.async {
            let result = Result { try StatusStore.load(source) }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let file): self.took(file, from: source)
                case .failure(let error): self.problem = StatusStore.words(for: error)
                }
            }
        }
    }

    /// Reads one source, on the caller's thread.
    static func load(_ source: DataSource) throws -> StatusFile {
        switch source {
        case .sample:
            guard let url = sampleURL() else { throw Problem("the sample file is missing") }
            return enliven(try StatusFile.decode(Data(contentsOf: url)).moved(to: Date()), at: Date())
        case .crowd:
            guard let url = sampleURL() else { throw Problem("the sample file is missing") }
            let now = Date()
            return enliven(crowded(try StatusFile.decode(Data(contentsOf: url)).moved(to: now), workers: 12, at: now), at: now)
        case .file(let path):
            return try StatusFile.decode(Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)))
        case .url(let text):
            guard let url = URL(string: text), ["http", "https"].contains(url.scheme ?? "") else {
                throw Problem("not a web address")
            }
            return try StatusFile.decode(fetch(url))
        case .jig:
            return try StatusFile.decode(runJig())
        }
    }

    /// The sample file never changes, so the screen would sit still. This gives its agents a made-up
    /// rhythm from the clock: one busy, one slow. A stalled agent stays stalled.
    static func enliven(_ file: StatusFile, at now: Date) -> StatusFile {
        var copy = file
        let time = now.timeIntervalSince1970
        let tools = ["Bash", "Edit", "Read", "Grep", "", "Bash", "Edit"]
        for index in copy.agents.indices {
            guard let beat = copy.agents[index].lastHeartbeat, now.timeIntervalSince(beat) < Board.stallAfter else { continue }
            let pace = samplePace(index)
            copy.agents[index].toolCalls = Int(time / pace)
            copy.agents[index].lastHeartbeat = now.addingTimeInterval(-time.truncatingRemainder(dividingBy: pace))
            copy.agents[index].activity = tools[(Int(time / max(20, pace)) + index * 2) % tools.count]
        }
        return copy
    }

    /// Seconds between a sample agent's tool calls: some busy, some slow, some nearly quiet.
    private static func samplePace(_ index: Int) -> Double {
        let paces = [13.0, 7.0, 75.0, 5.0, 28.0, 9.0, 240.0, 18.0, 45.0, 11.0, 150.0, 6.0]
        return paces[index % paces.count]
    }

    /// The sample with more agents at work, until `workers` of them show under "Working".
    /// Every seventh one is stalled, so a full house shows each state.
    static func crowded(_ file: StatusFile, workers: Int, at now: Date) -> StatusFile {
        var copy = file
        let names = ["api", "api 2", "billing", "mobile", "search", "infra", "blog", "mail", "auth", "reports", "admin", "sync", "cache", "forms"]
        let tasks = ["Add rate limits to the public API", "Move invoices to the new template", "Fix the login loop on small phones",
                     "Rank exact matches first", "Rotate the build cache weekly", "Write the launch post", "Retry a bounced receipt",
                     "Drop the old session cookie", "Cut the weekly report query time", "Add bulk edit to the orders table",
                     "Sync stock every 5 minutes", "Warm the cache after a deploy", "Check every form for a label", "Tidy the 404 page"]
        var index = 0
        while Board(copy, now: now, idleSince: now).workers.count < workers, index < names.count {
            let id = "sample:\(index)"
            let stalled = index % 7 == 4
            copy.items.append(.init(id: id, title: tasks[index], kind: .task, state: .working, agent: names[index],
                                    startedAt: now.addingTimeInterval(-Double(4 + index * 7) * 60)))
            copy.agents.append(.init(name: names[index], currentItemId: id,
                                     lastHeartbeat: now.addingTimeInterval(stalled ? -14 * 60 : -5), activity: "Bash", toolCalls: 0))
            index += 1
        }
        return copy
    }

    /// A made-up last 12 minutes for the sample's agents, so the strips are not empty at first sight.
    private static func seed(_ log: inout ActivityLog, for file: StatusFile, at now: Date) {
        for (index, agent) in file.agents.enumerated() {
            guard let beat = agent.lastHeartbeat, now.timeIntervalSince(beat) < Board.stallAfter else { continue }
            let perMinute = 60 / samplePace(index)
            let bars = (0..<12).map { minute in
                max(0, Int((perMinute * (0.62 + 0.55 * sin(Double(minute) * 1.7 + Double(index) * 2.1))).rounded()))
            }
            log.seed(agent.name, bars: bars, at: now)
        }
    }

    /// The sample ships in the app's Resources. A build run from the repo reads `mock/status.json`.
    static func sampleURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "mock-status", withExtension: "json") { return bundled }
        let local = URL(fileURLWithPath: "mock/status.json")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    private static func fetch(_ url: URL) throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let done = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(Problem("no answer"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(Problem("the server said \(http.statusCode)"))
            } else if let data { result = .success(data) }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    /// Runs Jig's own tool in a login shell, so `gh` and `jq` are on the PATH.
    private static func runJig() throws -> Data {
        let tool = ("~/.claude/jig/bin/jig" as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: tool) else { throw Problem("Jig is not set up on this Mac") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \"$0\" status --json", tool]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Problem(process.terminationStatus == 2 ? "GitHub can't be reached" : "jig status failed")
        }
        return data
    }

    struct Problem: Error, LocalizedError {
        var text: String
        init(_ text: String) { self.text = text }
        var errorDescription: String? { text }
    }

    private static func words(for error: Error) -> String {
        if error is DecodingError { return "the status is not in the right shape" }
        return error.localizedDescription
    }
}
