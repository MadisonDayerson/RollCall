import SwiftUI

@main
struct RollCallApp: App {
    @State private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// Rides, Sources and Settings: tabs on iPhone, a sidebar on iPad.
struct RootView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            Tab("Rides", systemImage: "motorcycle") { RidesView() }
            Tab("Sources", systemImage: "antenna.radiowaves.left.and.right") { SourcesView() }
            Tab("Settings", systemImage: "gearshape") { SettingsView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(isPresented: .constant(!model.state.setupDone)) { SetupView() }
        .alert("RollCall", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.problem ?? "")
        }
        // Takes in the Mac's changes every minute while RollCall is open.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if phase == .active { model.shareNow() }
            }
        }
        .onChange(of: phase) { _, now in
            if now == .active { model.shareNow() }
            // Coming back to the app after a few hours reads the sources again.
            guard now == .active, model.state.setupDone,
                  (model.state.lastRefresh ?? .distantPast) < Date().addingTimeInterval(-3 * 3600) else { return }
            Task { await model.refresh() }
        }
    }
}
