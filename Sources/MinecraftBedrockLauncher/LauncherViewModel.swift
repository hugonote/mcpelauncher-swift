import AppKit
import Foundation
import MinecraftBedrockLauncherCore
import CoreGraphics
import Network

private struct PendingGameLaunch {
    var captureLog: Bool
}

private struct MinecraftVersionResolution {
    var reportedLatest: LatestVersion
    var downloadable: LatestVersion
    var usedSupportedFallback: Bool
}

private struct SignOutLegacyGooglePlayStateCleanupError: LocalizedError {
    var url: URL
    var underlyingError: Error

    var errorDescription: String? {
        "Signed out, but legacy Google Play state could not be removed at \(url.path): \(underlyingError.localizedDescription)"
    }
}

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
    @Published private var errorState = LauncherErrorState()
    @Published var updateWarningText: String?
    @Published var credentialAccessDenied = false
    @Published var selectedVersionWarning: String?
    @Published private(set) var isLaunchingGame = false
    @Published private(set) var isQuickLaunchActive = false
    @Published var showingLogin = false
    @Published var isShowingRunningGameWarning = false
    @Published var canSkipRuntimeUpdateCheck = false
    @Published var isDeletingRuntime = false
    @Published var isDeletingGame = false
    @Published var isDeletingData = false

    var activeIssue: LauncherIssue? {
        errorState.activeIssue
    }

    var errorText: String? {
        get {
            errorState.errorText
        }
        set {
            reduceError(.setMessage(newValue))
        }
    }

    var isBlockingNetworkUnavailable: Bool {
        get {
            errorState.isBlockingNetworkUnavailable
        }
        set {
            reduceError(.setBlockingNetworkUnavailable(newValue))
        }
    }

    var isGooglePlayBusy: Bool {
        switch downloadState.phase {
        case .authenticating, .fetchingLatest, .downloading, .extracting, .preparingFirstLaunch:
            return true
        case .idle, .installed, .failed:
            return false
        }
    }

    var isRuntimeBusy: Bool {
        runtimeState.phase == .checking || runtimeState.phase == .downloading || runtimeState.phase == .installing
    }

    var isStorageActionBusy: Bool {
        isDeletingRuntime || isDeletingGame || isDeletingData || isGooglePlayBusy || isRuntimeBusy || isLaunchingGame
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
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "MinecraftBedrockLauncher.NetworkMonitor")
    private var didStart = false
    private var didContinueStartupAfterWindowReveal = false
    private var didTryLoadingStoredCredential = false
    private var runtimeUpdateTask: Task<Void, Never>?
    private var runtimeSkipDelayTask: Task<Void, Never>?
    private var activeRuntimeUpdateID: UUID?
    private var lastDownloadProgressUpdate: Date?
    private var lastDownloadProgressEventDate: Date?
    private var lastDownloadProgressBytes: Int64 = 0
    private var lastRuntimeProgressUpdate: Date?
    private var downloadStallTask: Task<Void, Never>?
    private var activeDownloadTask: Task<Void, Never>?
    private var activeDownloadID: UUID?
    private var activeDownloadOutputURL: URL?
    private var pendingRunningGameLaunch: PendingGameLaunch?

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
        try? preloadLocalStateForInitialLayout()
        preloadStoredCredentialForInitialLayout()
        startNetworkMonitor()
    }

    deinit {
        networkMonitor.cancel()
    }

    func start() async {
        guard !didStart else {
            return
        }
        didStart = true
        await load(startsAutomaticRuntimeUpdate: false)
        await loadStoredCredential()
    }

    func continueStartupAfterWindowReveal() async {
        await continueStartupAfterInitialLoad(awaitsRuntimeUpdate: false)
    }

    func continueStartupForQuickLaunch() async {
        await continueStartupAfterInitialLoad(awaitsRuntimeUpdate: true)
    }

    private func continueStartupAfterInitialLoad(awaitsRuntimeUpdate: Bool) async {
        guard didStart, !didContinueStartupAfterWindowReveal else {
            return
        }

        guard !credentialAccessDenied else {
            return
        }
        didContinueStartupAfterWindowReveal = true

        if LauncherPreferences.automaticallyCheckRuntimeUpdates {
            if awaitsRuntimeUpdate {
                startAutomaticRuntimeUpdate()
                let updateTask = runtimeUpdateTask
                await updateTask?.value
            } else {
                startAutomaticRuntimeUpdate()
            }
        }
        guard credential != nil, LauncherPreferences.automaticallyCheckGameUpdates else {
            return
        }
        await fetchLatest()
    }

    var canQuickLaunchSelectedVersion: Bool {
        credential != nil && canUseSelectedVersion && !credentialAccessDenied
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
            installedVersions = try registry.load()
            selectedVersion = installedVersions.first
            refreshSelectedVersionCompatibility()
            refreshInstalledRuntimeState()
            if startsAutomaticRuntimeUpdate && LauncherPreferences.automaticallyCheckRuntimeUpdates {
                startAutomaticRuntimeUpdate()
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
                statusText = "Signed in as \(email). Checking latest Google Play version"
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
        statusText = "Requesting Keychain access"
        await loadStoredCredential()
        await continueStartupAfterWindowReveal()
    }

    func signOut() {
        do {
            try credentialStore.clearCredential()
            let legacyStateCleanupSucceeded = clearLegacyGooglePlayStateForSignOut()
            credential = nil
            didTryLoadingStoredCredential = false
            credentialAccessDenied = false
            latestVersion = nil
            googlePlayLatestVersion = nil
            downloadState = DownloadState()
            errorText = nil
            if legacyStateCleanupSucceeded {
                updateWarningText = nil
                statusText = "Signed out."
            } else {
                updateWarningText = "Signed out, but old Google Play state could not be fully removed. Sign in will recreate it."
                statusText = "Signed out with legacy Google Play cleanup warning."
            }
        } catch {
            show(error)
        }
    }

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
            statusText = "Runtime deleted."
            return true
        } catch {
            show(error)
            return false
        }
    }

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
            installedVersions = []
            selectedVersion = nil
            latestVersion = nil
            googlePlayLatestVersion = nil
            downloadState = DownloadState()
            errorText = nil
            updateWarningText = nil
            statusText = "Installed games deleted."
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
            return true
        } catch {
            show(error)
            return false
        }
    }

    func completeLogin(email: String, userID: String, oauthToken: String) async -> Bool {
        do {
            try Task.checkCancellation()
            errorText = nil
            updateWarningText = nil
            downloadState = DownloadState(phase: .authenticating)
            statusText = "Completing Google Play sign in"
            let coordinator = LoginCoordinator(
                googlePlay: makeGooglePlayClient(),
                credentialStore: credentialStore
            )
            let savedCredential = try await coordinator.completeLogin(
                email: email,
                userID: userID,
                oauthToken: oauthToken
            )
            try Task.checkCancellation()
            credential = savedCredential
            credentialAccessDenied = false
            didTryLoadingStoredCredential = true
            downloadState = DownloadState()
            errorText = nil
            statusText = "Signed in as \(displayEmail(for: savedCredential.email)). Checking latest Google Play version"
            await fetchLatest()
            return true
        } catch is CancellationError {
            if downloadState.phase == .authenticating {
                downloadState = DownloadState()
            }
            if credential == nil {
                statusText = selectedVersion == nil ? "Sign in to Google Play to download Minecraft." : "Ready."
            }
            return false
        } catch {
            downloadState = DownloadState(versionName: latestVersion?.versionName, phase: .failed, error: error.localizedDescription)
            show(error)
            return false
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
            let resolution = try await resolveDownloadableVersion(credential: credential)
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
            }
            downloadState = DownloadState(versionName: downloadable.versionName)
            errorText = nil
            if let installed = installedVersions.first(where: { $0.versionCode == downloadable.versionCode }) {
                selectedVersion = installed
                statusText = "\(downloadable.versionName) is already installed."
            } else if resolution.usedSupportedFallback {
                statusText = "Using latest macOS-supported Minecraft version: \(downloadable.versionName)."
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

    private func resolveDownloadableVersion(credential: GoogleCredential) async throws -> MinecraftVersionResolution {
        let downloadCoordinator = makeMinecraftDownloadCoordinator()
        let latest: LatestVersion
        let usedSupportedFallback: Bool
        do {
            latest = try await downloadCoordinator.latestVersion(credential: credential)
            googlePlayLatestVersion = latest
            usedSupportedFallback = false
        } catch {
            latest = try await supportedVersionFallback(after: error)
            googlePlayLatestVersion = nil
            usedSupportedFallback = true
            updateWarningText = "Latest Google Play version unavailable"
        }
        let downloadable = try await downloadableVersion(for: latest)
        return MinecraftVersionResolution(
            reportedLatest: latest,
            downloadable: downloadable,
            usedSupportedFallback: usedSupportedFallback
        )
    }

    private func supportedVersionFallback(after error: Error) async throws -> LatestVersion {
        guard canUseSupportedVersionFallback(after: error) else {
            throw error
        }
        let metadata = try await ensureCompatibilityPatch()
        newestSupportedVersion = metadata.newestSupportedVersion
        guard let supported = metadata.newestSupportedVersion else {
            throw error
        }
        return LatestVersion(
            packageName: MinecraftDownloadCoordinator.packageName,
            versionName: supported.versionName,
            versionCode: supported.versionCode,
            isBeta: false
        )
    }

    private func canUseSupportedVersionFallback(after error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("DF-DFERH-01")
    }

    func refreshVersionInfo() async {
        if !isRuntimeBusy {
            startAutomaticRuntimeUpdate()
        }
        guard credential != nil else {
            return
        }
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

    private func startNetworkMonitor() {
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
                statusText = "Sign in to Google Play to download Minecraft."
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

    func cancelDownload() {
        guard downloadState.phase == .downloading else {
            return
        }
        cancelActiveDownloadWork()
        downloadState = latestVersion.map { DownloadState(versionName: $0.versionName) } ?? DownloadState()
        errorText = nil
        updateWarningText = nil
        statusText = "Download canceled."
    }

    private func cancelActiveDownloadWork() {
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
        if let state = coordinator.installedState(fallbackDetail: "Using installed runtime; runtime download canceled.") {
            runtimeState = state
        } else {
            runtimeState = RuntimeState(phase: .missing, detail: "Runtime is not installed.")
        }
        errorText = nil
        updateWarningText = nil
        statusText = "Runtime download canceled."
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
            let downloadable: LatestVersion
            if let knownVersion = latestVersion {
                downloadable = try await downloadableVersion(for: knownVersion)
            } else {
                downloadState = DownloadState(phase: .fetchingLatest)
                let resolution = try await resolveDownloadableVersion(credential: credential)
                downloadable = resolution.downloadable
                if resolution.usedSupportedFallback {
                    statusText = "Using latest macOS-supported Minecraft version: \(downloadable.versionName)."
                }
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
                return
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
                return
            }
            downloadState = DownloadState(
                versionName: downloadable.versionName,
                progress: 0.98,
                phase: .extracting,
                detail: "Preparing first launch"
            )
            let patchPath = try await compatibilityPatchPath(for: installed)
            try applyCompatibilityLibraryPatches(to: installed, patchPath: patchPath)
            if let runtimePath = await ensureRuntimeForUse() {
                let credentialsHelperDirectory = credentialsHelperURL().deletingLastPathComponent()
                let dataPath = paths.minecraftDataURL
                let cachePath = paths.minecraftCacheURL
                try applyRuntimeClientPreferences(dataPath: dataPath)
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
            }
            try removeObsoleteMinecraftFiles(keeping: installed)
            try registry.save([installed])
            installedVersions = try registry.load()
            selectedVersion = installed
            refreshSelectedVersionCompatibility()
            activeDownloadID = nil
            activeDownloadOutputURL = nil
            downloadState = DownloadState(versionName: downloadable.versionName, progress: 1, phase: .installed)
            lastDownloadProgressEventDate = nil
            lastDownloadProgressBytes = 0
            errorText = nil
            updateWarningText = nil
            statusText = "Installed \(downloadable.versionName)."
        } catch is CancellationError {
            guard activeDownloadID == downloadID else {
                return
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
            statusText = "Download canceled."
            scheduleDownloadOutputCleanup(outputURL)
        } catch {
            guard activeDownloadID == downloadID else {
                return
            }
            activeDownloadID = nil
            activeDownloadOutputURL = nil
            downloadStallTask?.cancel()
            downloadStallTask = nil
            lastDownloadProgressEventDate = nil
            lastDownloadProgressBytes = 0
            downloadState = DownloadState(phase: .failed, error: error.localizedDescription)
            show(error)
        }
    }

    func playSelected(captureLog: Bool = false, allowsRunningGame: Bool = false) async {
        guard !isLaunchingGame else {
            return
        }
        do {
            errorText = nil
            isBlockingNetworkUnavailable = false
            updateWarningText = nil
            guard let selectedVersion else {
                statusText = "Install a version first."
                return
            }
            if !allowsRunningGame, isMinecraftAlreadyRunning {
                pendingRunningGameLaunch = PendingGameLaunch(captureLog: captureLog)
                isShowingRunningGameWarning = true
                statusText = "Minecraft is already running."
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
            statusText = "Launching \(selectedVersion.versionName)"
            let credentialsHelperDirectory = credentialsHelperURL().deletingLastPathComponent()
            guard let googleCredential = try loadStoredCredentialIfNeeded() else {
                throw LauncherError.missingCredential
            }
            let logURL = captureLog ? launchLogURL(for: selectedVersion) : nil
            let dataPath = paths.minecraftDataURL
            let cachePath = paths.minecraftCacheURL
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
                statusText = "Launching \(selectedVersion.versionName)"
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
            if let logURL {
                statusText = "Minecraft exited. Log: \(logURL.path)"
            } else {
                statusText = "Minecraft exited."
            }
        } catch {
            isLaunchingGame = false
            downloadState = DownloadState(versionName: selectedVersion?.versionName, phase: .failed, error: error.localizedDescription)
            show(error)
        }
    }

    func cancelRunningGameWarning() {
        pendingRunningGameLaunch = nil
        isShowingRunningGameWarning = false
        statusText = "Minecraft is already running."
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

    private func prepareFirstLaunchUntilReady(
        launcher: RuntimeLauncher,
        runtimePath: URL,
        version: InstalledVersion,
        patchPath: URL,
        dataPath: URL,
        cachePath: URL,
        credentialsHelperDirectory: URL,
        googleCredential: GoogleCredential,
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
            statusText = detail

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

    private func firstLaunchTokenURL(dataPath: URL) -> URL {
        dataPath.appendingPathComponent("pass.token", isDirectory: false)
    }

    private func applyRuntimeClientPreferences(dataPath: URL) throws {
        let settingsStore = RuntimeClientSettingsStore()
        try settingsStore.setInGameStatusBarEnabled(
            LauncherPreferences.showInGameStatusBar,
            dataPath: dataPath
        )
        try settingsStore.setFPSHUDVisibility(
            LauncherPreferences.fpsCounterVisibility,
            dataPath: dataPath
        )
        try settingsStore.setVSyncEnabled(
            LauncherPreferences.vSyncEnabled,
            dataPath: dataPath
        )
    }

    private func syncRuntimeClientPreferencesFromDisk() throws {
        let settingsStore = RuntimeClientSettingsStore()
        if let isEnabled = try settingsStore.inGameStatusBarEnabled(dataPath: paths.minecraftDataURL) {
            UserDefaults.standard.set(isEnabled, forKey: LauncherPreferences.showInGameStatusBarKey)
        }
        if let fpsHUDVisibility = try settingsStore.fpsHUDVisibility(dataPath: paths.minecraftDataURL) {
            UserDefaults.standard.set(fpsHUDVisibility.rawValue, forKey: LauncherPreferences.fpsCounterVisibilityKey)
        }
        if let vSyncEnabled = try settingsStore.vSyncEnabled(dataPath: paths.minecraftDataURL) {
            UserDefaults.standard.set(vSyncEnabled, forKey: LauncherPreferences.vSyncEnabledKey)
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

    private func preloadLocalStateForInitialLayout() throws {
        try paths.ensureDirectories()
        try syncRuntimeClientPreferencesFromDisk()
        installedVersions = try registry.load()
        selectedVersion = installedVersions.first
        refreshSelectedVersionCompatibility()
        refreshInstalledRuntimeState()
    }

    private func preloadStoredCredentialForInitialLayout() {
        do {
            didTryLoadingStoredCredential = true
            credential = try credentialStore.loadCredential()
        } catch {
            didTryLoadingStoredCredential = false
        }
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
        FinskyGooglePlayClient()
    }

    private func signOutLegacyCredentialIfNeeded() {
        guard credential?.finskyCredential == nil, credential != nil else {
            return
        }
        try? credentialStore.clearCredential()
        credential = nil
        didTryLoadingStoredCredential = true
    }

    private func clearLegacyGooglePlayStateForSignOut() -> Bool {
        do {
            try paths.removeLegacyGooglePlayState()
            return true
        } catch {
            let cleanupError = SignOutLegacyGooglePlayStateCleanupError(
                url: paths.legacyGooglePlayStateURL,
                underlyingError: error
            )
            NSLog("%@", cleanupError.localizedDescription)
            writeLastErrorLog(cleanupError)
            return false
        }
    }

    private func makeMinecraftDownloadCoordinator() -> MinecraftDownloadCoordinator {
        MinecraftDownloadCoordinator(
            googlePlay: makeGooglePlayClient(),
            processRunner: processRunner
        )
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
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(fallbackDetail: "Using installed runtime.") {
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
        let hasRuntime = manager.hasInstalledRuntime()
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(fallbackDetail: "Using installed runtime.") {
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

    private func ensureRuntimeForUse() async -> URL? {
        let launcher = RuntimeLauncher(processRunner: processRunner)
        let current = runtimeURL()
        if (try? launcher.runtimeExecutable(in: current)) != nil {
            return current
        }
        await installRuntime(forceStatus: "Downloading runtime", phase: .downloading)
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
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        if let state = coordinator.installedState(fallbackDetail: "Using installed runtime; update skipped.") {
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
        let coordinator = RuntimeInstallCoordinator(manager: manager)
        let updateID = UUID()
        activeRuntimeUpdateID = updateID
        runtimeSkipDelayTask?.cancel()
        runtimeSkipDelayTask = nil
        canSkipRuntimeUpdateCheck = false
        lastRuntimeProgressUpdate = nil
        errorText = nil
        updateWarningText = nil
        isBlockingNetworkUnavailable = false
        statusText = forceStatus
        runtimeState = RuntimeState(phase: phase, version: runtimeState.version, detail: forceStatus)
        if allowsSkip {
            runtimeSkipDelayTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard self?.activeRuntimeUpdateID == updateID,
                          self?.runtimeState.phase == .checking else {
                        return
                    }
                    self?.canSkipRuntimeUpdateCheck = true
                }
            }
        }
        do {
            let metadata: RuntimeMetadata
            if allowsSkip {
                let release = try await coordinator.resolveLatestRelease()
                try Task.checkCancellation()
                canSkipRuntimeUpdateCheck = false
                metadata = try await coordinator.install(release, progress: runtimeDownloadProgress)
            } else {
                metadata = try await coordinator.installLatest(progress: runtimeDownloadProgress)
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
            if let state = coordinator.installedState(fallbackDetail: "Using installed runtime; update skipped.") {
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

    private func startDownloadStallWatch(versionName: String) {
        downloadStallTask?.cancel()
        downloadStallTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let shouldStop = await MainActor.run {
                    guard let self,
                          self.downloadState.phase == .downloading,
                          self.downloadState.versionName == versionName else {
                        return true
                    }

                    let bytesReceived = self.downloadState.bytesReceived ?? 0
                    let lastProgressDate = self.lastDownloadProgressEventDate ?? Date()
                    let timeout: TimeInterval = bytesReceived > 0 ? 30 : 10
                    guard Date().timeIntervalSince(lastProgressDate) >= timeout else {
                        return false
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
                    self.statusText = message
                    return true
                }
                if shouldStop {
                    break
                }
            }
        }
    }

    private func runtimeDownloadStatusText(for progress: DownloadProgress) -> String {
        guard let total = progress.totalBytes, total > 0 else {
            return "Downloading runtime"
        }
        let percent = Double(progress.bytesReceived) / Double(total) * 100
        return String(format: "Downloading runtime %.1f%%", percent)
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
        try await makeMinecraftDownloadCoordinator().checkDownloadAccess(
            for: version,
            credential: credential,
            outputDirectory: probeURL
        )
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
            detail: "Extracting APK files"
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

    private func show(_ error: Error) {
        writeLastErrorLog(error)
        let issue = LauncherIssue(error: error)
        reduceError(.present(
            error: error,
            blocksNetworkUnavailable: shouldShowBlockingNetworkUnavailable(for: issue)
        ))
        statusText = error.localizedDescription
    }

    private func writeLastErrorLog(_ error: Error) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        \(stamp)
        \(type(of: error))
        \(error.localizedDescription)

        """
        do {
            try FileManager.default.createDirectory(at: paths.logsURL, withIntermediateDirectories: true)
            // Single-slot postmortem; historical launch output uses timestamped launch logs.
            try Data(content.utf8).write(
                to: paths.logsURL.appendingPathComponent("last-error.log", isDirectory: false),
                options: [.atomic]
            )
        } catch {
            // Best-effort diagnostic only; do not mask the original user-facing error.
        }
    }

    private func shouldShowBlockingNetworkUnavailable(for issue: LauncherIssue) -> Bool {
        guard selectedVersion == nil || !isRuntimeReady else {
            return false
        }
        return issue.isNetworkUnavailable
    }

    private func reduceError(_ action: LauncherErrorAction) {
        LauncherErrorReducer.reduce(&errorState, action: action)
    }
}
