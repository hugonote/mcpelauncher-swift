import AppKit
import MinecraftBedrockLauncherCore
import SwiftUI

extension ContentView {
    var titleBlock: some View {
        ZStack {
            if isContentDropTargeted {
                contentImportTitleBlock
                    .transition(contentDropTitleTransition)
            } else {
                launcherTitleBlock
                    .transition(contentDropTitleTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(contentDropStateAnimation, value: isContentDropTargeted)
    }

    private var launcherTitleBlock: some View {
        VStack(spacing: 10) {
            titleIcon
                .scaleEffect(isTitleIconVisible || reduceMotion ? 1 : 0.72)
                .opacity(isTitleIconVisible || reduceMotion ? 1 : 0)
                .onAppear {
                    playTitleIconEntranceIfNeeded()
                }
                .onChange(of: isStartupComplete) { _, isComplete in
                    guard isComplete else {
                        return
                    }
                    playTitleIconEntranceIfNeeded()
                }
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(titleText)
                    .font(.title2.weight(.semibold))
                versionLine
            }
        }
    }

    private var contentImportTitleBlock: some View {
        VStack(spacing: 10) {
            DrawOnSymbolView(systemName: "square.and.arrow.down", size: 44)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Import Minecraft Content")
                    .font(.title2.weight(.semibold))
                Text(contentImportDropPreview?.releaseText ?? "Release to import Minecraft content")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
    }

    private var versionLine: some View {
        HStack(spacing: 5) {
            versionSubtitle
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(subtitleLineLimit)
                .help(versionText)

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

    @ViewBuilder
    private var versionSubtitle: some View {
        if let transition = updateVersionTransition {
            (Text(transition.installed)
                + Text(" → ")
                + Text(transition.latest))
                .accessibilityLabel("Version \(transition.installed) updates to \(transition.latest)")
        } else {
            Text(versionText)
        }
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
                .disabled(model.isGooglePlayBusy || model.isRuntimeBusy)
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

            if let titleIconBadge, !isContentDropTargeted {
                TitleIconBadgeView(kind: titleIconBadge)
                    .offset(x: 3, y: 2)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
        .frame(width: 60, height: 60)
        .animation(.easeInOut(duration: 0.18), value: titleIconBadge)
    }

    private var versionText: String {
        if isPurchaseRequired {
            return "Minecraft is not owned by this account"
        }
        if shouldShowRuntimeTitle {
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

    var shouldUseBedrockIcon: Bool {
        !isPurchaseRequired && !shouldShowRuntimeTitle
    }

    private var bedrockIconImage: NSImage? {
        LauncherResourceLoader.image(named: "cut-bedrock-launcher-icon-foreground-transparent", fileExtension: "png")
    }

    private var titleIconColor: Color {
        .secondary
    }

    private var usesMultilineSubtitle: Bool {
        shouldShowRuntimeTitle || isPurchaseRequired || isShowingErrorSubtitle
    }

    private var subtitleLineLimit: Int {
        isShowingErrorSubtitle ? 3 : (usesMultilineSubtitle ? 2 : 1)
    }

    private var isShowingErrorSubtitle: Bool {
        model.downloadState.phase == .failed
            || model.runtimeState.phase == .failed
            || model.errorText != nil
    }

    private var shouldShowVersionInfoButton: Bool {
        model.credential != nil
            && !isPurchaseRequired
            && !shouldShowRuntimeTitle
            && model.downloadState.phase != .failed
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

    private var updateVersionTransition: (installed: String, latest: String)? {
        guard shouldUseBedrockIcon,
              isMinecraftUpdateAvailable,
              let installed = model.selectedVersion,
              let latest = model.latestVersion else {
            return nil
        }
        return (installed.versionName, latest.versionName)
    }

    var shouldShowRuntimeTitle: Bool {
        shouldFocusRuntime || isRuntimeDownloadWork
    }

    private var isRuntimeDownloadWork: Bool {
        switch model.runtimeState.phase {
        case .downloading, .installing:
            return true
        case .missing, .checking, .ready, .failed:
            return false
        }
    }

    var isRuntimeUpdateWork: Bool {
        switch model.runtimeState.phase {
        case .downloading, .installing:
            return model.runtimeState.version != nil
        case .missing, .checking, .ready, .failed:
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
        if shouldUseBedrockIcon && isMinecraftUpdateAvailable {
            return .updateAvailable
        }
        return nil
    }

    private var isTitleIconWorking: Bool {
        switch model.downloadState.phase {
        case .downloading, .extracting, .preparingFirstLaunch:
            return true
        case .idle, .authenticating, .fetchingLatest, .installed, .failed:
            break
        }

        switch model.runtimeState.phase {
        case .downloading, .installing:
            return true
        case .missing, .checking, .ready, .failed:
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

    private func centerErrorText(for error: String) -> String {
        if let centerText = model.activeIssue?.centerText {
            return centerText
        }
        return error
    }
}
