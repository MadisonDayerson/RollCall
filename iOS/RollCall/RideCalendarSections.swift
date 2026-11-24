import SwiftUI

/// The Rides tab's week and month: the days in a grid, with their rides listed underneath. Choosing a day lists just its
/// rides; choosing it again goes back to all of them.
struct RideCalendarSections: View {
    @Environment(PhoneModel.self) private var model
    let span: RideCalendar.Span
    @Binding var day: Date
    @Binding var oneDay: Bool

    var body: some View {
        let rides = RideCalendar.byDay(model.calendarRides)
        let start = Calendar.current.startOfDay(for: day)
        let shown = (oneDay ? [start] : RideCalendar.days(of: span, at: day)).filter { rides[$0] != nil }
        Section {
            heading
            RideGrid(weeks: RideCalendar.grid(of: span, at: day), rides: rides, chosen: oneDay ? start : nil) { new in
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
        HStack(spacing: 20) {
            Text(Format.span(span, at: day)).font(.headline)
            Spacer()
            if !RideCalendar.days(of: span, at: day).contains(Calendar.current.startOfDay(for: Date())) {
                Button("Today") { withAnimation { day = Date(); oneDay = false } }
            }
            Button("Previous \(name)", systemImage: "chevron.left") { move(-1) }
            Button("Next \(name)", systemImage: "chevron.right") { move(1) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private var name: String { span == .week ? "week" : "month" }

    private func move(_ n: Int) {
        withAnimation {
            day = RideCalendar.move(day, by: n, span)
            oneDay = false
        }
    }
}

extension PhoneModel {
    /// The rides a calendar shows: coming up and not skipped, and those you went on.
    var calendarRides: [RideEvent] {
        (sections.filter { $0.name != "Skipped" }.flatMap(\.rides)).sorted { $0.start < $1.start }
    }
}
