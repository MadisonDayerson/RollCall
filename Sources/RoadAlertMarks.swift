import SwiftUI
import MapKit

/// Road alerts marked on the route map: an icon set off to the side of the route, on a stalk pointing to where the
/// alert is, so the route stays clear. Holding the pointer over an icon shows what it is. Icons that would overlap
/// are shown as one, listing them all. Road closures are in orange.
struct RoadAlertMarks: View {
    let alerts: [RoadAlerts.Alert]
    let route: [CLLocationCoordinate2D]
    let map: RouteMapImage.Drawn
    let size: CGSize
    @StateObject private var hovered = Box<Int?>(nil)

    /// Alerts closer than this on the picture are shown as one.
    private static let apart: CGFloat = 18
    /// How far the icon sits from the route.
    private static let stalk: CGFloat = 34
    private static let iconSize: CGFloat = 18
    /// Lines shown when hovering, before "and n more".
    private static let lines = 6

    private struct Mark {
        /// Where the alert is on the route, and where its icon goes.
        var at: CGPoint
        var icon: CGPoint = .zero
        var alerts: [RoadAlerts.Alert]
        var worst: RoadAlerts.Alert { alerts.min { RoadAlerts.rank($0) < RoadAlerts.rank($1) }! }
    }

    var body: some View {
        GeometryReader { g in
            let scale = g.size.width / size.width
            let marks = self.marks
            ZStack(alignment: .topLeading) {
                Path { path in
                    for m in marks {
                        path.move(to: scaled(m.at, scale))
                        path.addLine(to: scaled(m.icon, scale))
                    }
                }
                .stroke(Color.primary.opacity(0.7), lineWidth: 1)
                ForEach(marks.indices, id: \.self) { i in
                    Circle().fill(Color.primary).frame(width: 4, height: 4).position(scaled(marks[i].at, scale))
                    icon(marks[i].worst)
                        .position(scaled(marks[i].icon, scale))
                        .onHover { inside in
                            if inside { hovered.value = i } else if hovered.value == i { hovered.value = nil }
                        }
                }
                if let i = hovered.value, marks.indices.contains(i) {
                    callout(marks[i], at: scaled(marks[i].icon, scale), in: g.size)
                }
            }
        }
    }

    private func scaled(_ p: CGPoint, _ scale: CGFloat) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }

    /// The alerts on the picture, worst first so a closure's icon is the one kept where they meet, each with its
    /// icon moved out from the route.
    private var marks: [Mark] {
        let line = route.map(map.spot)
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
        for i in marks.indices { marks[i].icon = iconSpot(for: marks[i].at, line: line) }
        return marks
    }

    /// Out from the route at right angles, on the side away from the middle of the route, kept inside the picture.
    private func iconSpot(for p: CGPoint, line: [CGPoint]) -> CGPoint {
        let half = Self.iconSize / 2 + 1
        func inside(_ q: CGPoint) -> CGPoint {
            CGPoint(x: min(max(q.x, half), size.width - half), y: min(max(q.y, half), size.height - half))
        }
        guard line.count >= 2, let i = line.indices.min(by: { hypot(line[$0].x - p.x, line[$0].y - p.y) < hypot(line[$1].x - p.x, line[$1].y - p.y) })
        else { return inside(CGPoint(x: p.x, y: p.y - Self.stalk)) }
        let a = line[max(0, i - 3)], b = line[min(line.count - 1, i + 3)]
        var dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        if length == 0 { (dx, dy) = (1, 0) } else { (dx, dy) = (dx / length, dy / length) }
        var normal = CGPoint(x: -dy, y: dx)
        let middle = CGPoint(x: line.map(\.x).reduce(0, +) / CGFloat(line.count), y: line.map(\.y).reduce(0, +) / CGFloat(line.count))
        if normal.x * (p.x - middle.x) + normal.y * (p.y - middle.y) < 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let out = CGPoint(x: p.x + normal.x * Self.stalk, y: p.y + normal.y * Self.stalk)
        // Near the edge, go the other way rather than squash the stalk.
        let back = CGPoint(x: p.x - normal.x * Self.stalk, y: p.y - normal.y * Self.stalk)
        return inside(out) == out || inside(back) != back ? inside(out) : back
    }

    private func icon(_ a: RoadAlerts.Alert) -> some View {
        Image(systemName: a.closesRoad ? "xmark.octagon.fill" : a.planned ? "cone.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(a.closesRoad ? Color.orange : Color.primary)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
            .contentShape(Circle())
            .accessibilityLabel(a.summary)
    }

    /// What's at the icon, beside it and kept inside the picture.
    private func callout(_ m: Mark, at p: CGPoint, in area: CGSize) -> some View {
        let all = Array(Set(m.alerts.map(\.summary))).sorted()
        let text = all.prefix(Self.lines).joined(separator: "\n") + (all.count > Self.lines ? "\nand \(all.count - Self.lines) more" : "")
        let left = p.x < area.width / 2, top = p.y < area.height / 2
        let gap = Self.iconSize / 2 + 4
        return Text(text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.25), lineWidth: 1))
            .frame(maxWidth: max(80, left ? area.width - p.x - gap - 4 : p.x - gap - 4), alignment: left ? .leading : .trailing)
            .padding(left ? .leading : .trailing, left ? p.x + gap : area.width - p.x + gap)
            .padding(top ? .top : .bottom, max(4, top ? p.y - 10 : area.height - p.y - 10))
            .frame(width: area.width, height: area.height, alignment: top ? (left ? .topLeading : .topTrailing) : (left ? .bottomLeading : .bottomTrailing))
            .allowsHitTesting(false)
    }
}
