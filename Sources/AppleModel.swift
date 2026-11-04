import Foundation
import FoundationModels

/// Every request to Apple's on-device model goes through here, prepared so the model will take it:
/// - Its blocking filter is set to the mode Apple provides for reading people's own messages
///   (`permissiveContentTransformations`), since RollCall only ever asks for plain text back.
/// - Swearing and slurs are left out (the model itself can still refuse over them), long tracking links are
///   shortened and junk characters removed.
/// - The text is trimmed to fit the model's short memory (4,096 tokens), keeping the messages that matter.
/// - When it still says no, it tries once more in a way that suits the reason: less text, only the key
///   messages, only messages in a language it reads, or after a short wait when it's busy.
/// - One request at a time, as the model allows.
/// Nothing leaves the Mac, and the messages themselves are never changed: only what the model reads.
enum AppleModel {
    enum Failure: Error, Equatable { case unavailable, filtered, refused, tooLong, language, busy, other }

    /// What to read: a heading, then lines (messages, or a post). `keep` marks lines that stay when it's trimmed.
    struct Input: Equatable {
        var heading: String
        var lines: [String]
        var keep: Set<Int> = []

        /// The original text, for checking a link the model gives back.
        var text: String { ([heading] + lines).joined(separator: "\n") }
    }

    /// Apple Intelligence is on and the model is ready (macOS 26 or later).
    static var available: Bool {
        guard #available(macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// About a third of the model's memory, which leaves room for the instructions and its reply.
    static let maxChars = 6000

    static func ask(instructions: String, _ input: Input) async -> String? {
        guard available, #available(macOS 26, *) else { return nil }
        await turn.enter()
        defer { Task { await turn.leave() } }
        var input = input
        var budget = maxChars
        var waited = false
        for _ in 0..<4 {
            switch await once(instructions, fitted(input, maxChars: budget)) {
            case .success(let reply):
                guard looksLikeRefusal(reply) else { return reply }
                guard let fewer = keyOnly(input) else { return nil }
                input = fewer
            case .failure(.tooLong):
                budget /= 2
            case .failure(.filtered), .failure(.refused):
                guard let fewer = keyOnly(input) else { return nil }
                input = fewer
            case .failure(.language):
                guard let readable = readableOnly(input) else { return nil }
                input = readable
            case .failure(.busy) where !waited:
                waited = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            default:
                return nil
            }
        }
        return nil
    }

    @available(macOS 26, *)
    private static func once(_ instructions: String, _ prompt: String) async -> Result<String, Failure> {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            // Greedy sampling gives the same answer for the same text every time.
            return .success(try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy)).content)
        } catch {
            return .failure(failure(error))
        }
    }

    /// macOS 26 and 27 name the model's errors differently.
    @available(macOS 26, *)
    static func failure(_ error: Error) -> Failure {
        if #available(macOS 27, *) {
            if let e = error as? LanguageModelError {
                switch e {
                case .contextSizeExceeded: return .tooLong
                case .rateLimited, .timeout: return .busy
                case .guardrailViolation: return .filtered
                case .refusal: return .refused
                case .unsupportedLanguageOrLocale: return .language
                default: return .other
                }
            }
            if let e = error as? LanguageModelSession.Error, e == .concurrentRequests { return .busy }
        }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return .tooLong
            case .rateLimited, .concurrentRequests: return .busy
            case .guardrailViolation: return .filtered
            case .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .language
            case .assetsUnavailable: return .unavailable
            default: return .other
            }
        }
        return .other
    }

    // MARK: Preparing the text

    /// Group chats swear. The model can refuse a whole conversation over one slur or swear word,
    /// so those are left out of what it reads.
    static func tidied(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\b(?:retard\w*|f+u+c+k\w*|fck\w*|sh[i1]t\w*|c+u+n+t\w*|bitch\w*|fag\w*|wank\w*|twat\w*|dickhead\w*|motherf\w*|bastard\w*|slut\w*|whore\w*|n[i1]gg\w*|spastic\w*|tranny\w*)"#,
                                  with: "…", options: .regularExpression)
    }

    /// A link without its tracking (`?fbclid=…`), and no longer than it needs to be to recognise.
    static func shortened(_ link: String) -> String {
        var l = link
        if let q = l.firstIndex(where: { $0 == "?" || $0 == "#" }) { l = String(l[..<q]) }
        return l.count > 100 ? String(l.prefix(100)) : l
    }

    /// What the model reads: swearing hidden, links shortened, invisible characters, runs of the same
    /// character ("!!!!!!!!", "hahahahahaha") and extra spaces cut down.
    static func prepared(_ text: String) -> String {
        var t = tidied(text)
        let links = try! NSRegularExpression(pattern: #"https?://[^\s<>"]+"#)
        for m in links.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            if let r = Range(m.range, in: t) { t.replaceSubrange(r, with: shortened(String(t[r]))) }
        }
        t = t.unicodeScalars.filter { !(CharacterSet.controlCharacters.contains($0) && $0 != "\n") && !["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{2060}"].contains($0) }
            .map(String.init).joined()
        t = t.replacingOccurrences(of: #"(.)\1{3,}"#, with: "$1$1$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\S{2,4}?)\1{3,}"#, with: "$1$1$1", options: .regularExpression)
        return t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
    }

    /// The prepared text in no more than `maxChars`: the oldest lines go first, then long kept lines are cut.
    static func fitted(_ input: Input, maxChars: Int) -> String {
        var lines = input.lines.enumerated().map { (i: $0.offset, text: prepared($0.element)) }
        let heading = prepared(input.heading)
        func size() -> Int { heading.count + 2 + lines.reduce(0) { $0 + $1.text.count + 1 } }
        while size() > maxChars, let drop = lines.firstIndex(where: { !input.keep.contains($0.i) }), lines.count > 1 {
            lines.remove(at: drop)
        }
        while size() > maxChars, let longest = lines.indices.max(by: { lines[$0].text.count < lines[$1].text.count }),
              lines[longest].text.count > 40 {
            let over = size() - maxChars
            lines[longest].text = String(lines[longest].text.prefix(max(40, lines[longest].text.count - over - 1))) + "…"
        }
        return heading + "\n\n" + lines.map(\.text).joined(separator: "\n")
    }

    /// Just the lines that matter (or the last few), for a second try. Nil when that's already all there is.
    static func keyOnly(_ input: Input) -> Input? {
        let keep = input.keep.isEmpty ? Set(input.lines.indices.suffix(3)) : input.keep
        guard keep.count < input.lines.count else { return nil }
        let order = input.lines.indices.filter(keep.contains)
        return Input(heading: input.heading, lines: order.map { input.lines[$0] }, keep: Set(order.indices))
    }

    /// Lines mostly in a script the model reads (Latin letters). Nil when nothing would change.
    static func readableOnly(_ input: Input) -> Input? {
        let order = input.lines.indices.filter { mostlyLatin(input.lines[$0]) }
        guard !order.isEmpty, order.count < input.lines.count else { return nil }
        return Input(heading: input.heading, lines: order.map { input.lines[$0] },
                     keep: Set(order.enumerated().filter { input.keep.contains($0.element) }.map(\.offset)))
    }

    static func mostlyLatin(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }
        return Double(letters.filter { $0.value < 0x250 }.count) / Double(letters.count) >= 0.6
    }

    /// With the filter relaxed, the model says no in words instead of with an error.
    static func looksLikeRefusal(_ reply: String) -> Bool {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"(?i)^(?:i'?m sorry|sorry,? (?:but )?i|i (?:can(?:no|')t|am unable|won'?t)|as an ai|i apologi[sz]e)"#, options: .regularExpression) != nil
    }

    /// The link as it was written, for a shortened one the model gave back. Nil if the text never had it.
    static func originalLink(_ link: String, in text: String) -> String? {
        let links = (try? NSRegularExpression(pattern: #"https?://[^\s<>"]+"#))?.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
        return links.first { $0 == link || shortened($0) == link || ($0.hasPrefix(link) && link.count >= 15) }
    }

    /// One request at a time: the model turns down a second while it's answering.
    private static let turn = Turn()

    private actor Turn {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            guard busy else { busy = true; return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func leave() {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
    }
}
