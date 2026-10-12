import Foundation
import MinecraftBedrockLauncherCore
import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: LauncherViewModel
    @ObservedObject var appDelegate: AppDelegate
    @State var isShowingVersionInfo = false
    @State var isShowingErrorDetails = false
    @State var didCopyError = false
    @State var isStartupComplete = false
    @State var isTitleIconVisible = false
    @State var window: NSWindow?
    @State var pendingQuickLaunch = false
    @State var isShowingContentImporter = false
    @State var contentImportConfirmation = ContentImportConfirmation()
    @State var pendingRuntimeVersion: String?
    @State var isShowingRuntimeVersionWarning = false
    @State var contentImportDropPreview: ContentImportDropPreview?
    @State var contentImportResultTitle = ""
    @State var contentImportResultMessage = ""
    @State var isShowingContentImportResult = false
    @State var isProcessingQueuedContentImport = false
    @Environment(\.openSettings) var openSettings
    @Environment(\.accessibilityReduceMotion) var reduceMotion

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
                if !shouldHideChrome && !isContentDropTargeted {
                    VStack(spacing: 6) {
                        if model.isQuickLaunchActive {
                            quickLaunchHint
                        }
                        utilityBar
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, bottomContentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !shouldHideChrome && !isContentDropTargeted {
                VStack {
                    accountBar
                    Spacer()
                }
                .padding(.top, 2)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .ignoresSafeArea(.container, edges: .top)
                .transition(.opacity)
            }
        }
        .animation(contentDropStateAnimation, value: isContentDropTargeted)
        .background(contentImportDropTarget)
        .background(contentImportDialogs)
        .background(runtimeVersionWarning)
        .sheet(isPresented: $model.showingLogin) {
            GoogleLoginSheet(model: model)
        }
        .alert("Sign out?", isPresented: $model.showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                model.signOut()
            }
        } message: {
            Text("You will need to sign in again before downloading Minecraft updates.")
        }
        .alert(contentImportResultTitle, isPresented: $isShowingContentImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(contentImportResultMessage)
        }
        .background {
            Color.clear
                .alert("Minecraft is already running.", isPresented: $model.isShowingRunningGameWarning) {
                    Button("Cancel", role: .cancel) {
                        model.cancelRunningGameWarning()
                    }
                    Button("Launch Anyway", role: .destructive) {
                        Task { await model.launchAnywayAfterRunningGameWarning() }
                    }
                } message: {
                    Text("""
                    Launching another copy will use the same worlds, settings, and cache. This can corrupt saved data or leave Minecraft in an inconsistent state.

                    Continue only if you know why you need another copy.
                    """)
                }
                .dialogSeverity(.critical)
        }
        .background(WindowConfigurator(window: $window))
        .background(
            QuickLaunchOptionMonitor(isActive: model.isQuickLaunchActive) {
                model.cancelQuickLaunch()
            }
        )
        .background(touchBarConfigurator)
        .onChange(of: model.downloadState) { _, _ in
            updateDockProgress()
        }
        .onChange(of: model.runtimeState) { _, _ in
            updateDockProgress()
        }
        .onChange(of: isContentDropTargeted) { _, isTargeted in
            if isTargeted {
                isShowingContentImportResult = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ContentImportOpenFileQueue.filesOpenedNotification)) { _ in
            cancelQuickLaunchForContentImportIfNeeded()
            revealLauncherForContentImportIfNeeded()
            importQueuedContentFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: ContentImportOpenFileQueue.openPanelRequestedNotification)) { _ in
            presentContentImportPanel()
        }
        .onDisappear {
            contentImportConfirmation.resolve(false)
            DockProgressController.shared.clear()
        }
        .task(id: appDelegate.isInitialStartupComplete) {
            guard appDelegate.isInitialStartupComplete else {
                return
            }
            if hasQueuedOrActiveContentImport {
                revealLauncherForContentImportIfNeeded()
                await Task.yield()
            }
            if shouldUseQuickLaunch,
               model.credentialAccessDenied,
               model.selectedVersion != nil || LauncherPreferences.canAutomaticallyInstallGameUpdates {
                pendingQuickLaunch = true
            }
            isStartupComplete = true
            if hasQueuedOrActiveContentImport {
                cancelQuickLaunchForContentImportIfNeeded()
            }
            importQueuedContentFiles()
            await Task.yield()
            if model.isQuickLaunchActive {
                guard !StartupLaunchModifiers.isOptionPressed else {
                    model.cancelQuickLaunch()
                    return
                }
                model.startQuickLaunchSession()
            } else {
                await model.continueStartupAfterWindowReveal()
            }
        }
    }

    var shouldUseQuickLaunch: Bool {
        LauncherPreferences.quickLaunch
            && !StartupLaunchModifiers.didHoldOption
            && !hasQueuedOrActiveContentImport
    }

    var hasQueuedOrActiveContentImport: Bool {
        ContentImportOpenFileQueue.shared.hasPendingURLs
            || isProcessingQueuedContentImport
            || model.isImportingContent
    }

    func cancelQuickLaunchForContentImportIfNeeded() {
        guard pendingQuickLaunch || model.isQuickLaunchActive else {
            return
        }
        pendingQuickLaunch = false
        model.cancelQuickLaunch()
    }

    func revealLauncherForContentImportIfNeeded() {
        guard hasQueuedOrActiveContentImport || isProcessingQueuedContentImport else {
            return
        }
        isStartupComplete = true
        revealLauncherWindow()
    }

    func revealLauncherWindow() {
        if let window {
            StartupWindowVisibility.shared.reveal(window)
        } else {
            StartupWindowVisibility.shared.revealLauncherWindow()
        }
    }

    private func updateDockProgress() {
        DockProgressController.shared.update(downloadState: model.downloadState, runtimeState: model.runtimeState)
    }

    private func revealLauncherAfterFailedQuickLaunchIfNeeded() {
        guard model.isShowingRunningGameWarning
            || model.errorText != nil
            || model.downloadState.phase == .failed
            || model.runtimeState.phase == .failed else {
            return
        }
        isStartupComplete = true
        StartupWindowVisibility.shared.revealLauncherWindow()
    }

    func playTitleIconEntranceIfNeeded() {
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

    var shouldHideChrome: Bool {
        model.credentialAccessDenied || isShowingCorruptedAppError
    }

    var isShowingCorruptedAppError: Bool {
        model.activeIssue == .bundledHelperMissing
    }

    var bottomContentPadding: CGFloat {
        if shouldHideChrome {
            return 20
        }
        if model.isQuickLaunchActive {
            return 4
        }
        if model.isBlockingNetworkUnavailable {
            return 12
        }
        return 28
    }
}
