import AppKit

struct SyncedMessage {
    let address: String
    let body: String
    let timestampMs: Int64
}

final class MessagesWindowController {
    private var window: NSWindow?
    private var closeDelegate: MessagesWindowCloseHandler?
    private let textView = NSTextView(frame: .zero)
    private let subtitleLabel = NSTextField(labelWithString: "")

    func showLoading() {
        ensureWindow()
        subtitleLabel.stringValue = "Fetching latest messages from Android…"
        textView.string = "Please wait…"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showError(_ message: String) {
        ensureWindow()
        subtitleLabel.stringValue = "Could not load messages"
        textView.string = message
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show(messages: [SyncedMessage]) {
        ensureWindow()
        subtitleLabel.stringValue = "Showing latest \(messages.count) messages"

        if messages.isEmpty {
            textView.string = "No messages found on the Android device."
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            textView.string = messages.enumerated().map { index, message in
                let date = Date(timeIntervalSince1970: TimeInterval(message.timestampMs) / 1000)
                let time = formatter.string(from: date)
                return "\(index + 1). [\(time)] \(message.address)\n\(message.body)"
            }.joined(separator: "\n\n")
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureWindow() {
        if window == nil {
            window = buildWindow()
        }
    }

    private func buildWindow() -> NSWindow {
        textView.isEditable = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        let titleLabel = NSTextField(labelWithString: "Latest Messages")
        titleLabel.font = .boldSystemFont(ofSize: 18)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        let stack = NSStackView(views: [titleLabel, subtitleLabel, scrollView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Latest Messages"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = stack
        newWindow.center()

        let delegate = MessagesWindowCloseHandler { [weak self] in
            self?.window = nil
            self?.closeDelegate = nil
        }
        closeDelegate = delegate
        newWindow.delegate = delegate
        return newWindow
    }
}

private final class MessagesWindowCloseHandler: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
