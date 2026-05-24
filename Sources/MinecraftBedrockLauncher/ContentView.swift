import Foundation
import MinecraftBedrockLauncherCore
import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var isShowingSignOutConfirmation = false
    @State private var isShowingVersionInfo = false
    @State private var isStartupComplete = false
    @State private var isTitleIconVisible = false
    @State private var isOptionKeyPressed = false
    @State private var modifierFlagsMonitor: Any?
    @State private var window: NSWindow?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onAppear {
            installModifierFlagsMonitor()
        }
        .onDisappear {
            removeModifierFlagsMonitor()
            DockProgressController.shared.clear()
        }
        .task(id: window != nil) {
            guard let window else {
                return
            }
            await model.start()
            isStartupComplete = true
            StartupWindowVisibility.shared.reveal(window)
            await Task.yield()
            await model.continueStartupAfterWindowReveal()
        }
    }

    private func updateDockProgress() {
        DockProgressController.shared.update(downloadState: model.downloadState, runtimeState: model.runtimeState)
    }

    private func playTitleIconEntranceIfNeeded() {
        guard isStartupComplete else {
            return
        }
        guard !isTitleIconVisible else {
            return
        }
        if reduceMotion {
            isTitleIconVisible = true
            return
        }

        let animation = Animation.interpolatingSpring(
            mass: 0.42,
            stiffness: 190,
            damping: 9.5,
            initialVelocity: 5
        )

        DispatchQueue.main.async {
            withAnimation(animation) {
                isTitleIconVisible = true
            }
        }
    }

    private var accountBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 104)

            Text(model.displayCredentialEmail ?? "Not signed in")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 250, alignment: .trailing)
                .help(model.displayCredentialEmail ?? "Not signed in")

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

    private var versionLine: some View {
        HStack(spacing: 5) {
            versionSubtitle
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
            DrawOnSymbolView(systemName: "key.slash", size: 36)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Keychain Access Needed")
                    .font(.title3.weight(.semibold))
                Text("Authorization lets the launcher check Google Play and download Minecraft")
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
                    .frame(width: compactButtonWidth)
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
                    .frame(width: compactButtonWidth)
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

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for connection")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 32)
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
        HStack(spacing: 6) {
            Button {
                Task { await primaryAction() }
            } label: {
                primaryButtonLabel
                    .font(.body.weight(.semibold))
                    .frame(width: primaryButtonWidth)
                    .animation(.easeInOut(duration: 0.09), value: shouldShowPlayLogPrimaryButton)
                    .animation(.easeOut(duration: 0.12), value: primaryButtonTitle)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                playLogIcon
                    .frame(width: shouldShowPlayLogPrimaryButton ? 24 : 16, height: 18)

                HStack(spacing: 0) {
                    Text("Play")
                    if shouldShowPlayLogPrimaryButton {
                        Text(" & Log")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
            .clipped()
        } else {
            Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                .contentTransition(.opacity)
        }
    }

    private var playLogIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .offset(x: shouldShowPlayLogPrimaryButton ? -2 : 0)
            if shouldShowPlayLogPrimaryButton {
                Image(systemName: "doc.text")
                    .font(.system(size: 7.5, weight: .bold))
                    .offset(x: 4, y: 2)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
    }

    private var playSideButton: some View {
        let isDisabled = model.isGooglePlayBusy || model.isRuntimeBusy

        return Button {
            Task { await model.playSelected(captureLog: shouldCapturePlayLog) }
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
        .help(shouldCapturePlayLog ? "Play installed version and write launch log" : "Play installed version")
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    @ViewBuilder
    private var progress: some View {
        if model.canSkipRuntimeUpdateCheck {
            runtimeProgress
        } else if isShowingDownloadProgress {
            VStack(spacing: 6) {
                if model.downloadState.phase == .extracting {
                    inlineProgressText(primary: downloadStatusText)
                } else {
                    if isDeterminateDownloadProgress {
                        ProgressView(value: model.downloadState.progress)
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
                    } else {
                        inlineProgressText(primary: downloadStatusText, secondary: downloadSecondaryStatusText)
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
                inlineProgressText(primary: runtimeProgressText, height: 50)
            } else {
                if isDeterminateRuntimeProgress {
                    ProgressView(value: model.runtimeState.progress)
                    if model.canSkipRuntimeUpdateCheck {
                        runtimeSkipProgress
                    } else {
                        runtimeCancelableProgressText
                    }
                } else {
                    if model.canSkipRuntimeUpdateCheck {
                        runtimeSkipProgress
                    } else if model.runtimeState.phase == .downloading {
                        runtimeCancelableInlineProgress
                    } else {
                        inlineProgressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
                    }
                }
            }
        }
    }

    private var runtimeSkipProgress: some View {
        ZStack(alignment: .trailing) {
            inlineProgressText(primary: runtimeProgressText)
                .padding(.horizontal, 76)

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

    private var runtimeCancelableProgressText: some View {
        HStack(spacing: 8) {
            progressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
            runtimeCancelButton
        }
    }

    private var runtimeCancelableInlineProgress: some View {
        HStack(spacing: 8) {
            inlineProgressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
            runtimeCancelButton
        }
    }

    private var runtimeCancelButton: some View {
        Button {
            model.cancelRuntimeDownload()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Cancel runtime download")
    }

    private func inlineProgressText(primary: String, secondary: String? = nil, height: CGFloat = 31) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            compactProgressText(primary: primary, secondary: secondary)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func compactProgressText(primary: String, secondary: String?) -> some View {
        if let secondary {
            VStack(alignment: .leading, spacing: 1) {
                progressLine(primary, font: .caption, style: .secondary)
                progressLine(secondary, font: .caption2, style: .tertiary)
            }
        } else {
            progressLine(primary, font: .caption, style: .secondary)
        }
    }

    private func progressText(primary: String, secondary: String?) -> some View {
        VStack(spacing: 1) {
            progressLine(primary, font: .caption, style: .secondary)
                .frame(maxWidth: .infinity)

            progressLine(secondary ?? " ", font: .caption2, style: .tertiary)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 31)
    }

    private func progressLine(_ text: String, font: Font, style: HierarchicalShapeStyle) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(style)
            .lineLimit(1)
            .truncationMode(.middle)
            .monospacedDigit()
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
                await model.playSelected(captureLog: shouldCapturePlayLog)
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
            if model.isRuntimeReady {
                return shouldCapturePlayLog ? "Play & Log" : "Play"
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

    private var shouldShowPlayLogPrimaryButton: Bool {
        primaryButtonTitle == "Play & Log"
    }

    private var isPrimaryPlayButton: Bool {
        primaryButtonTitle == "Play" || shouldShowPlayLogPrimaryButton
    }

    private var primaryButtonWidth: CGFloat {
        primaryButtonTitle == "Download Runtime" ? 172 : 96
    }

    private var compactButtonWidth: CGFloat {
        96
    }

    private var shouldCapturePlayLog: Bool {
        isOptionKeyPressed || NSEvent.modifierFlags.contains(.option)
    }

    private func installModifierFlagsMonitor() {
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)
        guard modifierFlagsMonitor == nil else {
            return
        }
        modifierFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func removeModifierFlagsMonitor() {
        guard let modifierFlagsMonitor else {
            return
        }
        NSEvent.removeMonitor(modifierFlagsMonitor)
        self.modifierFlagsMonitor = nil
        isOptionKeyPressed = false
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

    private var isPurchaseRequired: Bool {
        guard model.credential != nil,
              model.downloadState.phase == .failed else {
            return false
        }
        return model.activeIssue == .minecraftNotOwned
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

    private var updateVersionTransition: (installed: String, latest: String)? {
        guard shouldUseBedrockIcon,
              isMinecraftUpdateAvailable,
              let installed = currentInstalledVersionForUpdate,
              let latest = model.latestVersion else {
            return nil
        }
        return (installed.versionName, latest.versionName)
    }

    private var currentInstalledVersionForUpdate: InstalledVersion? {
        if let selected = model.selectedVersion {
            return selected
        }
        return model.installedVersions.max { lhs, rhs in
            lhs.installedAt < rhs.installedAt
        }
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

    private var shouldShowRuntimeTitle: Bool {
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

    private var isRuntimeUpdateWork: Bool {
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

    private var statusColor: Color {
        if model.isBlockingNetworkUnavailable {
            return .red
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
        model.activeIssue == .bundledHelperMissing
    }

    private func centerErrorText(for error: String) -> String {
        if let centerText = model.activeIssue?.centerText {
            return centerText
        }
        return error
    }

    private func shortErrorText(for error: String) -> String {
        if model.isBlockingNetworkUnavailable {
            return "No internet connection"
        }
        if let shortText = model.activeIssue?.shortText {
            return shortText
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
        case .preparingFirstLaunch:
            return "Preparing first launch"
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
