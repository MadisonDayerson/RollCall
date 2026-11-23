import SwiftUI

/// An empty page, as on the Mac: the gothic "RC" with a line of help underneath. The "RC" is a picture of the
/// letters (Design/Monogram.png), because the font's licence doesn't allow shipping it.
struct EmptyState: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image("Monogram").resizable().scaledToFit()
                .frame(height: 46).foregroundStyle(.quaternary).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(text)
                if let detail { Text(detail).font(.callout) }
            }
            .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
