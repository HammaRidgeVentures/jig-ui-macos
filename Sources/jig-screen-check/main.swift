// Checks for JigScreenCore. Run from the repo's top folder: swift run jig-screen-check
import Foundation
import JigScreenCore

var passed = 0, failed = 0
func check<T: Equatable>(_ name: String, _ want: T, _ got: T) {
    if want == got { passed += 1 } else { failed += 1; print("FAIL \(name)\n  want: \(want)\n  got:  \(got)") }
}

let data = try Data(contentsOf: URL(fileURLWithPath: "mock/status.json"))
let file = try StatusFile.decode(data)
let now = file.updatedAt
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(identifier: "UTC")!
let board = Board(file, now: now, calendar: utc)

check("the sample decodes: items", 20, file.items.count)
check("the sample decodes: agents", 6, file.agents.count)
check("blocked: the sessions that wait, longest wait first", ["session:a1", "session:c3"], board.blocked.map(\.id))
check("blocked: a kind comes through", .approval, board.blocked[0].kind)
check("blocked: the session's name and its issue", "shop · #210", board.blocked[0].origin)
check("blocked: a session with no issue has its name only", "docs", board.blocked[1].origin)
check("decisions: the issues that wait, outside every session", 2, board.decisions)
check("waiting: the blocked sessions and the decisions", 4, board.waitingCount)
check("working: an agent that waits on the owner is left out", ["feeds", "site", "news", "shop 2"], board.workers.map(\.name))
check("working: a heartbeat older than 10 minutes is stalled", [true, false, false, false], board.workers.map(\.stalled))
check("working: the task is the agent's item", "Speed up the pricing page", board.workers[1].task)
check("working: an agent on an issue shows its number", "#208 · Fix the cart total when a coupon is removed", board.workers[3].line)
check("working: a session with no issue shows its title", "Nightly import of supplier feeds", board.workers[0].line)
check("working: a session whose turn ended works in the background", [false, false, true, false], board.workers.map(\.background))
check("working: background work is never stalled", .steady, board.workers[2].pulse(at: now.addingTimeInterval(3600)))
check("running: the agents at work that are not stalled", 3, board.running)
check("done: the sessions that wait to be archived", ["session:g7"], board.finished.map(\.id))
check("footer: to do", 5, board.queued)
check("footer: shipped counts the issues closed today, not the sessions", 4, board.shipped)
check("footer: failed", 1, board.failed)
check("issue: a short number", "#42", Board.shortIssue("acme/shop#42"))
check("issue: a session is no issue", true, Board.shortIssue("session:a1") == nil && Board.shortIssue(nil) == nil && Board.shortIssue("sample:3") == nil)
let yesterday = StatusFile(updatedAt: now, items: [.init(id: "a/b#1", title: "t", kind: .task, state: .done, completedAt: now.addingTimeInterval(-20 * 3600))], agents: [])
check("footer: an issue closed yesterday is not shipped today", 0, Board(yesterday, now: now, calendar: utc).shipped)
let older = StatusFile(updatedAt: now, items: [.init(id: "session:x", title: "Pick one", kind: .question, state: .waitingUser, agent: "shop")], agents: [.init(name: "shop", currentItemId: "session:x", lastHeartbeat: now)])
check("an older writer's waiting session is blocked", [1, 0, 0], [Board(older, now: now).blocked.count, Board(older, now: now).decisions, Board(older, now: now).workers.count])
check("fresh data is not stale", false, board.isStale(now: now))
check("data older than 2 minutes is stale", true, board.isStale(now: now.addingTimeInterval(121)))

let later = now.addingTimeInterval(3600)
let moved = file.moved(to: later)
check("moved: updatedAt is now", later, moved.updatedAt)
check("moved: a wait is as long as before", 42 * 60, Int(later.timeIntervalSince(moved.items[0].waitingSince!)))
check("moved: the board is the same", board.workers.map(\.stalled), Board(moved, now: later).workers.map(\.stalled))

