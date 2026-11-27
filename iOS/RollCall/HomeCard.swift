import SwiftUI

/// A heading and what's under it on a rounded card of glass, with a button or a note beside the heading.
struct HomeCard<Content: View>: View {
    let title: String
    var count: Int? = nil
    var note: String? = nil
    var action: String? = nil
    var perform: () -> Void = {}
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PatchLabel(text: title, count: count)
                Spacer()
                if let note { Text(note).font(.subheadline.weight(.semibold)) }
                if let action { Button(action, action: perform).font(.subheadline) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        // The glass is behind what's on the card, so date patches and text keep their full black and white.
        .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 26)) }
    }
}
