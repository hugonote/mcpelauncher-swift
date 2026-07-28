import AppKit
import MinecraftBedrockLauncherCore
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var updaterController: SPUStandardUpdaterController?
    private var instanceCoordinator: LauncherInstanceCoordinator?
    private weak var model: LauncherViewModel?
    private var initialStartupTask: Task<Void, Never>?
    private var didFinishLaunching = false

    @Published private(set) var isInitialStartupComplete = false

    func configure(model: LauncherViewModel, instanceCoordinator: LauncherInstanceCoordinator) {
        precondition(instanceCoordinator.role.isPrimary)
        self.model = model
        self.instanceCoordinator = instanceCoordinator
        instanceCoordinator.setRequestHandler { [weak self] urls in
            Task { @MainActor [weak self] in
                self?.handleForwardedRequest(urls)
            }
        }
        if didFinishLaunching {
            startInitialStartupIfNeeded()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        StartupLaunchModifiers.capture()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LauncherPreferences.registerDefaults()
        didFinishLaunching = true

        if ContentImportOpenFileQueue.shared.hasPendingURLs {
            StartupWindowVisibility.shared.revealLauncherWindow()
        } else {
            StartupWindowVisibility.shared.hideUntilStartupCompletes()
        }

        if AppUpdateConfiguration.isEnabled {
            let updateCheckGate = LauncherUpdateCheckGate.shared
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: updateCheckGate,
                userDriverDelegate: nil
            )
            let automaticallyChecksForLauncherUpdates = LauncherPreferences.automaticallyCheckLauncherUpdates
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForLauncherUpdates
            updaterController = controller
            controller.startUpdater()
            if shouldForceLauncherUpdateCheckDuringQuickLaunch(controller.updater) {
                updateCheckGate.startQuickLaunchCheck(updater: controller.updater)
            }
        }

        startInitialStartupIfNeeded()
    }

    private func shouldForceLauncherUpdateCheckDuringQuickLaunch(_ updater: SPUUpdater) -> Bool {
        guard updater.automaticallyChecksForUpdates,
              LauncherPreferences.quickLaunch,
              !StartupLaunchModifiers.didHoldOption else {
            return false
        }
        guard let lastUpdateCheckDate = updater.lastUpdateCheckDate else {
            return true
        }
        return Date().timeIntervalSince(lastUpdateCheckDate) >= updater.updateCheckInterval
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        StartupWindowVisibility.shared.shouldTerminateAfterLastWindowClosed
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ChildProcessRegistry.shared.terminateAll()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        initialStartupTask?.cancel()
        ChildProcessRegistry.shared.terminateAll()
        instanceCoordinator?.shutdown()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        ContentImportOpenFileQueue.shared.append(urls)
        StartupWindowVisibility.shared.revealLauncherWindow()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    private func handleForwardedRequest(_ urls: [URL]) {
        if !urls.isEmpty {
            ContentImportOpenFileQueue.shared.append(urls)
        }
        StartupWindowVisibility.shared.revealLauncherWindow()
    }

    private func startInitialStartupIfNeeded() {
        guard !isInitialStartupComplete,
              initialStartupTask == nil,
              let model else {
            return
        }

        initialStartupTask = Task { @MainActor [weak self, weak model] in
            guard let self, let model else {
                return
            }
            await model.start()
            guard !Task.isCancelled else {
                return
            }

            if LauncherPreferences.quickLaunch,
               !StartupLaunchModifiers.didHoldOption,
               !ContentImportOpenFileQueue.shared.hasPendingURLs,
               model.canStartQuickLaunch {
                model.beginQuickLaunch()
            }

            isInitialStartupComplete = true
            await Task.yield()
            StartupWindowVisibility.shared.startupDidFinish()
        }
    }
}

@MainActor
enum LauncherPrimaryInstanceContext {
    static var coordinator: LauncherInstanceCoordinator?
}

@MainActor
enum StartupLaunchModifiers {
    private(set) static var didHoldOption = false

    static func capture() {
        didHoldOption = isOptionPressed
    }

    static var isOptionPressed: Bool {
        NSEvent.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.option)
    }
}

@MainActor
final class StartupWindowVisibility {
    static let shared = StartupWindowVisibility()

    private static let launcherWindowTitle = "Minecraft Bedrock Launcher"

    private weak var launcherWindow: NSWindow?
    private var shouldHideMainWindow = true
    private var startupHasCompleted = false

    private init() {}

    var shouldTerminateAfterLastWindowClosed: Bool {
        startupHasCompleted
    }

    func hideUntilStartupCompletes() {
        guard !startupHasCompleted else {
            return
        }
        shouldHideMainWindow = true
        if launcherWindow == nil,
           let window = NSApp.windows.first(where: isLauncherWindow) {
            attachLauncherWindow(window)
        } else if let launcherWindow {
            hide(launcherWindow)
        }
    }

    func attachLauncherWindow(_ window: NSWindow) {
        if launcherWindow !== window {
            launcherWindow = window
        }

        if shouldHideMainWindow && !startupHasCompleted {
            hide(window)
        } else {
            restoreVisibility(of: window)
        }
    }

    func startupDidFinish() {
        startupHasCompleted = true
        revealLauncherWindow()
    }

    func reveal(_ window: NSWindow?) {
        shouldHideMainWindow = false
        guard let window else {
            revealLauncherWindow()
            return
        }
        attachLauncherWindow(window)
        show(window)
    }

    func revealLauncherWindow() {
        shouldHideMainWindow = false
        let window = launcherWindow ?? NSApp.windows.first(where: isLauncherWindow)
        guard let window else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        attachLauncherWindow(window)
        show(window)
    }

