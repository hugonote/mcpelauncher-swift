import AppKit
import Foundation
import MinecraftBedrockLauncherCore

struct LauncherTouchBarConfiguration {
    var state: LauncherTouchBarState
    var onPrimary: @MainActor () -> Void
    var onSignIn: @MainActor () -> Void
    var onCancel: @MainActor () -> Void
    var onSettings: @MainActor () -> Void
    var onOpenDataFolder: @MainActor () -> Void
}

struct LauncherTouchBarState {
    var statusText: String
    var statusColor: NSColor
    var primaryTitle: String
    var primarySystemImage: String
    var isPrimaryDisabled: Bool
    var isSignInVisible: Bool
    var progress: Double?
    var progressText: String?
    var progressPercentText: String?
    var progressDetailText: String?
    var isProgressVisible: Bool
    var isCancelVisible: Bool
    var isTrailingActionsVisible: Bool
    var isPrimaryVisible: Bool
    var isHidden: Bool

    @MainActor
    init(model: LauncherViewModel) {
        let progressVisible = Self.isProgressVisible(model)
        let credentialAccessDenied = model.credentialAccessDenied

        statusText = credentialAccessDenied ? "Keychain Access Needed" : Self.shortStatusText(model)
        statusColor = Self.statusColor(model)
        primaryTitle = credentialAccessDenied ? "Retry" : Self.primaryButtonTitle(model)
        primarySystemImage = credentialAccessDenied ? "arrow.clockwise" : Self.primaryButtonIcon(model)
        isPrimaryDisabled = credentialAccessDenied ? false : Self.isPrimaryButtonDisabled(model)
        isSignInVisible = credentialAccessDenied ? false : Self.isSignInVisible(model, isProgressVisible: progressVisible)
        let progressInfo = Self.progressInfo(model)
        progress = Self.progress(model)
        progressText = progressInfo.accessibilityText
        progressPercentText = progressInfo.percentText
        progressDetailText = progressInfo.detailText
        isProgressVisible = progressVisible
        isCancelVisible = model.downloadState.phase == .downloading || model.runtimeState.phase == .downloading
        isPrimaryVisible = !progressVisible
        isTrailingActionsVisible = Self.areTrailingActionsVisible(model, isProgressVisible: progressVisible)
        isHidden = model.activeIssue == .bundledHelperMissing
    }

    @MainActor
    private static func primaryButtonTitle(_ model: LauncherViewModel) -> String {
        if LauncherTouchBarRules.needsCredentialRefresh(model) {
            return "Sign in"
        }
        if LauncherTouchBarRules.isPurchaseRequired(model) {
            return "Switch Account"
        }
        if LauncherTouchBarRules.shouldFocusRuntime(model) {
            return "Download Runtime"
        }
        if LauncherTouchBarRules.isMinecraftUpdateAvailable(model) {
            return "Update"
        }
        if model.canUseSelectedVersion {
            if model.isRuntimeReady {
                return "Play"
            }
            return "Download Runtime"
        }
        if model.credential == nil {
            return "Sign in"
        }
        if model.downloadState.phase == .failed {
            return "Retry"
        }
        if model.latestVersion == nil {
            return "Check"
        }
        return "Download"
    }

    @MainActor
    private static func primaryButtonIcon(_ model: LauncherViewModel) -> String {
        if LauncherTouchBarRules.needsCredentialRefresh(model) {
            return "person.crop.circle.badge.plus"
        }
        if LauncherTouchBarRules.isPurchaseRequired(model) {
            return "person.crop.circle.badge.plus"
        }
        if LauncherTouchBarRules.shouldFocusRuntime(model) {
            return "arrow.down.circle"
        }
        if LauncherTouchBarRules.isMinecraftUpdateAvailable(model) {
            return "arrow.down.circle"
        }
        if model.canUseSelectedVersion {
            return model.isRuntimeReady ? "play.fill" : "arrow.down.circle"
        }
        if model.credential == nil {
            return "person.crop.circle.badge.plus"
        }
        if model.downloadState.phase == .failed {
            return "arrow.clockwise"
        }
        if model.latestVersion == nil {
            return "arrow.clockwise"
        }
        return "arrow.down.circle"
    }

