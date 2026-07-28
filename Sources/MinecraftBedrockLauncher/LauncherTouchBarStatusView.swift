import AppKit

@MainActor
final class LauncherTouchBarStatusView: NSView {
    private let stack = NSStackView()
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private var width = TouchBarMetrics.statusFullWidth
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: TouchBarMetrics.height)
    }

    init() {
        super.init(frame: .zero)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func apply(_ state: LauncherTouchBarState) {
        let isCompact = state.isProgressVisible
        let fullWidth = state.statusLabel == "Keychain Access Needed"
            ? TouchBarMetrics.statusWideWidth
            : TouchBarMetrics.statusFullWidth
        width = isCompact ? TouchBarMetrics.statusCompactWidth : fullWidth
        label.stringValue = state.statusLabel
        leadingConstraint.constant = TouchBarMetrics.statusHorizontalPadding
        trailingConstraint.constant = -TouchBarMetrics.statusHorizontalPadding
        layer?.backgroundColor = isCompact ? NSColor.clear.cgColor : NSColor.black.withAlphaComponent(0.22).cgColor
        dot.layer?.backgroundColor = state.statusColor.usingColorSpace(.deviceRGB)?.cgColor ?? state.statusColor.cgColor
        setFrameSize(intrinsicContentSize)
        invalidateIntrinsicContentSize()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = TouchBarMetrics.textColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(dot)
        stack.addArrangedSubview(label)

        leadingConstraint = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TouchBarMetrics.statusHorizontalPadding)
        trailingConstraint = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TouchBarMetrics.statusHorizontalPadding)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: TouchBarMetrics.height),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            leadingConstraint,
            trailingConstraint,
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
