import AppKit
import Foundation
import MinecraftBedrockLauncherCore

struct PendingGameLaunch {
    var captureLog: Bool
}

extension LauncherViewModel {
    func playSelected(captureLog: Bool = false, allowsRunningGame: Bool = false) async {
        guard !isGameLaunchBlocked else {
            return
        }
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            guard let selectedVersion else {
                return
            }
            guard registry.isInstalled(selectedVersion) else {
                let installedVersions = (try? registry.load()) ?? []
                self.selectedVersion = installedVersions.first
                try? registry.save(installedVersions)
                throw LauncherError.missingInstalledMinecraftVersion(selectedVersion.installPath)
            }
            if !allowsRunningGame, isMinecraftAlreadyRunning {
                pendingRunningGameLaunch = PendingGameLaunch(captureLog: captureLog)
                isShowingRunningGameWarning = true
                return
            }
            isLaunchingGame = true
            guard let runtimePath = await ensureRuntimeForUse() else {
                isLaunchingGame = false
                return
            }
            let patchPath = try await compatibilityPatchPath(for: selectedVersion)
            try applyCompatibilityLibraryPatches(to: selectedVersion, patchPath: patchPath)
            let launcher = RuntimeLauncher(processRunner: processRunner)
            let credentialsHelperDirectory = credentialsHelperURL().deletingLastPathComponent()
            let googleCredential = try loadStoredCredentialIfNeeded()
            let logURL = captureLog ? launchLogURL(for: selectedVersion) : nil
            let dataPath = paths.minecraftDataURL
            let cachePath = dataPath
            try applyRuntimeClientPreferences(dataPath: dataPath)
            if shouldWarmUpFirstLaunch(dataPath: dataPath) {
                try await prepareFirstLaunchUntilReady(
                    launcher: launcher,
                    runtimePath: runtimePath,
                    version: selectedVersion,
                    patchPath: patchPath,
                    dataPath: dataPath,
                    cachePath: cachePath,
                    credentialsHelperDirectory: credentialsHelperDirectory,
                    googleCredential: googleCredential,
                    detail: "Preparing first launch",
                    captureLog: captureLog
                )
            }
            let clientWrapperExecutableURL = clientWrapperExecutableURL()
            let clientWrapperIconURL = clientWrapperIconURL()
            try await LaunchCoordinator(launcher: launcher).launchDetached(
                runtimePath: runtimePath,
                version: selectedVersion,
                compatibilityPatchPath: patchPath,
                dataPath: dataPath,
                cachePath: cachePath,
                credentialsHelperDirectory: credentialsHelperDirectory,
                googleCredential: googleCredential,
                logURL: logURL,
                clientWrapperExecutableURL: clientWrapperExecutableURL,
                clientWrapperIconURL: clientWrapperIconURL
            )
            NSApplication.shared.terminate(nil)
            errorText = nil
        } catch {
            isLaunchingGame = false
            downloadState = DownloadState(versionName: selectedVersion?.versionName, phase: .failed, error: error.localizedDescription)
            show(error)
        }
    }

    func cancelRunningGameWarning() {
        pendingRunningGameLaunch = nil
        isShowingRunningGameWarning = false
    }

    func launchAnywayAfterRunningGameWarning() async {
        let pendingLaunch = pendingRunningGameLaunch ?? PendingGameLaunch(captureLog: false)
        pendingRunningGameLaunch = nil
        isShowingRunningGameWarning = false
        await playSelected(captureLog: pendingLaunch.captureLog, allowsRunningGame: true)
    }

    private var isMinecraftAlreadyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: RuntimeLauncher.clientBundleIdentifier).isEmpty
    }

    func prepareFirstLaunchUntilReady(
        launcher: RuntimeLauncher,
        runtimePath: URL,
        version: InstalledVersion,
        patchPath: URL,
        dataPath: URL,
        cachePath: URL,
        credentialsHelperDirectory: URL,
        googleCredential: GoogleCredential?,
        detail: String,
        captureLog: Bool,
        maxAttempts: Int = 3
    ) async throws {
        var lastWarmUpLogURL: URL?
        for attempt in 1...maxAttempts {
            downloadState = DownloadState(
                versionName: version.versionName,
                progress: 0.98,
                phase: .preparingFirstLaunch,
                detail: detail
            )

            let warmUpLogURL = captureLog ? firstLaunchWarmUpLogURL(for: version, attempt: attempt) : nil
            lastWarmUpLogURL = warmUpLogURL
            let result = try await runOffMain {
                try launcher.warmUpFirstLaunch(
                    runtimePath: runtimePath,
                    version: version,
                    compatibilityPatchPath: patchPath,
                    dataPath: dataPath,
                    cachePath: cachePath,
                    credentialsHelperDirectory: credentialsHelperDirectory,
                    googleCredential: googleCredential,
                    logURL: warmUpLogURL
                )
            }
            if result == .loadedPairIP {
                return
            }
        }

        throw LauncherError.gameLaunchFailed(
            status: 11,
            logURL: lastWarmUpLogURL,
            outputTail: "First launch preparation did not reach Loaded libpairipcore."
        )
    }

    private func shouldWarmUpFirstLaunch(dataPath: URL) -> Bool {
        !FileManager.default.fileExists(atPath: firstLaunchTokenURL(dataPath: dataPath).path)
    }

    func firstLaunchTokenURL(dataPath: URL) -> URL {
        dataPath.appendingPathComponent("pass.token", isDirectory: false)
    }

    private func bundledHelperURL(named name: String) -> URL {
        return Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

    func credentialsHelperURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_CREDENTIALS_HELPER_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return bundledHelperURL(named: "mcpelauncher-ui-qt")
    }

    private func clientWrapperExecutableURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_CLIENT_WRAPPER_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return bundledHelperURL(named: "mcpelauncher-client-wrapper")
    }

    private func clientWrapperIconURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_CLIENT_WRAPPER_ICON_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let iconFile = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        let iconName = iconFile?.replacingOccurrences(of: ".icns", with: "") ?? "minecraft-bedrock"
        return Bundle.main.url(forResource: iconName, withExtension: "icns")
    }

    private func launchLogURL(for version: InstalledVersion) -> URL {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return paths.logsURL.appendingPathComponent(
            "launch-\(version.versionName)-\(stamp).log",
            isDirectory: false
        )
    }

    private func firstLaunchWarmUpLogURL(for version: InstalledVersion, attempt: Int? = nil) -> URL {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let attemptSuffix = attempt.map { "-attempt-\($0)" } ?? ""
        return paths.logsURL.appendingPathComponent(
            "first-launch-warmup-\(version.versionName)-\(stamp)\(attemptSuffix).log",
            isDirectory: false
        )
    }

    func makeMinecraftDownloadCoordinator() -> MinecraftDownloadCoordinator {
        MinecraftDownloadCoordinator(
            googlePlay: makeGooglePlayClient(),
            processRunner: processRunner
        )
    }
}
