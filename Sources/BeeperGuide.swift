import SwiftUI
import AppKit

/// Big, plain steps for setting up Beeper, each with a check RollCall does itself.
struct BeeperGuide: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        let step = model.guide ?? .download
        VStack(alignment: .leading, spacing: 16) {
            if step != .done {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Setting up Beeper · Step \(step.rawValue + 1) of \(SetupModel.GuideStep.counted)")
                        .font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: Double(step.rawValue + 1), total: Double(SetupModel.GuideStep.counted))
                        .tint(.primary)
                }
            }
            switch step {
            case .download: download
            case .open: openApp
            case .accounts: accounts
            case .api: api
            case .connect: connect
            case .done: done
            }
        }
    }

    var download: some View {
        GuidePage(title: "Download Beeper",
                  intro: "Beeper is a free app that puts WhatsApp, Messenger and your other chats in one place on your Mac.",
                  steps: ["Click **Download Beeper** below. Beeper's website opens in your browser.",
                          "Click the **Download** button for Mac.",
                          "When it has downloaded, click **Open Downloads folder** below and double-click the Beeper file.",
                          "If a window shows Beeper and an Applications folder, drag Beeper onto Applications."]) {
            HStack {
                Button("Download Beeper") { model.app.open(SetupModel.beeperDownload) }.buttonStyle(.borderedProminent).brandFill()
                Button("Open Downloads") { model.openDownloads() }
            }
            Status(done: model.beeperInstalled, waiting: "Waiting for Beeper to be installed…", finished: "Beeper is installed")
        }
    }

    var openApp: some View {
        GuidePage(title: "Open Beeper and make an account",
                  intro: "Beeper needs a free account. You only do this once.",
                  steps: ["Click **Open Beeper** below.",
                          "If your Mac asks whether you're sure you want to open it, click **Open**.",
                          "Choose to sign up, and type your email address.",
                          "Beeper emails you a code. Type it into Beeper to finish signing up.",
                          "Come back here and click **Next**."]) {
            Button("Open Beeper") { model.openBeeper() }.buttonStyle(.borderedProminent).brandFill()
            Status(done: model.beeperOpen, waiting: "Waiting for Beeper to open…", finished: "Beeper is open")
        }
    }

    var accounts: some View {
        GuidePage(title: "Add your chats to Beeper",
                  intro: "Add the chat apps your riding groups use. You can add more later.",
                  steps: []) {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    Label("Open Beeper's settings", systemImage: "gearshape").font(.headline)
                    HStack(spacing: 6) {
                        Text("Click **Show Beeper**, then press")
                        KeyCap("⌘"); Text("and"); KeyCap(","); Text("together.")
                    }
                    Text("Click **Accounts** in the list on the left, then the **+** button to add one.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show Beeper") { model.bringBeeperForward() }
                }
                Card {
                    Label("WhatsApp", systemImage: "phone.bubble").font(.headline)
                    NumberedSteps(["Choose **WhatsApp**. Beeper shows a square code.",
                                   "On your phone, open WhatsApp, then **Settings** → **Linked Devices** → **Link a Device**.",
                                   "Point your phone's camera at the code on your Mac screen."])
                }
                Card {
                    Label("Messenger", systemImage: "message").font(.headline)
                    NumberedSteps(["Choose **Messenger** and sign in with your Facebook account."])
                }
                Text("Chats can take a few minutes to appear in Beeper. You can click **Next** while they load.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var api: some View {
        GuidePage(title: "Switch on the connection for RollCall",
                  intro: "Beeper keeps other apps out until you switch this on. It only works on this Mac.",
                  steps: []) {
            Card {
                NumberedSteps(["Click **Show Beeper** below.",
                               "Press **⌘** and **,** together to open Beeper's settings.",
                               "In the list on the left, click **Developers**. You may need to scroll down to see it.",
                               "Switch on **Beeper Desktop API**."])
                Button("Show Beeper") { model.bringBeeperForward() }.buttonStyle(.borderedProminent).brandFill()
            }
            Status(done: model.apiOn, waiting: "Waiting for the switch to be turned on…", finished: "It's on")
            DisclosureGroup("Can't find Developers?") {
                Text("Make sure Beeper is up to date: in the menu bar at the top of the screen, click **Beeper** → **Check for Updates**, then try again.")
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            .font(.callout)
        }
    }

    var connect: some View {
        GuidePage(title: "Let RollCall read your ride chats",
                  intro: "RollCall asks Beeper for permission to read. It can never send, change or delete messages, and nothing leaves your Mac.",
                  steps: ["Click **Connect RollCall** below.",
                          "A Beeper page opens in your browser. Then switch to Beeper and click **Allow**.",
                          "Back in RollCall, tick the group chats where people post rides, and click **Check these chats**."]) {
            Button("Connect RollCall") { model.connectFromGuide() }.buttonStyle(.borderedProminent).brandFill()
            Status(done: Keychain.read() != nil && model.watchingChats > 0,
                   waiting: "Waiting for you to connect and choose chats…", finished: "Connected")
        }
    }

    var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54))
            Text("Beeper is set up").font(.title.bold())
            Text("RollCall is checking \(model.watchingChats) chat\(model.watchingChats == 1 ? "" : "s"). When someone plans a ride, RollCall sums it up and asks you to check it.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep Beeper open (it can sit in the background) so RollCall can check your chats.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A step's title, a line of explanation, numbered instructions, then the step's own buttons and checks.
struct GuidePage<Extra: View>: View {
    var title: String
    var intro: String
    var steps: [String]
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title.bold())
            Text(intro).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !steps.isEmpty { NumberedSteps(steps).font(.title3) }
            extra
        }
    }
}

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

/// A key on the keyboard, drawn like the real thing.
struct KeyCap: View {
    var key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(.system(.body, design: .rounded).bold())
            .frame(minWidth: 26, minHeight: 24)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5)))
    }
}

/// What RollCall can see right now, so nobody has to guess whether a step worked.
struct Status: View {
    var done: Bool
    var waiting: String
    var finished: String
    var body: some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark.circle.fill")
                Text(finished).bold()
            } else {
                ProgressView().controlSize(.small)
                Text(waiting).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

struct GuideFooter: View {
    @ObservedObject var model: SetupModel
    var step: SetupModel.GuideStep

    var body: some View {
        HStack {
            Button(step == .done ? "Back" : "Leave Beeper setup") {
                if step == .done { model.guideBack() } else { model.leaveGuide() }
            }
            Spacer()
            if step != .done, step != .download { Button("Back") { model.guideBack() } }
            if step == .done {
                Button("Continue") { model.leaveGuide(); model.next() }
                    .keyboardShortcut(.defaultAction).brandFill()
            } else {
                Button("Next") { model.guideNext() }
                    .keyboardShortcut(.defaultAction).brandFill()
            }
        }
    }
}
