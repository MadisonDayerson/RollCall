import SwiftUI

/// Something that went wrong, in orange.
struct ProblemLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
    }
}

/// Something that's set up.
struct DoneLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
    }
}
