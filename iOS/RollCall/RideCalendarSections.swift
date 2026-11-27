import SwiftUI

/// The Rides tab's week and month: the days in a grid, with their rides listed underneath. Choosing a day lists just its
/// rides; choosing it again goes back to all of them.
struct RideCalendarSections: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let span: RideCalendar.Span
    @Binding var day: Date
    @Binding var oneDay: Bool

    var body: some View {
        let rides = RideCalendar.byDay(model.calendarRides)
        let start = Calendar.current.startOfDay(for: day)
        let shown = (oneDay ? [start] : RideCalendar.days(of: span, at: day)).filter { rides[$0] != nil }
        Section {
            heading
            RideGrid(weeks: RideCalendar.grid(of: span, at: day), rides: rides, chosen: oneDay ? start : nil, decision: model.decision) { new in
                oneDay = !(oneDay && new == start)
                day = new
            }
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { drag in
                guard abs(drag.translation.width) > 2 * abs(drag.translation.height) else { return }
                move(drag.translation.width < 0 ? 1 : -1)
            })
        } footer: {
            Text("Filled: going. Dashed: maybe. Outlined: undecided.")
        }
        .listRowSeparator(.hidden)
        ForEach(shown, id: \.self) { date in
            Section {
                ForEach(rides[date] ?? [], id: \.id) { ride in
                    RideRow(ride: ride, past: ride.finish < Date()).tag(ride.id)
                }
            } header: {
                PatchLabel(text: Format.day.string(from: date))
            }
        }
        if shown.isEmpty {
            Section {
                Text(oneDay ? "No rides on \(Format.day.string(from: day))." : span == .week ? "No rides this week." : "No rides this month.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 0) {
            Text(Format.span(span, at: day)).font(.headline)
            Spacer()
            if !RideCalendar.days(of: span, at: day).contains(Calendar.current.startOfDay(for: Date())) {
                Button("Today") { show(Date()) }.padding(.trailing, 12)
            }
            arrow("Previous \(name)", "chevron.left", -1)
            arrow("Next \(name)", "chevron.right", 1)
        }
        .buttonStyle(.borderless)
    }

    private func arrow(_ title: String, _ icon: String, _ n: Int) -> some View {
        Button { move(n) } label: {
            Label(title, systemImage: icon).labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
        }
    }

    private var name: String { span == .week ? "week" : "month" }

    private func move(_ n: Int) { show(RideCalendar.move(day, by: n, span)) }

    /// Goes to the week or month with the day in it.
    private func show(_ new: Date) {
        withAnimation(reduceMotion ? nil : .default) {
            day = new
            oneDay = false
        }
    }
}
