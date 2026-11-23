import AppKit
import VisionKit
import UniformTypeIdentifiers

/// Event posters: the picture you copied or chose, and the writing on it, read on this Mac with Live Text
/// (as in Preview and Photos). Nothing is sent anywhere.
enum Poster {
    /// The picture on the clipboard: a copied image, or a copied image file. Nil for anything else.
    static func pasted(_ pb: NSPasteboard = .general) -> CGImage? {
        let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        // A copied file: only a picture counts (the clipboard also holds the file's icon, which isn't a poster).
        if let file = files.first {
            return UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true ? image(at: file) : nil
        }
        return NSImage(pasteboard: pb).flatMap(cgImage)
    }

    static func image(at url: URL) -> CGImage? { NSImage(contentsOf: url).flatMap(cgImage) }

    private static func cgImage(_ i: NSImage) -> CGImage? { i.cgImage(forProposedRect: nil, context: nil, hints: nil) }

    /// The poster's writing in reading order, keeping each column together. Empty if there's none.
    static func text(in image: CGImage) async -> String {
        let analysis = try? await ImageAnalyzer().analyze(image, orientation: .up, configuration: .init(.text))
        return analysis?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
