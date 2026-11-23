import SwiftUI

/// Sharing with RollCall on the Mac through iCloud Drive.
struct MacStep: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let device = UIDevice.current.model
        StepHeader(title: "Share with your Mac",
                   text: "RollCall on your Mac and \(device) share rides, choices and sources through a folder in your iCloud Drive. Your Mac's sources, Facebook events and chat rides then come here by themselves. No Mac? Skip this step.")
        if model.macFolder != nil {
            Section { DoneLabel(text: "Sharing with RollCall on your Mac") }
        } else {
            Section {
                NumberedSteps(["Open the **Settings** app, then tap your name → **iCloud** → **Drive**.",
                               "Turn on **Sync this \(device)**."])
            } header: {
                PatchLabel(text: "On this \(device)")
            }
            Section {
                NumberedSteps(["Open RollCall, then its **Settings**.",
                               "Under **iPhone and iPad**, turn on **Share with RollCall on iPhone and iPad**."])
            } header: {
                PatchLabel(text: "On your Mac")
            } footer: {
                Text("If it's greyed out, turn on iCloud Drive first: System Settings → your name → iCloud. Use the same Apple Account as here.")
            }
            Section {
                NumberedSteps(["Tap **Choose folder…** below.",
                               "Tap **Browse**, then **iCloud Drive**.",
                               "Open the **RollCall** folder and tap **Open**."])
                // Above the button, where it was tapped, rather than out of sight under it.
                if let problem = model.shareProblem { ProblemLabel(text: problem) }
                MacFolderButton(title: "Choose folder…")
            } header: {
                PatchLabel(text: "Then, here")
            }
        }
    }
}
