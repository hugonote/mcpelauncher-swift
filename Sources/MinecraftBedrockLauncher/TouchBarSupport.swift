import AppKit
import SwiftUI

struct LauncherTouchBarConfigurator: NSViewRepresentable {
    var configuration: LauncherTouchBarConfiguration

    func makeCoordinator() -> LauncherTouchBarCoordinator {
        LauncherTouchBarCoordinator(configuration: configuration)
    }

    func makeNSView(context: Context) -> LauncherTouchBarHostView {
        let view = LauncherTouchBarHostView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(configuration)
        return view
    }

    func updateNSView(_ view: LauncherTouchBarHostView, context: Context) {
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(configuration)
        context.coordinator.attach(to: view.window)
    }

    static func dismantleNSView(_ view: LauncherTouchBarHostView, coordinator: LauncherTouchBarCoordinator) {
        coordinator.detach(from: view.window)
        view.windowDidChange = nil
    }
}

@MainActor
final class LauncherTouchBarCoordinator: NSObject, NSTouchBarDelegate {
    private enum ItemID {
        static let status = NSTouchBarItem.Identifier("launcher.status")
        static let progress = NSTouchBarItem.Identifier("launcher.progress")
        static let cancel = NSTouchBarItem.Identifier("launcher.cancel")
        static let skip = NSTouchBarItem.Identifier("launcher.skip")
        static let primary = NSTouchBarItem.Identifier("launcher.primary")
        static let signIn = NSTouchBarItem.Identifier("launcher.signIn")
        static let folder = NSTouchBarItem.Identifier("launcher.folder")
        static let settings = NSTouchBarItem.Identifier("launcher.settings")
    }

    private var configuration: LauncherTouchBarConfiguration
    private weak var attachedWindow: NSWindow?
    private var touchBar: NSTouchBar?
    private var statusView: LauncherTouchBarStatusView?
    private var progressView: LauncherTouchBarProgressView?
    private var primaryButton: NSButton?
    private var signInButton: NSButton?

    init(configuration: LauncherTouchBarConfiguration) {
        self.configuration = configuration
    }

    func update(_ configuration: LauncherTouchBarConfiguration) {
        self.configuration = configuration
        applyConfiguration()
        touchBar?.defaultItemIdentifiers = itemIdentifiers(for: configuration.state)
        syncWindowTouchBar()
    }

    func attach(to window: NSWindow?) {
        if attachedWindow !== window {
            if let touchBar, attachedWindow?.touchBar === touchBar {
                attachedWindow?.touchBar = nil
            }
            attachedWindow = window
        }
        syncWindowTouchBar()
    }

    func detach(from window: NSWindow?) {
        if let touchBar, window?.touchBar === touchBar {
            window?.touchBar = nil
        }
        if attachedWindow === window {
            attachedWindow = nil
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case ItemID.status:
            return statusItem()
        case ItemID.progress:
            return progressItem()
        case ItemID.cancel:
            return iconButtonItem(
                identifier: identifier,
                systemImage: "xmark",
                label: "Cancel",
                action: #selector(cancel),
                bezelColor: .systemRed
            )
        case ItemID.skip:
            return skipItem()
        case ItemID.primary:
            return primaryItem()
        case ItemID.signIn:
            return signInItem()
        case ItemID.folder:
            return iconButtonItem(
                identifier: identifier,
                systemImage: "folder",
                label: "Open data folder",
                action: #selector(openDataFolder)
            )
        case ItemID.settings:
            return iconButtonItem(
                identifier: identifier,
                systemImage: "gearshape",
                label: "Settings",
                action: #selector(openSettings)
            )
        default:
            return nil
        }
    }

    @objc func performPrimaryAction() {
        configuration.onPrimary()
    }

    @objc func cancel() {
        configuration.onCancel()
    }

    @objc func skipRuntimeUpdateCheck() {
        configuration.onSkipRuntimeUpdateCheck()
    }

    @objc func signIn() {
        configuration.onSignIn()
    }

    @objc func openSettings() {
        configuration.onSettings()
    }

    @objc func openDataFolder() {
        configuration.onOpenDataFolder()
    }

    private func syncWindowTouchBar() {
        guard let window = attachedWindow else {
            return
        }
        guard !configuration.state.isHidden else {
            if let touchBar, window.touchBar === touchBar {
                window.touchBar = nil
            }
            return
        }

        let currentTouchBar = touchBar ?? makeTouchBar()
        currentTouchBar.defaultItemIdentifiers = itemIdentifiers(for: configuration.state)
        touchBar = currentTouchBar
        if window.touchBar !== currentTouchBar {
            window.touchBar = currentTouchBar
        }
    }

