import SwiftUI

/// Getting your own free road alerts key, and pasting it.
struct RoadsStep: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        StepHeader(title: "Road alerts",
                   text: "See crashes, closures and roadworks on each ride's route in Victoria. It needs a free key of your own. Don't ride in Victoria? Skip this step.")
        if !model.roadAlertsKeySaved {
            Section {
                NumberedSteps(["Open the Transport Victoria Open Data Portal (**opendata.transport.vic.gov.au**), then choose **Login** → **Sign up**.",
                               "Enter your details, then the code they email you.",
                               "The portal asks for an authenticator app, such as Google Authenticator: scan its QR code and enter the code the app shows.",
                               "Log in, open **My Account → Profile → API tokens** and copy your key."])
            } header: {
                PatchLabel(text: "Get your key")
            } footer: {
                Text("It's easiest on a computer, so your phone can scan the QR code. Already have a key on your Mac? Each device needs it pasted once: it isn't shared between them.")
            }
        }
        RoadAlertsSection()
    }
}