check("elapsed: seconds", "45s", Elapsed.short(45))
check("elapsed: minutes", "12m", Elapsed.short(12 * 60 + 9))
check("elapsed: hours", "1h 05m", Elapsed.short(3900))
check("elapsed: days", "2d 3h", Elapsed.short(2 * 86400 + 3 * 3600))
check("elapsed: no start, no text", "", Elapsed.short(from: nil, to: now))

// How lively an agent is.
check("pulse: a tool call 5 seconds ago is active", .active, Board.Pulse(heartbeat: now.addingTimeInterval(-5), now: now))
check("pulse: 2 minutes ago is steady", .steady, Board.Pulse(heartbeat: now.addingTimeInterval(-120), now: now))
check("pulse: 5 minutes ago is quiet", .quiet, Board.Pulse(heartbeat: now.addingTimeInterval(-300), now: now))
check("pulse: 11 minutes ago is stalled", .stalled, Board.Pulse(heartbeat: now.addingTimeInterval(-660), now: now))
check("pulse: no heartbeat is steady", .steady, Board.Pulse(heartbeat: nil, now: now))
check("pulse: a worker carries its heartbeat", .active, board.workers[3].pulse(at: now))
check("action: a tool's name in plain words", "running a command", Activity.words(for: "Bash"))
check("action: no tool is thinking", "thinking", Activity.words(for: ""))
check("action: a browser tool", "using the browser", Activity.words(for: "mcp__claude-in-chrome__navigate"))
check("action: another connector tool", "using a tool", Activity.words(for: "mcp__github__list_issues"))
check("action: not known stays nil", true, Activity.words(for: nil) == nil)
check("action: the sample's worker has one", "editing files", board.workers[3].action)

// How the lists share the panel's room.
func crowd(_ workers: Int, blocked: Int = 0, done: Int = 0) -> Board.Layout {
    let agents = (0..<workers).map { StatusFile.Agent(name: "a\($0)", lastHeartbeat: now) }
    let waits = (0..<blocked).map { StatusFile.Item(id: "session:w\($0)", title: "?", kind: .question, state: .waitingUser) }
    let ended = (0..<done).map { StatusFile.Item(id: "session:d\($0)", title: "t", kind: .task, state: .done, completedAt: now) }
    return Board(StatusFile(updatedAt: now, items: waits + ended, agents: agents), now: now).layout()
}
func layout(_ blocked: Int, _ density: Board.Density, _ workers: Int, _ finished: Int) -> Board.Layout {
    Board.Layout(blocked: blocked, density: density, workers: workers, finished: finished)
}
check("layout: five agents alone get full rows", layout(0, .full, 5, 0), crowd(5))
check("layout: six are over the limit for full rows", layout(0, .medium, 6, 0), crowd(6))
check("layout: eight are medium", layout(0, .medium, 8, 0), crowd(8))
check("layout: nine are a grid", layout(0, .compact, 9, 0), crowd(9))
check("layout: the blocked list shows three at most", layout(3, .full, 2, 0), crowd(2, blocked: 5))
check("layout: four agents keep full rows beside two blocked and one done", layout(2, .full, 4, 1), crowd(4, blocked: 2, done: 1))
check("layout: the done list shows two at most", layout(0, .full, 3, 2), crowd(3, done: 6))
check("layout: a done row is worth one step down for the agents", layout(3, .medium, 4, 1), crowd(4, blocked: 3, done: 1))
check("layout: the done list gives way before the agents go to a grid", layout(3, .medium, 6, 0), crowd(6, blocked: 3, done: 2))
check("layout: in a grid there is room for done again", layout(3, .compact, 9, 2), crowd(9, blocked: 3, done: 2))
check("layout: sixteen agents fit the grid when nothing is blocked", layout(0, .compact, 16, 2), crowd(16, done: 2))
check("layout: more agents than the room holds are cut, and done gives way", layout(3, .compact, 14, 0), crowd(20, blocked: 4, done: 2))
check("layout: compact shows up to sixteen", 16, Board.Density.compact.limit)
check("layout: the room on a display 900 points high", 647, Int(Board.Layout.room(height: 900, scale: 900.0 / 980)))
let eight = Board(StatusFile(updatedAt: now, items: (0..<2).map { .init(id: "session:w\($0)", title: "?", kind: .question, state: .waitingUser) },
                             agents: (0..<8).map { .init(name: "a\($0)", lastHeartbeat: now) }), now: now)
