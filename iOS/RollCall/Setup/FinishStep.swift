import SwiftUI

/// What's set up and what isn't; tapping one that isn't goes back to it.
struct FinishStep: View {
    @Environment(PhoneModel.self) private var model
    let open: (SetupStep) -> Void

    var body: some View {
        StepHeader(title: "You're all set", text: "RollCall now reads your sources and lists the rides it finds.")
        Section {
            ForEach(SetupStep.counted, id: \.self) { step in
                if model.isDone(step) {
                    DoneLabel(text: step.name)
                } else {
                    Button { open(step) } label: {
                        LabeledContent {
                            Text("Set up").foregroundStyle(Color.accentColor)
                        } label: {
                            Label(step.name, systemImage: "circle").foregroundStyle(Color.primary)
                        }
                    }
                }
            }
        } footer: {
            Text("You can run this setup again any time from Settings → Run setup…")
        }
    }
}
