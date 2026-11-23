import SwiftUI

/// First run: where you live, then the sources suggested for your area.
struct SetupView: View {
    @Environment(PhoneModel.self) private var model
    @State private var home = ""
    @State private var finding = false
    @State private var problem: String?
    @State private var suggested: [Feed]?
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                if let suggested {
                    Section {
                        ForEach(suggested, id: \.id) { feed in
                            Toggle(feed.name, isOn: Binding(get: { chosen.contains(feed.id) },
                                                            set: { on in if on { chosen.insert(feed.id) } else { chosen.remove(feed.id) } }))
                        }
                    } header: {
                        Text("Sources near \(model.state.settings.homeName)")
                    } footer: {
                        Text("You can add your own clubs, calendars and event sites under Sources.")
                    }
                } else {
                    Section {
                        TextField("Suburb or town", text: $home)
                            .textContentType(.addressCity)
                            .submitLabel(.next)
                            .onSubmit(next)
                    } header: {
                        Text("Where do you ride from?")
                    } footer: {
                        if let problem { Text(problem).foregroundStyle(.red) } else {
                            Text("RollCall shows rides within 100 km of here. Only your suburb is kept, never your address.")
                        }
                    }
                }
            }
            .navigationTitle("Welcome to RollCall")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if finding { ProgressView() } else if let suggested {
                        Button("Done") {
                            let feeds = suggested.filter { chosen.contains($0.id) }
                            Task { await model.finishSetup(with: feeds) }
                        }
                    } else {
                        Button("Next", action: next).disabled(home.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func next() {
        finding = true
        Task {
            problem = await model.setHome(home)
            finding = false
            if problem == nil {
                let feeds = Starter.suggestions(for: model.state.settings).feeds
                chosen = Set(feeds.map(\.id))
                suggested = feeds
            }
        }
    }
}
