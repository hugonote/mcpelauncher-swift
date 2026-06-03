import AppKit

enum TouchBarMetrics {
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

extension NSColor {
    func resolvedCGColor(for appearance: NSAppearance) -> CGColor {
        _ = appearance
        return usingColorSpace(NSColorSpace.deviceRGB)?.cgColor ?? cgColor
    }
}
