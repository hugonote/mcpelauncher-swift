import AppKit
import Darwin
import MinecraftBedrockLauncherCore
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let openExistingInstanceNotification = Notification.Name(
        "local.minecraft.bedrock.swiftlauncher.openExistingInstance"
    )
    nonisolated private static let openedContentPathsKey = "openedContentPaths"

    private var updaterController: SPUStandardUpdaterController?
    private let instanceLock = LauncherSingleInstanceLock()
    private var openExistingInstanceObserver: NSObjectProtocol?
    private var secondaryTerminationTask: Task<Void, Never>?
    private var secondaryReceivedOpenURLs = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        StartupLaunchModifiers.capture()

        guard instanceLock.acquire() else {
            LauncherProcessRole.isSecondaryInstance = true
            StartupWindowVisibility.shared.hideUntilStartupCompletes()
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenExistingInstanceNotification(_:)),
            name: Self.openExistingInstanceNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        openExistingInstanceObserver = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LauncherPreferences.registerDefaults()
        StartupWindowVisibility.shared.hideUntilStartupCompletes()

        guard !LauncherProcessRole.isSecondaryInstance else {
            scheduleSecondaryRevealFallback()
            return
        }

        guard AppUpdateConfiguration.isEnabled else {
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = LauncherPreferences.automaticallyCheckLauncherUpdates
        updaterController = controller
        controller.startUpdater()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ChildProcessRegistry.shared.terminateAll()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        secondaryTerminationTask?.cancel()
        ChildProcessRegistry.shared.terminateAll()
        if let openExistingInstanceObserver {
            DistributedNotificationCenter.default().removeObserver(openExistingInstanceObserver)
        }
        instanceLock.release()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        guard !LauncherProcessRole.isSecondaryInstance else {
            secondaryReceivedOpenURLs = true
            postOpenExistingInstanceNotification(contentURLs: urls)
            scheduleSecondaryTermination()
            return
        }
        ContentImportOpenFileQueue.shared.append(urls)
        StartupWindowVisibility.shared.revealLauncherWindow()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handleOpenedContentURLs([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handleOpenedContentURLs(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: .success)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    @objc private func handleOpenExistingInstanceNotification(_ notification: Notification) {
        let openedContentURLs = Self.contentURLs(from: notification.userInfo)
        Task { @MainActor in
            if let urls = openedContentURLs {
                ContentImportOpenFileQueue.shared.append(urls)
            }
            StartupWindowVisibility.shared.revealLauncherWindow()
        }
    }

    private func handleOpenedContentURLs(_ urls: [URL]) {
        guard !LauncherProcessRole.isSecondaryInstance else {
            secondaryReceivedOpenURLs = true
            postOpenExistingInstanceNotification(contentURLs: urls)
            scheduleSecondaryTermination()
            return
        }
        ContentImportOpenFileQueue.shared.append(urls)
        StartupWindowVisibility.shared.revealLauncherWindow()
    }

    private func postOpenExistingInstanceNotification(contentURLs urls: [URL] = []) {
        let paths = urls.filter(\.isFileURL).map(\.path)
        let userInfo = paths.isEmpty ? nil : [Self.openedContentPathsKey: paths]
        DistributedNotificationCenter.default().postNotificationName(
            Self.openExistingInstanceNotification,
            object: nil,
            userInfo: userInfo,
            options: [.deliverImmediately]
        )
    }

    nonisolated private static func contentURLs(from userInfo: [AnyHashable: Any]?) -> [URL]? {
        guard let paths = userInfo?[openedContentPathsKey] as? [String] else {
            return nil
        }
        let urls = paths.map(URL.init(fileURLWithPath:))
        return urls.isEmpty ? nil : urls
    }

    private func scheduleSecondaryRevealFallback() {
        secondaryTerminationTask?.cancel()
        secondaryTerminationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !secondaryReceivedOpenURLs {
                postOpenExistingInstanceNotification()
            }
            NSApp.terminate(nil)
        }
    }

    private func scheduleSecondaryTermination() {
        secondaryTerminationTask?.cancel()
        secondaryTerminationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            NSApp.terminate(nil)
        }
    }
}

@MainActor
enum LauncherProcessRole {
    static var isSecondaryInstance = false
}

private final class LauncherSingleInstanceLock {
    private let lockURL: URL
    private var descriptor: Int32 = -1

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        lockURL = supportURL
            .appendingPathComponent("Minecraft Bedrock Launcher", isDirectory: true)
            .appendingPathComponent("launcher.lock", isDirectory: false)
    }

    func acquire(fileManager: FileManager = .default) -> Bool {
        guard descriptor < 0 else {
            return true
        }

        do {
            try fileManager.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return true
        }

        let lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard lockDescriptor >= 0 else {
            return true
        }

        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            close(lockDescriptor)
            return lockError == EWOULDBLOCK ? false : true
        }

        descriptor = lockDescriptor
        return true
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
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

    private var shouldHideMainWindow = false

    private init() {}

    func hideUntilStartupCompletes() {
        shouldHideMainWindow = true
        NSApp.windows.forEach(hideIfNeeded)
    }

    func hideIfNeeded(_ window: NSWindow) {
        guard shouldHideMainWindow, isLauncherWindow(window) else {
            return
        }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    func reveal(_ window: NSWindow?) {
        shouldHideMainWindow = false
        guard let window else {
            return
        }
        window.ignoresMouseEvents = false
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func revealLauncherWindow() {
        shouldHideMainWindow = false
        let window = NSApp.windows.first(where: isLauncherWindow) ?? NSApp.windows.first
        guard let window else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window.ignoresMouseEvents = false
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func isLauncherWindow(_ window: NSWindow) -> Bool {
        window.title == "Minecraft Bedrock Launcher" || window.contentView != nil
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

@main
struct MinecraftBedrockLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LauncherViewModel()
    @Environment(\.openWindow) private var openWindow

    init() {
        LauncherPreferences.registerDefaults()
    }

    var body: some Scene {
        Window("Minecraft Bedrock Launcher", id: "main") {
            ContentView(model: model)
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
