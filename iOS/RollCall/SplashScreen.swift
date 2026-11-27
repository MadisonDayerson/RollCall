import SwiftUI

/// The splash over the whole screen, once RollCall is on it. Black to begin with, like the launch screen before it.
struct SplashScreen: View {
    /// It's been shown since RollCall opened.
    @MainActor static var played = false
    @Environment(\.scenePhase) private var phase
    @State private var started = false
    let finished: () -> Void

    var body: some View {
        GeometryReader { screen in
            if started, let monogram = UIImage(named: "Monogram")?.cgImage, let title = UIImage(named: "Title")?.cgImage {
                Splash(logo: SplashLogo(monogram: monogram, title: title), size: screen.size, finished: finished)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .onChange(of: phase, initial: true) { _, now in
            if now == .active {
                started = true
                Self.played = true
            }
        }
    }
}
