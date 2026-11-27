import Foundation

/// The rides list's headings, the same on the Mac, iPhone and iPad.
enum RideGroup: String, CaseIterable { case undecided = "Undecided", going = "Going", skipped = "Skipped", past = "Past" }

/// A heading's rides.
struct GroupedRides: Identifiable {
    var id: RideGroup { group }
    var group: RideGroup
    var rides: [RideEvent]
}

/// How the Rides page shows the rides: in a list under the headings, or the week's or month's in a calendar.
enum RidesLayout: String, CaseIterable {
    case list, week, month
    var name: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .week: "calendar.day.timeline.left"
        case .month: "calendar"
        }
    }
}

extension Store {
    /// Every ride once, under its heading. Maybe counts as undecided.
    func groupedRides() -> [GroupedRides] {
        let all = upcoming()
        return [
            GroupedRides(group: .undecided, rides: all.filter { [.undecided, .maybe].contains(decision($0.id)) }),
            GroupedRides(group: .going, rides: all.filter { decision($0.id) == .attending }),
            GroupedRides(group: .skipped, rides: all.filter { decision($0.id) == .skip }),
            GroupedRides(group: .past, rides: past()),
        ]
    }

    /// The rides a calendar shows: coming up and not skipped, and those you went on.
    func calendarRides() -> [RideEvent] {
        groupedRides().filter { $0.group != .skipped }.flatMap(\.rides).sorted { $0.start < $1.start }
    }
}

extension [GroupedRides] {
    func rides(_ group: RideGroup) -> [RideEvent] { first { $0.group == group }?.rides ?? [] }
}
