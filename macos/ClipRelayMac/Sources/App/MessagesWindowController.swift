import AppKit

final class MessagesWindowController {
    private var window: NSWindow?
    private var closeDelegate: WindowCloseHandler?

    func show(messages: [String]) {
        let contentView = makeContentView(messages: messages)

        if let window {
            window.contentView = contentView
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Latest Messages"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = contentView
        newWindow.center()

        let delegate = WindowCloseHandler { [weak self] in
            self?.window = nil
            self?.closeDelegate = nil
        }
        closeDelegate = delegate
        newWindow.delegate = delegate

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    private func makeContentView(messages: [String]) -> NSView {
        let titleLabel = NSTextField(labelWithString: "Latest Messages")
        titleLabel.font = .boldSystemFont(ofSize: 18)

        let subtitleLabel = NSTextField(labelWithString: "Dummy data preview")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = messages.enumerated().map { index, message in
            "\(index + 1). \(message)"
        }.joined(separator: "\n\n")

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
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        return stack
    }
}

private final class WindowCloseHandler: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
