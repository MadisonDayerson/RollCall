import SwiftUI

/// The gothic "RC" with "RollCall" under it (Design/Monogram.png and Design/Title.png), lit blue.
struct SplashLogo {
    let monogram: CGImage
    let title: CGImage
    /// Where the rows are, from the middle of the logo.
    private static let monogramHeight: CGFloat = 124
    private static let titleHeight: CGFloat = 40
    private static let gap: CGFloat = 22
    /// Room around the letters for their glow.
    static let side: CGFloat = 320

    var view: some View {
        ZStack {
            letters(monogram, 0)
            letters(title, 1)
        }
        .frame(width: Self.side, height: Self.side)
    }

    /// Each row's picture and where it is, with the middle of the logo at `middle`.
    func rows(around middle: CGPoint) -> [Fire.Letters] {
        [(monogram, 0), (title, 1)].map { ($0, Self.frame($0, of: $1).offsetBy(dx: middle.x, dy: middle.y)) }
    }

    private func letters(_ picture: CGImage, _ row: Int) -> some View {
        let box = Self.frame(picture, of: row)
        return Image(decorative: picture, scale: 1).renderingMode(.template).resizable()
            .foregroundStyle(Neon.core)
            .neonHaze()
            .frame(width: box.width, height: box.height)
            .offset(x: box.midX, y: box.midY)
    }

    private static func frame(_ picture: CGImage, of row: Int) -> CGRect {
        let height = row == 0 ? monogramHeight : titleHeight
        let width = height * CGFloat(picture.width) / CGFloat(picture.height)
        let top = -(monogramHeight + gap + titleHeight) / 2
        return CGRect(x: -width / 2, y: row == 0 ? top : top + monogramHeight + gap, width: width, height: height)
    }
}
