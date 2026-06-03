import Foundation
import MinecraftBedrockLauncherCore

extension LauncherViewModel {
    func start() async {
        guard !didStart else {
            return
        }
        didStart = true
        await load(startsAutomaticRuntimeUpdate: false)
        await loadStoredCredential()
    }

    func continueStartupAfterWindowReveal() async {
        await continueStartupAfterInitialLoad()
    }

    func continueStartupForQuickLaunch() async {
        await continueStartupAfterInitialLoad()
    }

    private func continueStartupAfterInitialLoad() async {
        guard didStart, !didContinueStartupAfterWindowReveal else {
            return
        }

        guard !credentialAccessDenied else {
            return
        }
        didContinueStartupAfterWindowReveal = true

        if LauncherPreferences.automaticallyCheckRuntimeUpdates {
            startAutomaticRuntimeUpdate()
            let updateTask = runtimeUpdateTask
            await updateTask?.value
        }
        guard runtimePathForReadyRuntime() != nil else {
            return
        }
        guard credential != nil else {
            return
        }
        guard LauncherPreferences.canAutomaticallyCheckGameUpdates else {
            return
        }
        guard shouldRunAutomaticGameUpdateCheck() else {
            return
        }
        await runAutomaticGameUpdateCheck()
    }

    private func runAutomaticGameUpdateCheck() async {
        await Task { @MainActor in
            await fetchLatest()
            if LauncherPreferences.canAutomaticallyInstallGameUpdates {
                _ = await installAutomaticGameUpdateIfNeeded()
            }
        }.value
    }

    func beginQuickLaunch() {
        isQuickLaunchActive = true
    }

    func finishQuickLaunch() {
        isQuickLaunchActive = false
    }

    func load(startsAutomaticRuntimeUpdate: Bool = true) async {
        do {
            try paths.ensureDirectories()
            signOutLegacyCredentialIfNeeded()
            try paths.removeLegacyGooglePlayState()
            try syncRuntimeClientPreferencesFromDisk()
            selectedVersion = try registry.load().first
            refreshSelectedVersionCompatibility()
            refreshInstalledRuntimeState()
            if startsAutomaticRuntimeUpdate && LauncherPreferences.automaticallyCheckRuntimeUpdates {
                startAutomaticRuntimeUpdate()
            }
        } catch {
            show(error)
        }
    }

    func preloadLocalStateForInitialLayout() throws {
        try paths.ensureDirectories()
        try syncRuntimeClientPreferencesFromDisk()
        selectedVersion = try registry.load().first
        refreshSelectedVersionCompatibility()
        refreshInstalledRuntimeState()
    }

    func preloadStoredCredentialForInitialLayout() {
        do {
            didTryLoadingStoredCredential = true
            credential = try credentialStore.loadCredential()
        } catch {
            didTryLoadingStoredCredential = false
        }
    }

    func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.retryBlockingNetworkUnavailableIfNeeded()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func retryBlockingNetworkUnavailableIfNeeded() async {
        guard isBlockingNetworkUnavailable,
              !isGooglePlayBusy,
              !isRuntimeBusy else {
            return
        }

        isBlockingNetworkUnavailable = false
        errorText = nil
        updateWarningText = nil

        if selectedVersion == nil {
            guard credential != nil else {
                return
            }
            if !isRuntimeReady {
                startRuntimeInstall()
                return
            }
            startDownloadAndInstallLatest()
            return
        }

        if !isRuntimeReady {
            startRuntimeInstall()
            return
        }

        await fetchLatest()
    }

    func displayEmail(for email: String) -> String {
        guard Self.isScreenshotModeEnabled else {
            return email
        }
        return ProcessInfo.processInfo.environment["SCREENSHOT_EMAIL"]?.isEmpty == false
            ? ProcessInfo.processInfo.environment["SCREENSHOT_EMAIL"]!
            : "demo@example.com"
    }

    static var isScreenshotModeEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SCREENSHOT_MODE"] == "1"
            || environment["MCPELAUNCHER_SCREENSHOT_MODE"] == "1"
    }
}