check("layout: eight agents beside two blocked are medium on a tall display", .medium, eight.layout().density)
check("layout: on a small display they are a grid", .compact, eight.layout(room: Board.Layout.room(height: 800, scale: 0.85)).density)

// The history of tool calls.
func one(_ calls: Int?, beat: TimeInterval = 0) -> StatusFile {
    StatusFile(updatedAt: now, items: [], agents: [.init(name: "a", currentItemId: nil, lastHeartbeat: now.addingTimeInterval(beat), activity: "Bash", toolCalls: calls)])
}
let t0 = Date(timeIntervalSinceReferenceDate: 60 * 1000 + 5)
var log = ActivityLog()
log.record(one(10), at: t0)
check("log: the first load adds nothing", 0, log.bars(for: "a", at: t0).reduce(0, +))
log.record(one(14), at: t0.addingTimeInterval(15))
check("log: new calls go into this minute", 4, log.bars(for: "a", at: t0.addingTimeInterval(15)).last!)
log.record(one(14), at: t0.addingTimeInterval(30))
check("log: the same count adds nothing", 4, log.bars(for: "a", at: t0.addingTimeInterval(30)).last!)
log.record(one(20), at: t0.addingTimeInterval(70))
check("log: the next minute is the next bar", [4, 6], Array(log.bars(for: "a", at: t0.addingTimeInterval(70)).suffix(2)))
check("log: twelve bars", 12, log.bars(for: "a", at: t0).count)
check("log: the rate is calls a minute over 3 minutes", 3, log.rate(at: t0.addingTimeInterval(70)))
log.record(one(3), at: t0.addingTimeInterval(80))
check("log: a count that went down (a new session) adds nothing", 6, log.bars(for: "a", at: t0.addingTimeInterval(80)).last!)
log.record(one(nil, beat: 1), at: t0.addingTimeInterval(90))
log.record(one(nil, beat: 2), at: t0.addingTimeInterval(100))
check("log: with no count, each new heartbeat is one", 8, log.bars(for: "a", at: t0.addingTimeInterval(100)).last!)
log.record(StatusFile(updatedAt: now, items: [], agents: []), at: t0.addingTimeInterval(110))
check("log: an agent that is gone is forgotten", 0, log.bars(for: "a", at: t0.addingTimeInterval(110)).reduce(0, +))

let odd = #"{"updatedAt":"2026-11-27T19:00:00.250Z","items":[{"id":"x","title":"t","kind":"vote","state":"paused"}],"agents":[{"name":"a"}]}"#
let oddFile = try StatusFile.decode(Data(odd.utf8))
check("a time with fractions reads", true, oddFile.updatedAt > Date(timeIntervalSince1970: 0))
check("an unknown kind and state read as other", [StatusFile.Kind.other.rawValue, StatusFile.State.other.rawValue], [oddFile.items[0].kind.rawValue, oddFile.items[0].state.rawValue])
check("a missing optional key is nil", true, oddFile.agents[0].lastHeartbeat == nil && oddFile.items[0].agent == nil)
check("no desk key, no desk", true, oddFile.desk == nil)
let withDesk = try StatusFile.decode(Data(#"{"updatedAt":"2026-11-27T19:00:00Z","items":[],"agents":[],"deskUrl":"https://claude.ai/artifact/abc"}"#.utf8))
check("the desk's link reads", "https://claude.ai/artifact/abc", withDesk.desk?.absoluteString ?? "")
check("a desk link that is not https is not opened", true,
      StatusFile(updatedAt: now, items: [], agents: [], deskUrl: "file:///etc/hosts").desk == nil)
check("an agent with no item shows a dash", "—", Board(oddFile, now: oddFile.updatedAt).workers[0].task)

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
