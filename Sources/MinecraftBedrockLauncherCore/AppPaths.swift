import Foundation

public struct AppPaths: Equatable, Sendable {
    public var baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public static func `default`(
        fileManager: FileManager = .default,
        applicationName: String = "Minecraft Bedrock Launcher"
    ) throws -> AppPaths {
        guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LauncherError.missingApplicationSupportDirectory
        }
        return AppPaths(baseURL: supportURL.appendingPathComponent(applicationName, isDirectory: true))
    }

    public var downloadsURL: URL {
        baseURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    public var versionsURL: URL {
        baseURL.appendingPathComponent("game-versions", isDirectory: true)
    }

    public var runtimeURL: URL {
        baseURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    public var runtimeMetadataURL: URL {
        runtimeURL.appendingPathComponent("runtime.json", isDirectory: false)
    }

    public var compatibilityPatchesURL: URL {
        baseURL.appendingPathComponent("CompatibilityPatches", isDirectory: true)
    }

    public var compatibilityPatchMetadataURL: URL {
        compatibilityPatchesURL.appendingPathComponent("mcpelauncher-updates.json", isDirectory: false)
    }

    public var contentImportsURL: URL {
        baseURL.appendingPathComponent("ContentImports", isDirectory: true)
    }

    public var minecraftDataURL: URL {
        baseURL.appendingPathComponent("MinecraftData", isDirectory: true)
    }

    public var minecraftMojangURL: URL {
        minecraftDataURL
            .appendingPathComponent("games", isDirectory: true)
            .appendingPathComponent("com.mojang", isDirectory: true)
    }

    public var logsURL: URL {
        baseURL.appendingPathComponent("Logs", isDirectory: true)
    }

    public var installedVersionsURL: URL {
        baseURL.appendingPathComponent("versions.json", isDirectory: false)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for url in [baseURL, downloadsURL, versionsURL, runtimeURL, compatibilityPatchesURL, minecraftDataURL, logsURL] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func removeStaleGameInstallDirectories(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: versionsURL.path) else {
            return
        }
        let installItems = try fileManager.contentsOfDirectory(
            at: versionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for item in installItems where item.lastPathComponent.hasPrefix(".install-") {
            try fileManager.removeItem(at: item)
        }
    }

    public func deleteGameFiles(fileManager: FileManager = .default) throws {
        for url in [versionsURL, downloadsURL, installedVersionsURL] {
            try removeItemWithRetry(at: url, fileManager: fileManager)
        }
        try fileManager.createDirectory(at: versionsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
    }

    private func removeItemWithRetry(at url: URL, fileManager: FileManager) throws {
        for attempt in 0..<3 {
            guard fileManager.fileExists(atPath: url.path) else {
                return
            }
            do {
                try fileManager.removeItem(at: url)
                return
            } catch {
                guard attempt == 2 else {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                throw error
            }
        }
    }
}

public enum LauncherError: Error, LocalizedError, Equatable {
    case missingApplicationSupportDirectory
    case googlePlayFailed(String)
    case googlePlayCredentialRequiresSignIn
    case minecraftNotOwned(account: String?)
    case missingCredential
    case invalidAPK(URL, reason: String)
    case noCompatibleMinecraftLibrary(URL)
    case missingRuntimeExecutable(URL)
    case unsupportedArchiveTool(URL)
    case runtimeReleaseNotFound(String)
    case runtimeInstallFailed(String)
    case runtimeChecksumMismatch(expected: String, actual: String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case unsupportedMinecraftVersion(versionName: String, versionCode: Int, supportedVersionName: String?, supportedVersionCode: Int?)
    case missingInstalledMinecraftVersion(URL)
    case gameLaunchFailed(status: Int32, logURL: URL?, outputTail: String)
    case unsupportedContentPack(URL)
    case contentPackImportFailed(URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            return "Could not locate the user Application Support directory."
        case .googlePlayFailed(let message):
            return "Google Play request failed: \(message)"
        case .googlePlayCredentialRequiresSignIn:
            return "Google Play credentials need to be refreshed. Sign in again."
        case .minecraftNotOwned:
            return "Minecraft is not purchased on this Google Play account."
        case .missingCredential:
            return "No saved Google Play credential is available."
        case .invalidAPK(let url, let reason):
            return "Invalid APK \(url.lastPathComponent): \(reason)"
        case .noCompatibleMinecraftLibrary(let url):
            return "No arm64-v8a libminecraftpe.so was extracted into \(url.path)."
        case .missingRuntimeExecutable(let url):
            return "Could not find mcpelauncher-client in runtime path \(url.path)."
        case .unsupportedArchiveTool(let url):
            return "The archive tool is not available or not executable: \(url.path)."
        case .runtimeReleaseNotFound(let source):
            return "Could not find a compatible runtime release at \(source)."
        case .runtimeInstallFailed(let message):
            return "Runtime install failed: \(message)"
        case .runtimeChecksumMismatch(let expected, let actual):
            return "Runtime download checksum mismatch. Expected \(expected), got \(actual)."
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "Not enough disk space. Need \(formatter.string(fromByteCount: requiredBytes)), available \(formatter.string(fromByteCount: availableBytes))."
        case .unsupportedMinecraftVersion(let versionName, let versionCode, let supportedVersionName, let supportedVersionCode):
            if let supportedVersionName, let supportedVersionCode {
                return "\(versionName) (\(versionCode)) is not supported by the current macOS compatibility patch. Latest supported version is \(supportedVersionName) (\(supportedVersionCode))."
            }
            return "\(versionName) (\(versionCode)) is not supported by the current macOS compatibility patch."
        case .missingInstalledMinecraftVersion(let url):
            return "Minecraft is not installed at \(url.path). Install the game again."
        case .gameLaunchFailed(let status, let logURL, let outputTail):
            let logText = logURL.map { " Log: \($0.path)." } ?? ""
            let tailText = outputTail.isEmpty ? "" : " Last output: \(outputTail)"
            return "Minecraft exited with status \(status).\(logText)\(tailText)"
        case .unsupportedContentPack(let url):
            return "Unsupported Minecraft content file: \(url.lastPathComponent)."
        case .contentPackImportFailed(let url, let reason):
            return "Could not import \(url.lastPathComponent): \(reason)"
        }
    }
}
