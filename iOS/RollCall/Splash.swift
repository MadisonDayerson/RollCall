import SwiftUI

/// Shown as RollCall opens: the logo bursts out of a blast of blue flame and embers, stays long enough to read, then a
/// shimmer of heat and a low blue fire sweep across it from left to right, leaving embers on the breeze as the app appears
/// behind. With Reduce Motion on, or without Metal, it fades in and out.
struct Splash: View {
    let logo: SplashLogo
    let size: CGSize
    /// The last ember is out.
    let finished: () -> Void
    @State private var fire: Fire?
    /// The fire's ready to start, or there won't be one.
    @State private var ready = false
    /// How far the splash has got since then, in seconds.
    @State private var clock = 0.0
    @Environment(\.displayScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Without the fire: the logo fades in, stays until this, then fades away.
    private static let fades = 1.4, fading = 0.6

    var body: some View {
        ZStack {
            // Under the fire for a moment too, until it's drawn its first picture.
            if fire == nil || clock < 0.2 {
                ZStack {
                    Color.black
                    if ready && fire == nil { logo.view.opacity(ease(clock, from: 0, for: 0.3)) }
                }
                .opacity(fire == nil ? 1 - ease(clock, from: Self.fades, for: Self.fading) : 1)
            }
            if let fire { FireView(fire: fire, time: clock) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        // Until the app starts to show, a tap isn't for what's unseen behind.
        .allowsHitTesting(clock < (fire == nil ? Self.fades : Fire.opens))
        .accessibilityHidden(true)
        .task {
            fire = reduceMotion ? nil : await makeFire()?.value
            ready = true
            await run(to: fire == nil ? Self.fades + Self.fading : Fire.seconds)
            finished()
        }
    }

    /// Moves the clock on, waiting while the app is too busy opening to draw, so none of the splash is missed.
    private func run(to end: Double) async {
        var last = Date()
        while clock < end, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(8))
            let now = Date()
            clock += min(0.05, now.timeIntervalSince(last))
            last = now
        }
    }

    /// Made off the main thread, as its shaders take a moment to compile.
    private func makeFire() -> Task<Fire?, Never>? {
        let picture = ImageRenderer(content: ZStack { Color.black; logo.view }.frame(width: SplashLogo.side, height: SplashLogo.side))
        picture.scale = scale
        guard let lit = picture.cgImage else { return nil }
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let frame = CGRect(x: middle.x - SplashLogo.side / 2, y: middle.y - SplashLogo.side / 2, width: SplashLogo.side, height: SplashLogo.side)
        let letters = logo.rows(around: middle), size = size, scale = scale
        return Task.detached { Fire(size: size, scale: scale, lit: lit, frame: frame, letters: letters) }
    }
}

/// From 0 to 1, starting and ending gently.
func ease(_ time: Double, from start: Double, for length: Double) -> Double {
    let part = min(1, max(0, (time - start) / length))
    return part * part * (3 - 2 * part)
}
