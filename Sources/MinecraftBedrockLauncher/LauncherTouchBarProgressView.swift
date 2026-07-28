import AppKit

@MainActor
final class LauncherTouchBarProgressView: NSView {
    private let stack = NSStackView()
    private let progressIndicator = NSProgressIndicator()
    private let percentLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override var intrinsicContentSize: NSSize {
        NSSize(width: TouchBarMetrics.progressWidth, height: TouchBarMetrics.height)
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
        percentLabel.stringValue = state.progressPercentText ?? ""
        detailLabel.stringValue = state.progressDetailText ?? ""
        percentLabel.isHidden = false
        detailLabel.isHidden = false

        if let progress = state.progress {
            progressIndicator.isIndeterminate = false
            progressIndicator.doubleValue = min(max(progress, 0), 1)
            progressIndicator.stopAnimation(nil)
        } else {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
        }

        setFrameSize(intrinsicContentSize)
        invalidateIntrinsicContentSize()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        stack.detachesHiddenViews = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        progressIndicator.style = .bar
        progressIndicator.controlSize = .small
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        [percentLabel, detailLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            $0.textColor = TouchBarMetrics.textColor
            $0.lineBreakMode = .byTruncatingTail
            $0.maximumNumberOfLines = 1
            $0.usesSingleLineMode = true
        }

        stack.addArrangedSubview(progressIndicator)
        stack.addArrangedSubview(percentLabel)
        stack.addArrangedSubview(detailLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TouchBarMetrics.progressWidth),
            heightAnchor.constraint(equalToConstant: TouchBarMetrics.height),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: TouchBarMetrics.progressIndicatorWidth),
            progressIndicator.heightAnchor.constraint(equalToConstant: 12),
            percentLabel.widthAnchor.constraint(equalToConstant: TouchBarMetrics.progressPercentWidth),
            detailLabel.widthAnchor.constraint(equalToConstant: TouchBarMetrics.progressDetailWidth)
        ])
    }
}
