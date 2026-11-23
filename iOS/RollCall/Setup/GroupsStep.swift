import SwiftUI

/// The clubs, forums and event sites to follow: suggestions for your area, and your own links.
struct GroupsStep: View {
    @Environment(PhoneModel.self) private var model
    @State private var link = ""
    @State private var adding = false
    @State private var problem: String?

    var body: some View {
        let suggested = Starter.suggestions(for: model.state.settings).feeds
        let own = model.groups.filter { feed in !suggested.contains { $0.id == feed.id } }
        StepHeader(title: "Follow groups and websites",
                   text: "Add the clubs, Meetup groups, forums and event pages you follow. RollCall checks them by itself.")
        if !suggested.isEmpty {
            Section {
                ForEach(suggested, id: \.id) { feed in
                    Toggle(feed.name, isOn: Binding(get: { model.groups.contains { $0.id == feed.id } },
                                                    set: { model.follow(feed, $0) }))
                }
            } header: {
                PatchLabel(text: "Suggested for \(model.state.settings.homeName)")
            }
        }
        Section {
            HStack {
                TextField("Paste a link", text: $link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).onSubmit(add)
                if adding { ProgressView() } else {
                    Button("Add", action: add).buttonStyle(.borderless)
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            if let problem { ProblemLabel(text: problem) }
            ForEach(own, id: \.id) { Text($0.name) }
                .onDelete { rows in rows.map { own[$0].id }.forEach(model.removeSource) }
        } header: {
            PatchLabel(text: "Add your own")
        } footer: {
            Text("Works with a club or event website, a forum section, a Meetup group, a calendar link or a news feed. Facebook doesn't let apps read groups.")
        }
    }

    private func add() {
        let pasted = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty, !adding else { return }
        adding = true
        Task {
            problem = await model.follow(pasted)
            if problem == nil { link = "" }
            adding = false
        }
    }
}
