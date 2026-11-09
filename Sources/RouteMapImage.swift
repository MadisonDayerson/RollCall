import MapKit
import AppKit
import CoreImage

/// A still picture of a planned route: Apple's muted map with the road route drawn over it in the text
/// colour, a filled dot at the start, small dots at named stops and a ring at the finish.
@MainActor
enum RouteMapImage {
    /// The picture, and where a place falls on it (in points from the top left).
    struct Drawn {
        var image: NSImage
        var spot: (CLLocationCoordinate2D) -> CGPoint
    }

    private static var drawn: [String: Drawn] = [:]

    static func draw(_ route: RoutePlanner.Planned, size: CGSize, dark: Bool) async -> Drawn? {
        let key = "\(route.stops.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";"))|\(size.width)x\(size.height)|\(dark)"
        if let img = drawn[key] { return img }
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let config = MKStandardMapConfiguration(emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config
        // The whole route, with room around it for the marks.
        var rect = route.legs.map(\.boundingMapRect).reduce(MKMapRect.null) { $0.union($1) }
        rect = rect.insetBy(dx: -rect.width * 0.1 - 1, dy: -rect.height * 0.1 - 1)
        // Widen the short side to the picture's shape, so MapKit doesn't crop the route to fit.
        let aspect = size.width / size.height
        if rect.width / rect.height < aspect {
            rect = rect.insetBy(dx: -(rect.height * aspect - rect.width) / 2, dy: 0)
        } else {
            rect = rect.insetBy(dx: 0, dy: -(rect.width / aspect - rect.height) / 2)
        }
        options.mapRect = rect
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let ink = dark ? NSColor.white : NSColor.black
        let paper = dark ? NSColor.black : NSColor.white
        let map = greyscale(snapshot.image)
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
        let result = Drawn(image: image) { c in
            let p = snapshot.point(for: c)
            return CGPoint(x: p.x, y: size.height - p.y)
        }
        drawn[key] = result
        return result
    }

    /// The map in greys, to match RollCall's black and white.
    private static func greyscale(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
}
