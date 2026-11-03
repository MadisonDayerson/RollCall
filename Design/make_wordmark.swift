// Draws the "Roll Call" wordmark shown at the foot of the window's sidebar: black gothic letters on a clear
// background, which the app tints to match the sidebar text, so it suits light and dark mode.
// Run: swift Design/make_wordmark.swift Design/Wordmark.png [font file or font name]
import AppKit
import CoreText

let args = Array(CommandLine.arguments.dropFirst())
let out = args.first ?? "Wordmark.png"
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

let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Roll Call", attributes: [
    .init(kCTFontAttributeName as String): font(fontChoice, size: 200),
    .init(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)]))

// Measure the drawn letters, then draw them into a canvas that just fits, with a little room around.
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let probe = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let b = CTLineGetImageBounds(line, probe)
let pad = 12.0
let ctx = CGContext(data: nil, width: Int(ceil(b.width + pad * 2)), height: Int(ceil(b.height + pad * 2)),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.textPosition = CGPoint(x: pad - b.minX, y: pad - b.minY)
CTLineDraw(line, ctx)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Saved \(out) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
