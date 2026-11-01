// Draws the RollCall logo: white gothic "RC" on black, in a thin double frame (streetwear-patch style).
// Run: swift Design/make_icon.swift Design/RollCall.png [font file or font name]
// (then build.sh turns the picture into the app icon)
import AppKit
import CoreText

let size = 1024.0
let args = Array(CommandLine.arguments.dropFirst())
let out = args.first ?? "RollCall.png"
let fontChoice = args.count > 1 ? args[1] : "Design/fonts/bosieh/Bosieh-Regular.otf"

/// A font from a file in this folder, or one installed on the Mac.
func font(_ choice: String, size: Double) -> CTFont {
    if FileManager.default.fileExists(atPath: choice),
       let descs = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: choice) as CFURL) as? [CTFontDescriptor],
       let d = descs.first {
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }
    return CTFontCreateWithName(choice as CFString, size, nil)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func grey(_ v: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: a) }
func rounded(_ r: CGRect, _ radius: Double) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// The tile, on Apple's icon grid (824 pt body in a 1024 canvas), with a soft shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: grey(0, 0.45))
ctx.addPath(rounded(tile, 185)); ctx.setFillColor(grey(0.04)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(tile, 185)); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [grey(0.17), grey(0.06), grey(0.0)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// A thin double frame inside the tile.
ctx.setStrokeColor(grey(1, 0.9)); ctx.setLineWidth(6)
ctx.addPath(rounded(tile.insetBy(dx: 44, dy: 44), 146)); ctx.strokePath()
ctx.setLineWidth(2.5)
ctx.addPath(rounded(tile.insetBy(dx: 60, dy: 60), 132)); ctx.strokePath()

func line(_ text: String, _ f: CTFont, kern: Double = 0) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        .init(kCTFontAttributeName as String): f,
        .init(kCTForegroundColorAttributeName as String): grey(1),
        .kern: kern]))
}

/// Draws a line of text centred on (x, y) by its drawn shape rather than its font box.
func draw(_ l: CTLine, centre x: Double, _ y: Double) {
    ctx.textPosition = .zero  // image bounds are measured from the current text position
    let b = CTLineGetImageBounds(l, ctx)
    ctx.textPosition = CGPoint(x: x - b.midX, y: y - b.midY)
    CTLineDraw(l, ctx)
}

// "RC", as large as fits inside the frame.
ctx.textPosition = .zero
let probe = CTLineGetImageBounds(line("RC", font(fontChoice, size: 500)), ctx)
let rcSize = 500 * min(560 / probe.width, 380 / probe.height)
draw(line("RC", font(fontChoice, size: rcSize)), centre: 512, 548)

// The name in small spaced capitals underneath.
draw(line("ROLLCALL", CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 44, nil), kern: 16), centre: 512, 250)

let img = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")

// The menu bar icon: black gothic "RC" on clear, 18 pt tall at 2x. macOS recolours it for light and dark menu bars.
let menuHeight = 36.0
ctx.textPosition = .zero
let menuProbe = CTLineGetImageBounds(line("RC", font(fontChoice, size: 100)), ctx)
let menuFont = font(fontChoice, size: 100 * (menuHeight - 4) / menuProbe.height)
let menuLine = line("RC", menuFont)
let menuBox = CTLineGetImageBounds(menuLine, ctx)
let menuWidth = ceil(menuBox.width + 4)
let mctx = CGContext(data: nil, width: Int(menuWidth), height: Int(menuHeight), bitsPerComponent: 8, bytesPerRow: 0,
                     space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
mctx.textPosition = CGPoint(x: 2 - menuBox.minX, y: 2 - menuBox.minY)
let blackLine = CTLineCreateWithAttributedString(NSAttributedString(string: "RC", attributes: [
    .init(kCTFontAttributeName as String): menuFont,
    .init(kCTForegroundColorAttributeName as String): grey(0)]))
CTLineDraw(blackLine, mctx)
let menuOut = URL(fileURLWithPath: out).deletingLastPathComponent().appendingPathComponent("MenuIcon.png")
try! NSBitmapImageRep(cgImage: mctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: menuOut)
print("Wrote \(menuOut.path)")
