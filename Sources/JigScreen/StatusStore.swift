import Foundation
import Combine
import JigScreenCore

/// Loads the status from the chosen source, and loads it again while the screen shows.
final class StatusStore: ObservableObject {
    @Published private(set) var status: StatusFile?
    /// Why the last load failed, in a few words. Nil after a good load.
    @Published private(set) var problem: String?

    private var timer: Timer?
    private var loading = false
    private let queue = DispatchQueue(label: "jig-screen.status", qos: .utility)

    /// A file or a URL is read every 15 seconds. `jig status --json` asks GitHub, so it runs once a minute.
    private var interval: TimeInterval { Settings.shared.source == .jig ? 60 : 15 }

    func startPolling() {
        stopPolling()
        refresh()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Puts a status in place by hand. A snapshot run uses it.
    func set(_ file: StatusFile) { status = file; problem = nil }

    func refresh() {
        guard !loading else { return }
        loading = true
        let source = Settings.shared.source
        queue.async {
            let result = Result { try StatusStore.load(source) }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let file): self.status = file; self.problem = nil
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
            return try StatusFile.decode(Data(contentsOf: url)).moved(to: Date())
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
