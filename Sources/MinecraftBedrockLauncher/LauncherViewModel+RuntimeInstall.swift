import Foundation
import MinecraftBedrockLauncherCore

extension LauncherViewModel {
    func deleteRuntime() async -> Bool {
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = nil
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        activeRuntimeUpdateID = nil
        canSkipRuntimeUpdateCheck = false
        do {
            isDeletingRuntime = true
            defer { isDeletingRuntime = false }
            let runtimeURL = paths.runtimeURL
            try await runOffMain {
                if FileManager.default.fileExists(atPath: runtimeURL.path) {
                    try FileManager.default.removeItem(at: runtimeURL)
                }
                try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
            }
            runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
            errorText = nil
            updateWarningText = nil
            return true
        } catch {
            show(error)
            return false
        }
    }

    func startRuntimeInstall() {
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = Task { [weak self] in
            _ = await self?.ensureRuntimeForUse()
        }
    }

    func startAutomaticRuntimeUpdate() {
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = Task { [weak self] in
            await self?.updateRuntimeIfNeeded()
        }
    }

    func refreshRuntimeReleases() async {
        guard !didLoadRuntimeReleases, !isLoadingRuntimeReleases else {
            return
        }
        isLoadingRuntimeReleases = true
        defer { isLoadingRuntimeReleases = false }
        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        guard let releases = try? await RuntimeInstallCoordinator(manager: manager).availableReleases() else {
            return
        }
        availableRuntimeReleases = releases
        didLoadRuntimeReleases = true
    }

    func selectRuntimeVersion(_ version: String?) {
        guard version != LauncherPreferences.runtimeVersion else {
            return
        }
        LauncherPreferences.runtimeVersion = version
        Task { [weak self] in
            guard let self, await deleteRuntime() else {
                return
            }
            startAutomaticRuntimeUpdate()
        }
    }

    func cancelRuntimeDownload() {
        guard runtimeState.phase == .downloading else {
            return
        }
        activeRuntimeUpdateID = nil
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = nil
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        canSkipRuntimeUpdateCheck = false
        lastRuntimeProgressUpdate = nil

        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(
            requiredVersion: LauncherPreferences.runtimeVersion,
            fallbackDetail: "Using installed runtime; runtime download canceled."
        ) {
            runtimeState = state
        } else {
            runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
        }
        errorText = nil
        updateWarningText = nil
    }

    func skipRuntimeUpdateCheck() {
        guard canSkipRuntimeUpdateCheck else {
            return
        }
        activeRuntimeUpdateID = nil
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = nil
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        canSkipRuntimeUpdateCheck = false
        if credential != nil && LauncherPreferences.canAutomaticallyCheckGameUpdates {
            shouldSkipNextAutomaticGameUpdateCheck = true
        }
        skipActiveGameUpdateCheckForRuntimeSkip()

        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(
            requiredVersion: LauncherPreferences.runtimeVersion,
            fallbackDetail: "Using installed runtime; update skipped."
        ) {
            errorText = nil
            runtimeState = state
            return
        }
        runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
    }

    func refreshInstalledRuntimeState() {
        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(
            requiredVersion: LauncherPreferences.runtimeVersion,
            fallbackDetail: "Using installed runtime."
        ) {
            runtimeState = state
        } else {
            runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
        }
    }

    private func updateRuntimeIfNeeded() async {
        if let override = runtimeOverrideURL() {
            canSkipRuntimeUpdateCheck = false
            runtimeState = RuntimeState(phase: .ready, version: "override", detail: override.path)
            return
        }

        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        let hasRuntime = manager.hasInstalledRuntime(version: LauncherPreferences.runtimeVersion)
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(
            requiredVersion: LauncherPreferences.runtimeVersion,
            fallbackDetail: "Using installed runtime."
        ) {
            runtimeState = state
        } else {
            runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
        }

        await installRuntime(
            forceStatus: hasRuntime ? "Checking for updates" : "Downloading runtime",
            phase: hasRuntime ? .checking : .downloading,
            allowsSkip: hasRuntime
        )
    }

    func ensureRuntimeForUse() async -> URL? {
        if let ready = runtimePathForReadyRuntime() {
            return ready
        }
        await installRuntime(forceStatus: "Downloading runtime", phase: .downloading)
        return runtimePathForReadyRuntime()
    }

