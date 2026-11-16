import AppKit
import Vision
import UniformTypeIdentifiers

/// Event posters: the picture you copied or chose, and the writing on it, read on this Mac with Apple's
/// text recognition. Nothing is sent anywhere.
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

    /// The poster's writing, top to bottom, with words side by side on one line. Empty if there's none.
    static func text(in image: CGImage) async -> String {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-AU", "en-US"]
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let pieces = (request.results ?? []).compactMap { o in
                    o.topCandidates(1).first.map { (text: $0.string, box: o.boundingBox) }
                }
                done.resume(returning: readingOrder(pieces))
            }
        }
    }

    /// Lines of text in reading order. Boxes are Vision's: 0 to 1, measured up from the bottom left.
    /// Pieces whose middles are level (within half a line) are one line, read left to right.
    static func readingOrder(_ pieces: [(text: String, box: CGRect)]) -> String {
        var lines: [[(text: String, box: CGRect)]] = []
        for p in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = lines.last?.last, abs(last.box.midY - p.box.midY) < min(last.box.height, p.box.height) / 2 {
                lines[lines.count - 1].append(p)
            } else {
                lines.append([p])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
            .joined(separator: "\n")
    }
}
