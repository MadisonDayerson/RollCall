import MapKit
import AppKit
import CoreImage

/// A still picture of a planned route: Apple's muted map with the road route drawn over it in the text
/// colour, a filled dot at the start, small dots at named stops and a ring at the finish.
@MainActor
enum RouteMapImage {
    /// The picture, its size, and where a place falls on it (in points from the top left).
    final class Drawn {
        let image: NSImage
        let size: CGSize
        let spot: (CLLocationCoordinate2D) -> CGPoint

        init(image: NSImage, size: CGSize, spot: @escaping (CLLocationCoordinate2D) -> CGPoint) {
            (self.image, self.size, self.spot) = (image, size, spot)
        }
    }

    /// The last few pictures only: a full screen one is several megabytes.
    private static let drawn: NSCache<NSString, Drawn> = {
        let cache = NSCache<NSString, Drawn>()
        cache.countLimit = 6
        return cache
    }()

    /// Which route a picture shows.
    static func key(_ route: RoutePlanner.Planned) -> String {
        route.stops.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";") + "|\(route.metres)"
    }

    /// `scale` is the screen's pixels per point.
    static func draw(_ route: RoutePlanner.Planned, size: CGSize, scale: CGFloat, dark: Bool) async -> Drawn? {
        let key = "\(key(route))|\(size.width)x\(size.height)@\(scale)|\(dark)" as NSString
        if let kept = drawn.object(forKey: key) { return kept }
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let config = MKStandardMapConfiguration(emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config
        options.mapRect = route.mapRect(size: size)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let ink = dark ? NSColor.white : NSColor.black
        let paper = dark ? NSColor.black : NSColor.white
        let map = greyscale(snapshot.image, scale: scale)
        let image = NSImage(size: size, flipped: false) { _ in
            map.draw(in: CGRect(origin: .zero, size: size))
            func spot(_ c: CLLocationCoordinate2D) -> CGPoint { snapshot.point(for: c) }
            let line = NSBezierPath()
            line.lineWidth = 3
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            for leg in route.legs {
                let points = leg.points()
                for i in 0..<leg.pointCount {
                    let p = spot(points[i].coordinate)
                    if i == 0 { line.move(to: p) } else { line.line(to: p) }
                }
            }
            ink.setStroke()
            line.stroke()
            func dot(_ c: CLLocationCoordinate2D, radius: CGFloat, filled: Bool) {
                let p = spot(c)
                let circle = NSBezierPath(ovalIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                circle.lineWidth = 2.5
                (filled ? ink : paper).setFill()
                circle.fill()
                ink.setStroke()
                circle.stroke()
            }
            for (stop, named) in zip(route.stops, route.named).dropFirst().dropLast() where named { dot(stop, radius: 3.5, filled: false) }
            if let finish = route.stops.last { dot(finish, radius: 6, filled: false) }
            if let start = route.stops.first { dot(start, radius: 6, filled: true) }
            return true
        }
        let result = Drawn(image: image, size: size) { c in
            let p = snapshot.point(for: c)
            return CGPoint(x: p.x, y: size.height - p.y)
        }
        drawn.setObject(result, forKey: key)
        return result
    }

    /// The map in greys, to match RollCall's black and white. MapKit's picture comes in several resolutions, so the
    /// screen's one is asked for.
    private static func greyscale(_ image: NSImage, scale: CGFloat) -> NSImage {
        guard let map = image.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: NSAffineTransform(transform: AffineTransform(scale: scale))]),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(CIImage(cgImage: map), forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
}
