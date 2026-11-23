import SwiftUI

/// Numbered steps to follow, in setup on both apps. **Bold** works in them.
struct NumberedSteps: View {
    var steps: [String]
    init(_ steps: [String]) { self.steps = steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").bold().frame(width: 22, height: 22)
                        .background(Circle().stroke(Color.primary, lineWidth: 1.5))
                    Text(.init(s)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
