import AppKit
import UniformTypeIdentifiers

/// Small modal windows for typing in links and ride details.
@MainActor
enum Dialogs {
    static func bringForward() { NSApp.activate(ignoringOtherApps: true) }

    static func info(_ title: String, _ text: String) {
        bringForward()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    static func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        bringForward()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Asks for one or more lines of text. Returns nil on Cancel.
    static func ask(_ title: String, _ text: String, fields: [(label: String, placeholder: String)], values: [String] = [], ok: String = "Add") -> [String]? {
        bringForward()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        let width: CGFloat = 380
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        var inputs: [NSTextField] = []
        for (i, f) in fields.enumerated() {
            if !f.label.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: f.label)) }
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
            tf.placeholderString = f.placeholder
            if i < values.count { tf.stringValue = values[i] }
            tf.widthAnchor.constraint(equalToConstant: width).isActive = true
            stack.addArrangedSubview(tf)
            inputs.append(tf)
        }
        stack.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height)
        a.accessoryView = stack
        a.window.initialFirstResponder = inputs.first
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return inputs.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    struct ManualRide {
        var title: String
        var start: Date
        var hours: Double
        var location: String
        var link: String
        var notes = ""
    }

    static func manualRide(prefillLink: String = "") -> ManualRide? {
        manualRide(prefill: ManualRide(title: "", start: nextSundayMorning(), hours: 4, location: "", link: prefillLink),
                   note: "Type in the details from the event page.")
    }

    static func nextSundayMorning() -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 9, minute: 0, weekday: 1),
                                  matchingPolicy: .nextTime) ?? Date()
    }

    static func manualRide(prefill: ManualRide, note: String) -> ManualRide? {
        bringForward()
        let a = NSAlert()
        a.messageText = "Add a ride"
        a.informativeText = note
        a.addButton(withTitle: "Add")
        a.addButton(withTitle: "Cancel")
        let width: CGFloat = 380
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        func field(_ label: String, _ placeholder: String, _ value: String = "") -> NSTextField {
            stack.addArrangedSubview(NSTextField(labelWithString: label))
            let tf = NSTextField(string: value)
            tf.placeholderString = placeholder
            tf.widthAnchor.constraint(equalToConstant: width).isActive = true
            stack.addArrangedSubview(tf)
            return tf
        }
        let title = field("Ride name", "Sunday breakfast ride to Marysville", prefill.title)
        stack.addArrangedSubview(NSTextField(labelWithString: "Starts"))
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = prefill.start
        stack.addArrangedSubview(picker)
        let hours = field("How long (hours)", "4", String(format: "%g", prefill.hours))
        let place = field("Meeting place", "Shell Coldstream, Maroondah Hwy", prefill.location)
        let link = field("Event link (optional)", "https://www.facebook.com/events/…", prefill.link)
        stack.addArrangedSubview(NSTextField(labelWithString: "Notes (optional)"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 90))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let notes = NSTextView(frame: scroll.bounds)
        notes.isRichText = false
        notes.font = .systemFont(ofSize: 13)
        notes.string = prefill.notes
        notes.autoresizingMask = [.width]
        scroll.documentView = notes
        scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        stack.addArrangedSubview(scroll)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height)
        a.accessoryView = stack
        a.window.initialFirstResponder = title
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let name = title.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return ManualRide(title: name, start: picker.dateValue,
                          hours: Double(hours.stringValue) ?? 4,
                          location: place.stringValue.trimmingCharacters(in: .whitespaces),
                          link: link.stringValue.trimmingCharacters(in: .whitespaces),
                          notes: notes.string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Asks for a post's link and text (an Instagram caption, forum post or message).
    /// Starts with whatever is on the clipboard. Returns nil on Cancel.
    static func pastedPost(link prefillLink: String = "") -> (link: String, text: String)? {
        bringForward()
        let a = NSAlert()
        a.messageText = "Add a ride from a post"
        a.informativeText = "Copy the post's text (on Instagram: open the post, select the caption, press ⌘C) and paste it below. RollCall fills in the date, time and place it finds, and you can check them on the next screen."
        a.addButton(withTitle: "Next")
        a.addButton(withTitle: "Cancel")
        let width: CGFloat = 420
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        var clipText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var clipLink = ""
        if clipText.hasPrefix("http"), !clipText.contains(where: \.isWhitespace) { clipLink = clipText; clipText = "" }
        if !prefillLink.isEmpty { clipLink = prefillLink }

        stack.addArrangedSubview(NSTextField(labelWithString: "Link to the post (optional)"))
        let link = NSTextField(string: clipLink)
        link.placeholderString = "https://www.instagram.com/p/…"
        link.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.addArrangedSubview(link)

        stack.addArrangedSubview(NSTextField(labelWithString: "Post text"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 160))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 13)
        tv.string = clipText
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        stack.addArrangedSubview(scroll)

        stack.frame = NSRect(x: 0, y: 0, width: width, height: stack.fittingSize.height)
        a.accessoryView = stack
        a.window.initialFirstResponder = clipText.isEmpty ? tv : link
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return (link.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                tv.string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A list of chats with tick boxes. Returns the ticked chat ids, or nil on Cancel.
    static func pickChats(_ chats: [Beeper.Chat], watched: Set<String>) -> Set<String>? {
        bringForward()
        let a = NSAlert()
        a.messageText = "Which chats should RollCall check for rides?"
        a.informativeText = "Tick the chats where people post rides. RollCall only reads new messages in these chats, on your Mac, and never sends anything. Group chats are listed first, most recently active at the top."
        a.addButton(withTitle: "Check these chats")
        a.addButton(withTitle: "Cancel")
        let width: CGFloat = 440
        let rowHeight: CGFloat = 24
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: width - 20, height: CGFloat(chats.count) * rowHeight))
        var boxes: [(NSButton, String)] = []
        for (i, c) in chats.enumerated() {
            var label = c.title.isEmpty ? "(no name)" : c.title
            if let n = c.network, !n.isEmpty { label += "  ·  \(n)" }
            if c.type == "single" { label += "  ·  direct message" }
            let box = NSButton(checkboxWithTitle: label, target: nil, action: nil)
            box.state = watched.contains(c.id) ? .on : .off
            box.lineBreakMode = .byTruncatingTail
            // Flipped by hand: the first chat goes at the top.
            box.frame = NSRect(x: 4, y: doc.frame.height - CGFloat(i + 1) * rowHeight, width: width - 30, height: rowHeight)
            doc.addSubview(box)
            boxes.append((box, c.id))
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = doc
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, doc.frame.height - scroll.contentSize.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        a.accessoryView = scroll
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return Set(boxes.filter { $0.0.state == .on }.map(\.1))
    }

    static func chooseICSFiles() -> [URL] {
        bringForward()
        let panel = NSOpenPanel()
        panel.title = "Choose calendar files (.ics)"
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.urls : []
    }
}
