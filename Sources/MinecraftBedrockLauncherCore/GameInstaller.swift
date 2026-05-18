import Foundation

public struct GameInstaller: @unchecked Sendable {
    private let fileManager: FileManager
    private let processRunner: ProcessRunning
    private let unzipURL: URL

    public init(
        fileManager: FileManager = .default,
        processRunner: ProcessRunning = FoundationProcessRunner(),
        unzipURL: URL = URL(fileURLWithPath: "/usr/bin/unzip")
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.unzipURL = unzipURL
    }

    public func install(
        apkFiles: [URL],
        latestVersion: LatestVersion,
        versionsDirectory: URL,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> InstalledVersion {
        guard fileManager.isExecutableFile(atPath: unzipURL.path) else {
            throw LauncherError.unsupportedArchiveTool(unzipURL)
        }
        guard !apkFiles.isEmpty else {
            throw LauncherError.invalidAPK(versionsDirectory, reason: "No APK files were provided.")
        }

        try fileManager.createDirectory(at: versionsDirectory, withIntermediateDirectories: true)
        let workURL = versionsDirectory.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        let extractURL = workURL.appendingPathComponent("merged", isDirectory: true)
        let stagingURL = workURL.appendingPathComponent("staging", isDirectory: true)
        defer { try? fileManager.removeItem(at: workURL) }

        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        for (index, apkURL) in apkFiles.enumerated() {
            let partURL = stagingURL.appendingPathComponent("apk-\(index)", isDirectory: true)
            try fileManager.createDirectory(at: partURL, withIntermediateDirectories: true)
            let result = try processRunner.run(
                executableURL: unzipURL,
                arguments: ["-qq", "-o", apkURL.path, "-d", partURL.path],
                input: nil,
                currentDirectoryURL: nil,
                environment: [:]
            )
            guard result.status == 0 else {
                throw LauncherError.invalidAPK(apkURL, reason: result.stderrString)
            }
            try copyMinecraftPayload(from: partURL, to: extractURL)
            progress(Double(index + 1) / Double(apkFiles.count + 1))
        }

        let manifestURL = extractURL.appendingPathComponent("AndroidManifest.xml", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw LauncherError.invalidAPK(extractURL, reason: "AndroidManifest.xml was not found.")
        }

        let minecraftLibraryURL = extractURL
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("arm64-v8a", isDirectory: true)
            .appendingPathComponent("libminecraftpe.so", isDirectory: false)
        guard fileManager.fileExists(atPath: minecraftLibraryURL.path) else {
            throw LauncherError.noCompatibleMinecraftLibrary(extractURL)
        }

        let targetURL = versionsDirectory.appendingPathComponent(latestVersion.versionName, isDirectory: true)
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.moveItem(at: extractURL, to: targetURL)
        progress(1)

        return InstalledVersion(
            versionName: latestVersion.versionName,
            versionCode: latestVersion.versionCode,
            installPath: targetURL
        )
    }

    public func install(
        downloadedAPKs: [DownloadedAPK],
        latestVersion: LatestVersion,
        versionsDirectory: URL,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> InstalledVersion {
        try install(
            apkFiles: downloadedAPKs.map(\.path),
            latestVersion: latestVersion,
            versionsDirectory: versionsDirectory,
            progress: progress
        )
    }

    private func copyMinecraftPayload(from sourceRoot: URL, to outputRoot: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LauncherError.invalidAPK(sourceRoot, reason: "Could not enumerate archive contents.")
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                continue
            }
            let relativePath = Self.relativePath(of: fileURL, from: sourceRoot)
            guard let mappedPath = Self.mappedMinecraftPath(relativePath) else {
                continue
            }

            let destinationURL = outputRoot.appendingPathComponent(mappedPath, isDirectory: false)
            if mappedPath == "AndroidManifest.xml", fileManager.fileExists(atPath: destinationURL.path) {
                continue
            }
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)
        }
    }

    private static func relativePath(of fileURL: URL, from rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath == rootPath {
            return ""
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(prefix.count))
    }

    private static func mappedMinecraftPath(_ relativePath: String) -> String? {
        if relativePath == "AndroidManifest.xml" {
            return relativePath
        }
        if relativePath.hasPrefix("assets/") {
            return relativePath
        }
        if relativePath.hasPrefix("res/raw/") {
            return "assets/" + String(relativePath.dropFirst("res/raw/".count))
        }
        if relativePath == "res/drawable-xxxhdpi-v4/icon.png" {
            return "assets/icon.png"
        }
        if relativePath.hasPrefix("lib/") {
            return relativePath
        }
        return nil
    }
}
