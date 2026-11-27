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

let odd = #"{"updatedAt":"2026-11-27T19:00:00.250Z","items":[{"id":"x","title":"t","kind":"vote","state":"paused"}],"agents":[{"name":"a"}]}"#
let oddFile = try StatusFile.decode(Data(odd.utf8))
check("a time with fractions reads", true, oddFile.updatedAt > Date(timeIntervalSince1970: 0))
check("an unknown kind and state read as other", [StatusFile.Kind.other.rawValue, StatusFile.State.other.rawValue], [oddFile.items[0].kind.rawValue, oddFile.items[0].state.rawValue])
check("a missing optional key is nil", true, oddFile.agents[0].lastHeartbeat == nil && oddFile.items[0].agent == nil)
check("an agent with no item shows a dash", "—", Board(oddFile, now: oddFile.updatedAt, idleSince: oddFile.updatedAt).workers[0].task)

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
