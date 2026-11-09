import SwiftUI
import MapKit

/// Road alerts marked on the route map: an icon where each one is on the route, with what it is when you hover
/// over it. Icons that would overlap are shown as one, listing them all. Road closures are in orange.
struct RoadAlertMarks: View {
    let alerts: [RoadAlerts.Alert]
    let map: RouteMapImage.Drawn
    let size: CGSize

    /// Icons closer than this on the picture are shown as one.
    private static let apart: CGFloat = 18

    private struct Mark {
        var at: CGPoint
        var alerts: [RoadAlerts.Alert]
        var worst: RoadAlerts.Alert { alerts.min { RoadAlerts.rank($0) < RoadAlerts.rank($1) }! }
    }

    var body: some View {
        GeometryReader { g in
            let scale = g.size.width / size.width
            ForEach(marks.indices, id: \.self) { i in
                let mark = marks[i]
                icon(mark.worst)
                    .help(Array(Set(mark.alerts.map(\.summary))).sorted { a, b in a < b }.joined(separator: "\n"))
                    .position(x: mark.at.x * scale, y: mark.at.y * scale)
            }
        }
    }

    /// Worst first, so a closure's icon is the one kept where icons meet.
    private var marks: [Mark] {
        var marks: [Mark] = []
        for a in alerts.sorted(by: { RoadAlerts.rank($0) < RoadAlerts.rank($1) }) {
            guard let spot = a.mark else { continue }
            let p = map.spot(spot)
            guard (0...size.width).contains(p.x), (0...size.height).contains(p.y) else { continue }
            if let i = marks.firstIndex(where: { hypot($0.at.x - p.x, $0.at.y - p.y) < Self.apart }) {
                marks[i].alerts.append(a)
            } else {
                marks.append(Mark(at: p, alerts: [a]))
            }
        }
        return marks
    }

    private func icon(_ a: RoadAlerts.Alert) -> some View {
        Image(systemName: a.closesRoad ? "xmark.octagon.fill" : a.planned ? "cone.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(a.closesRoad ? Color.orange : Color.primary)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(Circle().stroke(Color.primary.opacity(0.35), lineWidth: 1))
            .contentShape(Circle())
    }
}
