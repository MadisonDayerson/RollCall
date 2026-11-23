import SwiftUI

/// Connecting Facebook's private calendar of the events you've responded to.
struct FacebookStep: View {
    @Environment(PhoneModel.self) private var model
    @State private var link = ""
    @State private var connecting = false
    @State private var problem: String?

    var body: some View {
        StepHeader(title: "Your Facebook events",
                   text: "Facebook can share a private calendar of the events you're Going or Interested in, so the bike ones come in by themselves.")
        if model.facebookConnected {
            Section {
                DoneLabel(text: "Connected. Bike events you're Going or Interested in on Facebook come in by themselves, as Going or Maybe.")
                Button("Disconnect", role: .destructive) { model.removeSource(FeedLinks.facebookCalendarID) }
            } footer: {
                if model.macFolder != nil { Text("It's shared with your Mac, so disconnecting it here disconnects it there too.") }
            }
        } else {
            Section {
                NumberedSteps(["On a computer, go to **facebook.com/events** and sign in.",
                               "Find **Add to calendar** on the Events page.",
                               "Right-click it and choose **Copy Link**.",
                               "Send the link to yourself (in Notes, say), then copy it here."])
            } header: {
                PatchLabel(text: "Copy your link")
            } footer: {
                Text((model.macFolder == nil ? "" : "Or connect it in RollCall on your Mac, under Settings → Facebook, and it comes here by itself.\n\n")
                     + "No computer? Type facebook.com/events into Safari here (not the Facebook app), choose Request Desktop Website from the page menu, then touch and hold Add to calendar and tap Copy Link. Facebook doesn't always show it on a phone.")
            }
            Section {
                TextField("https://www.facebook.com/events/ical/…", text: $link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).onSubmit(connect)
                if let problem { ProblemLabel(text: problem) }
                if connecting { ProgressView() } else {
                    Button("Connect", action: connect).disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                PatchLabel(text: "Paste it here")
            } footer: {
                Text("Keep this link to yourself: anyone who has it can see your events. Only bike events are kept.")
            }
        }
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            problem = await model.connectFacebook(link)
            if problem == nil { link = "" }
            connecting = false
        }
    }
}