    private func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = itemIdentifiers(for: configuration.state)
        return touchBar
    }

    private func itemIdentifiers(for state: LauncherTouchBarState) -> [NSTouchBarItem.Identifier] {
        var identifiers: [NSTouchBarItem.Identifier] = [ItemID.status]

        if state.isProgressVisible {
            identifiers.append(.fixedSpaceSmall)
            identifiers.append(ItemID.progress)
        }

        identifiers.append(.flexibleSpace)
        if state.isPrimaryVisible {
            identifiers.append(ItemID.primary)
            if state.isSignInVisible {
                identifiers.append(.fixedSpaceSmall)
                identifiers.append(ItemID.signIn)
            }
            identifiers.append(.flexibleSpace)
        }

        if state.isCancelVisible {
            identifiers.append(ItemID.cancel)
            identifiers.append(.fixedSpaceSmall)
        }
        if state.isSkipVisible {
            identifiers.append(ItemID.skip)
            identifiers.append(.fixedSpaceSmall)
        }
        if state.isTrailingActionsVisible {
            identifiers.append(ItemID.folder)
            identifiers.append(.fixedSpaceSmall)
            identifiers.append(ItemID.settings)
        }

        return identifiers
    }

    private func statusItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: ItemID.status)
        let view = statusView ?? LauncherTouchBarStatusView()
        statusView = view
        view.apply(configuration.state)
        item.view = view
        item.customizationLabel = configuration.state.statusText
        item.visibilityPriority = .high
        return item
    }

    private func skipItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: ItemID.skip)
        let button = NSButton(title: "Skip", target: self, action: #selector(skipRuntimeUpdateCheck))
        setupButton(button)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = #selector(skipRuntimeUpdateCheck)
        button.title = "Skip"
        button.attributedTitle = NSAttributedString(
            string: "Skip",
            attributes: TouchBarMetrics.secondaryButtonTitleAttributes
        )
        button.image = Self.symbol("forward.end", accessibilityLabel: "Skip")
        button.toolTip = "Skip runtime and Google Play update checks"
        button.setAccessibilityLabel("Skip runtime and Google Play update checks")
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: TouchBarMetrics.skipButtonWidth),
            button.heightAnchor.constraint(equalToConstant: TouchBarMetrics.height)
        ])
        item.view = button
        item.customizationLabel = "Skip"
        item.visibilityPriority = .high
        return item
    }

    private func signInItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: ItemID.signIn)
        let button = signInButton ?? NSButton(title: "Sign in", target: self, action: #selector(signIn))
        signInButton = button
        setupButton(button)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = #selector(signIn)
        button.title = "Sign in"
        button.attributedTitle = NSAttributedString(
            string: "Sign in",
            attributes: TouchBarMetrics.secondaryButtonTitleAttributes
        )
        button.image = Self.symbol("person.crop.circle.badge.plus", accessibilityLabel: "Sign in")
        button.toolTip = "Sign in"
        button.setAccessibilityLabel("Sign in")
        if let widthConstraint = button.constraints.first(where: { $0.identifier == TouchBarMetrics.signInWidthConstraintID }) {
            widthConstraint.constant = TouchBarMetrics.signInButtonWidth
        } else {
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: TouchBarMetrics.signInButtonWidth)
            widthConstraint.identifier = TouchBarMetrics.signInWidthConstraintID
            NSLayoutConstraint.activate([
                widthConstraint,
                button.heightAnchor.constraint(equalToConstant: TouchBarMetrics.height)
            ])
        }
        item.view = button
        item.customizationLabel = "Sign in"
        item.visibilityPriority = .high
        return item
    }

    private func progressItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: ItemID.progress)
        let view = progressView ?? LauncherTouchBarProgressView()
        progressView = view
        view.apply(configuration.state)
        item.view = view
        item.customizationLabel = configuration.state.progressText ?? "Progress"
        item.visibilityPriority = .high
        return item
    }

    private func primaryItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: ItemID.primary)
        let button = primaryButton ?? NSButton(title: "", target: self, action: #selector(performPrimaryAction))
        primaryButton = button
        setupButton(button)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.target = self
        button.action = #selector(performPrimaryAction)
        updatePrimaryButton(button, state: configuration.state)
        item.view = button
        item.customizationLabel = configuration.state.primaryTitle
        item.visibilityPriority = .high
        return item
    }

    private func iconButtonItem(
        identifier: NSTouchBarItem.Identifier,
        systemImage: String,
        label: String,
        action: Selector,
        bezelColor: NSColor? = nil
    ) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton()
        setupButton(button)
        button.bezelColor = bezelColor
        button.image = Self.symbol(systemImage, accessibilityLabel: label)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: TouchBarMetrics.iconButtonWidth),
            button.heightAnchor.constraint(equalToConstant: TouchBarMetrics.height)
        ])
        item.view = button
        item.customizationLabel = label
        item.visibilityPriority = .high
        return item
    }

    private func applyConfiguration() {
        statusView?.apply(configuration.state)
        progressView?.apply(configuration.state)
        if let primaryButton {
            updatePrimaryButton(primaryButton, state: configuration.state)
        }
        signInButton?.isHidden = !configuration.state.isSignInVisible
    }

    private func setupButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updatePrimaryButton(_ button: NSButton, state: LauncherTouchBarState) {
        button.title = state.primaryTitle
        button.attributedTitle = NSAttributedString(
            string: state.primaryTitle,
            attributes: TouchBarMetrics.buttonTitleAttributes
        )
        button.image = Self.symbol(state.primarySystemImage, accessibilityLabel: state.primaryTitle)
        button.isEnabled = !state.isPrimaryDisabled
        button.toolTip = state.primaryTitle
        button.setAccessibilityLabel(state.primaryTitle)

        let width = Self.primaryWidth(for: state.primaryTitle)
        if let widthConstraint = button.constraints.first(where: { $0.identifier == TouchBarMetrics.primaryWidthConstraintID }) {
            widthConstraint.constant = width
        } else {
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: width)
            widthConstraint.identifier = TouchBarMetrics.primaryWidthConstraintID
            NSLayoutConstraint.activate([
                widthConstraint,
                button.heightAnchor.constraint(equalToConstant: TouchBarMetrics.height)
            ])
        }
    }

    private static func primaryWidth(for title: String) -> CGFloat {
        switch title {
        case "Download Runtime", "Switch Account":
            return TouchBarMetrics.primaryWideWidth
        default:
            return TouchBarMetrics.primaryDefaultWidth
        }
    }

    private static func symbol(_ name: String, accessibilityLabel: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        return image
    }
}

