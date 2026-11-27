import SwiftUI

/// "Roll Call" in the logo's gothic lettering, at the foot of the Mac's sidebar and above the rides list when it's
/// pulled down to refresh on iPhone and iPad. While the sources are checked it fills from left to right with glowing blue
/// letters, like a neon sign warming up, whose glow gently breathes while it works, and pulses blue when it's done.
struct Wordmark: View {
    /// The lettering (Design/Wordmark.png), which each app keeps in its own way.
    let picture: Image
    /// How far the check has got, 0 to 1; nil when it isn't checking.
    @ObservedObject var progress: Box<Double?>
    var width: CGFloat = 120
    /// How much of it glows, following the progress smoothly.
    @StateObject private var lit = Box(0.0)
    /// The whole wordmark's glow when the check finishes.
    @StateObject private var pulse = Box(0.0)
    /// The lit letters' glow breathing in and out while checking, 0 to 1.
    @StateObject private var breath = Box(0.0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let letters = picture.renderingMode(.template).resizable().scaledToFit()
        letters
            .foregroundStyle(.secondary)
            .overlay {
                letters.foregroundStyle(Neon.core).mask(alignment: .leading) { NeonReveal(lit: lit.value) }.neonHaze(breath: breath.value)
            }
            .overlay { letters.foregroundStyle(Neon.core).neonHaze().opacity(pulse.value) }
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Roll Call")
            .accessibilityValue(progress.value.map { "Checking sources, \(Int($0 * 100)) percent" } ?? "")
            .onChange(of: progress.value) { old, new in changed(from: old, to: new) }
    }

    private func changed(from old: Double?, to new: Double?) {
        if let new {
            withAnimation(.easeOut(duration: 0.6)) { lit.value = new }
            if old == nil, !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breath.value = 1 }
            }
            return
        }
        guard old != nil else { return }
        withAnimation(.easeOut(duration: 0.25)) { breath.value = 0 }
        // Done: the rest lights up, the whole wordmark glows, then it fades back to its usual grey.
        guard !reduceMotion else { lit.value = 0; return }
        withAnimation(.easeOut(duration: 0.25)) { lit.value = 1; pulse.value = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            lit.value = 0  // hidden under the pulse, so it doesn't sweep back
            withAnimation(.easeOut(duration: 1.0)) { pulse.value = 0 }
        }
    }
}
