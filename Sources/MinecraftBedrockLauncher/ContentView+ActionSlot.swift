import SwiftUI

extension ContentView {
    @ViewBuilder
    var actionSlot: some View {
        ZStack {
            if isContentDropTargeted {
                EmptyView()
                    .transition(.opacity)
            } else if isShowingProgress {
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
        .animation(contentDropStateAnimation, value: isContentDropTargeted)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button {
                Task { await primaryAction() }
            } label: {
                primaryButtonLabel
                    .font(.body.weight(.semibold))
                    .frame(width: primaryButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isPrimaryButtonDisabled)

            if shouldShowPlaySideButton {
                playSideButton
            }
        }
    }

    @ViewBuilder
    private var primaryButtonLabel: some View {
        if isPrimaryPlayButton {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 16, height: 18)
                Text("Play")
            }
            .frame(maxWidth: .infinity)
        } else {
            Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                .contentTransition(.opacity)
        }
    }

    private var playSideButton: some View {
        let isDisabled = model.isGameLaunchBlocked

        return Button {
            Task { await model.playSelected(captureLog: false) }
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(.regularMaterial)
                }
                .overlay {
                    Circle()
                        .strokeBorder(.secondary.opacity(0.22), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 30, height: 30)
        .fixedSize()
        .help("Play installed version")
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private func primaryAction() async {
        if needsCredentialRefresh {
            model.signOut()
            model.showingLogin = true
            return
        }
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
                await model.playSelected(captureLog: false)
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
        if needsCredentialRefresh {
            return "Sign in"
        }
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

    private var primaryButtonIcon: String {
        if needsCredentialRefresh {
            return "person.crop.circle.badge.plus"
        }
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

    private var isPrimaryPlayButton: Bool {
        primaryButtonTitle == "Play"
    }

    private var primaryButtonWidth: CGFloat {
        switch primaryButtonTitle {
        case "Download Runtime":
            return 172
        case "Switch Account":
            return 172
        default:
            return 96
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        if model.isGameLaunchBlocked {
            return true
        }
        if model.canUseSelectedVersion {
            return false
        }
        return false
    }

    var isPurchaseRequired: Bool {
        guard model.credential != nil,
              model.downloadState.phase == .failed else {
            return false
        }
        return model.activeIssue == .minecraftNotOwned
    }

    private var needsCredentialRefresh: Bool {
        guard model.credential != nil,
              model.downloadState.phase == .failed else {
            return false
        }
        return model.activeIssue == .googlePlayCredentialRequiresSignIn
    }

    var shouldFocusRuntime: Bool {
        !model.isRuntimeReady
            && !model.isRuntimeBusy
            && model.runtimeState.phase != .checking
            && model.credential != nil
    }

    var isMinecraftUpdateAvailable: Bool {
        guard model.credential != nil,
              let latest = model.latestVersion,
              let installed = model.selectedVersion else {
            return false
        }
        return installed.versionCode != latest.versionCode
    }

    private var shouldShowPlaySideButton: Bool {
        model.canUseSelectedVersion
            && model.isRuntimeReady
            && !isPrimaryPlayAction
            && (isMinecraftUpdateAvailable || model.downloadState.phase == .failed)
    }

    private var isPrimaryPlayAction: Bool {
        !isPurchaseRequired
            && !shouldFocusRuntime
            && !isMinecraftUpdateAvailable
            && model.canUseSelectedVersion
            && model.isRuntimeReady
    }
}
