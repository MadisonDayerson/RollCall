import SwiftUI

@main
struct RollCallApp: App {
    @UIApplicationDelegateAdaptor private var delegate: PhoneDelegate

    var body: some Scene {
        let model = delegate.model
        WindowGroup {
            RootView()
                .environment(model)
        }
        .backgroundTask(.appRefresh(PhoneModel.backgroundCheck)) { await model.checkInBackground() }
    }
}

enum PhoneTab { case home, rides, sources, settings }

/// Home, Rides, Sources and Settings: tabs on iPhone, a sidebar on iPad.
struct RootView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.scenePhase) private var phase
    /// The splash is on as RollCall opens: once, not again for another iPad window or when RollCall comes back.
    @State private var opening = !SplashScreen.played

    var body: some View {
        @Bindable var model = model
        let settingUp = !model.state.setupDone || model.settingUp
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house", value: .home) { HomeView() }
            Tab("Rides", systemImage: "motorcycle", value: .rides) { RidesView() }
            Tab("Sources", systemImage: "antenna.radiowaves.left.and.right", value: .sources) { SourcesView() }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: .constant(settingUp)) { SetupView().overlay { splash } }
        .alert("RollCall", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.problem ?? "")
        }
        .overlay {
            // Setup covers this page, so it has the splash; black here until it does.
            if !settingUp { splash } else if opening { Color.black.ignoresSafeArea() }
        }
        // Takes in the Mac's changes every minute while RollCall is open.
        .task(id: phase) {
            while phase == .active {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                model.shareNow()
            }
        }
        .onChange(of: phase) { _, now in
            if now == .active {
                model.shareNow()
                model.checkCalendar()
                Task { await model.checkNotifications() }
            }
            if now == .background { model.scheduleCheck() }
            // Coming back to the app after a few hours reads the sources again.
            guard now == .active, model.state.setupDone,
                  (model.state.lastRefresh ?? .distantPast) < Date().addingTimeInterval(-3 * 3600) else { return }
            Task { await model.refresh() }
        }
    }

    @ViewBuilder private var splash: some View {
        if opening { SplashScreen { opening = false } }
    }
}
