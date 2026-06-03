import Foundation
import MinecraftBedrockLauncherCore
import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: LauncherViewModel
    @State var isShowingSignOutConfirmation = false
    @State var isShowingVersionInfo = false
    @State var isStartupComplete = false
    @State var isTitleIconVisible = false
    @State private var isPresentingRunningGameWarning = false
    @State var window: NSWindow?
    @State var pendingQuickLaunch = false
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
                if !shouldHideChrome {
                    if model.isQuickLaunchActive {
                        quickLaunchHint
                    }
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
        .background(
            QuickLaunchOptionMonitor(isActive: model.isQuickLaunchActive) {
                model.finishQuickLaunch()
            }
        )
        .background(touchBarConfigurator)
        .onChange(of: model.downloadState) { _, _ in
            updateDockProgress()
        }
        .onChange(of: model.runtimeState) { _, _ in
            updateDockProgress()
        }
        .onChange(of: model.isShowingRunningGameWarning) { _, isShowing in
            if isShowing {
                presentRunningGameWarning()
            }
        }
        .onDisappear {
            DockProgressController.shared.clear()
        }
        .task(id: window != nil) {
            guard let window else {
                return
            }
            let shouldUseQuickLaunch = LauncherPreferences.quickLaunch && !StartupLaunchModifiers.didHoldOption
            await model.start()
            if shouldUseQuickLaunch && model.credentialAccessDenied && model.selectedVersion != nil {
                pendingQuickLaunch = true
            }
            if shouldUseQuickLaunch && model.canStartQuickLaunch {
                model.beginQuickLaunch()
            }
            isStartupComplete = true
            StartupWindowVisibility.shared.reveal(window)
            await Task.yield()
            if model.isQuickLaunchActive {
                guard !StartupLaunchModifiers.isOptionPressed else {
                    model.finishQuickLaunch()
                    return
                }
                await model.continueStartupForQuickLaunch()
                await runQuickLaunchIfReady()
            } else {
                await model.continueStartupAfterWindowReveal()
            }
        }
    }

    func runQuickLaunchIfReady() async {
        await Task.yield()
        guard model.isQuickLaunchActive,
              model.canStartQuickLaunch,
              model.isRuntimeReady,
              !StartupLaunchModifiers.isOptionPressed else {
            model.finishQuickLaunch()
            return
        }

        guard await model.installAutomaticGameUpdateIfNeeded() else {
            model.finishQuickLaunch()
            revealLauncherAfterFailedQuickLaunchIfNeeded()
            return
        }

        await Task.yield()
        guard model.isQuickLaunchActive,
              model.canQuickLaunchSelectedVersion,
              !StartupLaunchModifiers.isOptionPressed else {
            model.finishQuickLaunch()
            return
        }

        await model.playSelected(captureLog: false)
        if model.isQuickLaunchActive {
            model.finishQuickLaunch()
        }
        revealLauncherAfterFailedQuickLaunchIfNeeded()
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

    private func presentRunningGameWarning() {
        guard !isPresentingRunningGameWarning else {
            return
        }
        isPresentingRunningGameWarning = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = Self.cautionIcon
        alert.messageText = "Minecraft is already running"
        alert.informativeText = """
        Launching another copy will use the same worlds, settings, and cache. This can corrupt saved data or leave Minecraft in an inconsistent state.

        Continue only if you know why you need another copy.
        """
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\r"
        let launchButton = alert.addButton(withTitle: "Launch Anyway")
        launchButton.keyEquivalent = ""
        launchButton.hasDestructiveAction = true

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            isPresentingRunningGameWarning = false
            if response == .alertSecondButtonReturn {
                Task { await model.launchAnywayAfterRunningGameWarning() }
            } else {
                model.cancelRunningGameWarning()
            }
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
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
            return 10
        }
        if model.isBlockingNetworkUnavailable {
            return 12
        }
        return 28
    }

    private static let cautionIcon: NSImage = {
        let size = NSSize(width: 64, height: 64)
        guard let source = NSImage(named: NSImage.cautionName) else {
            return NSImage(size: size)
        }
        source.size = size
        let baked = NSImage(size: size)
        baked.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size))
        baked.unlockFocus()
        return baked
    }()
}
