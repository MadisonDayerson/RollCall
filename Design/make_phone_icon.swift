// Draws the layers of the iPhone and iPad icon, which iOS lights as Liquid Glass: the gothic "RC", the double frame and
// "ROLLCALL" under it, each white on clear. iOS/RollCall/AppIcon.icon/icon.json puts them on black (it opens in Icon
// Composer, which comes with Xcode).
// Run: swift Design/make_phone_icon.swift [font file]
import AppKit
import CoreText

let size = 1024.0
let file = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design/fonts/bosieh/Bosieh-Regular.otf"
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: file) as CFURL) as! [CTFontDescriptor]
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

func layer(_ name: String, _ draw: (CGContext) -> Void) {
    let c = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setStrokeColor(white)
    draw(c)
    let out = URL(fileURLWithPath: "iOS/RollCall/AppIcon.icon/Assets/\(name).png")
    try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: out)
}

/// Text centred on (x, y) by its drawn shape, as large as fits in a box.
func text(_ c: CGContext, _ text: String, _ font: CTFont, kern: Double = 0, at centre: CGPoint, fitting box: CGSize) {
    func line(_ scale: Double) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .init(kCTFontAttributeName as String): CTFontCreateCopyWithAttributes(font, 100 * scale, nil, nil),
            .init(kCTForegroundColorAttributeName as String): white, .kern: kern * scale]))
    }
    c.textPosition = .zero
    let probe = CTLineGetImageBounds(line(1), c)
    let drawn = line(min(box.width / probe.width, box.height / probe.height)), b = CTLineGetImageBounds(drawn, c)
    c.textPosition = CGPoint(x: centre.x - b.midX, y: centre.y - b.midY)
    CTLineDraw(drawn, c)
}

layer("RC") { text($0, "RC", CTFontCreateWithFontDescriptor(descriptors[0], 100, nil), at: CGPoint(x: 512, y: 552), fitting: CGSize(width: 600, height: 440)) }
layer("Name") { text($0, "ROLLCALL", CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 100, nil), kern: 36, at: CGPoint(x: 512, y: 228), fitting: CGSize(width: 440, height: 46)) }
layer("Frame") { c in
    // Their corners follow the icon's.
    for (inset, width) in [(62.0, 9.0), (84, 4)] {
        c.setLineWidth(width)
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset),
                         cornerWidth: 256 - inset, cornerHeight: 256 - inset, transform: nil))
        c.strokePath()
    }
}
