import SwiftUI
import AppKit

// MARK: - Add

/// What + adds: a single ride, or a source RollCall keeps checking for rides.
enum AddKind: String, Identifiable {
    case ride, source
    var id: String { rawValue }
}

struct AddSheet: View {
    @ObservedObject var model: UIModel
    let kind: AddKind
    @Environment(\.dismiss) private var dismiss
    @StateObject private var link = Box("")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind == .ride ? "Add a ride" : "Add a source").font(.title2).fontWeight(.semibold)
            switch kind {
            case .ride: rideChoices
            case .source: sourceChoices
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            guard kind == .source else { return }
            let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if clip.hasPrefix("http"), !clip.contains(where: \.isWhitespace) { link.value = clip }
        }
    }

    private var rideChoices: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                choice("photo", "Paste an event poster", "Copy its picture first, or choose the file") {
                    model.app.addFromPoster()
                }
                choice("doc.on.clipboard", "Paste a post or message", "Reads the date and place from the text") {
                    model.app.addFromPost()
                }
            }
            GridRow {
                choice("square.and.pencil", "Type a ride in", "Name, time and meeting place") {
                    model.app.addManual()
                }
                choice("calendar.badge.plus", "Import a calendar file", "An .ics file someone sent you") {
                    model.app.importICS()
                }
            }
            GridRow {
                choice("link", "Add a Facebook event", "Paste the event's link") {
                    model.app.addFacebookEvent()
                }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    @ViewBuilder private var sourceChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste a link")
                .font(.headline)
            TextField("https://…  or  @instagramaccount", text: $link.value, onCommit: go)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 460)
            Text("Works with a club or event website, a forum section, a Meetup group, a calendar link, a news feed or an Instagram account. RollCall works out what it is, and checks it for new rides.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button("Add link", action: go)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        Divider()
        Text("Or").font(.headline)
        choice("bubble.left.and.bubble.right", "Check chats", "WhatsApp, Messenger and more, through Beeper") {
            Task { await model.app.setUpBeeper() }
        }
    }

    func go() {
        let l = link.value
        guard !l.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dismiss()
        model.page = .sources
        model.later { model.app.add(link: l) }
    }

    func choice(_ symbol: String, _ title: String, _ detail: String, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            dismiss()
            model.later(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChoiceButton())
    }
}

/// A box to choose from: it lights up under the pointer and more when pressed, as glass controls do.
struct ChoiceButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Choice(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Choice<Label: View>: View {
        let label: Label
        let pressed: Bool
        @StateObject private var hovering = Box(false)

        var body: some View {
            label
                .background(Color.primary.opacity(pressed ? 0.16 : hovering.value ? 0.1 : 0.06), in: Brand.card)
                .onHover { hovering.value = $0 }
        }
    }
}
