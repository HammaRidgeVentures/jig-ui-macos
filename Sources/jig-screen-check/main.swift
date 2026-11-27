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
let idle = now.addingTimeInterval(-5 * 60)
let board = Board(file, now: now, idleSince: idle)

check("the sample decodes: items", 17, file.items.count)
check("the sample decodes: agents", 5, file.agents.count)
check("waiting: every waiting item counts", 4, board.waitingCount)
check("waiting: the top three, longest wait first", ["session:a1", "acme/shop#212", "session:c3"], board.waiting.map(\.id))
check("waiting: a kind comes through", .approval, board.waiting[0].kind)
check("working: an agent that waits on the owner is left out", ["feeds", "site", "shop 2"], board.workers.map(\.name))
check("working: a heartbeat older than 10 minutes is stalled", [true, false, false], board.workers.map(\.stalled))
check("working: the task is the agent's item", "Speed up the pricing page", board.workers[1].task)
check("running: the agents at work that are not stalled", 2, board.running)
check("footer: queued", 5, board.queued)
check("footer: done counts only since idle started", 3, board.done)
check("footer: failed", 1, board.failed)
check("fresh data is not stale", false, board.isStale(now: now))
check("data older than 2 minutes is stale", true, board.isStale(now: now.addingTimeInterval(121)))

let later = now.addingTimeInterval(3600)
let moved = file.moved(to: later)
check("moved: updatedAt is now", later, moved.updatedAt)
check("moved: a wait is as long as before", 42 * 60, Int(later.timeIntervalSince(moved.items[0].waitingSince!)))
check("moved: the board is the same", board.workers.map(\.stalled), Board(moved, now: later, idleSince: later.addingTimeInterval(-300)).workers.map(\.stalled))

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
check("pulse: a worker carries its heartbeat", .active, board.workers[2].pulse(at: now))
check("action: a tool's name in plain words", "running a command", Activity.words(for: "Bash"))
check("action: no tool is thinking", "thinking", Activity.words(for: ""))
check("action: a browser tool", "using the browser", Activity.words(for: "mcp__claude-in-chrome__navigate"))
check("action: another connector tool", "using a tool", Activity.words(for: "mcp__github__list_issues"))
check("action: not known stays nil", true, Activity.words(for: nil) == nil)
check("action: the sample's worker has one", "editing files", board.workers[2].action)

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
check("an agent with no item shows a dash", "—", Board(oddFile, now: oddFile.updatedAt, idleSince: oddFile.updatedAt).workers[0].task)

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
