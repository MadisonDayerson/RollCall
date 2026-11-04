import SwiftUI
import AppKit

// MARK: - Add

struct AddSheet: View {
    @ObservedObject var model: UIModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var link = Box("")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add").font(.title2).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste a link")
                    .font(.headline)
                TextField("https://…  or  @instagramaccount", text: $link.value, onCommit: go)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 460)
                Text("Works with a club or event website, a forum section, a Meetup group, a calendar link, a news feed, a Facebook event, or an Instagram account or post. RollCall works out what it is.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Add link", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(link.value.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()
            Text("Or").font(.headline)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    choice("bubble.left.and.bubble.right", "Check chats", "WhatsApp, Messenger and more, through Beeper") {
                        Task { await model.app.setUpBeeper() }
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
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if clip.hasPrefix("http"), !clip.contains(where: \.isWhitespace) { link.value = clip }
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
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
