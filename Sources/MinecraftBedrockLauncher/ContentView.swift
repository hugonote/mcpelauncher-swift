import Foundation
import MinecraftBedrockLauncherCore
import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var isShowingSignOutConfirmation = false
    @State private var isShowingVersionInfo = false
    @State private var isStartupComplete = false
    @State private var window: NSWindow?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 30)
                if isShowingCorruptedAppError {
                    corruptedAppView
                } else if model.credentialAccessDenied {
                    keychainErrorView
                } else if model.isBlockingNetworkUnavailable {
                    networkUnavailableView
                } else {
                    titleBlock
                    actionSlot
                }
                Spacer(minLength: 0)
                if !shouldHideChrome {
                    statusBar
                }
            }
            .padding(.top, 20)
            .padding(.bottom, bottomContentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !shouldHideChrome {
                VStack {
                    accountBar
                    Spacer()
                }
                .padding(.top, 2)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .sheet(isPresented: $model.showingLogin) {
            GoogleLoginSheet(model: model)
        }
        .alert("Log out?", isPresented: $isShowingSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log out", role: .destructive) {
                model.signOut()
            }
        } message: {
            Text("You will need to sign in again before downloading Minecraft updates.")
        }
        .background(WindowConfigurator(window: $window, isVisible: isStartupComplete))
        .onChange(of: model.downloadState) { _, _ in
            updateDockProgress()
        }
        .onChange(of: model.runtimeState) { _, _ in
            updateDockProgress()
        }
        .onDisappear {
            DockProgressController.shared.clear()
        }
        .task(id: window != nil) {
            guard window != nil else {
                return
            }
            await model.start()
            isStartupComplete = true
        }
    }

    private func updateDockProgress() {
        DockProgressController.shared.update(downloadState: model.downloadState, runtimeState: model.runtimeState)
    }

    private var accountBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 104)

            Text(model.displayCredentialEmail ?? "Not signed in")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .fixedSize(horizontal: true, vertical: false)

            if model.credential == nil {
                Button("Sign in") {
                    model.showingLogin = true
                }
                .buttonStyle(.link)
                .font(.callout.weight(.semibold))
            } else {
                Button {
                    isShowingSignOutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Log out")
            }
        }
        .frame(height: 28)
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            titleIcon
                .primaryIconBounce(id: titleIconBounceID)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(titleText)
                    .font(.title2.weight(.semibold))
                versionLine
            }
        }
    }

    private var versionLine: some View {
        HStack(spacing: 5) {
            Text(versionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(usesMultilineSubtitle ? 2 : 1)

            if shouldShowVersionInfoButton {
                Button {
                    isShowingVersionInfo.toggle()
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Version details")
                .popover(isPresented: $isShowingVersionInfo, arrowEdge: .bottom) {
                    versionInfoPopover
                }
            }
        }
        .frame(maxWidth: usesMultilineSubtitle ? 280 : .infinity)
    }

    private var versionInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Versions")
                    .font(.headline)
                Spacer()
                Button {
                    isShowingVersionInfo = false
                    Task { await model.refreshVersionInfo() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isGooglePlayBusy)
                .help("Refresh")
            }

            VStack(alignment: .leading, spacing: 7) {
                versionInfoRow("Runtime", runtimeInfoVersionText)
                versionInfoRow("Compatible", compatibleVersionText)
                versionInfoRow("Google Play", googlePlayVersionText)
            }
        }
        .padding(12)
        .frame(width: 166)
    }

    private func versionInfoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private var titleIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            if shouldUseBedrockIcon {
                if let bedrockIconImage {
                    Image(nsImage: bedrockIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                } else {
                    Image(systemName: titleIconName)
                        .font(.system(size: 44))
                        .foregroundStyle(titleIconColor)
                        .frame(width: 56, height: 56)
                }
            } else {
                Image(systemName: titleIconName)
                    .font(.system(size: 44))
                    .foregroundStyle(titleIconColor)
                    .frame(width: 56, height: 56)
            }

            if let titleIconBadge {
                TitleIconBadgeView(kind: titleIconBadge)
                    .offset(x: 3, y: 2)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
        .frame(width: 60, height: 60)
        .animation(.easeInOut(duration: 0.18), value: titleIconBadge)
    }

    private var keychainErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .primaryIconBounce(id: "key.slash")
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Keychain Access Needed")
                    .font(.title3.weight(.semibold))
                Text("Authorization lets the launcher check Google Play and pass credentials to Minecraft")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
            }

            Button {
                Task { await model.retryStoredCredentialAccess() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: primaryButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .offset(y: -18)
    }

    private var corruptedAppView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.yellow)
                .primaryIconBounce(id: "corrupted-app")
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Application Corrupted")
                    .font(.title3.weight(.semibold))
                Text("Reinstall the launcher and try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
            }

            Button {
                window?.close()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: primaryButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .offset(y: -18)
    }

    private var networkUnavailableView: some View {
        VStack(spacing: 12) {
            OfflineGlobeView()
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("No Internet Connection")
                    .font(.title3.weight(.semibold))
                Text(networkUnavailableMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 276)
            }

            Button {
                Task { await primaryAction() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: primaryButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isGooglePlayBusy || model.isRuntimeBusy)
        }
        .offset(y: -26)
    }

    @ViewBuilder
    private var actionSlot: some View {
        ZStack {
            if isShowingProgress {
                progress
                    .padding(.horizontal, 40)
                    .transition(.opacity)
            } else {
                actions
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await primaryAction() }
            } label: {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .font(.body.weight(.semibold))
                    .frame(width: primaryButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPrimaryButtonDisabled)

            if shouldShowPlaySideButton {
                Button {
                    Task { await model.playSelected() }
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .clipShape(Circle())
                .help("Play installed version")
                .disabled(model.isGooglePlayBusy || model.isRuntimeBusy)
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if model.canSkipRuntimeUpdateCheck {
            runtimeProgress
        } else if isShowingDownloadProgress {
            VStack(spacing: 6) {
                if model.downloadState.phase == .extracting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(downloadStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(height: 31)
                    .frame(maxWidth: .infinity)
                } else {
                    if isDeterminateDownloadProgress {
                        ProgressView(value: model.downloadState.progress)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    HStack(spacing: 8) {
                        progressText(primary: downloadStatusText, secondary: downloadSecondaryStatusText)
                        if model.downloadState.phase == .downloading {
                            Button {
                                model.cancelDownload()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Cancel download")
                        }
                    }
                }
            }
        } else if model.isRuntimeBusy {
            runtimeProgress
        }
    }

    private var runtimeProgress: some View {
        VStack(spacing: 6) {
            if model.runtimeState.phase == .installing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(runtimeProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
            } else {
                if isDeterminateRuntimeProgress {
                    ProgressView(value: model.runtimeState.progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                if model.canSkipRuntimeUpdateCheck {
                    runtimeSkipProgress
                } else {
                    progressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
                }
            }
        }
    }

    private var runtimeSkipProgress: some View {
        ZStack(alignment: .trailing) {
            Text(runtimeProgressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Button {
                model.skipRuntimeUpdateCheck()
            } label: {
                Label("Skip", systemImage: "forward.end")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Skip runtime update check")
        }
        .frame(height: 31)
        .frame(maxWidth: .infinity)
    }

    private func progressText(primary: String, secondary: String?) -> some View {
        VStack(spacing: 1) {
            Text(primary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Text(secondary ?? " ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
        }
        .frame(height: 31)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Text(shortStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                NSWorkspace.shared.open(model.dataFolderURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open data folder")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private func primaryAction() async {
        if isPurchaseRequired {
            model.signOut()
            model.showingLogin = true
            return
        }
        if shouldFocusRuntime {
            model.startRuntimeInstall()
            return
        }
        if isMinecraftUpdateAvailable {
            model.startDownloadAndInstallLatest()
            return
        }
        if model.canUseSelectedVersion {
            if model.isRuntimeReady {
                await model.playSelected()
            } else {
                model.startRuntimeInstall()
            }
            return
        }
        if model.credential == nil {
            model.showingLogin = true
            return
        }
        model.startDownloadAndInstallLatest()
    }

    private var primaryButtonTitle: String {
        if isPurchaseRequired {
            return "Switch Account"
        }
        if shouldFocusRuntime {
            return "Download Runtime"
        }
        if isMinecraftUpdateAvailable {
            return "Update"
        }
        if model.canUseSelectedVersion {
            return model.isRuntimeReady ? "Play" : "Download Runtime"
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

    private var primaryButtonIcon: String {
        if isPurchaseRequired {
            return "person.crop.circle.badge.plus"
        }
        if shouldFocusRuntime {
            return "arrow.down.circle"
        }
        if isMinecraftUpdateAvailable {
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

    private var primaryButtonWidth: CGFloat {
        primaryButtonTitle == "Download Runtime" ? 172 : 96
    }

    private var isPrimaryButtonDisabled: Bool {
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return true
        }
        if model.canUseSelectedVersion {
            return false
        }
        return false
    }

    private var isShowingProgress: Bool {
        if model.canSkipRuntimeUpdateCheck {
            return true
        }
        if isShowingDownloadProgress {
            return true
        }
        return model.isRuntimeBusy
    }

    private var isShowingDownloadProgress: Bool {
        model.downloadState.phase != .idle
            && model.downloadState.phase != .failed
            && model.downloadState.phase != .installed
    }

    private var isDeterminateDownloadProgress: Bool {
        model.downloadState.phase == .downloading || model.downloadState.phase == .extracting
    }

    private var isDeterminateRuntimeProgress: Bool {
        model.runtimeState.phase == .downloading && model.runtimeState.progress > 0
    }

    private var versionText: String {
        if isPurchaseRequired {
            return "Minecraft is not owned by this account"
        }
        if shouldShowRuntimeTitle {
            if isRuntimeUpdateWork {
                return "Updating native files for Bedrock on macOS"
            }
            return "Native files needed to run Bedrock on macOS"
        }
        if let selected = model.selectedVersion {
            return "Version \(selected.versionName)"
        }
        if model.downloadState.phase == .failed, let error = model.downloadState.error ?? model.errorText {
            return centerErrorText(for: error)
        }
        if let latest = model.latestVersion {
            return "Latest \(latest.versionName)"
        }
        return "No version installed"
    }

    private var titleText: String {
        if isPurchaseRequired {
            return "Purchase Required"
        }
        if shouldShowRuntimeTitle {
            if isRuntimeUpdateWork {
                return "Runtime Update"
            }
            return "Runtime Required"
        }
        return "Minecraft Bedrock"
    }

    private var titleIconName: String {
        if isPurchaseRequired {
            return "cart"
        }
        if shouldShowRuntimeTitle {
            return "cpu"
        }
        return "cube.fill"
    }

    private var titleIconBounceID: String {
        shouldUseBedrockIcon ? "bedrock-icon" : titleIconName
    }

    private var shouldUseBedrockIcon: Bool {
        !isPurchaseRequired && !shouldShowRuntimeTitle
    }

    private var bedrockIconImage: NSImage? {
        LauncherResourceLoader.image(named: "cut-bedrock-launcher-icon-foreground-transparent", fileExtension: "png")
    }

    private var titleIconColor: Color {
        .secondary
    }

    private var usesMultilineSubtitle: Bool {
        shouldShowRuntimeTitle || isPurchaseRequired
    }

    private var shouldShowVersionInfoButton: Bool {
        !isPurchaseRequired && !shouldShowRuntimeTitle
    }

    private var runtimeInfoVersionText: String {
        model.runtimeState.version ?? "Not installed"
    }

    private var compatibleVersionText: String {
        if let supported = model.newestSupportedVersion {
            return supported.versionName
        }
        if let latest = model.latestVersion {
            return latest.versionName
        }
        return "Unknown"
    }

    private var googlePlayVersionText: String {
        model.googlePlayLatestVersion?.versionName ?? "Unknown"
    }

    private var isPurchaseRequired: Bool {
        guard model.credential != nil,
              model.downloadState.phase == .failed,
              let error = model.downloadState.error ?? model.errorText else {
            return false
        }
        return isMinecraftPurchaseError(error)
    }

    private var shouldFocusRuntime: Bool {
        !model.isRuntimeReady
            && !model.isRuntimeBusy
            && model.runtimeState.phase != .checking
            && model.credential != nil
    }

    private var isMinecraftUpdateAvailable: Bool {
        guard model.credential != nil,
              let latest = model.latestVersion,
              !model.installedVersions.isEmpty else {
            return false
        }
        return !model.installedVersions.contains { $0.versionCode == latest.versionCode }
    }

    private var shouldShowPlaySideButton: Bool {
        isMinecraftUpdateAvailable && model.canUseSelectedVersion && model.isRuntimeReady
    }

    private var shouldShowRuntimeTitle: Bool {
        shouldFocusRuntime || isRuntimePrimaryWork
    }

    private var isRuntimePrimaryWork: Bool {
        !model.isGooglePlayBusy
            && !model.isRuntimeReady
            && model.isRuntimeBusy
    }

    private var isRuntimeUpdateWork: Bool {
        guard shouldShowRuntimeTitle else {
            return false
        }
        switch model.runtimeState.phase {
        case .checking:
            return true
        case .downloading, .installing:
            return model.runtimeState.version != nil
        case .missing, .ready, .failed:
            return false
        }
    }

    private var titleIconBadge: TitleIconBadge? {
        if isTitleIconWorking {
            return .working
        }
        if isTitleIconMissing {
            return .missing
        }
        return nil
    }

    private var isTitleIconWorking: Bool {
        switch model.downloadState.phase {
        case .downloading, .extracting:
            return true
        case .idle, .authenticating, .fetchingLatest, .installed, .failed:
            break
        }

        switch model.runtimeState.phase {
        case .checking, .downloading, .installing:
            return true
        case .missing, .ready, .failed:
            return false
        }
    }

    private var isTitleIconMissing: Bool {
        if isPurchaseRequired {
            return false
        }
        if isRuntimeUpdateWork {
            return false
        }
        if shouldShowRuntimeTitle {
            return !model.isRuntimeReady
        }
        return model.selectedVersion == nil && model.downloadState.phase != .installed
    }

    private var statusColor: Color {
        if model.isBlockingNetworkUnavailable {
            return .orange
        }
        if model.errorText != nil || model.runtimeState.phase == .failed || model.downloadState.phase == .failed {
            return .red
        }
        if model.updateWarningText != nil {
            return .orange
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return .orange
        }
        if isMinecraftUpdateAvailable {
            return .orange
        }
        if model.canUseSelectedVersion && model.isRuntimeReady {
            return .green
        }
        return .secondary
    }

    private var shortStatusText: String {
        if model.isBlockingNetworkUnavailable {
            return "No internet connection"
        }
        if let errorText = model.errorText {
            return shortErrorText(for: errorText)
        }
        if let updateWarningText = model.updateWarningText {
            return updateWarningText
        }
        if model.isRuntimeBusy && isRuntimeUpdateWork {
            return "Runtime update"
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return "Working"
        }
        if shouldFocusRuntime {
            return "Runtime missing"
        }
        if isMinecraftUpdateAvailable {
            return "Update available"
        }
        if model.canUseSelectedVersion && model.isRuntimeReady {
            return "Ready"
        }
        if model.credential == nil {
            return "Sign in required"
        }
        if model.latestVersion == nil {
            return "Ready to check"
        }
        return "Not installed"
    }

    private var shouldHideChrome: Bool {
        model.credentialAccessDenied || isShowingCorruptedAppError
    }

    private var isShowingCorruptedAppError: Bool {
        if let errorText = model.errorText, isBundledHelperNotFoundError(errorText) {
            return true
        }
        if model.downloadState.phase == .failed,
           let error = model.downloadState.error,
           isBundledHelperNotFoundError(error) {
            return true
        }
        return false
    }

    private func centerErrorText(for error: String) -> String {
        if isBundledHelperNotFoundError(error) {
            return "Application corrupted"
        }
        if isMinecraftPurchaseError(error) {
            return "Minecraft not purchased"
        }
        return error
    }

    private func shortErrorText(for error: String) -> String {
        if model.isBlockingNetworkUnavailable {
            return "No internet connection"
        }
        if isMinecraftPurchaseError(error) {
            return "Purchase required"
        }
        if isBundledHelperNotFoundError(error) {
            return "Application corrupted"
        }
        return error
    }

    private var networkUnavailableMessage: String {
        if model.selectedVersion == nil {
            return "Connect to download Minecraft"
        }
        return "Connect to download the runtime"
    }

    private var bottomContentPadding: CGFloat {
        if shouldHideChrome {
            return 20
        }
        if model.isBlockingNetworkUnavailable {
            return 12
        }
        return 28
    }

    private func isMinecraftPurchaseError(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("minecraft is not purchased")
    }

    private func isBundledHelperNotFoundError(_ error: String) -> Bool {
        let helperNames = [
            "Google Play tool",
            "gplayver",
            "gplaydl",
            "mcpelauncher-ui-qt",
            "mcpelauncher-webview"
        ]
        let missingMarkers = [
            "was not found",
            "not found",
            "no such file"
        ]
        return helperNames.contains { helperName in
            error.localizedCaseInsensitiveContains(helperName)
        } && missingMarkers.contains { marker in
            error.localizedCaseInsensitiveContains(marker)
        }
    }

    private var runtimeStatusText: String {
        switch model.runtimeState.phase {
        case .missing:
            return "Not installed"
        case .checking:
            return model.runtimeState.detail ?? "Checking"
        case .downloading:
            return model.runtimeState.detail ?? "Downloading"
        case .installing:
            return model.runtimeState.detail ?? "Installing"
        case .ready:
            let version = model.runtimeState.version ?? "installed"
            if let detail = model.runtimeState.detail, !detail.isEmpty {
                return "\(version) - \(detail)"
            }
            return version
        case .failed:
            return model.runtimeState.error ?? "Runtime update failed"
        }
    }

    private var runtimeProgressText: String {
        let state = model.runtimeState
        if state.phase == .downloading {
            var parts: [String] = []
            if let bytes = state.bytesReceived, let total = state.totalBytes, total > 0 {
                let percent = Double(bytes) / Double(total) * 100
                parts.append(String(format: "%.1f%%", percent))
                parts.append("\(Self.byteFormatter.string(fromByteCount: bytes)) / \(Self.byteFormatter.string(fromByteCount: total))")
            }
            if !parts.isEmpty {
                return parts.joined(separator: " - ")
            }
        }
        return state.detail ?? runtimeStatusText
    }

    private var runtimeSecondaryProgressText: String? {
        guard model.runtimeState.phase == .downloading else {
            return nil
        }
        return speedAndETA(speed: model.runtimeState.speedBytesPerSecond, eta: model.runtimeState.etaSeconds)
    }

    private var downloadStatusText: String {
        let state = model.downloadState
        if state.phase == .downloading {
            var parts: [String] = []
            if let bytes = state.bytesReceived, let total = state.totalBytes, total > 0 {
                let percent = Double(bytes) / Double(total) * 100
                parts.append(String(format: "%.1f%%", percent))
                parts.append("\(Self.byteFormatter.string(fromByteCount: bytes)) / \(Self.byteFormatter.string(fromByteCount: total))")
            }
            if parts.isEmpty {
                parts.append("Downloading")
            }
            return parts.joined(separator: " - ")
        }
        if let detail = state.detail {
            return detail
        }
        switch state.phase {
        case .idle:
            return "Ready"
        case .authenticating:
            return "Signing in"
        case .fetchingLatest:
            return "Checking for updates"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Extracting"
        case .installed:
            return "Installed"
        case .failed:
            return state.error ?? "Failed"
        }
    }

    private var downloadSecondaryStatusText: String? {
        guard model.downloadState.phase == .downloading else {
            return nil
        }
        return speedAndETA(speed: model.downloadState.speedBytesPerSecond, eta: model.downloadState.etaSeconds)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

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

    private func speedAndETA(speed: Double?, eta: Double?) -> String? {
        var parts: [String] = []
        if let speed, speed > 1 {
            parts.append("\(Self.byteFormatter.string(fromByteCount: Int64(speed)))/s")
        }
        if let eta, eta.isFinite, eta > 0 {
            parts.append("\(Self.formatETA(eta)) left")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

}

private enum TitleIconBadge: Equatable {
    case missing
    case working
}

private struct OfflineGlobeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                ZStack {
                    if isVisible {
                        networkSlashIcon
                            .transition(.symbolEffect(.drawOn.byLayer))
                    }
                }
                .onAppear {
                    guard !isVisible else {
                        return
                    }
                    if reduceMotion {
                        isVisible = true
                        return
                    }
                    withAnimation {
                        isVisible = true
                    }
                }
            } else {
                networkSlashIcon
            }
        }
        .frame(width: 68, height: 68)
    }

    private var networkSlashIcon: some View {
        Image(systemName: "network.slash")
            .font(.system(size: 54, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

private struct TitleIconBadgeView: View {
    var kind: TitleIconBadge

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        Group {
            switch kind {
            case .missing:
                missingBadge
            case .working:
                workingBadge
            }
        }
        .frame(width: 18, height: 18)
        .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
    }

    private var missingBadge: some View {
        ZStack {
            Circle()
                .fill(.orange)

            Image(systemName: "questionmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var workingBadge: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .opacity(0.85)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isRotating && !reduceMotion ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 3.4).repeatForever(autoreverses: false),
                    value: isRotating
                )
                .onAppear {
                    guard !reduceMotion else {
                        return
                    }
                    isRotating = true
                }
                .onDisappear {
                    isRotating = false
                }
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

private enum LauncherResourceLoader {
    static func image(named name: String, fileExtension: String) -> NSImage? {
        for url in candidateURLs(named: name, fileExtension: fileExtension) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private static func candidateURLs(named name: String, fileExtension: String) -> [URL] {
        let fileName = "\(name).\(fileExtension)"
        var urls: [URL] = []

        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            urls.append(url)
        }

        let resourceURL = Bundle.main.resourceURL
        let bundleNames = [
            "SwiftLauncher_MinecraftBedrockLauncher.bundle",
            "MinecraftBedrockLauncher_MinecraftBedrockLauncher.bundle"
        ]
        for bundleName in bundleNames {
            if let url = resourceURL?
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false) {
                urls.append(url)
            }
        }

        if let executableURL = Bundle.main.executableURL {
            let buildDirectoryURL = executableURL.deletingLastPathComponent()
            for bundleName in bundleNames {
                urls.append(
                    buildDirectoryURL
                        .appendingPathComponent(bundleName, isDirectory: true)
                        .appendingPathComponent(fileName, isDirectory: false)
                )
            }
        }

        return urls
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    @Binding var window: NSWindow?
    var isVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window, isVisible: isVisible)
            window = view.window
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window, isVisible: isVisible)
            window = view.window
        }
    }

    private func configure(window: NSWindow?, isVisible: Bool) {
        guard let window else {
            return
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.remove(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.level = .normal
        window.hidesOnDeactivate = false
        StartupWindowVisibility.shared.hideIfNeeded(window)
        let wasHidden = window.alphaValue == 0
        window.alphaValue = isVisible ? 1 : 0
        if isVisible && wasHidden {
            StartupWindowVisibility.shared.reveal(window)
        } else if isVisible {
            window.ignoresMouseEvents = false
        }
    }
}