    @MainActor
    private static func isPrimaryButtonDisabled(_ model: LauncherViewModel) -> Bool {
        model.isGooglePlayBusy || model.isRuntimeBusy || model.isLaunchingGame
    }

    @MainActor
    private static func isSignInVisible(_ model: LauncherViewModel, isProgressVisible: Bool) -> Bool {
        model.credential == nil
            && model.canUseSelectedVersion
            && model.isRuntimeReady
            && !isProgressVisible
    }

    @MainActor
    private static func isProgressVisible(_ model: LauncherViewModel) -> Bool {
        if model.isBlockingNetworkUnavailable {
            return true
        }

        switch model.downloadState.phase {
        case .authenticating, .fetchingLatest, .downloading, .extracting, .preparingFirstLaunch:
            return true
        case .idle, .installed, .failed:
            break
        }

        switch model.runtimeState.phase {
        case .checking, .downloading, .installing:
            return true
        case .missing, .ready, .failed:
            return false
        }
    }

    @MainActor
    private static func areTrailingActionsVisible(_ model: LauncherViewModel, isProgressVisible: Bool) -> Bool {
        guard !model.credentialAccessDenied else {
            return false
        }
        if model.downloadState.phase == .downloading || model.runtimeState.phase == .downloading {
            return true
        }
        return !isProgressVisible
    }

    @MainActor
    private static func progress(_ model: LauncherViewModel) -> Double? {
        if model.downloadState.phase == .downloading {
            return model.downloadState.progress > 0 ? model.downloadState.progress : nil
        }
        if model.runtimeState.phase == .downloading {
            return model.runtimeState.progress > 0 ? model.runtimeState.progress : nil
        }
        return nil
    }

    @MainActor
    private static func progressInfo(_ model: LauncherViewModel) -> ProgressInfo {
        if model.isBlockingNetworkUnavailable {
            return ProgressInfo(detailText: "Waiting for connection")
        }

        if model.downloadState.phase == .downloading {
            return compactProgressText(
                progress: model.downloadState.progress,
                eta: model.downloadState.etaSeconds,
                fallback: downloadBusyText(model)
            )
        }
        if model.downloadState.phase == .extracting {
            return ProgressInfo(detailText: downloadBusyText(model))
        }
        if model.runtimeState.phase == .downloading {
            return compactProgressText(
                progress: model.runtimeState.progress,
                eta: model.runtimeState.etaSeconds,
                fallback: "Downloading"
            )
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return ProgressInfo(detailText: busyText(model))
        }
        return ProgressInfo()
    }

    private static func compactProgressText(progress: Double, eta: Double?, fallback: String) -> ProgressInfo {
        let percentText: String?
        let detailText: String?
        if progress > 0 {
            percentText = String(format: "%.0f%%", min(max(progress, 0), 1) * 100)
        } else {
            percentText = nil
        }
        if let eta, eta.isFinite, eta > 0 {
            detailText = "\(formatETA(eta)) left"
        } else {
            detailText = nil
        }
        if percentText == nil && detailText == nil {
            return ProgressInfo(detailText: fallback)
        }
        return ProgressInfo(percentText: percentText, detailText: detailText)
    }

    @MainActor
    private static func busyText(_ model: LauncherViewModel) -> String {
        switch model.downloadState.phase {
        case .authenticating:
            return "Signing in"
        case .fetchingLatest:
            return "Checking"
        case .preparingFirstLaunch:
            return "Preparing"
        case .extracting:
            return "Extracting"
        case .idle, .downloading, .installed, .failed:
            break
        }

        switch model.runtimeState.phase {
        case .checking:
            return "Checking"
        case .installing:
            return model.runtimeState.detail ?? "Installing runtime"
        case .downloading:
            return "Downloading"
        case .missing, .ready, .failed:
            return shortStatusText(model)
        }
    }

