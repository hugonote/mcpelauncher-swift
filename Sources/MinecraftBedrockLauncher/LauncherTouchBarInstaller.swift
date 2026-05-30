import AppKit
import SwiftUI

@MainActor
struct LauncherTouchBarInstaller: View {
    @ObservedObject var model: LauncherViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        LauncherTouchBarConfigurator(
            configuration: LauncherTouchBarConfiguration(
                state: LauncherTouchBarState(model: model),
                onPrimary: performPrimaryAction,
                onSignIn: showLogin,
                onCancel: cancelActiveWork,
                onSettings: { openSettings() },
                onOpenDataFolder: openDataFolder
            )
        )
    }

    private func performPrimaryAction() {
        if model.credentialAccessDenied {
            Task { @MainActor in
                await model.retryStoredCredentialAccess()
            }
            return
        }

        Task { @MainActor in
            await runPrimaryAction()
        }
    }

    private func runPrimaryAction() async {
        if LauncherTouchBarRules.needsCredentialRefresh(model) {
            model.signOut()
            model.showingLogin = true
            return
        }
        if LauncherTouchBarRules.isPurchaseRequired(model) {
            model.signOut()
            model.showingLogin = true
            return
        }
        if LauncherTouchBarRules.shouldFocusRuntime(model) {
            model.startRuntimeInstall()
            return
        }
        if LauncherTouchBarRules.isMinecraftUpdateAvailable(model) {
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

    private func cancelActiveWork() {
        if model.runtimeState.phase == .downloading {
            model.cancelRuntimeDownload()
            return
        }
        if model.downloadState.phase == .downloading {
            model.cancelDownload()
        }
    }

    private func showLogin() {
        model.showingLogin = true
    }

    private func openDataFolder() {
        NSWorkspace.shared.open(model.dataFolderURL)
    }
}
