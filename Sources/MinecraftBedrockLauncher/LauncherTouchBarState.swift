import Foundation
import MinecraftBedrockLauncherCore

struct LauncherTouchBarConfiguration {
    var state: LauncherTouchBarState
    var onPrimary: @MainActor () -> Void
    var onPlay: @MainActor () -> Void
    var onSignIn: @MainActor () -> Void
    var onCancel: @MainActor () -> Void
    var onSkipRuntimeUpdateCheck: @MainActor () -> Void
    var onSettings: @MainActor () -> Void
    var onOpenDataFolder: @MainActor () -> Void
    var onImportContent: @MainActor () -> Void
}

struct LauncherTouchBarState {
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
    var isSkipVisible: Bool
    var isTrailingActionsVisible: Bool
    var isPrimaryVisible: Bool
    var isPlaySideVisible: Bool
    var isHidden: Bool

    @MainActor
    init(model: LauncherViewModel) {
        let progressVisible = Self.isProgressVisible(model)
        let credentialAccessDenied = model.credentialAccessDenied

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
        isSkipVisible = model.canSkipRuntimeUpdateCheck
        isPrimaryVisible = !progressVisible
        isTrailingActionsVisible = Self.areTrailingActionsVisible(model, isProgressVisible: progressVisible)
        isPlaySideVisible = credentialAccessDenied ? false : Self.isPlaySideVisible(model, isProgressVisible: progressVisible)
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
            return "Download"
        }
        if LauncherTouchBarRules.isMinecraftUpdateAvailable(model) {
            return "Update"
        }
        if model.canUseSelectedVersion {
            if model.isRuntimeReady {
                return "Play"
            }
            return "Download"
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
        model.isGameLaunchBlocked
    }

    @MainActor
    private static func isSignInVisible(_ model: LauncherViewModel, isProgressVisible: Bool) -> Bool {
        model.credential == nil
            && model.canUseSelectedVersion
            && model.isRuntimeReady
            && !isProgressVisible
    }

    @MainActor
    private static func isPlaySideVisible(_ model: LauncherViewModel, isProgressVisible: Bool) -> Bool {
        guard !isProgressVisible,
              model.canUseSelectedVersion,
              model.isRuntimeReady,
              !LauncherTouchBarRules.needsCredentialRefresh(model),
              !LauncherTouchBarRules.isPurchaseRequired(model) else {
            return false
        }
        return LauncherTouchBarRules.isMinecraftUpdateAvailable(model) || model.downloadState.phase == .failed
    }

    @MainActor
    private static func isProgressVisible(_ model: LauncherViewModel) -> Bool {
        if model.isImportingContent {
            return true
        }
        if model.isBlockingNetworkUnavailable {
            return true
        }
        if model.isCheckingLauncherUpdates {
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
        if model.isImportingContent {
            return model.contentImportProgress?.fraction
        }
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
        if model.isImportingContent {
            if let contentImportProgress = model.contentImportProgress {
                return ProgressInfo(
                    percentText: String(format: "%.0f%%", min(max(contentImportProgress.fraction, 0), 1) * 100),
                    detailText: contentImportProgress.text
                )
            }
            return ProgressInfo()
        }
        if model.isCheckingLauncherUpdates {
            return ProgressInfo(detailText: "Checking")
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy || model.isImportingContent {
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
            return "Working"
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
            return "Working"
        }
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
            && model.canDownloadRuntime
    }

    @MainActor
    static func isMinecraftUpdateAvailable(_ model: LauncherViewModel) -> Bool {
        guard model.credential != nil,
              let latest = model.latestVersion,
              let installed = model.selectedVersion else {
            return false
        }
        return installed.versionCode != latest.versionCode
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
