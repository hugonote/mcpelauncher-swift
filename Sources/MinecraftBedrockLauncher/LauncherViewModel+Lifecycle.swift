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
        await continueStartupAfterInitialLoad(installsAutomaticGameUpdates: true)
    }

    func continueStartupForQuickLaunch() async {
        await continueStartupAfterInitialLoad(installsAutomaticGameUpdates: false)
    }

    private func continueStartupAfterInitialLoad(installsAutomaticGameUpdates: Bool) async {
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
        await runAutomaticGameUpdateCheck(installsAutomaticGameUpdates: installsAutomaticGameUpdates)
    }

    private func runAutomaticGameUpdateCheck(installsAutomaticGameUpdates: Bool) async {
        await Task { @MainActor in
            await fetchLatest()
            if LauncherPreferences.canAutomaticallyInstallGameUpdates {
                guard installsAutomaticGameUpdates else {
                    return
                }
                _ = await installAutomaticGameUpdateIfNeeded()
            }
        }.value
    }

    func beginQuickLaunch() {
        quickLaunchState = .starting
    }

    func finishQuickLaunch() {
        quickLaunchState = .inactive
        quickLaunchTask = nil
    }

    func cancelQuickLaunch() {
        quickLaunchState = .inactive
        quickLaunchTask?.cancel()
        quickLaunchTask = nil
    }

    func startQuickLaunchSession() {
        guard isQuickLaunchActive, quickLaunchTask == nil else {
            return
        }
        quickLaunchTask = Task { @MainActor [weak self] in
            await self?.runQuickLaunchSession()
        }
    }

    private func setQuickLaunchState(_ state: QuickLaunchState) {
        guard isQuickLaunchActive else {
            return
        }
        quickLaunchState = state
    }

    private func runQuickLaunchSession() async {
        defer {
            if quickLaunchTask != nil, quickLaunchState != .inactive {
                quickLaunchTask = nil
            }
        }

        guard await waitForQuickLaunchPreconditions(requiresRuntimeReady: false) else {
            return
        }

        await continueStartupForQuickLaunch()
        guard await waitForQuickLaunchPreconditions(requiresRuntimeReady: true) else {
            return
        }

        if AppUpdateConfiguration.isEnabled && LauncherPreferences.automaticallyCheckLauncherUpdates {
            setQuickLaunchState(.waitingForLauncherUpdate)
            guard await waitForLauncherUpdateCheckBeforeQuickLaunch() else {
                cancelQuickLaunch()
                return
            }
        }

        setQuickLaunchState(.waitingForGameUpdate)
        guard await installAutomaticGameUpdateIfNeeded() else {
            cancelQuickLaunch()
            return
        }

        guard await waitForQuickLaunchPreconditions(requiresRuntimeReady: true) else {
            return
        }
        guard canQuickLaunchSelectedVersion else {
            finishQuickLaunch()
            return
        }

        setQuickLaunchState(.launching)
        await playSelected(captureLog: false)
        if isQuickLaunchActive {
            finishQuickLaunch()
        }
    }

    private func waitForQuickLaunchPreconditions(requiresRuntimeReady: Bool) async -> Bool {
        while isQuickLaunchActive {
            if Task.isCancelled {
                return false
            }
            if StartupLaunchModifiers.isOptionPressed {
                cancelQuickLaunch()
                return false
            }
            if ContentImportOpenFileQueue.shared.hasPendingURLs || isImportingContent {
                cancelQuickLaunch()
                return false
            }
            if credentialAccessDenied || credential == nil || selectedVersion == nil {
                finishQuickLaunch()
                return false
            }
            if isCheckingLauncherUpdates {
                setQuickLaunchState(.waitingForLauncherUpdate)
                await sleepBeforeQuickLaunchRetry()
                continue
            }
            if isRuntimeBusy {
                setQuickLaunchState(.waitingForRuntime)
                await sleepBeforeQuickLaunchRetry()
                continue
            }
            if requiresRuntimeReady && runtimePathForReadyRuntime() == nil {
                finishQuickLaunch()
                return false
            }
            if isGooglePlayBusy {
                setQuickLaunchState(.waitingForGameUpdate)
                await sleepBeforeQuickLaunchRetry()
                continue
            }
            setQuickLaunchState(.ready)
            return true
        }
        return false
    }

    private func sleepBeforeQuickLaunchRetry() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    func waitForLauncherUpdateCheckBeforeQuickLaunch() async -> Bool {
        isCheckingLauncherUpdates = true
        defer {
            isCheckingLauncherUpdates = false
        }
        return await LauncherUpdateCheckGate.shared.allowsQuickLaunchAfterLauncherUpdateCheck()
    }

    func load(startsAutomaticRuntimeUpdate: Bool = true) async {
        do {
            try paths.ensureDirectories()
            CompatibilityPatchManager(paths: paths, processRunner: processRunner).cleanupOldVersions()
            try? FileManager.default.removeItem(at: paths.contentImportsURL)
            try paths.removeStaleGameInstallDirectories()
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
        try paths.removeStaleGameInstallDirectories()
        try syncRuntimeClientPreferencesFromDisk()
        selectedVersion = try registry.load().first
        refreshSelectedVersionCompatibility()
        refreshInstalledRuntimeState()
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
