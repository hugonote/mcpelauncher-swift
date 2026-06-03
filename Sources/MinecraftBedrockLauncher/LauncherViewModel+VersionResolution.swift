import Foundation
import MinecraftBedrockLauncherCore

struct MinecraftVersionResolution {
    var reportedLatest: LatestVersion
    var downloadable: LatestVersion
    var googlePlayLatestVersion: LatestVersion?
    var newestSupportedVersion: SupportedMinecraftVersion?
    var usedSupportedFallback: Bool
}

struct DownloadableVersionResolution {
    var downloadable: LatestVersion
    var newestSupportedVersion: SupportedMinecraftVersion?
}

extension LauncherViewModel {
    func fetchLatest() async {
        guard runtimePathForReadyRuntime() != nil else {
            return
        }
        let checkID = beginGameUpdateCheck()
        defer {
            finishGameUpdateCheck(checkID)
        }
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            guard let credential = try loadStoredCredentialIfNeeded() else {
                throw LauncherError.missingCredential
            }
            guard isActiveGameUpdateCheck(checkID) else {
                return
            }
            downloadState = DownloadState(phase: .fetchingLatest)
            let resolution = try await resolveDownloadableVersion(credential: credential)
            guard isActiveGameUpdateCheck(checkID) else {
                return
            }
            applyVersionResolution(resolution)
            let latest = resolution.reportedLatest
            let downloadable = resolution.downloadable
            latestVersion = downloadable
            if selectedVersion == nil {
                downloadState = DownloadState(
                    versionName: downloadable.versionName,
                    phase: .fetchingLatest,
                    detail: "Checking purchase"
                )
                try await checkDownloadAccess(for: downloadable, credential: credential)
                guard isActiveGameUpdateCheck(checkID) else {
                    return
                }
            }
            downloadState = DownloadState(versionName: downloadable.versionName)
            errorText = nil
            if selectedVersion?.versionCode == downloadable.versionCode
                || downloadable.versionCode != latest.versionCode {
                refreshSelectedVersionCompatibility()
            }
        } catch {
            guard isActiveGameUpdateCheck(checkID) else {
                return
            }
            if selectedVersion != nil {
                downloadState = DownloadState()
                updateWarningText = "Update check failed"
            } else {
                downloadState = DownloadState(phase: .failed, error: error.localizedDescription)
                show(error)
            }
        }
    }

    func refreshVersionInfo() async {
        if !isRuntimeBusy {
            startAutomaticRuntimeUpdate()
        }
        let updateTask = runtimeUpdateTask
        await updateTask?.value
        guard credential != nil else {
            return
        }
        await fetchLatest()
    }

    private func beginGameUpdateCheck() -> UUID {
        let checkID = UUID()
        activeGameUpdateCheckID = checkID
        return checkID
    }

    private func finishGameUpdateCheck(_ checkID: UUID) {
        if activeGameUpdateCheckID == checkID {
            activeGameUpdateCheckID = nil
        }
    }

    private func isActiveGameUpdateCheck(_ checkID: UUID) -> Bool {
        activeGameUpdateCheckID == checkID && !Task.isCancelled
    }

    func shouldRunAutomaticGameUpdateCheck() -> Bool {
        guard shouldSkipNextAutomaticGameUpdateCheck else {
            return true
        }
        shouldSkipNextAutomaticGameUpdateCheck = false
        return false
    }

    func skipActiveGameUpdateCheckForRuntimeSkip() {
        guard activeGameUpdateCheckID != nil else {
            return
        }
        activeGameUpdateCheckID = nil
        if downloadState.phase == .fetchingLatest {
            downloadState = latestVersion.map { DownloadState(versionName: $0.versionName) } ?? DownloadState()
        }
    }

    func applyVersionResolution(_ resolution: MinecraftVersionResolution) {
        googlePlayLatestVersion = resolution.googlePlayLatestVersion
        newestSupportedVersion = resolution.newestSupportedVersion
        if resolution.usedSupportedFallback {
            updateWarningText = "Latest Google Play version unavailable"
        }
    }

    func resolveDownloadableVersion(credential: GoogleCredential) async throws -> MinecraftVersionResolution {
        let downloadCoordinator = makeMinecraftDownloadCoordinator()
        let latest: LatestVersion
        let usedSupportedFallback: Bool
        do {
            latest = try await downloadCoordinator.latestVersion(credential: credential)
            usedSupportedFallback = false
        } catch {
            latest = try await supportedVersionFallback(after: error)
            usedSupportedFallback = true
        }
        let downloadableResolution = try await downloadableVersionResolution(for: latest)
        return MinecraftVersionResolution(
            reportedLatest: latest,
            downloadable: downloadableResolution.downloadable,
            googlePlayLatestVersion: usedSupportedFallback ? nil : latest,
            newestSupportedVersion: downloadableResolution.newestSupportedVersion,
            usedSupportedFallback: usedSupportedFallback
        )
    }

    private func supportedVersionFallback(after error: Error) async throws -> LatestVersion {
        guard canUseSupportedVersionFallback(after: error) else {
            throw error
        }
        let metadata = try await ensureCompatibilityPatch()
        guard let supported = metadata.newestSupportedVersion else {
            throw error
        }
        return LatestVersion(
            packageName: MinecraftDownloadCoordinator.packageName,
            versionName: supported.versionName,
            versionCode: supported.versionCode
        )
    }

    private func canUseSupportedVersionFallback(after error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("DF-DFERH-01")
    }

    func downloadableVersion(for latest: LatestVersion) async throws -> LatestVersion {
        let resolution = try await downloadableVersionResolution(for: latest)
        newestSupportedVersion = resolution.newestSupportedVersion
        return resolution.downloadable
    }

    private func downloadableVersionResolution(for latest: LatestVersion) async throws -> DownloadableVersionResolution {
        let metadata = try await ensureCompatibilityPatch()
        if metadata.supports(versionCode: latest.versionCode) {
            return DownloadableVersionResolution(
                downloadable: latest,
                newestSupportedVersion: metadata.newestSupportedVersion
            )
        }
        guard let supported = metadata.newestSupportedVersion else {
            throw LauncherError.unsupportedMinecraftVersion(
                versionName: latest.versionName,
                versionCode: latest.versionCode,
                supportedVersionName: nil,
                supportedVersionCode: nil
            )
        }
        return DownloadableVersionResolution(
            downloadable: LatestVersion(
                packageName: latest.packageName,
                versionName: supported.versionName,
                versionCode: supported.versionCode
            ),
            newestSupportedVersion: metadata.newestSupportedVersion
        )
    }

    func checkDownloadAccess(for version: LatestVersion, credential: GoogleCredential) async throws {
        let probeURL = paths.downloadsURL.appendingPathComponent("AccessProbe-\(UUID().uuidString)", isDirectory: true)
        try await makeMinecraftDownloadCoordinator().checkDownloadAccess(
            for: version,
            credential: credential,
            outputDirectory: probeURL
        )
    }

    func refreshSelectedVersionCompatibility() {
        guard let selectedVersion else {
            selectedVersionWarning = nil
            return
        }
        let manager = CompatibilityPatchManager(paths: paths, processRunner: processRunner)
        guard let metadata = manager.installedMetadata() else {
            selectedVersionWarning = nil
            return
        }
        newestSupportedVersion = metadata.newestSupportedVersion
        guard metadata.supports(versionCode: selectedVersion.versionCode) else {
            let supported = metadata.newestSupportedVersion
            selectedVersionWarning = LauncherError.unsupportedMinecraftVersion(
                versionName: selectedVersion.versionName,
                versionCode: selectedVersion.versionCode,
                supportedVersionName: supported?.versionName,
                supportedVersionCode: supported?.versionCode
            ).localizedDescription
            return
        }
        selectedVersionWarning = nil
    }

    func refreshCompatibilityMetadata() async {
        do {
            let metadata = try await ensureCompatibilityPatch()
            newestSupportedVersion = metadata.newestSupportedVersion
        } catch {
            if CompatibilityPatchManager(paths: paths, processRunner: processRunner).installedMetadata() == nil {
                selectedVersionWarning = nil
            }
        }
    }

    func ensureCompatibilityPatch() async throws -> CompatibilityPatchMetadata {
        let manager = CompatibilityPatchManager(paths: paths, processRunner: processRunner)
        return try await Task.detached(priority: .utility) {
            try await manager.installLatest()
        }.value
    }

    func compatibilityPatchPath(for version: InstalledVersion) async throws -> URL {
        let manager = CompatibilityPatchManager(paths: paths, processRunner: processRunner)
        if let patchPath = manager.installedPatchPath(for: version.versionCode) {
            return patchPath
        }
        let metadata = try await ensureCompatibilityPatch()
        if metadata.supports(versionCode: version.versionCode),
           let patchPath = manager.installedPatchPath(for: version.versionCode) {
            return patchPath
        }
        let supported = metadata.newestSupportedVersion
        throw LauncherError.unsupportedMinecraftVersion(
            versionName: version.versionName,
            versionCode: version.versionCode,
            supportedVersionName: supported?.versionName,
            supportedVersionCode: supported?.versionCode
        )
    }

    func applyCompatibilityLibraryPatches(to version: InstalledVersion) async throws {
        let patchPath = try await compatibilityPatchPath(for: version)
        try applyCompatibilityLibraryPatches(to: version, patchPath: patchPath)
    }

    func applyCompatibilityLibraryPatches(to version: InstalledVersion, patchPath: URL) throws {
        let manager = CompatibilityPatchManager(paths: paths, processRunner: processRunner)
        try manager.applyLibraryPatches(from: patchPath, to: version)
        let unapplied = try manager.unappliedLibraryPatchNames(from: patchPath, to: version)
        if !unapplied.isEmpty {
            throw LauncherError.runtimeInstallFailed("Compatibility patches were not applied: \(unapplied.joined(separator: ", "))")
        }
    }
}
