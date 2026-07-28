import AppKit
import MinecraftBedrockLauncherCore
import SwiftUI

@MainActor
enum LauncherApplicationBootstrap {
    static func run() {
        let instanceCoordinator = LauncherInstanceCoordinator()

        switch instanceCoordinator.role {
        case .primary:
            LauncherPrimaryInstanceContext.coordinator = instanceCoordinator
            MinecraftBedrockLauncherApp.main()
        case .secondary:
            let application = NSApplication.shared
            let delegate = SecondaryInstanceApplicationDelegate(
                instanceCoordinator: instanceCoordinator
            )
            application.delegate = delegate
            application.setActivationPolicy(.prohibited)
            application.run()
            withExtendedLifetime(delegate) {}
        case .failed(let message):
            instanceCoordinator.shutdown()
            presentStartupFailure(message)
        }
    }

    private static func presentStartupFailure(_ message: String) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could not start Minecraft Bedrock Launcher"
        alert.informativeText = message
        alert.runModal()
    }
}

@MainActor
private final class SecondaryInstanceApplicationDelegate: NSObject, NSApplicationDelegate {
    private let instanceCoordinator: LauncherInstanceCoordinator
    private var activationFallbackTask: Task<Void, Never>?
    private var receivedOpenURLs = false

    init(instanceCoordinator: LauncherInstanceCoordinator) {
        self.instanceCoordinator = instanceCoordinator
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduleActivationFallback()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        forwardToPrimary(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        activationFallbackTask?.cancel()
        instanceCoordinator.shutdown()
    }

    private func forwardToPrimary(_ urls: [URL]) {
        receivedOpenURLs = receivedOpenURLs || !urls.isEmpty
        activationFallbackTask?.cancel()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if !(await instanceCoordinator.forward(urls)) {
                presentForwardingFailure(urls: urls)
            }
            NSApp.terminate(nil)
        }
    }

    private func scheduleActivationFallback() {
        activationFallbackTask?.cancel()
        activationFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled, !receivedOpenURLs else {
                return
            }
            activationFallbackTask = nil
            forwardToPrimary([])
        }
    }

    private func presentForwardingFailure(urls: [URL]) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = urls.isEmpty
            ? "Could not activate Minecraft Bedrock Launcher"
            : "Could not send Minecraft content to the running launcher"
        alert.informativeText = "The running launcher did not acknowledge the request. Quit it and try again."
        alert.runModal()
    }
}
