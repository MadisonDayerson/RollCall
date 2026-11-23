import SwiftUI

/// The clubs, forums, calendars and event sites RollCall reads. Group chats are read by the Mac app.
struct SourcesView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var adding = false
    @State private var link = ""
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                let feeds = model.state.feeds.filter { $0.type != .chat }
                ForEach(feeds, id: \.id) { feed in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feed.name).font(.headline)
                        Text(status(feed)).font(.subheadline)
                            .foregroundStyle(model.state.feedErrors[feed.id] == nil ? Color.secondary : Color.orange)
                    }
                    .contextMenu {
                        if let page = URL(string: feed.groupURL ?? feed.url), page.scheme?.hasPrefix("http") == true {
                            Button("Open website", systemImage: "safari") { openURL(page) }
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) { model.removeSource(feed.id) }
                    }
                }
                .onDelete { rows in rows.map { feeds[$0].id }.forEach(model.removeSource) }
            }
            .navigationTitle("Sources")
            .overlay {
                if model.state.feeds.isEmpty {
                    EmptyState(text: "No sources yet.", detail: "Add a club's calendar, a Meetup group, a forum or an event site with +.")
                }
            }
            .toolbar {
                Button("Add source", systemImage: "plus") { link = ""; adding = true }
            }
            .alert("Add a source", isPresented: $adding) {
                TextField("Link", text: $link)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Cancel", role: .cancel) {}
                Button("Add") { add() }
            } message: {
                Text("Paste a link to a club's website or calendar, a Meetup group, a forum section or an event listing.")
            }
            .alert("Couldn't add that source", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") {}
            } message: {
                Text(problem ?? "")
            }
            .overlay(alignment: .bottom) {
                if working { ProgressView("Reading the source…").padding().background(.regularMaterial, in: .capsule).padding() }
            }
        }
    }

    private func add() {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        working = true
        Task {
            problem = await model.addSource(raw)
            working = false
        }
    }

    private func status(_ feed: Feed) -> String {
        if let error = model.state.feedErrors[feed.id] { return error }
        let rides = model.state.events.values.filter { $0.source == feed.id && $0.finish >= Date() }.count
        guard let checked = model.state.lastChecked[feed.id] else { return "Not checked yet" }
        let ago = checked.formatted(.relative(presentation: .named))
        return "\(rides) upcoming ride\(rides == 1 ? "" : "s") · checked \(ago)"
    }
}
