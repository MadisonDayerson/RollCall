import SwiftUI

/// Linking Beeper. Its connection for other apps only runs on a computer, so the Mac reads the chats and shares the rides
/// here; this says how, and watches for the Mac to say it's connected.
struct ChatsStep: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let device = UIDevice.current.model
        StepHeader(title: "Connect your group chats",
                   text: "Lots of rides are planned in group chats. Beeper is a free app that brings WhatsApp, Messenger and your other chats into one place, and RollCall on your Mac reads just the ones you choose. Rides come here without the messages: chats stay on your Mac.")
        if let chats = model.state.macChats {
            Section { DoneLabel(text: "Connected to Beeper: your Mac is checking \(chats) chat\(chats == 1 ? "" : "s").") }
        } else if model.macFolder == nil {
            Section {
                Label("Share with your Mac first", systemImage: "laptopcomputer").foregroundStyle(.primary)
            } footer: {
                Text("Go back a step to do that. Beeper only lets other apps read chats on a computer, so without a Mac, skip this step.")
            }
        } else {
            Section {
                NumberedSteps(["Open RollCall, click **RC** in the menu bar, then **Set up RollCall…**",
                               "Click through to **Chats**, then **Set up Beeper**. (Already use Beeper? Click **Connect to Beeper…** instead.)",
                               "Follow the steps there. They go through downloading Beeper, adding your chats and letting RollCall read them.",
                               "For WhatsApp, Beeper shows a square code: on your phone, open WhatsApp → **Settings** → **Linked Devices** → **Link a Device** and point the camera at it.",
                               "Tick the group chats where people post rides."])
            } header: {
                PatchLabel(text: "On your Mac")
            } footer: {
                Text("RollCall can never send, edit or delete messages.")
            }
            Section {
                HStack(spacing: 10) { ProgressView(); Text("Waiting for your Mac…").foregroundStyle(.secondary) }
            } footer: {
                Text("It can take a few minutes to reach this \(device). You can skip this and finish it later.")
            }
        }
    }
}
