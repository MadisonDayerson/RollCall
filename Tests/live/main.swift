import Foundation
// Reads every starter source once, with a throwaway store, and prints what it found.
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("motorides-live-\(UUID()).json")
let store = Store(file: tmp)
for feed in Starter.feeds {
    do {
        let r = try await SourceReader.read(feed, store: store)
        print("== \(feed.name): \(r.events.count) events, \(r.guessed.count) read from posts, \(r.undated.count) undated posts")
        for e in (r.events + r.guessed).sorted(by: { $0.start < $1.start }) {
            print("   \(e.start) \(e.allDay ? "(all day)" : "") | \(e.title) | \(e.location) | \(e.url ?? "")")
        }
        for p in r.undated.prefix(5) { print("   📰 \(p.title)") }
    } catch {
        print("== \(feed.name): ERROR \(error.localizedDescription)")
    }
}
try? FileManager.default.removeItem(at: tmp)
