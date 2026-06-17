import AppKit

@MainActor
final class LauncherTouchBarCoordinator: NSObject, NSTouchBarDelegate {
    private enum ItemID {
        static let status = NSTouchBarItem.Identifier("launcher.status")
        static let progress = NSTouchBarItem.Identifier("launcher.progress")
        static let cancel = NSTouchBarItem.Identifier("launcher.cancel")
        static let skip = NSTouchBarItem.Identifier("launcher.skip")
        static let primary = NSTouchBarItem.Identifier("launcher.primary")
        static let play = NSTouchBarItem.Identifier("launcher.play")
        static let signIn = NSTouchBarItem.Identifier("launcher.signIn")
        static let contentImport = NSTouchBarItem.Identifier("launcher.contentImport")
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
        case ItemID.play:
            return iconButtonItem(
                identifier: identifier,
                systemImage: "play.fill",
                label: "Play",
                action: #selector(play)
            )
        case ItemID.signIn:
            return signInItem()
        case ItemID.contentImport:
            return iconButtonItem(
                identifier: identifier,
                systemImage: "square.and.arrow.down",
                label: "Import Minecraft content",
                action: #selector(importContent)
            )
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

    @objc func play() {
        configuration.onPlay()
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

    @objc func importContent() {
        configuration.onImportContent()
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
            if state.isPlaySideVisible {
                identifiers.append(.fixedSpaceSmall)
                identifiers.append(ItemID.play)
            }
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
            identifiers.append(ItemID.contentImport)
            identifiers.append(.fixedSpaceSmall)
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
        item.customizationLabel = configuration.state.statusLabel
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