    private func installRuntime(
        forceStatus: String,
        phase: RuntimePhase,
        allowsSkip: Bool = false
    ) async {
        guard canDownloadRuntime else {
            return
        }
        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        let updateID = UUID()
        activeRuntimeUpdateID = updateID
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        canSkipRuntimeUpdateCheck = false
        lastRuntimeProgressUpdate = nil
        reduceError(.clear)
        updateWarningText = nil
        runtimeState = RuntimeState(phase: phase, version: runtimeState.version, detail: forceStatus)
        if allowsSkip {
            runtimeSkipDelayTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                guard self?.activeRuntimeUpdateID == updateID,
                      self?.runtimeState.phase == .checking else {
                    return
                }
                self?.canSkipRuntimeUpdateCheck = true
            }
        }
        do {
            let release = try await coordinator.resolveRelease(version: LauncherPreferences.runtimeVersion)
            try Task.checkCancellation()
            if allowsSkip {
                canSkipRuntimeUpdateCheck = false
            }
            let metadata = try await coordinator.install(release, progress: runtimeDownloadProgress)
            guard activeRuntimeUpdateID == updateID, !Task.isCancelled else {
                return
            }
            refreshSelectedVersionCompatibility()
            runtimeSkipDelayTask?.cancel()
            runtimeSkipDelayTask = nil
            canSkipRuntimeUpdateCheck = false
            activeRuntimeUpdateID = nil
            updateWarningText = nil
            runtimeState = RuntimeState(phase: .ready, version: metadata.version, detail: metadata.assetName)
        } catch is CancellationError {
            guard activeRuntimeUpdateID == updateID else {
                return
            }
            canSkipRuntimeUpdateCheck = false
            runtimeSkipDelayTask?.cancel()
            runtimeSkipDelayTask = nil
            activeRuntimeUpdateID = nil
            if let state = coordinator.installedState(
                requiredVersion: LauncherPreferences.runtimeVersion,
                fallbackDetail: "Using installed runtime; update skipped."
            ) {
                errorText = nil
                runtimeState = state
            } else {
                runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
            }
        } catch {
            guard activeRuntimeUpdateID == updateID else {
                return
            }
            canSkipRuntimeUpdateCheck = false
            runtimeSkipDelayTask?.cancel()
            runtimeSkipDelayTask = nil
            activeRuntimeUpdateID = nil
            if let state = coordinator.installedState(
                requiredVersion: LauncherPreferences.runtimeVersion,
                fallbackDetail: "Using installed runtime; update check failed: \(error.localizedDescription)"
            ) {
                refreshSelectedVersionCompatibility()
                errorText = nil
                updateWarningText = "Runtime update check failed"
                runtimeState = state
                return
            }
            runtimeState = RuntimeState(phase: .failed, error: error.localizedDescription)
            show(error)
        }
    }

    private var runtimeDownloadProgress: @Sendable (DownloadProgress) -> Void {
        { [weak self] progress in
            Task { @MainActor in
                self?.updateRuntimeDownloadProgress(progress)
            }
        }
    }

    private func updateRuntimeDownloadProgress(_ progress: DownloadProgress) {
        guard shouldPublishRuntimeProgress(progress) else {
            return
        }
        canSkipRuntimeUpdateCheck = false
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        let fraction = progress.fractionCompleted
        let progressValue = fraction > 0 ? min(max(fraction, 0.02), 1) : runtimeState.progress
        let isComplete = progress.totalBytes.map { $0 > 0 && progress.bytesReceived >= $0 } ?? false
        if isComplete {
            runtimeState = RuntimeState(
                phase: .installing,
                version: runtimeState.version,
                detail: "Installing runtime",
                progress: 1,
                bytesReceived: progress.bytesReceived,
                totalBytes: progress.totalBytes,
                speedBytesPerSecond: progress.speedBytesPerSecond,
                etaSeconds: nil
            )
            return
        }
        runtimeState = RuntimeState(
            phase: .downloading,
            version: runtimeState.version,
            detail: runtimeDownloadStatusText(for: progress),
            progress: progressValue,
            bytesReceived: progress.bytesReceived,
            totalBytes: progress.totalBytes,
            speedBytesPerSecond: progress.speedBytesPerSecond,
            etaSeconds: progress.etaSeconds
        )
    }

    private func shouldPublishRuntimeProgress(_ progress: DownloadProgress) -> Bool {
        shouldPublishProgress(
            bytesReceived: progress.bytesReceived,
            totalBytes: progress.totalBytes,
            lastUpdate: &lastRuntimeProgressUpdate
        )
    }

    private func runtimeDownloadStatusText(for progress: DownloadProgress) -> String {
        guard let total = progress.totalBytes, total > 0 else {
            return "Downloading runtime"
        }
        let percent = Double(progress.bytesReceived) / Double(total) * 100
        return String(format: "Downloading runtime %.1f%%", percent)
    }

    func runtimeOverrideURL() -> URL? {
        guard let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_RUNTIME_PATH"], !override.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: override, isDirectory: true)
        return (try? RuntimeLauncher(processRunner: processRunner).runtimeExecutable(in: url)) == nil ? nil : url
    }

    func runtimePathForReadyRuntime() -> URL? {
        if let override = runtimeOverrideURL() {
            runtimeState = RuntimeState(phase: .ready, version: "override", detail: override.path)
            return override
        }

        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        guard manager.hasInstalledRuntime(version: LauncherPreferences.runtimeVersion) else {
            return nil
        }
        if runtimeState.phase != .ready {
            refreshInstalledRuntimeState()
        }
        return paths.runtimeURL
    }

    func ensureRuntimeReadyForGameWork() async -> Bool {
        if runtimePathForReadyRuntime() != nil {
            return true
        }
        if isRuntimeBusy {
            let updateTask = runtimeUpdateTask
            await updateTask?.value
            return runtimePathForReadyRuntime() != nil
        }

        startRuntimeInstall()
        let updateTask = runtimeUpdateTask
        await updateTask?.value
        return runtimePathForReadyRuntime() != nil
    }

    func cancelUnusedRuntimeUpdate() {
        guard selectedVersion == nil,
              runtimeState.phase != .installing else {
            return
        }
        activeRuntimeUpdateID = nil
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = nil
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        canSkipRuntimeUpdateCheck = false
        lastRuntimeProgressUpdate = nil
        refreshInstalledRuntimeState()
    }

    private func runtimeURL() -> URL {
        runtimeOverrideURL() ?? paths.runtimeURL
    }
}
