import Foundation

public enum LauncherBundleValidator {
    public static let requiredHelperNames = [
        "mcpelauncher-ui-qt",
        "mcpelauncher-webview",
        "mcpelauncher-client-wrapper"
    ]

    public static func isIncomplete(
        at bundleURL: URL,
        resourcesAvailable: Bool,
        fileManager: FileManager = .default
    ) -> Bool {
        guard bundleURL.pathExtension == "app" else {
            return false
        }
        let helpersURL = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        return !resourcesAvailable || requiredHelperNames.contains {
            !fileManager.isExecutableFile(atPath: helpersURL.appendingPathComponent($0).path)
        }
    }
}
