import SwiftUI
import AppKit

// MARK: - To review

struct ReviewPage: View {
    @ObservedObject var model: UIModel

    var body: some View {
        let plans = model.app.possiblePlans()
        let partial = model.app.partialPlans()
        let posts = model.app.postsToLookAt()
        let reviewed = model.app.reviewedPlans()
        let keep = model.store.state.settings.keepDismissed
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Possible plans").font(.title3).fontWeight(.semibold)
                        Spacer()
                        Text(PlanSummariser.modelAvailable ? "Summaries by Apple Intelligence, on this Mac" : "Summaries are RollCall's best guess")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Rides your chats have settled: a day still to come, a time and a place. Check what RollCall made of it, then add it as a ride or dismiss it.")
                        .font(.callout).foregroundStyle(.secondary)
                    if plans.isEmpty {
                        Text("Nothing to review.").foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(plans, id: \.id) { r in
                        PlanCard(review: r, model: model).id(r.id)
                    }
                    Divider().padding(.vertical, 6)
                    Text("Partial plans").font(.title3).fontWeight(.semibold)
                    Text("Rides being talked about that are still missing a day, time or place. RollCall keeps reading the conversation, and a plan moves up to Possible plans once those are settled.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if partial.isEmpty && posts.isEmpty {
                        Text("Nothing new.").foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(partial, id: \.id) { r in
                        PlanCard(review: r, model: model).id(r.id)
                    }
                    if !posts.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            PatchLabel(text: "Posts that didn't say when", count: posts.count)
                            Spacer()
                            Button("Mark all read") { model.app.markPostsRead() }
                        }
                        .padding(.top, 4)
                    }
                    ForEach(posts, id: \.post.id) { item in
                        PostRow(feed: item.feed, post: item.post, model: model)
                        Divider()
                    }
                    if keep > 0 {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Plans you marked Not a ride, kept for \(keep == 1 ? "a day" : keep == 7 ? "a week" : "\(keep) days") in case you change your mind. Change how long in Settings → Privacy.")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if reviewed.isEmpty {
                                    Text("Nothing here.").foregroundStyle(.secondary)
                                }
                                ForEach(reviewed, id: \.id) { r in
                                    PlanCard(review: r, model: model).id(r.id)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            PatchLabel(text: "Reviewed", count: reviewed.count)
                        }
                        .padding(.top, 12)
                    }

                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear { if let id = model.selectedReview { scroller.scrollTo(id, anchor: .top) } }
            .onChange(of: model.selectedReview) { _, id in if let id { withAnimation { scroller.scrollTo(id, anchor: .top) } } }
        }
        .navigationTitle("To review")
    }
}

struct PlanCard: View {
    let review: PlanReview
    @ObservedObject var model: UIModel

    var body: some View {
        let s = review.summary
        let app = model.app
        let others = app.crossPosts(review)
        let chatName = ([review] + others).map { model.feed($0.feedID)?.name ?? "Chat" }.joined(separator: ", ")
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.secondary)
                Text(others.isEmpty ? chatName : "\(others.count + 1) chats: " + chatName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .help(others.isEmpty ? chatName : "The same message was posted in \(others.count + 1) chats: \(chatName)")
                Text("· " + AppDelegate.relative.localizedString(for: min(review.updated, Date().addingTimeInterval(-1)), relativeTo: Date()))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Label(s.byAI ? "On-device summary" : "Best guess", systemImage: s.byAI ? "sparkles" : "text.magnifyingglass")
                    .font(.caption)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            Text(s.title).font(.headline)
            Text(s.summary).textSelection(.enabled)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow { Text("When").foregroundStyle(.secondary); Text(s.when) }
                GridRow { Text("Where").foregroundStyle(.secondary); Text(s.place ?? "Not settled") }
                if !s.who.isEmpty {
                    GridRow { Text("Who's in").foregroundStyle(.secondary); Text(s.who.joined(separator: ", ")) }
                }
                if case .partial(let missing) = s.readiness(), review.status == .open {
                    GridRow { Text("Still needed").foregroundStyle(.secondary); Text(missing.joined(separator: ", ").capitalizedFirst) }
                }
                if let u = s.undecided {
                    GridRow { Text("Still open").foregroundStyle(.secondary); Text(u) }
                }
            }
            .font(.callout)

            DisclosureGroup("The conversation (\(review.lines.count) message\(review.lines.count == 1 ? "" : "s"))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(review.lines, id: \.id) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(AppDelegate.timeFmt.string(from: l.sent)).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .trailing)
                            Text((l.sender.isEmpty ? "" : l.sender + ": ") + l.text)
                                .font(.callout)
                                .fontWeight(l.mentionsWhen ? .semibold : .regular)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)

            HStack {
                Button(model.readingReview == review.id ? "Reading…" : "Add ride…") { model.later { app.addRide(fromReview: review.id) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.readingReview != nil)
                Button("Open chat") { app.open(Beeper.chatLink(chatID: review.chatID, messageID: review.keyMessage?.id)) }
                Spacer()
                if review.status == .dismissed {
                    Button("Restore") { app.restoreReview(review.id) }
                        .help("Put it back under Possible plans")
                } else {
                    Button("Not a ride") { app.dismissReview(review.id) }
                        .help("Move it to Reviewed")
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(model.selectedReview == review.id ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PostRow: View {
    let feed: Feed
    let post: PostItem
    @ObservedObject var model: UIModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feed.type == .chat ? "bubble.left" : "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.title).fontWeight(.medium).lineLimit(2)
                if !post.text.isEmpty, post.text != post.title {
                    Text(post.text).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(feed.name + (post.published.map { " · " + AppDelegate.relative.localizedString(for: $0, relativeTo: Date()) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Button("Open") { model.app.open(post.link) }
                Button("Add ride…") {
                    // The post dialog starts with the clipboard, so put the post there.
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(post.text, forType: .string)
                    let link = post.link.hasPrefix("http") ? post.link : ""
                    model.later { model.app.addFromPost(link: link) }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
