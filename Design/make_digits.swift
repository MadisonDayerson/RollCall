// Draws the digits 0–9 in the logo's gothic lettering for the day on each ride's date patch: black on a clear
// background, tinted by the app. Every digit is as wide as the font spaces it and shares one height and
// baseline, so placing them side by side sets a number as the font would.
// Run: swift Design/make_digits.swift            (writes Design/Digits/0.png … 9.png)
import AppKit
import CoreText

let fontFile = "Design/fonts/bosieh/Bosieh-Regular.otf"
let outDir = "Design/Digits"
let size = 160.0
let pad = 6.0

guard let descs = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: fontFile) as CFURL) as? [CTFontDescriptor],
      let desc = descs.first else { fatalError("Put the Bosieh font at \(fontFile) first (see Design/fonts/bosieh/ABOUT.txt).") }
let font = CTFontCreateWithFontDescriptor(desc, size, nil)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let probe = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func line(_ s: String) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
        .init(kCTFontAttributeName as String): font,
        .init(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)]))
}

// One height for all: from the lowest to the highest ink of any digit.
let digits = (0...9).map(String.init)
let bounds = digits.map { CTLineGetImageBounds(line($0), probe) }
let bottom = bounds.map(\.minY).min()!, top = bounds.map(\.maxY).max()!
let height = Int(ceil(top - bottom + pad * 2))

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for d in digits {
    let l = line(d)
    let width = Int(ceil(CTLineGetTypographicBounds(l, nil, nil, nil)))
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.textPosition = CGPoint(x: 0, y: pad - bottom)
    CTLineDraw(l, ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(d).png"))
}
print("Saved \(outDir)/0.png … 9.png (height \(height))")
