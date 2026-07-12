import Foundation
import MinecraftBedrockLauncherCore

extension LauncherViewModel {
    func deleteInstalledGames() async -> Bool {
        cancelActiveDownloadWork()
        do {
            isDeletingGame = true
            defer { isDeletingGame = false }
            let versionsURL = paths.versionsURL
            let downloadsURL = paths.downloadsURL
            let installedVersionsURL = paths.installedVersionsURL
            try await runOffMain {
                for url in [versionsURL, downloadsURL] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                if FileManager.default.fileExists(atPath: installedVersionsURL.path) {
                    try FileManager.default.removeItem(at: installedVersionsURL)
                }
                try FileManager.default.createDirectory(at: versionsURL, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
            }
            selectedVersion = nil
            latestVersion = nil
            googlePlayLatestVersion = nil
            downloadState = DownloadState()
            errorText = nil
            updateWarningText = nil
            return true
        } catch {
            show(error)
            return false
        }
    }

    func deleteMinecraftData() async -> Bool {
        do {
            isDeletingData = true
            defer { isDeletingData = false }
            let dataURL = paths.minecraftDataURL
            try await runOffMain {
                if FileManager.default.fileExists(atPath: dataURL.path) {
                    try FileManager.default.removeItem(at: dataURL)
                }
                try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
            }
            errorText = nil
            updateWarningText = nil
            return true
        } catch {
            show(error)
            return false
        }
    }

    func startDownloadAndInstallLatest() {
        let downloadID = UUID()
        activeDownloadID = downloadID
        activeDownloadTask?.cancel()
        activeDownloadTask = Task { [weak self] in
            _ = await self?.downloadAndInstallLatest(downloadID: downloadID)
        }
    }

    func installAutomaticGameUpdateIfNeeded() async -> Bool {
        guard LauncherPreferences.canAutomaticallyInstallGameUpdates else {
            return true
        }
        guard runtimePathForReadyRuntime() != nil else {
            return false
        }
        guard selectedVersion != nil else {
            return true
        }
        if latestVersion == nil {
            await fetchLatest()
        }
        guard let latestVersion else {
            return true
        }
        if selectedVersion?.versionCode == latestVersion.versionCode {
            return true
        }

        let downloadID = UUID()
        activeDownloadID = downloadID
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        return await downloadAndInstallLatest(downloadID: downloadID)
    }

    func cancelDownload() {
        guard downloadState.phase == .downloading else {
            return
        }
        cancelActiveDownloadWork()
        downloadState = latestVersion.map { DownloadState(versionName: $0.versionName) } ?? DownloadState()
        errorText = nil
        updateWarningText = nil
        if isQuickLaunchActive {
            cancelQuickLaunch()
        }
    }

    func cancelActiveDownloadWork() {
        let shouldTerminateChildren = activeDownloadTask != nil || activeDownloadID != nil || isGooglePlayBusy
        let outputURL = activeDownloadOutputURL
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadID = nil
        activeDownloadOutputURL = nil
        if shouldTerminateChildren {
            ChildProcessRegistry.shared.terminateAll()
        }
        downloadStallTask?.cancel()
        downloadStallTask = nil
        lastDownloadProgressEventDate = nil
        lastDownloadProgressBytes = 0
        URLCache.shared.removeAllCachedResponses()
        scheduleDownloadOutputCleanup(outputURL)
    }

    private func scheduleDownloadOutputCleanup(_ outputURL: URL?) {
        guard let outputURL else {
            return
        }

        Task.detached(priority: .utility) {
            let delays: [UInt64] = [0, 250_000_000, 1_000_000_000, 2_000_000_000]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                do {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private func downloadAndInstallLatest(downloadID: UUID) async -> Bool {
        guard await ensureRuntimeReadyForGameWork() else {
            if activeDownloadID == downloadID {
                activeDownloadID = nil
                activeDownloadOutputURL = nil
            }
            return false
        }
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            try ensureAvailableDiskSpace(minimumBytes: 3_000_000_000)
            guard let credential = try loadStoredCredentialIfNeeded() else {
                throw LauncherError.missingCredential
            }
            let downloadable: LatestVersion
            if let knownVersion = latestVersion {
                downloadable = try await downloadableVersion(for: knownVersion)
            } else {
                downloadState = DownloadState(phase: .fetchingLatest)
                let resolution = try await resolveDownloadableVersion(credential: credential)
                applyVersionResolution(resolution)
                downloadable = resolution.downloadable
            }
            latestVersion = downloadable

            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.02,
                phase: .downloading,
                detail: "Starting download"
            )
            lastDownloadProgressUpdate = nil
            lastDownloadProgressEventDate = Date()
            lastDownloadProgressBytes = 0
            startDownloadStallWatch(versionName: downloadable.versionName)
            let outputURL = paths.downloadsURL.appendingPathComponent(String(downloadable.versionCode), isDirectory: true)
            activeDownloadOutputURL = outputURL
            let downloadCoordinator = makeMinecraftDownloadCoordinator()
            let downloadProgress: @Sendable (DownloadProgress) -> Void = { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress, versionName: downloadable.versionName, downloadID: downloadID)
                }
            }
            let response = try await downloadCoordinator.download(
                downloadable,
                credential: credential,
                outputDirectory: outputURL,
                progress: downloadProgress
            )
            guard activeDownloadID == downloadID, !Task.isCancelled else {
                return false
            }
            downloadStallTask?.cancel()
            downloadStallTask = nil
            lastDownloadProgressEventDate = nil
            lastDownloadProgressBytes = 0

            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.86,
                phase: .extracting,
                detail: "Extracting APK files"
            )
            let versionsURL = paths.versionsURL
            let extractProgress: @Sendable (Double) -> Void = { [weak self] progress in
                Task { @MainActor in
                    self?.updateExtractionProgress(progress, versionName: downloadable.versionName)
                }
            }
            let installed = try await downloadCoordinator.install(
                downloadedAPKs: response.files,
                latestVersion: downloadable,
                versionsDirectory: versionsURL,
                progress: extractProgress
            )
            guard activeDownloadID == downloadID, !Task.isCancelled else {
                return false
            }
            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.98,
                phase: .extracting,
                detail: "Preparing first launch"
            )
            let patchPath = try await compatibilityPatchPath(for: installed)
            try applyCompatibilityLibraryPatches(to: installed, patchPath: patchPath)
            guard let runtimePath = runtimePathForReadyRuntime() else {
                return false
            }
            let credentialsHelperDirectory = credentialsHelperURL().deletingLastPathComponent()
            let dataPath = paths.minecraftDataURL
            let cachePath = dataPath
            try applyRuntimeClientPreferences(dataPath: dataPath)
            try? FileManager.default.removeItem(at: firstLaunchTokenURL(dataPath: dataPath))
            try await prepareFirstLaunchUntilReady(
                launcher: RuntimeLauncher(),
                runtimePath: runtimePath,
                version: installed,
                patchPath: patchPath,
                dataPath: dataPath,
                cachePath: cachePath,
                credentialsHelperDirectory: credentialsHelperDirectory,
                googleCredential: credential,
                detail: "Preparing first launch",
                captureLog: false
            )
            try removeObsoleteMinecraftFiles(keeping: installed)
            try registry.save([installed])
            selectedVersion = installed
            refreshSelectedVersionCompatibility()
            activeDownloadID = nil
            activeDownloadOutputURL = nil
            downloadState = DownloadState(versionName: downloadable.versionName, progress: 1, phase: .installed)
            lastDownloadProgressEventDate = nil
            lastDownloadProgressBytes = 0
            errorText = nil
            updateWarningText = nil
            return true
        } catch is CancellationError {
            guard activeDownloadID == downloadID else {
                return false
            }
            let outputURL = activeDownloadOutputURL
            activeDownloadID = nil
            activeDownloadOutputURL = nil
            downloadStallTask?.cancel()
            downloadStallTask = nil
            lastDownloadProgressEventDate = nil
            lastDownloadProgressBytes = 0
            downloadState = latestVersion.map { DownloadState(versionName: $0.versionName) } ?? DownloadState()
            errorText = nil
            updateWarningText = nil
            scheduleDownloadOutputCleanup(outputURL)
            return false
        } catch {
            guard activeDownloadID == downloadID else {
                return false
            }
            activeDownloadID = nil
            activeDownloadOutputURL = nil
            downloadStallTask?.cancel()
            downloadStallTask = nil
            lastDownloadProgressEventDate = nil
            lastDownloadProgressBytes = 0
            downloadState = DownloadState(phase: .failed, error: error.localizedDescription)
            show(error)
            return false
        }
    }

    private func updateDownloadProgress(_ progress: DownloadProgress, versionName: String, downloadID: UUID) {
        guard activeDownloadID == downloadID,
              downloadState.phase != .failed else {
            return
        }
        if progress.bytesReceived > lastDownloadProgressBytes {
            lastDownloadProgressBytes = progress.bytesReceived
            lastDownloadProgressEventDate = Date()
        }
        guard shouldPublishDownloadProgress(progress) else {
            return
        }
        let fraction = progress.fractionCompleted
        let progressValue = fraction > 0 ? min(max(fraction, 0.02), 1) : downloadState.progress
        var detail = "Downloading"
        if let component = progress.component, !component.isEmpty {
            detail += " \(component)"
        }
        if let index = progress.componentIndex, let count = progress.componentCount, count > 1 {
            detail += " (\(index)/\(count))"
        }
        downloadState = DownloadState(
            versionName: versionName,
            progress: progressValue,
            phase: .downloading,
            detail: detail,
            bytesReceived: progress.bytesReceived,
            totalBytes: progress.totalBytes,
            speedBytesPerSecond: progress.speedBytesPerSecond,
            etaSeconds: progress.etaSeconds
        )
    }

    private func shouldPublishDownloadProgress(_ progress: DownloadProgress) -> Bool {
        shouldPublishProgress(
            bytesReceived: progress.bytesReceived,
            totalBytes: progress.totalBytes,
            lastUpdate: &lastDownloadProgressUpdate
        )
    }

    func shouldPublishProgress(
        bytesReceived: Int64,
        totalBytes: Int64?,
        lastUpdate: inout Date?
    ) -> Bool {
        let now = Date()
        let isFinished = totalBytes.map { $0 > 0 && bytesReceived >= $0 } ?? false
        guard !isFinished else {
            lastUpdate = now
            return true
        }
        guard let previous = lastUpdate else {
            lastUpdate = now
            return true
        }
        guard now.timeIntervalSince(previous) >= 1 else {
            return false
        }
        lastUpdate = now
        return true
    }

    private func updateExtractionProgress(_ progress: Double, versionName: String) {
        let clamped = min(max(progress, 0), 1)
        downloadState = DownloadState(
            versionName: versionName,
            progress: clamped,
            phase: .extracting,
            detail: "Extracting APK files"
        )
    }

    private func startDownloadStallWatch(versionName: String) {
        downloadStallTask?.cancel()
        downloadStallTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self,
                      self.downloadState.phase == .downloading,
                      self.downloadState.versionName == versionName else {
                    break
                }

                let bytesReceived = self.downloadState.bytesReceived ?? 0
                let lastProgressDate = self.lastDownloadProgressEventDate ?? Date()
                let timeout: TimeInterval = bytesReceived > 0 ? 30 : 10
                guard Date().timeIntervalSince(lastProgressDate) >= timeout else {
                    continue
                }

                let message = bytesReceived > 0
                    ? "Download stalled. Check your connection and try again."
                    : "Download did not start. Check your connection and try again."
                self.activeDownloadID = nil
                self.activeDownloadTask?.cancel()
                self.activeDownloadTask = nil
                ChildProcessRegistry.shared.terminateAll()
                self.lastDownloadProgressEventDate = nil
                self.lastDownloadProgressBytes = 0
                self.downloadState = DownloadState(
                    versionName: versionName,
                    phase: .failed,
                    error: message
                )
                self.reduceError(.fail(
                    message: message,
                    issue: bytesReceived > 0 ? .downloadStalled : .downloadDidNotStart,
                    blocksNetworkUnavailable: false
                ))
                self.updateWarningText = nil
                break
            }
        }
    }

    private func ensureAvailableDiskSpace(minimumBytes: Int64) throws {
        let values = try paths.baseURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        guard available >= minimumBytes else {
            throw LauncherError.insufficientDiskSpace(requiredBytes: minimumBytes, availableBytes: available)
        }
    }

    private func removeObsoleteMinecraftFiles(keeping installed: InstalledVersion) throws {
        let fileManager = FileManager.default
        let currentInstallPath = installed.installPath.standardizedFileURL.path

        let existingVersions = try registry.load()
        for version in existingVersions {
            let path = version.installPath.standardizedFileURL.path
            guard path != currentInstallPath, fileManager.fileExists(atPath: path) else {
                continue
            }
            try fileManager.removeItem(at: version.installPath)
        }

        if fileManager.fileExists(atPath: paths.versionsURL.path) {
            let versionDirectories = try fileManager.contentsOfDirectory(
                at: paths.versionsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for directory in versionDirectories {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true,
                      directory.standardizedFileURL.path != currentInstallPath,
                      !directory.lastPathComponent.hasPrefix(".install-") else {
                    continue
                }
                try fileManager.removeItem(at: directory)
            }
        }

        if fileManager.fileExists(atPath: paths.downloadsURL.path) {
            let downloadItems = try fileManager.contentsOfDirectory(
                at: paths.downloadsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for item in downloadItems {
                try fileManager.removeItem(at: item)
            }
        }
    }
}
