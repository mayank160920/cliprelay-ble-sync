import AppKit

struct SyncedMessage {
    let address: String
    let body: String
    let timestampMs: Int64
}

final class MessagesWindowController {
    private var window: NSWindow?
    private var closeDelegate: MessagesWindowCloseHandler?
    private var scrollObservation: NSObjectProtocol?
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 260))
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView(frame: .zero)

    func showLoading() {
        ensureWindow()
        subtitleLabel.stringValue = "Fetching latest messages from Android…"
        updateTextView(with: "Please wait…")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showError(_ message: String) {
        ensureWindow()
        subtitleLabel.stringValue = "Could not load messages"
        updateTextView(with: message)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show(messages: [SyncedMessage], rawResponse: String? = nil) {
        ensureWindow()
        subtitleLabel.stringValue = "Showing latest \(messages.count) messages"

        var sections: [String] = []
        if messages.isEmpty {
            sections.append("No messages found on the Android device.")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let formattedMessages = messages.enumerated().map { index, message in
                let date = Date(timeIntervalSince1970: TimeInterval(message.timestampMs) / 1000)
                let time = formatter.string(from: date)
                return "\(index + 1). [\(time)] \(message.address)\n\(message.body)"
            }.joined(separator: "\n\n")
            sections.append(formattedMessages)
        }

        if messages.isEmpty, let rawResponse = rawResponse {
            sections.append("RAW RESPONSE:\n\(rawResponse)")
        }

        updateTextView(with: sections.joined(separator: "\n\n------------------------------\n\n"))

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
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0

        let titleLabel = NSTextField(labelWithString: "Latest Messages")
        titleLabel.font = .boldSystemFont(ofSize: 18)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let stack = NSStackView(views: [titleLabel, subtitleLabel, scrollView])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: .zero)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Latest Messages"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = contentView
        newWindow.center()
        newWindow.initialFirstResponder = textView

        let delegate = MessagesWindowCloseHandler { [weak self] in
            if let observation = self?.scrollObservation {
                NotificationCenter.default.removeObserver(observation)
            }
            self?.scrollObservation = nil
            self?.window = nil
            self?.closeDelegate = nil
        }
        closeDelegate = delegate
        newWindow.delegate = delegate

        if let observation = scrollObservation {
            NotificationCenter.default.removeObserver(observation)
        }
        scrollObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateTextViewLayout()
        }

        updateTextViewLayout()
        return newWindow
    }

    private func updateTextView(with text: String) {
        textView.string = text
        updateTextViewLayout()
    }

    private func updateTextViewLayout() {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }

        window?.contentView?.layoutSubtreeIfNeeded()
        let contentWidth = max(scrollView.contentSize.width, 1)
        textContainer.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentHeight = max(
            usedRect.height + (textView.textContainerInset.height * 2),
            scrollView.contentSize.height
        )

        textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
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