    @MainActor
    private static func downloadBusyText(_ model: LauncherViewModel) -> String {
        switch model.downloadState.phase {
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Extracting"
        case .preparingFirstLaunch:
            return "Preparing"
        case .authenticating:
            return "Signing in"
        case .fetchingLatest:
            return "Checking"
        case .idle, .installed, .failed:
            return shortStatusText(model)
        }
    }

    @MainActor
    private static func statusColor(_ model: LauncherViewModel) -> NSColor {
        if model.isBlockingNetworkUnavailable {
            return .systemRed
        }
        if model.errorText != nil || model.runtimeState.phase == .failed || model.downloadState.phase == .failed {
            return .systemRed
        }
        if model.updateWarningText != nil {
            return .systemOrange
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return .systemOrange
        }
        if LauncherTouchBarRules.isMinecraftUpdateAvailable(model) {
            return .systemOrange
        }
        if model.canUseSelectedVersion && model.isRuntimeReady {
            return .systemGreen
        }
        return .secondaryLabelColor
    }

    @MainActor
    private static func shortStatusText(_ model: LauncherViewModel) -> String {
        if model.isBlockingNetworkUnavailable {
            return "No internet"
        }
        if model.activeIssue?.isNetworkUnavailable == true {
            return "Offline"
        }
        if model.downloadState.phase == .failed {
            return "Download failed"
        }
        if model.runtimeState.phase == .failed {
            return "Runtime failed"
        }
        if let errorText = model.errorText {
            return model.activeIssue?.shortText ?? errorText
        }
        if let updateWarningText = model.updateWarningText {
            return updateWarningText
        }
        if model.isRuntimeBusy && LauncherTouchBarRules.isRuntimeUpdateWork(model) {
            return "Runtime update"
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return "Working"
        }
        if LauncherTouchBarRules.shouldFocusRuntime(model) {
            return "Runtime missing"
        }
        if LauncherTouchBarRules.isMinecraftUpdateAvailable(model) {
            return "Update available"
        }
        if model.canUseSelectedVersion && model.isRuntimeReady {
            return "Ready"
        }
        if model.credential == nil {
            return "Not signed in"
        }
        if model.latestVersion == nil {
            return "Ready to check"
        }
        return "Not installed"
    }

    private static func formatETA(_ seconds: Double) -> String {
        let value = max(Int(seconds.rounded()), 0)
        if value >= 3600 {
            return "\(value / 3600)h \((value % 3600) / 60)m"
        }
        if value >= 60 {
            return "\(value / 60)m \(value % 60)s"
        }
        return "\(value)s"
    }
}

private struct ProgressInfo {
    var percentText: String?
    var detailText: String?

    var accessibilityText: String? {
        [percentText, detailText]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }
}

enum LauncherTouchBarRules {
    @MainActor
    static func isPurchaseRequired(_ model: LauncherViewModel) -> Bool {
        guard model.credential != nil,
              model.downloadState.phase == .failed else {
            return false
        }
        return model.activeIssue == .minecraftNotOwned
    }

    @MainActor
    static func needsCredentialRefresh(_ model: LauncherViewModel) -> Bool {
        guard model.credential != nil,
              model.downloadState.phase == .failed else {
            return false
        }
        return model.activeIssue == .googlePlayCredentialRequiresSignIn
    }

    @MainActor
    static func shouldFocusRuntime(_ model: LauncherViewModel) -> Bool {
        !model.isRuntimeReady
            && !model.isRuntimeBusy
            && model.runtimeState.phase != .checking
            && model.credential != nil
    }

    @MainActor
    static func isMinecraftUpdateAvailable(_ model: LauncherViewModel) -> Bool {
        guard model.credential != nil,
              let latest = model.latestVersion,
              !model.installedVersions.isEmpty else {
            return false
        }
        return !model.installedVersions.contains { $0.versionCode == latest.versionCode }
    }

    @MainActor
    static func isRuntimeUpdateWork(_ model: LauncherViewModel) -> Bool {
        switch model.runtimeState.phase {
        case .downloading, .installing:
            return model.runtimeState.version != nil
        case .missing, .checking, .ready, .failed:
            return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