    private func hide(_ window: NSWindow) {
        restoreVisibility(of: window)
        window.orderOut(nil)
    }

    private func restoreVisibility(of window: NSWindow) {
        window.ignoresMouseEvents = false
        window.alphaValue = 1
    }

    private func show(_ window: NSWindow) {
        restoreVisibility(of: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    private func isLauncherWindow(_ window: NSWindow) -> Bool {
        window.title == Self.launcherWindowTitle
    }
}

enum AppUpdateConfiguration {
    static var isEnabled: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return !feedURL.isEmpty && !publicKey.isEmpty
    }
}

@MainActor
final class LauncherUpdateCheckGate: NSObject, SPUUpdaterDelegate {
    static let shared = LauncherUpdateCheckGate()

    private enum QuickLaunchCheckState {
        case idle
        case checking
        case updateFound
        case finished
    }

    private var quickLaunchCheckState = QuickLaunchCheckState.idle
    private var pendingContinuations: [CheckedContinuation<Bool, Never>] = []
    private var shouldShowFoundUpdate = false
    private weak var quickLaunchUpdater: SPUUpdater?

    func startQuickLaunchCheck(updater: SPUUpdater) {
        guard case .idle = quickLaunchCheckState else {
            return
        }
        quickLaunchUpdater = updater
        quickLaunchCheckState = .checking
        updater.checkForUpdateInformation()
    }

    func allowsQuickLaunchAfterLauncherUpdateCheck() async -> Bool {
        switch quickLaunchCheckState {
        case .idle, .finished:
            return true
        case .updateFound:
            return false
        case .checking:
            return await withCheckedContinuation { continuation in
                pendingContinuations.append(continuation)
            }
        }
    }

    @objc(updater:didFindValidUpdate:)
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard updater === quickLaunchUpdater,
              case .checking = quickLaunchCheckState else {
            return
        }
        shouldShowFoundUpdate = true
        finishQuickLaunchCheck(allowsQuickLaunch: false)
    }

    @objc(updaterDidNotFindUpdate:)
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        guard updater === quickLaunchUpdater,
              case .checking = quickLaunchCheckState else {
            return
        }
        finishQuickLaunchCheck(allowsQuickLaunch: true)
    }

    @objc(updaterDidNotFindUpdate:error:)
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        guard updater === quickLaunchUpdater,
              case .checking = quickLaunchCheckState else {
            return
        }
        finishQuickLaunchCheck(allowsQuickLaunch: true)
    }

    @objc(updater:didAbortWithError:)
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard updater === quickLaunchUpdater,
              case .checking = quickLaunchCheckState else {
            return
        }
        finishQuickLaunchCheck(allowsQuickLaunch: true)
    }

    @objc(updater:didFinishUpdateCycleForUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard updater === quickLaunchUpdater,
              updateCheck == .updateInformation else {
            return
        }
        if shouldShowFoundUpdate {
            shouldShowFoundUpdate = false
            updater.checkForUpdates()
            return
        }
        guard case .checking = quickLaunchCheckState else {
            return
        }
        finishQuickLaunchCheck(allowsQuickLaunch: true)
    }

    private func finishQuickLaunchCheck(allowsQuickLaunch: Bool) {
        if allowsQuickLaunch {
            quickLaunchCheckState = .finished
        } else {
            quickLaunchCheckState = .updateFound
        }
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume(returning: allowsQuickLaunch) }
    }

}

struct MinecraftBedrockLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: LauncherViewModel
    @Environment(\.openWindow) private var openWindow

    init() {
        guard let instanceCoordinator = LauncherPrimaryInstanceContext.coordinator else {
            preconditionFailure("Primary instance coordinator was not configured.")
        }
        LauncherPreferences.registerDefaults()
        let model = LauncherViewModel()
        _model = StateObject(wrappedValue: model)
        appDelegate.configure(model: model, instanceCoordinator: instanceCoordinator)
    }

    var body: some Scene {
        Window("Minecraft Bedrock Launcher", id: "main") {
            ContentView(model: model, appDelegate: appDelegate)
                .frame(
                    minWidth: model.preferredWindowWidth,
                    idealWidth: model.preferredWindowWidth,
                    maxWidth: model.preferredWindowWidth,
                    minHeight: 280,
                    idealHeight: 280,
                    maxHeight: 280
                )
                .fixedSize()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Minecraft Bedrock Launcher") {
                    openWindow(id: "about")
                }
            }

            if AppUpdateConfiguration.isEnabled {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates...") {
                        appDelegate.checkForUpdates(nil)
                    }
                }
            }

            CommandMenu("Game") {
                Button {
                    Task { await model.playSelected(captureLog: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!canPlayFromGameMenu)

                Button {
                    Task { await model.playSelected(captureLog: true) }
                } label: {
                    Text("Play & Log")
                }
                .disabled(!canPlayFromGameMenu)

                Divider()

                Button {
                    NSWorkspace.shared.open(model.dataFolderURL)
                } label: {
                    Text("Open Data Folder")
                }

                Button {
                    ContentImportOpenFileQueue.shared.requestOpenPanel()
                } label: {
                    Label("Import Minecraft Content...", systemImage: "square.and.arrow.down")
                }
            }
        }

        Settings {
            SettingsView(model: model)
        }

        Window("About Minecraft Bedrock Launcher", id: "about") {
            AboutView()
                .fixedSize()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private var canPlayFromGameMenu: Bool {
        model.canUseSelectedVersion
            && model.isRuntimeReady
            && !model.isGameLaunchBlocked
    }
}
