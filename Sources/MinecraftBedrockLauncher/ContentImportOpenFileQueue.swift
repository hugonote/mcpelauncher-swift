import Foundation
import MinecraftBedrockLauncherCore

@MainActor
final class ContentImportOpenFileQueue {
    static let shared = ContentImportOpenFileQueue()

    static let filesOpenedNotification = Notification.Name("local.minecraft.bedrock.swiftlauncher.contentFilesOpened")
    static let openPanelRequestedNotification = Notification.Name("local.minecraft.bedrock.swiftlauncher.contentOpenPanelRequested")

    private var pendingURLs: [URL] = []

    private init() {}

    var hasPendingURLs: Bool {
        !pendingURLs.isEmpty
    }

    func append(_ urls: [URL]) {
        let supportedURLs = urls.filter(Self.isSupportedContentURL)
        guard !supportedURLs.isEmpty else {
            return
        }
        pendingURLs.append(contentsOf: supportedURLs)
        NotificationCenter.default.post(name: Self.filesOpenedNotification, object: nil)
    }

    func takePendingURLs() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }

    func requestOpenPanel() {
        NotificationCenter.default.post(name: Self.openPanelRequestedNotification, object: nil)
    }

    static func isSupportedContentURL(_ url: URL) -> Bool {
        ContentPackImporter.isSupportedContentURL(url)
    }
}
