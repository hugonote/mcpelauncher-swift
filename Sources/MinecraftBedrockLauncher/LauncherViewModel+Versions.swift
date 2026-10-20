import Foundation
import MinecraftBedrockLauncherCore

extension LauncherViewModel {
    var isMinecraftUpdateAvailable: Bool {
        guard credential != nil, let latestVersion, selectedVersion != nil else {
            return false
        }
        return !installedVersions.contains { $0.versionCode == latestVersion.versionCode }
    }

    var newestInstalledVersionCode: Int? {
        installedVersions.map(\.versionCode).max()
    }

    var canManageVersions: Bool {
        !isStorageActionBusy && !isImportingContent
    }

    func reloadInstalledVersions() throws {
        installedVersions = try registry.load().sorted { $0.versionCode > $1.versionCode }
        selectedVersion = try registry.preferredVersion(
            named: selectedVersion?.versionName ?? LauncherPreferences.selectedGameVersion
        )
    }

    func selectVersion(_ version: InstalledVersion) {
        guard canManageVersions, registry.isInstalled(version) else {
            return
        }
        selectedVersion = version
        errorText = nil
        updateWarningText = nil
    }

    func installableVersions(from supportedVersions: [SupportedMinecraftVersion]) -> [SupportedMinecraftVersion] {
        let installedCodes = Set(installedVersions.map(\.versionCode))
        return supportedVersions
            .filter { !installedCodes.contains($0.versionCode) }
            .sorted { $0.versionCode > $1.versionCode }
    }

    func supportedMinecraftVersions() async -> [SupportedMinecraftVersion] {
        if let metadata = try? await ensureCompatibilityPatch() {
            return metadata.supportedVersions
        }
        return CompatibilityPatchManager(paths: paths, processRunner: processRunner)
            .installedMetadata()?
            .supportedVersions ?? []
    }

    @discardableResult
    func installVersion(_ version: SupportedMinecraftVersion) -> Task<Bool, Never> {
        startDownloadAndInstall(
            requested: LatestVersion(
                packageName: MinecraftDownloadCoordinator.packageName,
                versionName: version.versionName,
                versionCode: version.versionCode
            ),
            selectsInstalledVersion: true
        )
    }

    func deleteVersion(_ version: InstalledVersion) async -> Bool {
        guard canManageVersions else {
            return false
        }
        do {
            isDeletingGame = true
            defer { isDeletingGame = false }
            let registry = registry
            _ = try await runOffMain {
                try registry.remove(version)
            }
            if selectedVersion?.versionName == version.versionName {
                selectedVersion = nil
            }
            try reloadInstalledVersions()
            return true
        } catch {
            show(error)
            return false
        }
    }

    func modPathsForSelectedVersion(_ version: InstalledVersion) throws -> [URL] {
        try ModManager(paths: paths, processRunner: processRunner).enabledModPaths(for: version.versionName)
    }

    func backupWorldsBeforeLaunch(of version: InstalledVersion) async throws {
        let backupManager = WorldBackupManager(paths: paths)
        let backupURL = try await runOffMain {
            try backupManager.backupWorldsIfDowngrading(to: version)
        }
        if let backupURL {
            lastWorldBackupURL = backupURL
        }
        try backupManager.recordLaunch(of: version)
    }
}
