import SwiftUI
import MapKit

/// Road alerts marked on the route map: an icon set off to the side of the route, on a stalk pointing to where the
/// alert is, so the route stays clear. Holding the pointer over an icon shows what it is. Icons that would overlap
/// are shown as one. The label is a brief summary from Apple's on-device model, written in the background when the
/// map shows. Road closures are in orange.
struct RoadAlertMarks: View {
    let alerts: [RoadAlerts.Alert]
    let route: [CLLocationCoordinate2D]
    let map: RouteMapImage.Drawn
    let size: CGSize
    @StateObject private var hovered = Box<Int?>(nil)
    /// Summaries written so far, by the alerts they cover.
    @StateObject private var summaries = Box<[String: String]>([:])

    /// Alerts closer than this on the picture are shown as one.
    private static let apart: CGFloat = 18
    /// How far the icon sits from the route, at least.
    private static let stalk: CGFloat = 34
    /// Room kept between an icon's edge and the route line.
    private static let clearance: CGFloat = 4
    private static let iconSize: CGFloat = 18

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
                    // Hover is set before placing the icon, so it covers only the icon and not the whole map.
                    icon(marks[i].worst)
                        .onHover { inside in
                            if inside { hovered.value = i } else if hovered.value == i { hovered.value = nil }
                        }
                        .position(scaled(marks[i].icon, scale))
                }
                if let i = hovered.value, marks.indices.contains(i) {
                    callout(marks[i], at: scaled(marks[i].icon, scale), in: g.size)
                }
            }
        }
        .task(id: marks.map { AlertSummary.key($0.alerts) }) { await summarise() }
    }

    /// Writes each icon's summary in turn, keeping ones already written.
    private func summarise() async {
        for m in marks {
            if let done = await AlertSummary.write(m.alerts) { summaries.value[AlertSummary.key(m.alerts)] = done }
            if Task.isCancelled { return }
        }
    }

    private func scaled(_ p: CGPoint, _ scale: CGFloat) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }

    /// The alerts on the picture, worst first so a closure's icon is the one kept where they meet, each with its
    /// icon moved out to a clear spot beside the route.
    private var marks: [Mark] {
        // The route on the picture, with points closer than 3 pt dropped: plenty to keep icons off it.
        var line: [CGPoint] = []
        for p in route.map(map.spot) where line.last.map({ hypot($0.x - p.x, $0.y - p.y) >= 3 }) ?? true { line.append(p) }
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
        for i in marks.indices { marks[i].icon = iconSpot(for: marks[i].at, line: line, taken: marks[..<i].map(\.icon)) }
        return marks
    }

    /// A spot for the icon that's clear of the whole route line and the icons already placed, inside the picture:
    /// straight out from the route on the side away from its middle if that's clear, otherwise turned further
    /// round or further out. If nowhere is clear, the spot furthest from the route.
    private func iconSpot(for p: CGPoint, line: [CGPoint], taken: [CGPoint]) -> CGPoint {
        let half = Self.iconSize / 2
        // Which way the route runs here, and which side is away from its middle.
        let i = line.indices.min { hypot(line[$0].x - p.x, line[$0].y - p.y) < hypot(line[$1].x - p.x, line[$1].y - p.y) }
        var out = CGVector(dx: 0, dy: -1)
        if let i, line.count >= 2 {
            let a = line[max(0, i - 2)], b = line[min(line.count - 1, i + 2)]
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > 0 { out = CGVector(dx: -(b.y - a.y) / length, dy: (b.x - a.x) / length) }
            let middle = CGPoint(x: line.map(\.x).reduce(0, +) / CGFloat(line.count), y: line.map(\.y).reduce(0, +) / CGFloat(line.count))
            if out.dx * (p.x - middle.x) + out.dy * (p.y - middle.y) < 0 { out = CGVector(dx: -out.dx, dy: -out.dy) }
        }
        var best: (spot: CGPoint, room: CGFloat)? = nil
        for length in [Self.stalk, Self.stalk * 1.4, Self.stalk * 1.8] {
            for turn in [0, 25, -25, 50, -50, 75, -75, 100, -100, 125, -125, 150, -150, 180] as [CGFloat] {
                let r = turn * .pi / 180
                let d = CGVector(dx: out.dx * cos(r) - out.dy * sin(r), dy: out.dx * sin(r) + out.dy * cos(r))
                let q = CGPoint(x: p.x + d.dx * length, y: p.y + d.dy * length)
                guard q.x >= half + 1, q.x <= size.width - half - 1, q.y >= half + 1, q.y <= size.height - half - 1,
                      !taken.contains(where: { hypot($0.x - q.x, $0.y - q.y) < Self.iconSize + 2 }) else { continue }
                let room = distance(from: q, to: line) - half
                if room >= Self.clearance { return q }
                if room > best?.room ?? -.infinity { best = (q, room) }
            }
        }
        return best?.spot ?? CGPoint(x: min(max(p.x, half), size.width - half), y: min(max(p.y - Self.stalk, half), size.height - half))
    }

    /// How far a point is from the nearest part of the route line.
    private func distance(from p: CGPoint, to line: [CGPoint]) -> CGFloat {
        guard let first = line.first else { return .infinity }
        if line.count == 1 { return hypot(p.x - first.x, p.y - first.y) }
        return zip(line, line.dropFirst()).map { a, b in
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }.min()!
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

    /// What's at the icon, briefly, beside it and kept inside the picture.
    private func callout(_ m: Mark, at p: CGPoint, in area: CGSize) -> some View {
        let text = summaries.value[AlertSummary.key(m.alerts)] ?? AlertSummary.plain(m.alerts)
        let left = p.x < area.width / 2, top = p.y < area.height / 2
        let gap = Self.iconSize / 2 + 4
        return Text(text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.25), lineWidth: 1))
            .frame(maxWidth: min(240, max(80, left ? area.width - p.x - gap - 4 : p.x - gap - 4)), alignment: left ? .leading : .trailing)
            .padding(left ? .leading : .trailing, left ? p.x + gap : area.width - p.x + gap)
            .padding(top ? .top : .bottom, max(4, top ? p.y - 10 : area.height - p.y - 10))
            .frame(width: area.width, height: area.height, alignment: top ? (left ? .topLeading : .topTrailing) : (left ? .bottomLeading : .bottomTrailing))
            .allowsHitTesting(false)
    }
}
