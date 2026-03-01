import AppKit

final class OverlayPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private var dragOrigin: NSPoint = .zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        ignoresMouseEvents = false

        let vibrancy = NSVisualEffectView(frame: .zero)
        vibrancy.material = .menu
        vibrancy.state = .active
        vibrancy.blendingMode = .behindWindow
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 10
        vibrancy.layer?.masksToBounds = true
        vibrancy.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!, target: nil, action: nil)
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeOverlay)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        closeButton.image = closeButton.image?.withSymbolConfiguration(symbolConfig)

        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [label, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView = container

        container.addSubview(vibrancy)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            vibrancy.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vibrancy.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vibrancy.topAnchor.constraint(equalTo: container.topAnchor),
            vibrancy.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        setContentSize(NSSize(width: 200, height: 32))
        center()
    }

    func update(content: NSAttributedString) {
        label.attributedStringValue = content

        let fitted = label.intrinsicContentSize
        let newWidth = fitted.width + 52
        let frame = self.frame
        setContentSize(NSSize(width: max(newWidth, 120), height: 32))
        setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y))
    }

    @objc private func closeOverlay() {
        orderOut(nil)
        NotificationCenter.default.post(name: .overlayDidClose, object: nil)
    }
}

extension Notification.Name {
    static let overlayDidClose = Notification.Name("overlayDidClose")
}
