import SwiftUI

/// Setup, one step per page: your area, sharing with the Mac (and the chats it reads), groups and websites, Facebook
/// events, road alerts, the calendar and notifications. Every step after your area can be skipped, and Settings → Run setup… opens it
/// again.
struct SetupView: View {
    @Environment(PhoneModel.self) private var model
    @State private var path: [SetupStep] = []
    /// The suggested groups have been ticked once, so unticking them sticks.
    @State private var suggested = false

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep()
                .modifier(SetupFooter(title: "Get started") { path.append(.home) })
                .modifier(CloseSetup())
                .navigationDestination(for: SetupStep.self) { step in
                    page(step).modifier(CloseSetup())
                }
        }
    }

    @ViewBuilder private func page(_ step: SetupStep) -> some View {
        switch step {
        case .home: HomeStep { next(after: .home) }
        case .mac: SetupPage(step: .mac, next: next) { MacStep() }
        case .chats: SetupPage(step: .chats, next: next) { ChatsStep() }.task { await model.watchForChats() }
        case .groups: SetupPage(step: .groups, next: next) { GroupsStep() }
        case .facebook: SetupPage(step: .facebook, next: next) { FacebookStep() }
        case .roads: SetupPage(step: .roads, next: next) { RoadsStep() }
        case .calendar: SetupPage(step: .calendar, next: next) { CalendarStep() }
        case .notifications: SetupPage(step: .notifications, next: next) { NotificationsStep() }
        case .finish:
            Form { FinishStep(open: back) }
                .modifier(SetupFooter(title: "Start") { Task { await model.finishSetup() } })
        }
    }

    private func next(after step: SetupStep) {
        guard let next = step.next else { return }
        // The first time, with nothing followed yet (or come from the Mac), the suggestions start ticked.
        if next == .groups, !suggested, !model.state.setupDone, model.groups.isEmpty {
            suggested = true
            Starter.suggestions(for: model.state.settings).feeds.forEach { model.follow($0, true) }
        }
        path.append(next)
    }

    private func back(to step: SetupStep) {
        guard let i = path.lastIndex(of: step) else { return }
        path.removeLast(path.count - 1 - i)
    }
}

/// A step that can be skipped: its button says Skip until it's done.
struct SetupPage<Content: View>: View {
    @Environment(PhoneModel.self) private var model
    let step: SetupStep
    let next: (SetupStep) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        let done = model.isDone(step)
        Form { content }
            .modifier(SetupFooter(title: done ? "Continue" : "Skip", filled: done) { next(step) })
            .modifier(StepCount(step: step))
    }
}

/// "Step 2 of 8" in the title bar.
struct StepCount: ViewModifier {
    let step: SetupStep

    func body(content: Content) -> some View {
        content
            .navigationTitle("Step \(step.rawValue + 1) of \(SetupStep.counted.count)")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The wide glass button at the bottom of every page: black, or white in dark mode, like the logo.
struct SetupFooter: ViewModifier {
    let title: String
    var filled = true
    var working = false
    var disabled = false
    let action: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaBar(edge: .bottom) {
            Group {
                if filled { button.buttonStyle(.glassProminent).tint(.primary) } else { button.buttonStyle(.glass) }
            }
            .controlSize(.large)
            .disabled(working || disabled)
            .frame(maxWidth: 420)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
    }

    private var button: some View {
        Button(action: action) {
            Group { if working { ProgressView() } else { Text(title) } }
                .fontWeight(.semibold)
                // Left to the system, it's white on white in dark mode.
                .foregroundStyle(filled && !working && !disabled ? DateBadge.paper : .primary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Closes setup when it was opened again from Settings. The first time, it's finished by going through it.
struct CloseSetup: ViewModifier {
    @Environment(PhoneModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            if model.settingUp {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { Task { await model.finishSetup() } }
                }
            }
        }
    }
}

/// A heading and a line under it, at the top of each step.
struct StepHeader: View {
    let title: String
    let text: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(text).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        }
    }
}
