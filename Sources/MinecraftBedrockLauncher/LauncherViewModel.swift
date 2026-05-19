import AppKit
import Foundation
import MinecraftBedrockLauncherCore
import CoreGraphics

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var credential: GoogleCredential?
    @Published var latestVersion: LatestVersion?
    @Published var googlePlayLatestVersion: LatestVersion?
    @Published var newestSupportedVersion: SupportedMinecraftVersion?
    @Published var installedVersions: [InstalledVersion] = []
    @Published var selectedVersion: InstalledVersion? {
        didSet {
            refreshSelectedVersionCompatibility()
        }
    }
    @Published var downloadState = DownloadState()
    @Published var runtimeState = RuntimeState()
    @Published var statusText = "Ready"
    @Published var errorText: String?
    @Published var updateWarningText: String?
    @Published var credentialAccessDenied = false
    @Published var selectedVersionWarning: String?
    @Published var showingLogin = false
    @Published var canSkipRuntimeUpdateCheck = false
    @Published var isBlockingNetworkUnavailable = false
    @Published var isDeletingRuntime = false
    @Published var isDeletingGame = false
    @Published var isDeletingData = false

    var isGooglePlayBusy: Bool {
        switch downloadState.phase {
        case .authenticating, .fetchingLatest, .downloading, .extracting:
            return true
        case .idle, .installed, .failed:
            return false
        }
    }

    var isRuntimeBusy: Bool {
        runtimeState.phase == .checking || runtimeState.phase == .downloading || runtimeState.phase == .installing
    }

    var isRuntimeReady: Bool {
        runtimeState.phase == .ready
    }

    var canUseSelectedVersion: Bool {
        selectedVersion != nil && selectedVersionWarning == nil
    }

    var dataFolderURL: URL {
        paths.baseURL
    }

    var preferredWindowWidth: CGFloat {
        guard let email = displayCredentialEmail else {
            return 300
        }
        return min(max(300, CGFloat(email.count * 7 + 180)), 420)
    }

    var displayCredentialEmail: String? {
        guard let email = credential?.email else {
            return nil
        }
        return displayEmail(for: email)
    }

    private let paths: AppPaths
    private let credentialStore: CredentialStore
    private let registry: InstalledVersionRegistry
    private let processRunner: ProcessRunning
    private var didStart = false
    private var didTryLoadingStoredCredential = false
    private var runtimeUpdateTask: Task<Void, Never>?
    private var runtimeSkipDelayTask: Task<Void, Never>?
    private var activeRuntimeUpdateID: UUID?
    private var lastDownloadProgressUpdate: Date?
    private var lastRuntimeProgressUpdate: Date?
    private var downloadStallTask: Task<Void, Never>?
    private var activeDownloadTask: Task<Void, Never>?
    private var activeDownloadID: UUID?

    init(
        paths: AppPaths? = nil,
        credentialStore: CredentialStore = KeychainCredentialStore(),
        processRunner: ProcessRunning = FoundationProcessRunner()
    ) {
        let resolvedPaths: AppPaths
        if let paths {
            resolvedPaths = paths
        } else if let defaultPaths = try? AppPaths.default() {
            resolvedPaths = defaultPaths
        } else {
            resolvedPaths = AppPaths(
                baseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("Minecraft Bedrock Launcher", isDirectory: true)
            )
        }
        self.paths = resolvedPaths
        self.credentialStore = credentialStore
        self.registry = InstalledVersionRegistry(paths: resolvedPaths)
        self.processRunner = processRunner
    }

    func start() async {
        guard !didStart else {
            return
        }
        didStart = true
        await load()
        await loadStoredCredentialAndFetchLatest()
    }

    func load() async {
        do {
            try paths.ensureDirectories()
            installedVersions = try registry.load()
            selectedVersion = installedVersions.first
            refreshSelectedVersionCompatibility()
            if LauncherPreferences.automaticallyCheckRuntimeUpdates {
                startAutomaticRuntimeUpdate()
            } else {
                refreshInstalledRuntimeState()
            }
            statusText = selectedVersion == nil ? "Sign in to Google Play to download Minecraft." : "Ready."
        } catch {
            show(error)
        }
    }

    func loadStoredCredentialAndFetchLatest() async {
        await loadStoredCredential(fetchLatestAfterLoad: true)
    }

    func loadStoredCredential() async {
        await loadStoredCredential(fetchLatestAfterLoad: false)
    }

    private func loadStoredCredential(fetchLatestAfterLoad: Bool) async {
        do {
            credentialAccessDenied = false
            guard let credential = try loadStoredCredentialIfNeeded() else {
                statusText = selectedVersion == nil ? "Sign in to Google Play to download Minecraft." : "Ready."
                return
            }
            let email = displayEmail(for: credential.email)
            if fetchLatestAfterLoad && LauncherPreferences.automaticallyCheckGameUpdates {
                statusText = "Signed in as \(email). Checking latest Google Play version..."
                await fetchLatest()
            } else {
                statusText = "Signed in as \(email)."
            }
        } catch KeychainError.accessDenied {
            credentialAccessDenied = true
            errorText = "Keychain access was denied."
            statusText = "Keychain access required."
        } catch {
            show(error)
        }
    }

    func retryStoredCredentialAccess() async {
        didTryLoadingStoredCredential = false
        credentialAccessDenied = false
        errorText = nil
        updateWarningText = nil
        statusText = "Requesting Keychain access..."
        await loadStoredCredentialAndFetchLatest()
    }

    func signOut() {
        do {
            try credentialStore.clearCredential()
            if FileManager.default.fileExists(atPath: paths.helperStateURL.path) {
                try FileManager.default.removeItem(at: paths.helperStateURL)
            }
            try FileManager.default.createDirectory(at: paths.helperStateURL, withIntermediateDirectories: true)
            credential = nil
            didTryLoadingStoredCredential = false
            credentialAccessDenied = false
            latestVersion = nil
            googlePlayLatestVersion = nil
            downloadState = DownloadState()
            errorText = nil
            updateWarningText = nil
            statusText = "Signed out."
        } catch {
            show(error)
        }
    }

    func deleteRuntime() async {
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
            statusText = "Runtime deleted."
        } catch {
            show(error)
        }
    }

    func deleteInstalledGames() async {
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
            installedVersions = []
            selectedVersion = nil
            latestVersion = nil
            googlePlayLatestVersion = nil
            downloadState = DownloadState()
            errorText = nil
            updateWarningText = nil
            statusText = "Installed games deleted."
        } catch {
            show(error)
        }
    }

    func deleteMinecraftData() async {
        do {
            isDeletingData = true
            defer { isDeletingData = false }
            let dataURL = paths.minecraftDataURL
            let cacheURL = paths.minecraftCacheURL
            try await runOffMain {
                for url in [dataURL, cacheURL] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            }
            errorText = nil
            updateWarningText = nil
            statusText = "Minecraft data deleted."
        } catch {
            show(error)
        }
    }

    func completeLogin(email: String, userID: String, oauthToken: String) async {
        do {
            errorText = nil
            updateWarningText = nil
            showingLogin = false
            downloadState = DownloadState(phase: .authenticating)
            statusText = "Completing Google Play sign in..."
            let googlePlay = makeGooglePlayClient()
            let request = GooglePlayAuthRequest(
                accountIdentifier: email,
                userID: userID,
                oauthToken: oauthToken
            )
            let savedCredential = try await runOffMain { try googlePlay.auth(request) }
            try credentialStore.saveCredential(savedCredential)
            credential = savedCredential
            credentialAccessDenied = false
            didTryLoadingStoredCredential = true
            downloadState = DownloadState()
            errorText = nil
            statusText = "Signed in as \(displayEmail(for: savedCredential.email)). Checking latest Google Play version..."
            await fetchLatest()
        } catch {
            downloadState = DownloadState(versionName: latestVersion?.versionName, phase: .failed, error: error.localizedDescription)
            show(error)
        }
    }

    func fetchLatest() async {
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            guard let credential = try loadStoredCredentialIfNeeded() else {
                throw LauncherError.missingCredential
            }
            downloadState = DownloadState(phase: .fetchingLatest)
            let googlePlay = makeGooglePlayClient()
            let latest = try await runOffMain {
                try googlePlay.latest(packageName: "com.mojang.minecraftpe", abi: "arm64-v8a", credential: credential)
            }
            googlePlayLatestVersion = latest
            let downloadable = try await downloadableVersion(for: latest)
            latestVersion = downloadable
            if selectedVersion == nil {
                downloadState = DownloadState(
                    versionName: downloadable.versionName,
                    phase: .fetchingLatest,
                    detail: "Checking purchase..."
                )
                try await checkDownloadAccess(for: downloadable, credential: credential)
            }
            downloadState = DownloadState(versionName: downloadable.versionName)
            errorText = nil
            if let installed = installedVersions.first(where: { $0.versionCode == downloadable.versionCode }) {
                selectedVersion = installed
                statusText = "\(downloadable.versionName) is already installed."
            } else if downloadable.versionCode != latest.versionCode {
                refreshSelectedVersionCompatibility()
                statusText = "Google Play has \(latest.versionName), but macOS patches currently support \(downloadable.versionName)."
            } else {
                statusText = "Latest Google Play version: \(latest.versionName)."
            }
        } catch {
            if selectedVersion != nil {
                downloadState = DownloadState()
                updateWarningText = "Update check failed"
                statusText = "Could not check Minecraft updates: \(error.localizedDescription)"
            } else {
                downloadState = DownloadState(phase: .failed, error: error.localizedDescription)
                show(error)
            }
        }
    }

    func refreshVersionInfo() async {
        await fetchLatest()
    }

    func startDownloadAndInstallLatest() {
        let downloadID = UUID()
        activeDownloadID = downloadID
        activeDownloadTask?.cancel()
        activeDownloadTask = Task { [weak self] in
            await self?.downloadAndInstallLatest(downloadID: downloadID)
        }
    }

    func startRuntimeInstall() {
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = Task { [weak self] in
            _ = await self?.ensureRuntimeForUse()
        }
    }

    func cancelDownload() {
        guard downloadState.phase == .downloading else {
            return
        }
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadID = nil
        ChildProcessRegistry.shared.terminateAll()
        downloadStallTask?.cancel()
        downloadStallTask = nil
        downloadState = latestVersion.map { DownloadState(versionName: $0.versionName) } ?? DownloadState()
        errorText = nil
        updateWarningText = nil
        statusText = "Download canceled."
    }

    private func downloadAndInstallLatest(downloadID: UUID) async {
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            try ensureAvailableDiskSpace(minimumBytes: 3_000_000_000)
            guard let credential = try loadStoredCredentialIfNeeded() else {
                throw LauncherError.missingCredential
            }
            var latest = latestVersion
            if latest == nil {
                downloadState = DownloadState(phase: .fetchingLatest)
                let googlePlay = makeGooglePlayClient()
                let googleLatest = try await runOffMain {
                    try googlePlay.latest(packageName: "com.mojang.minecraftpe", abi: "arm64-v8a", credential: credential)
                }
                googlePlayLatestVersion = googleLatest
                latest = try await downloadableVersion(for: googleLatest)
                latestVersion = latest
            }
            guard let latest else {
                return
            }
            let downloadable = try await downloadableVersion(for: latest)
            latestVersion = downloadable

            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.02,
                phase: .downloading,
                detail: "Starting download..."
            )
            lastDownloadProgressUpdate = nil
            startDownloadStallWatch(versionName: downloadable.versionName)
            let outputURL = paths.downloadsURL.appendingPathComponent(String(downloadable.versionCode), isDirectory: true)
            let googlePlay = makeGooglePlayClient()
            let downloadProgress: @Sendable (DownloadProgress) -> Void = { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress, versionName: downloadable.versionName, downloadID: downloadID)
                }
            }
            let response = try await runOffMain {
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                return try googlePlay.download(
                    packageName: "com.mojang.minecraftpe",
                    versionCode: downloadable.versionCode,
                    outputDirectory: outputURL,
                    abi: "arm64-v8a",
                    credential: credential,
                    progress: downloadProgress
                )
            }
            guard activeDownloadID == downloadID, !Task.isCancelled else {
                return
            }
            downloadStallTask?.cancel()
            downloadStallTask = nil

            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.86,
                phase: .extracting,
                detail: "Extracting APK files..."
            )
            let installer = GameInstaller(processRunner: processRunner)
            let versionsURL = paths.versionsURL
            let extractProgress: @Sendable (Double) -> Void = { [weak self] progress in
                Task { @MainActor in
                    self?.updateExtractionProgress(progress, versionName: downloadable.versionName)
                }
            }
            let installed = try await runOffMain {
                try installer.install(
                    downloadedAPKs: response.files,
                    latestVersion: downloadable,
                    versionsDirectory: versionsURL,
                    progress: extractProgress
                )
            }
            guard activeDownloadID == downloadID, !Task.isCancelled else {
                return
            }
            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.98,
                phase: .extracting,
                detail: "Preparing first launch..."
            )
            let patchPath = try await compatibilityPatchPath(for: installed)
            try applyCompatibilityLibraryPatches(to: installed, patchPath: patchPath)
            if let runtimePath = await ensureRuntimeForUse() {
                let credentialsHelperDirectory = credentialsHelperURL().deletingLastPathComponent()
                let dataPath = paths.minecraftDataURL
                let cachePath = paths.minecraftCacheURL
                let warmUpLogURL = firstLaunchWarmUpLogURL(for: installed)
                _ = try await runOffMain {
                    try RuntimeLauncher().warmUpFirstLaunch(
                        runtimePath: runtimePath,
                        version: installed,
                        compatibilityPatchPath: patchPath,
                        dataPath: dataPath,
                        cachePath: cachePath,
                        credentialsHelperDirectory: credentialsHelperDirectory,
                        googleCredential: credential,
                        logURL: warmUpLogURL
                    )
                }
            }
            try removeObsoleteMinecraftFiles(keeping: installed)
            try registry.save([installed])
            installedVersions = try registry.load()
            selectedVersion = installed
            refreshSelectedVersionCompatibility()
            activeDownloadID = nil
            downloadState = DownloadState(versionName: downloadable.versionName, progress: 1, phase: .installed)
            errorText = nil
            updateWarningText = nil
            statusText = "Installed \(downloadable.versionName)."
        } catch is CancellationError {
            guard activeDownloadID == downloadID else {
                return
            }
            activeDownloadID = nil
            downloadStallTask?.cancel()
            downloadStallTask = nil
            downloadState = latestVersion.map { DownloadState(versionName: $0.versionName) } ?? DownloadState()
            errorText = nil
            updateWarningText = nil
            statusText = "Download canceled."
        } catch {
            guard activeDownloadID == downloadID else {
                return
            }
            activeDownloadID = nil
            downloadStallTask?.cancel()
            downloadStallTask = nil
            downloadState = DownloadState(phase: .failed, error: error.localizedDescription)
            show(error)
        }
    }

    func playSelected() async {
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            guard let selectedVersion else {
                statusText = "Install a version first."
                return
            }
            guard let runtimePath = await ensureRuntimeForUse() else {
                return
            }
            let patchPath = try await compatibilityPatchPath(for: selectedVersion)
            try applyCompatibilityLibraryPatches(to: selectedVersion, patchPath: patchPath)
            let launcher = RuntimeLauncher(processRunner: processRunner)
            statusText = "Launching \(selectedVersion.versionName)..."
            let credentialsHelperDirectory = credentialsHelperURL().deletingLastPathComponent()
            let googleCredential = try loadStoredCredentialIfNeeded()
            let logURL = launchLogURL(for: selectedVersion)
            let dataPath = paths.minecraftDataURL
            let cachePath = paths.minecraftCacheURL
            try await runOffMain {
                try launcher.launchDetached(
                    runtimePath: runtimePath,
                    version: selectedVersion,
                    compatibilityPatchPath: patchPath,
                    dataPath: dataPath,
                    cachePath: cachePath,
                    credentialsHelperDirectory: credentialsHelperDirectory,
                    googleCredential: googleCredential,
                    logURL: logURL
                )
            }
            NSApplication.shared.terminate(nil)
            errorText = nil
            statusText = "Minecraft exited. Log: \(logURL.path)"
        } catch {
            show(error)
        }
    }

    private func loadStoredCredentialIfNeeded() throws -> GoogleCredential? {
        if let credential {
            return credential
        }
        guard !didTryLoadingStoredCredential else {
            return nil
        }
        didTryLoadingStoredCredential = true
        let storedCredential = try credentialStore.loadCredential()
        credential = storedCredential
        return storedCredential
    }

    private func displayEmail(for email: String) -> String {
        guard Self.isScreenshotModeEnabled else {
            return email
        }
        return ProcessInfo.processInfo.environment["SCREENSHOT_EMAIL"]?.isEmpty == false
            ? ProcessInfo.processInfo.environment["SCREENSHOT_EMAIL"]!
            : "demo@example.com"
    }

    private static var isScreenshotModeEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SCREENSHOT_MODE"] == "1"
            || environment["MCPELAUNCHER_SCREENSHOT_MODE"] == "1"
    }

    private func makeGooglePlayClient() -> any GooglePlayDownloading {
        GPlayCLIClient(
            gplayverURL: gplayverURL(),
            gplaydlURL: gplaydlURL(),
            stateDirectoryURL: paths.helperStateURL,
            processRunner: processRunner
        )
    }

    private func gplayverURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["GPLAYVER_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return bundledHelperURL(named: "gplayver")
    }

    private func gplaydlURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["GPLAYDL_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return bundledHelperURL(named: "gplaydl")
    }

    private func bundledHelperURL(named name: String) -> URL {
        return Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

    private func credentialsHelperURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_CREDENTIALS_HELPER_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("mcpelauncher-ui-qt", isDirectory: false)
    }

    private func runtimeURL() -> URL {
        runtimeOverrideURL() ?? paths.runtimeURL
    }

    private func startAutomaticRuntimeUpdate() {
        runtimeUpdateTask?.cancel()
        runtimeUpdateTask = Task { [weak self] in
            await self?.updateRuntimeIfNeeded()
        }
    }

    private func refreshInstalledRuntimeState() {
        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        if let state = installedRuntimeState(
            using: manager,
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
        if manager.hasInstalledRuntime(), let metadata = manager.installedMetadata() {
            runtimeState = RuntimeState(phase: .ready, version: metadata.version, detail: metadata.assetName)
        } else {
            runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
        }

        let hasRuntime = manager.hasInstalledRuntime()
        await installRuntime(
            forceStatus: hasRuntime ? "Checking runtime update..." : "Downloading runtime...",
            phase: hasRuntime ? .checking : .downloading,
            allowsSkip: hasRuntime
        )
    }

    private func ensureRuntimeForUse() async -> URL? {
        let launcher = RuntimeLauncher(processRunner: processRunner)
        let current = runtimeURL()
        if (try? launcher.runtimeExecutable(in: current)) != nil {
            return current
        }
        await installRuntime(forceStatus: "Downloading runtime...", phase: .downloading)
        let installed = runtimeURL()
        if (try? launcher.runtimeExecutable(in: installed)) != nil {
            return installed
        }
        return nil
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

        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        if let state = installedRuntimeState(
            using: manager,
            fallbackDetail: "Using installed runtime; update skipped."
        ) {
            errorText = nil
            runtimeState = state
            return
        }
        runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
    }

    private func installRuntime(
        forceStatus: String,
        phase: RuntimePhase,
        allowsSkip: Bool = false
    ) async {
        let manager = RuntimeManager(paths: paths, processRunner: processRunner)
        let updateID = UUID()
        activeRuntimeUpdateID = updateID
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        canSkipRuntimeUpdateCheck = false
        lastRuntimeProgressUpdate = nil
        isBlockingNetworkUnavailable = false
        runtimeState = RuntimeState(phase: phase, version: runtimeState.version, detail: forceStatus)
        if allowsSkip {
            runtimeSkipDelayTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self?.activeRuntimeUpdateID == updateID else {
                        return
                    }
                    self?.canSkipRuntimeUpdateCheck = true
                }
            }
        }
        do {
            let metadata: RuntimeMetadata
            if allowsSkip {
                let release = try await manager.resolveLatestRelease()
                try Task.checkCancellation()
                canSkipRuntimeUpdateCheck = false
                runtimeState = RuntimeState(
                    phase: .downloading,
                    version: runtimeState.version,
                    detail: "Starting runtime download..."
                )
                metadata = try await manager.install(release, progress: runtimeDownloadProgress)
            } else {
                metadata = try await manager.installLatest(progress: runtimeDownloadProgress)
            }
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
            if let state = installedRuntimeState(
                using: manager,
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
            if let state = installedRuntimeState(
                using: manager,
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
        let fraction = progress.fractionCompleted
        let isComplete = progress.totalBytes.map { $0 > 0 && progress.bytesReceived >= $0 } ?? false
        if isComplete {
            runtimeState = RuntimeState(
                phase: .installing,
                version: runtimeState.version,
                detail: "Installing runtime...",
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
            progress: fraction > 0 ? fraction : runtimeState.progress,
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

    private func startDownloadStallWatch(versionName: String) {
        downloadStallTask?.cancel()
        downloadStallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run {
                guard let self,
                      self.downloadState.phase == .downloading,
                      self.downloadState.versionName == versionName,
                      (self.downloadState.bytesReceived ?? 0) == 0 else {
                    return
                }
                self.downloadState = DownloadState(
                    versionName: versionName,
                    phase: .failed,
                    error: "Download did not start. Check your connection and try again."
                )
                self.errorText = "Download did not start. Check your connection and try again."
                self.statusText = self.errorText ?? "Download failed."
            }
        }
    }

    private func runtimeDownloadStatusText(for progress: DownloadProgress) -> String {
        guard let total = progress.totalBytes, total > 0 else {
            return "Downloading runtime..."
        }
        let percent = Double(progress.bytesReceived) / Double(total) * 100
        return String(format: "Downloading runtime %.1f%%", percent)
    }

    private func installedRuntimeState(using manager: RuntimeManager, fallbackDetail: String) -> RuntimeState? {
        guard manager.hasInstalledRuntime() else {
            return nil
        }
        if let metadata = manager.installedMetadata() {
            return RuntimeState(phase: .ready, version: metadata.version, detail: fallbackDetail)
        }
        return RuntimeState(phase: .ready, version: "installed", detail: fallbackDetail)
    }

    private func runtimeOverrideURL() -> URL? {
        guard let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_RUNTIME_PATH"], !override.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: override, isDirectory: true)
        return (try? RuntimeLauncher(processRunner: processRunner).runtimeExecutable(in: url)) == nil ? nil : url
    }

    private func downloadableVersion(for latest: LatestVersion) async throws -> LatestVersion {
        let metadata = try await ensureCompatibilityPatch()
        newestSupportedVersion = metadata.newestSupportedVersion
        if metadata.supports(versionCode: latest.versionCode) {
            return latest
        }
        guard let supported = metadata.newestSupportedVersion else {
            throw LauncherError.unsupportedMinecraftVersion(
                versionName: latest.versionName,
                versionCode: latest.versionCode,
                supportedVersionName: nil,
                supportedVersionCode: nil
            )
        }
        return LatestVersion(
            packageName: latest.packageName,
            versionName: supported.versionName,
            versionCode: supported.versionCode,
            isBeta: latest.isBeta
        )
    }

    private func checkDownloadAccess(for version: LatestVersion, credential: GoogleCredential) async throws {
        let probeURL = paths.downloadsURL.appendingPathComponent("AccessProbe-\(UUID().uuidString)", isDirectory: true)
        let googlePlay = makeGooglePlayClient()
        do {
            try await runOffMain {
                try googlePlay.checkDownloadAccess(
                    packageName: "com.mojang.minecraftpe",
                    versionCode: version.versionCode,
                    outputDirectory: probeURL,
                    abi: "arm64-v8a",
                    credential: credential
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            throw error
        }
        try? FileManager.default.removeItem(at: probeURL)
    }

    private func updateDownloadProgress(_ progress: DownloadProgress, versionName: String, downloadID: UUID) {
        guard activeDownloadID == downloadID,
              downloadState.phase != .failed,
              shouldPublishDownloadProgress(progress) else {
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

    private func shouldPublishProgress(
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
            detail: "Extracting APK files..."
        )
    }

    private func refreshSelectedVersionCompatibility() {
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

    private func refreshCompatibilityMetadata() async {
        do {
            let metadata = try await ensureCompatibilityPatch()
            newestSupportedVersion = metadata.newestSupportedVersion
        } catch {
            if CompatibilityPatchManager(paths: paths, processRunner: processRunner).installedMetadata() == nil {
                selectedVersionWarning = nil
            }
        }
    }

    private func ensureCompatibilityPatch() async throws -> CompatibilityPatchMetadata {
        let manager = CompatibilityPatchManager(paths: paths, processRunner: processRunner)
        return try await Task.detached(priority: .utility) {
            try await manager.installLatest()
        }.value
    }

    private func compatibilityPatchPath(for version: InstalledVersion) async throws -> URL {
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

    private func applyCompatibilityLibraryPatches(to version: InstalledVersion) async throws {
        let patchPath = try await compatibilityPatchPath(for: version)
        try applyCompatibilityLibraryPatches(to: version, patchPath: patchPath)
    }

    private func applyCompatibilityLibraryPatches(to version: InstalledVersion, patchPath: URL) throws {
        let manager = CompatibilityPatchManager(paths: paths, processRunner: processRunner)
        try manager.applyLibraryPatches(from: patchPath, to: version)
        let unapplied = try manager.unappliedLibraryPatchNames(from: patchPath, to: version)
        if !unapplied.isEmpty {
            throw LauncherError.runtimeInstallFailed("Compatibility patches were not applied: \(unapplied.joined(separator: ", "))")
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

    private func launchLogURL(for version: InstalledVersion) -> URL {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return paths.logsURL.appendingPathComponent(
            "launch-\(version.versionName)-\(stamp).log",
            isDirectory: false
        )
    }

    private func firstLaunchWarmUpLogURL(for version: InstalledVersion) -> URL {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return paths.logsURL.appendingPathComponent(
            "first-launch-warmup-\(version.versionName)-\(stamp).log",
            isDirectory: false
        )
    }

    private func show(_ error: Error) {
        errorText = error.localizedDescription
        isBlockingNetworkUnavailable = shouldShowBlockingNetworkUnavailable(for: error)
        statusText = error.localizedDescription
    }

    private func shouldShowBlockingNetworkUnavailable(for error: Error) -> Bool {
        guard selectedVersion == nil || !isRuntimeReady else {
            return false
        }
        return Self.isNetworkUnavailable(error)
    }

    private static func isNetworkUnavailable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorTimedOut
            ].contains(nsError.code)
        }

        if case LauncherError.googlePlayToolFailed(let command, let status, let output) = error,
           command.localizedCaseInsensitiveContains("gplayver"),
           status == 1,
           output.localizedCaseInsensitiveContains("bad token") {
            return true
        }

        let description = error.localizedDescription
        return description.localizedCaseInsensitiveContains("not connected to the internet")
            || description.localizedCaseInsensitiveContains("network connection was lost")
            || description.localizedCaseInsensitiveContains("cannot find host")
            || description.localizedCaseInsensitiveContains("could not resolve host")
            || description.localizedCaseInsensitiveContains("timed out")
    }
}

private func runOffMain<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated) {
        try operation()
    }.value
}
