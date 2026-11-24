import Foundation

/// The steps of setup, in order. Sharing with the Mac comes early because the Mac's sources, Facebook calendar and chat
/// rides come with it.
enum SetupStep: Int, CaseIterable {
    case home, mac, chats, groups, facebook, roads, calendar, notifications, finish

    /// The steps counted in "Step 2 of 8"; the last page isn't.
    static let counted = allCases.filter { $0 != .finish }

    var next: SetupStep? { SetupStep(rawValue: rawValue + 1) }

    /// How it's listed on the last page.
    var name: String {
        switch self {
        case .home: "Your area"
        case .mac: "Your Mac"
        case .chats: "Chats"
        case .groups: "Groups and websites"
        case .facebook: "Facebook events"
        case .roads: "Road alerts"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        case .finish: "All set"
        }
    }
}

extension PhoneModel {
    /// The step has been set up, so there's nothing to skip.
    func isDone(_ step: SetupStep) -> Bool {
        switch step {
        case .home: state.settings.foundPlace != nil
        case .mac: macFolder != nil
        case .chats: state.macChats != nil
        case .groups: !groups.isEmpty
        case .facebook: facebookConnected
        case .roads: roadAlertsKeySaved
        case .calendar: calendarAllowed
        case .notifications: notificationsAllowed == true
        case .finish: true
        }
    }

    /// Looks for the Mac's chats every few seconds, while the Chats step is open.
    func watchForChats() async {
        while !Task.isCancelled, state.macChats == nil {
            shareNow()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    /// The clubs, forums and websites followed, besides chats and your Facebook events.
    var groups: [Feed] { state.feeds.filter { $0.type != .chat && $0.id != FeedLinks.facebookCalendarID } }
}
