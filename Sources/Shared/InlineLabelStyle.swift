import SwiftUI

/// An icon then its words on one line, in the text colour. A list on iPhone and iPad lays labels out as its own rows.
struct InlineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon; configuration.title }
    }
}
