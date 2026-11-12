import SwiftUI

/// "Roll Call" in the logo's gothic lettering, at the foot of the sidebar. While the sources are checked it fills
/// from left to right with glowing blue letters, like a neon sign warming up, and pulses blue when it's done.
struct Wordmark: View {
    /// How far the check has got, 0 to 1; nil when it isn't checking.
    @ObservedObject var progress: Box<Double?>
    /// How much of it glows, following the progress smoothly.
    @StateObject private var lit = Box(0.0)
    /// The whole wordmark's glow when the check finishes.
    @StateObject private var pulse = Box(0.0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Near-white blue letters in a deep blue haze.
    private static let core = Color(red: 0.62, green: 0.94, blue: 1.0)
    private static let haze = Color(red: 0.1, green: 0.45, blue: 1.0)
    /// The soft leading edge of the glow, in points.
    private static let edge: CGFloat = 14

    var body: some View {
        if let img = Brand.wordmark {
            let letters = Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
            letters
                .foregroundStyle(.secondary)
                .overlay {
                    glowing(letters.foregroundStyle(Self.core).mask(alignment: .leading) { reveal })
                }
                .overlay { glowing(letters.foregroundStyle(Self.core)).opacity(pulse.value) }
                .frame(maxWidth: 120, maxHeight: 34)
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityLabel("Roll Call")
                .accessibilityValue(progress.value.map { "Checking sources, \(Int($0 * 100)) percent" } ?? "")
                .onChange(of: progress.value) { old, new in changed(from: old, to: new) }
        }
    }

    /// Lit up to how far the check has got, fading out at the leading edge.
    private var reveal: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Rectangle().frame(width: max(0, g.size.width * lit.value - Self.edge))
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: lit.value > 0 ? Self.edge : 0)
                Spacer(minLength: 0)
            }
        }
    }

    private func glowing(_ v: some View) -> some View {
        v.shadow(color: Self.haze, radius: 2).shadow(color: Self.haze, radius: 6)
    }

    private func changed(from old: Double?, to new: Double?) {
        if let new {
            withAnimation(.easeOut(duration: 0.6)) { lit.value = new }
            return
        }
        guard old != nil else { return }
        // Done: the rest lights up, the whole wordmark glows, then it fades back to its usual grey.
        guard !reduceMotion else { lit.value = 0; return }
        withAnimation(.easeOut(duration: 0.25)) { lit.value = 1; pulse.value = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            lit.value = 0  // hidden under the pulse, so it doesn't sweep back
            withAnimation(.easeOut(duration: 1.0)) { pulse.value = 0 }
        }
    }
}
