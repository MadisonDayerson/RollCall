import SwiftUI

/// Days in a grid of weeks. A day with a ride is a patch, like a ride's date in the list: filled when you're going,
/// dashed for maybe, outlined while undecided. Today has a line under its number. Used by both apps.
struct RideGrid: View {
    let weeks: [[Date?]]
    let rides: [Date: [RideEvent]]
    var chosen: Date? = nil
    let decision: (String) -> Decision
    let choose: (Date) -> Void

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                // Any whole week has the days' names in order.
                ForEach(RideCalendar.days(of: .week, at: Date()), id: \.self) { day in
                    Text(DateBadge.weekday.string(from: day).uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(weeks.indices, id: \.self) { w in
                GridRow {
                    ForEach(0..<7, id: \.self) { d in
                        if let day = weeks[w][d] {
                            Button { choose(day) } label: {
                                DayPatch(day: day, rides: rides[day] ?? [], chosen: day == chosen, decision: decision)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }
}

/// One day in the grid.
private struct DayPatch: View {
    let day: Date
    let rides: [RideEvent]
    let chosen: Bool
    let decision: (String) -> Decision

    /// The day's ride you're surest of.
    private var surest: Decision? {
        let all = rides.map { decision($0.id) }
        return [.attending, .maybe, .undecided].first(where: all.contains)
    }

    var body: some View {
        let decision = surest
        let today = Calendar.current.isDateInToday(day)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Text(DateBadge.day.string(from: day))
            .font(.system(size: 18, weight: decision == nil ? .semibold : .black).width(.condensed)).monospacedDigit()
            .foregroundStyle(decision == .attending ? DateBadge.paper : decision == nil ? .secondary : .primary)
            .overlay(alignment: .bottom) {
                if today { Capsule().fill(decision == .attending ? DateBadge.paper : .primary).frame(width: 16, height: 2).offset(y: 4) }
            }
            .frame(minWidth: 26, maxWidth: 34, minHeight: 38, maxHeight: 38)  // narrower in a narrow column
            .background { if decision == .attending { shape.fill(Color.primary) } }
            .overlay {
                if let decision {
                    shape.strokeBorder(Color.primary, style: StrokeStyle(lineWidth: 1.5, dash: decision == .maybe ? [3, 2] : []))
                }
            }
            .compositingGroup()
            .opacity(day < Calendar.current.startOfDay(for: Date()) ? 0.5 : 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(chosen ? 0.1 : 0), in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(label(decision, today: today))
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private func label(_ decision: Decision?, today: Bool) -> String {
        let count = rides.count == 1 ? "1 ride" : "\(rides.count) rides"
        let answer = [.attending: "going", .maybe: "maybe", .undecided: "undecided"][decision ?? .skip]
        return [today ? "Today" : nil, Format.day.string(from: day), rides.isEmpty ? "no rides" : count, answer]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