final class LauncherTouchBarHostView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}

@MainActor
private final class LauncherTouchBarStatusView: NSView {
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
        let fullWidth = state.statusText == "Keychain Access Needed"
            ? TouchBarMetrics.statusWideWidth
            : TouchBarMetrics.statusFullWidth
        width = isCompact ? TouchBarMetrics.statusCompactWidth : fullWidth
        label.stringValue = state.statusText
        leadingConstraint.constant = TouchBarMetrics.statusHorizontalPadding
        trailingConstraint.constant = -TouchBarMetrics.statusHorizontalPadding
        layer?.backgroundColor = isCompact ? NSColor.clear.cgColor : NSColor.black.withAlphaComponent(0.22).cgColor
        dot.layer?.backgroundColor = state.statusColor.resolvedCGColor(for: effectiveAppearance)
        setFrameSize(intrinsicContentSize)
        invalidateIntrinsicContentSize()
        layoutSubtreeIfNeeded()
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

@MainActor
private final class LauncherTouchBarProgressView: NSView {
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
        layoutSubtreeIfNeeded()
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

private enum TouchBarMetrics {
    static let height: CGFloat = 30
    static let spacing: CGFloat = 6
    static let textColor = NSColor.white.withAlphaComponent(0.86)
    static let primaryWidthConstraintID = "launcher.primary.width"
    static let signInWidthConstraintID = "launcher.signIn.width"

    @MainActor
    static var buttonTitleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
    }

    @MainActor
    static var secondaryButtonTitleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.78)
        ]
    }

    static let statusCompactWidth: CGFloat = 104
    static let statusFullWidth: CGFloat = 148
    static let statusWideWidth: CGFloat = 184
    static let statusHorizontalPadding: CGFloat = 8
    static let progressWidth: CGFloat = 336
    static let progressIndicatorWidth: CGFloat = 136
    static let progressPercentWidth: CGFloat = 44
    static let progressDetailWidth: CGFloat = 140
    static let primaryDefaultWidth: CGFloat = 116
    static let primaryWideWidth: CGFloat = 166
    static let signInButtonWidth: CGFloat = 104
    static let skipButtonWidth: CGFloat = 88
    static let iconButtonWidth: CGFloat = 38
}

private extension NSColor {
    func resolvedCGColor(for appearance: NSAppearance) -> CGColor {
        _ = appearance
        return usingColorSpace(NSColorSpace.deviceRGB)?.cgColor ?? cgColor
    }
}
