import AppKit
import Foundation
import MinecraftBedrockLauncherCore
import CoreGraphics
import Network

enum QuickLaunchState: Equatable {
    case inactive
    case starting
    case waitingForRuntime
    case waitingForLauncherUpdate
    case waitingForGameUpdate
    case ready
    case launching

    var isActive: Bool {
        self != .inactive
    }
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var credential: GoogleCredential?
    @Published var latestVersion: LatestVersion?
    @Published var googlePlayLatestVersion: LatestVersion?
    @Published var newestSupportedVersion: SupportedMinecraftVersion?
    @Published var selectedVersion: InstalledVersion? {
        didSet {
            refreshSelectedVersionCompatibility()
        }
    }
    @Published var downloadState = DownloadState()
    @Published var runtimeState = RuntimeState()
    @Published var errorState = LauncherErrorState()
    @Published var updateWarningText: String?
    @Published var credentialAccessDenied = false
    @Published var selectedVersionWarning: String?
    @Published var isLaunchingGame = false
    @Published var quickLaunchState = QuickLaunchState.inactive
    @Published var isCheckingLauncherUpdates = false
    @Published var showingLogin = false
    @Published var isShowingRunningGameWarning = false
    @Published var canSkipRuntimeUpdateCheck = false
    @Published var isDeletingRuntime = false
    @Published var isDeletingGame = false
    @Published var isDeletingData = false
    @Published var isImportingContent = false
    @Published var importingContentDescription: ContentImportDescription?
    @Published var contentImportProgress: ContentImportProgress?

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

    var isGameLaunchBlocked: Bool {
        isGooglePlayBusy || isRuntimeBusy || isLaunchingGame || isImportingContent || isCheckingLauncherUpdates
    }

    var isRuntimeReady: Bool {
        runtimeState.phase == .ready
    }

    var isQuickLaunchActive: Bool {
        quickLaunchState.isActive
    }

    var canUseSelectedVersion: Bool {
        selectedVersion != nil && selectedVersionWarning == nil
    }

    var canQuickLaunchSelectedVersion: Bool {
        canUseSelectedVersion && !credentialAccessDenied
    }

    var canStartQuickLaunch: Bool {
        !credentialAccessDenied
            && (selectedVersion != nil
                || (credential != nil && LauncherPreferences.canAutomaticallyInstallGameUpdates))
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

    let paths: AppPaths
    let credentialStore: CredentialStore
    let registry: InstalledVersionRegistry
    let processRunner: ProcessRunning
    let networkMonitor = NWPathMonitor()
    let networkMonitorQueue = DispatchQueue(label: "MinecraftBedrockLauncher.NetworkMonitor")
    var didStart = false
    var didContinueStartupAfterWindowReveal = false
    var didTryLoadingStoredCredential = false
    var runtimeUpdateTask: Task<Void, Never>?
    var runtimeSkipDelayTask: Task<Void, Never>?
    var quickLaunchTask: Task<Void, Never>?
    var activeRuntimeUpdateID: UUID?
    var activeGameUpdateCheckID: UUID?
    var shouldSkipNextAutomaticGameUpdateCheck = false
    var lastDownloadProgressUpdate: Date?
    var lastDownloadProgressEventDate: Date?
    var lastDownloadProgressBytes: Int64 = 0
    var lastRuntimeProgressUpdate: Date?
    var downloadStallTask: Task<Void, Never>?
    var activeDownloadTask: Task<Void, Never>?
    var activeDownloadID: UUID?
    var activeDownloadOutputURL: URL?
    var pendingRunningGameLaunch: PendingGameLaunch?
    var activeContentImportURLs: [URL] = []
    var pendingContentImportURLs: [URL] = []
    var completedContentImportFileCount = 0

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
        startNetworkMonitor()
    }

    deinit {
        networkMonitor.cancel()
    }
}
