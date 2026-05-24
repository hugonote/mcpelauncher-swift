import CryptoKit
import Foundation

public struct RuntimeManager: @unchecked Sendable {
    public static let defaultRuntimeManifestURL = URL(
        string: "https://github.com/hugonote/mcpelauncher-swift/releases/latest/download/runtime-manifest.json"
    )!
    public static let defaultReleaseAPIURL = URL(string: "https://api.github.com/repos/minecraft-linux/mcpelauncher-manifest/releases/tags/nightly")!
    public static let stableReleaseAPIURL = URL(string: "https://api.github.com/repos/minecraft-linux/macos-builder/releases/latest")!

    private let paths: AppPaths
    private let processRunner: ProcessRunning
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(
        paths: AppPaths,
        processRunner: ProcessRunning = FoundationProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func installedMetadata() -> RuntimeMetadata? {
        guard let data = try? Data(contentsOf: paths.runtimeMetadataURL) else {
            return nil
        }
        return try? decoder.decode(RuntimeMetadata.self, from: data)
    }

    public func hasInstalledRuntime() -> Bool {
        (try? RuntimeLauncher(fileManager: fileManager, processRunner: processRunner)
            .runtimeExecutable(in: paths.runtimeURL)) != nil
    }

    public func resolveLatestRelease() async throws -> RuntimeRelease {
        if let manifestOverride = ProcessInfo.processInfo.environment["MCPELAUNCHER_RUNTIME_MANIFEST_URL"],
           !manifestOverride.isEmpty,
           let url = URL(string: manifestOverride) {
            return try await resolveRuntimeManifest(url)
        }

        if let override = ProcessInfo.processInfo.environment["MCPELAUNCHER_RUNTIME_ARCHIVE_URL"],
           !override.isEmpty,
           let url = URL(string: override) {
            return RuntimeRelease(
                version: ProcessInfo.processInfo.environment["MCPELAUNCHER_RUNTIME_VERSION"] ?? "override",
                assetName: url.lastPathComponent,
                downloadURL: url,
                sha256: ProcessInfo.processInfo.environment["MCPELAUNCHER_RUNTIME_SHA256"]
            )
        }

        do {
            return try await resolveRuntimeManifest(Self.defaultRuntimeManifestURL)
        } catch {
            return try await resolveUpstreamRelease()
        }
    }

    public func resolveUpstreamRelease() async throws -> RuntimeRelease {
        do {
            return try await resolveRelease(Self.stableReleaseAPIURL)
        } catch {
            return try await resolveRelease(Self.defaultReleaseAPIURL)
        }
    }

    public func installLatest(
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> RuntimeMetadata {
        let release = try await resolveLatestRelease()
        return try await install(release, progress: progress)
    }

    public func install(
        _ release: RuntimeRelease,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> RuntimeMetadata {
        if canReuseInstalledRuntime(for: release) {
            return installedMetadata() ?? RuntimeMetadata(
                version: release.version,
                assetName: release.assetName,
                sourceURL: release.downloadURL
            )
        }

        return try await downloadAndInstall(release, progress: progress)
    }

    private func downloadAndInstall(
        _ release: RuntimeRelease,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> RuntimeMetadata {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftBedrockRuntime-\(UUID().uuidString)", isDirectory: true)
        let downloadURL = tempRoot.appendingPathComponent(release.assetName, isDirectory: false)
        let extractURL = tempRoot.appendingPathComponent("extract", isDirectory: true)
        let mountURL = tempRoot.appendingPathComponent("mount", isDirectory: true)
        let stagingURL = paths.baseURL.appendingPathComponent("Runtime.installing", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        if fileManager.fileExists(atPath: downloadURL.path) {
            try fileManager.removeItem(at: downloadURL)
        }
        if release.downloadURL.isFileURL {
            try fileManager.copyItem(at: release.downloadURL, to: downloadURL)
        } else {
            do {
                try await download(release.downloadURL, to: downloadURL, expectedSize: release.size, progress: progress)
            } catch {
                if fileManager.fileExists(atPath: downloadURL.path) {
                    try fileManager.removeItem(at: downloadURL)
                }
                try await download(release.downloadURL, to: downloadURL, expectedSize: release.size, progress: progress)
            }
        }

        if let expected = release.sha256?.lowercased(), !expected.isEmpty {
            let actual = try sha256(of: downloadURL)
            if actual != expected {
                throw LauncherError.runtimeChecksumMismatch(expected: expected, actual: actual)
            }
        }

        try replaceDirectory(at: stagingURL)
        if downloadURL.pathExtension.lowercased() == "dmg" {
            try installRuntimeFromDMG(downloadURL, mountURL: mountURL, stagingURL: stagingURL)
        } else {
            try installRuntimeFromArchive(downloadURL, extractURL: extractURL, stagingURL: stagingURL)
        }

        try validateRuntime(at: stagingURL)
        let metadata = RuntimeMetadata(
            version: release.version,
            assetName: release.assetName,
            sourceURL: release.downloadURL
        )
        try write(metadata, into: stagingURL)
        try replaceInstalledRuntime(with: stagingURL)
        return metadata
    }

    private func download(
        _ sourceURL: URL,
        to destinationURL: URL,
        expectedSize: Int64?,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 10
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError.runtimeInstallFailed("Runtime download returned HTTP \(http.statusCode).")
        }

        let responseSize = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        let totalBytes = expectedSize ?? responseSize
        let start = Date()
        var received: Int64 = 0
        var iterator = bytes.makeAsyncIterator()
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? handle.close()
        }
        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)

        while let byte = try await iterator.next() {
            try Task.checkCancellation()
            buffer.append(byte)
            received += 1
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                progress(downloadProgress(bytesReceived: received, totalBytes: totalBytes, start: start))
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        progress(downloadProgress(bytesReceived: received, totalBytes: totalBytes, start: start))
    }

    private func downloadProgress(bytesReceived: Int64, totalBytes: Int64?, start: Date) -> DownloadProgress {
        let elapsed = Date().timeIntervalSince(start)
        let speed = elapsed > 0 ? Double(bytesReceived) / elapsed : nil
        let eta: Double?
        if let totalBytes, let speed, speed > 0, totalBytes > bytesReceived {
            eta = Double(totalBytes - bytesReceived) / speed
        } else {
            eta = nil
        }
        return DownloadProgress(
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
            etaSeconds: eta
        )
    }

    private func fetchRelease(_ url: URL) async throws -> GitHubRelease {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError.runtimeInstallFailed("GitHub release lookup returned HTTP \(http.statusCode) for \(url.absoluteString).")
        }
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func resolveRuntimeManifest(_ url: URL) async throws -> RuntimeRelease {
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            let (networkData, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LauncherError.runtimeInstallFailed("Runtime manifest lookup returned HTTP \(http.statusCode) for \(url.absoluteString).")
            }
            data = networkData
        }
        let manifest = try decoder.decode(RuntimeReleaseManifest.self, from: data)
        return try Self.runtimeRelease(from: manifest, manifestURL: url)
    }

    private func resolveRelease(_ apiURL: URL) async throws -> RuntimeRelease {
        let release = try await fetchRelease(apiURL)
        guard let asset = Self.selectRuntimeAsset(from: release.assets),
              let url = URL(string: asset.browserDownloadURL) else {
            throw LauncherError.runtimeReleaseNotFound(apiURL.absoluteString)
        }
        let build = Self.runtimeBuildNumber(from: asset.name)
        return RuntimeRelease(
            version: release.tagName == "nightly" ? "nightly-\(build)" : release.tagName,
            assetName: asset.name,
            downloadURL: url,
            sha256: asset.sha256Digest,
            size: asset.size
        )
    }

    private func installRuntimeFromDMG(_ dmgURL: URL, mountURL: URL, stagingURL: URL) throws {
        try replaceDirectory(at: mountURL)
        let attachResult = try processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["attach", dmgURL.path, "-nobrowse", "-readonly", "-mountpoint", mountURL.path],
            input: nil,
            currentDirectoryURL: nil,
            environment: [:]
        )
        guard attachResult.status == 0 else {
            throw LauncherError.runtimeInstallFailed(attachResult.stderrString)
        }
        defer {
            _ = try? processRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountURL.path, "-quiet"],
                input: nil,
                currentDirectoryURL: nil,
                environment: [:]
            )
        }
        let appURL = try findAppBundle(in: mountURL)
        try copyRuntimeFromAppBundle(appURL, to: stagingURL)
    }

    private func installRuntimeFromArchive(_ archiveURL: URL, extractURL: URL, stagingURL: URL) throws {
        try replaceDirectory(at: extractURL)
        let result = try processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractURL.path],
            input: nil,
            currentDirectoryURL: nil,
            environment: [:]
        )
        guard result.status == 0 else {
            throw LauncherError.runtimeInstallFailed(result.stderrString)
        }
        if let runtimeRoot = try findRuntimeRoot(in: extractURL) {
            try copyRuntimeContents(from: runtimeRoot, to: stagingURL)
            return
        }
        let appURL = try findAppBundle(in: extractURL)
        try copyRuntimeFromAppBundle(appURL, to: stagingURL)
    }

    private func copyRuntimeFromAppBundle(_ appURL: URL, to destinationURL: URL) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let embeddedRuntimeURL = contentsURL.appendingPathComponent("Resources/Minecraft Bedrock", isDirectory: true)
        if hasRuntime(at: embeddedRuntimeURL) {
            try copyRuntimeContents(from: embeddedRuntimeURL, to: destinationURL)
            return
        }

        let armClientURL = contentsURL.appendingPathComponent(
            "MacOS/mcpelauncher-client-arm64-v8a",
            isDirectory: false
        )
        if fileManager.isExecutableFile(atPath: armClientURL.path) {
            try copyAppleSiliconRuntime(from: contentsURL, to: destinationURL)
            return
        }

        for name in ["MacOS", "Frameworks", "Resources"] {
            let source = contentsURL.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: source.path) {
                try copyItemReplacingExisting(
                    from: source,
                    to: destinationURL.appendingPathComponent(name, isDirectory: true)
                )
            }
        }
    }

    private func copyAppleSiliconRuntime(from contentsURL: URL, to destinationURL: URL) throws {
        let binDestinationURL = destinationURL.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: binDestinationURL, withIntermediateDirectories: true)

        let executableURL = contentsURL.appendingPathComponent(
            "MacOS/mcpelauncher-client-arm64-v8a",
            isDirectory: false
        )
        try copyItemReplacingExisting(
            from: executableURL,
            to: binDestinationURL.appendingPathComponent("mcpelauncher-client", isDirectory: false)
        )

        let resourcesURL = contentsURL.appendingPathComponent("Resources/mcpelauncher", isDirectory: true)
        guard fileManager.fileExists(atPath: resourcesURL.path) else {
            throw LauncherError.runtimeInstallFailed("Runtime app bundle did not contain Resources/mcpelauncher.")
        }
        try copyItemReplacingExisting(
            from: resourcesURL,
            to: destinationURL.appendingPathComponent("share/mcpelauncher", isDirectory: true)
        )

        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        if fileManager.fileExists(atPath: frameworksURL.path) {
            try copyRuntimeFrameworks(from: frameworksURL, to: destinationURL.appendingPathComponent("Frameworks", isDirectory: true))
        }
    }

    private func copyRuntimeFrameworks(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let name = item.lastPathComponent
            guard item.pathExtension == "dylib" || name == "mvk-angle" else {
                continue
            }
            try copyItemReplacingExisting(
                from: item,
                to: destinationURL.appendingPathComponent(name, isDirectory: item.hasDirectoryPath)
            )
        }
    }

    private func copyRuntimeContents(from sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.lastPathComponent.hasSuffix(".app") {
            try copyRuntimeFromAppBundle(sourceURL, to: destinationURL)
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in contents {
            try copyItemReplacingExisting(
                from: item,
                to: destinationURL.appendingPathComponent(item.lastPathComponent)
            )
        }
    }

    private func validateRuntime(at url: URL) throws {
        _ = try RuntimeLauncher(fileManager: fileManager, processRunner: processRunner).runtimeExecutable(in: url)
        guard hasLauncherDataFiles(at: url) else {
            throw LauncherError.runtimeInstallFailed("Runtime did not contain mcpelauncher Android shim libraries.")
        }
        guard hasGraphicsFrameworks(at: url) else {
            throw LauncherError.runtimeInstallFailed("Runtime did not contain mvk-angle graphics frameworks.")
        }
    }

    private func hasRuntime(at url: URL) -> Bool {
        (try? RuntimeLauncher(fileManager: fileManager, processRunner: processRunner).runtimeExecutable(in: url)) != nil
    }

    private func canReuseInstalledRuntime(for release: RuntimeRelease) -> Bool {
        hasInstalledRuntime()
            && installedMetadata()?.version == release.version
            && hasLauncherDataFiles(at: paths.runtimeURL)
            && hasGraphicsFrameworks(at: paths.runtimeURL)
    }

    private func hasLauncherDataFiles(at runtimeURL: URL) -> Bool {
        let roots = [
            "share/mcpelauncher",
            "Resources/mcpelauncher",
            "Resources/Minecraft Bedrock/mcpelauncher-client",
            "mcpelauncher-client"
        ]
        let requiredLibraries = [
            "lib/arm64-v8a/libc.so",
            "lib/arm64-v8a/liblog.so"
        ]
        return roots.contains { root in
            let rootURL = runtimeURL.appendingPathComponent(root, isDirectory: true)
            return requiredLibraries.allSatisfy {
                fileManager.fileExists(atPath: rootURL.appendingPathComponent($0, isDirectory: false).path)
            }
        }
    }

    private func hasGraphicsFrameworks(at runtimeURL: URL) -> Bool {
        let roots = [
            runtimeURL.appendingPathComponent("Frameworks/mvk-angle", isDirectory: true),
            runtimeURL.appendingPathComponent("Resources/Minecraft Bedrock/Frameworks/mvk-angle", isDirectory: true)
        ]
        return roots.contains { root in
            fileManager.fileExists(atPath: root.appendingPathComponent("libEGL.dylib", isDirectory: false).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent("libGLESv2.dylib", isDirectory: false).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent("MoltenVK_icd.json", isDirectory: false).path)
        }
    }

    private func write(_ metadata: RuntimeMetadata, into runtimeURL: URL) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: runtimeURL.appendingPathComponent("runtime.json", isDirectory: false), options: [.atomic])
    }

    private func findAppBundle(in directoryURL: URL) throws -> URL {
        if directoryURL.pathExtension == "app" {
            return directoryURL
        }
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LauncherError.runtimeInstallFailed("Could not enumerate \(directoryURL.path).")
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }
        throw LauncherError.runtimeInstallFailed("Downloaded runtime did not contain a .app bundle.")
    }

    private func findRuntimeRoot(in directoryURL: URL) throws -> URL? {
        if hasRuntime(at: directoryURL) {
            return directoryURL
        }
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw LauncherError.runtimeInstallFailed("Could not enumerate \(directoryURL.path).")
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                continue
            }
            if hasRuntime(at: url) {
                return url
            }
        }
        return nil
    }

    private func replaceDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func replaceInstalledRuntime(with stagingURL: URL) throws {
        if fileManager.fileExists(atPath: paths.runtimeURL.path) {
            try fileManager.removeItem(at: paths.runtimeURL)
        }
        try fileManager.moveItem(at: stagingURL, to: paths.runtimeURL)
    }

    private func copyItemReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func selectRuntimeAsset(from assets: [GitHubAsset]) -> GitHubAsset? {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        let preferred = dmgAssets
            .filter {
                $0.name.contains("macOS-x86_64-0.2.") && $0.name.contains("macOS_10.13.0")
            }
            .max {
                runtimeBuildNumber(from: $0.name) < runtimeBuildNumber(from: $1.name)
            }
        if let preferred {
            return preferred
        }
        return dmgAssets
            .filter { $0.name.contains("macOS_10.13.0") }
            .max {
                runtimeBuildNumber(from: $0.name) < runtimeBuildNumber(from: $1.name)
            } ?? dmgAssets.max {
                runtimeBuildNumber(from: $0.name) < runtimeBuildNumber(from: $1.name)
            }
    }

    static func runtimeBuildNumber(from assetName: String) -> Int {
        let pattern = #"-0\.[0-9]\.(\d+)_macOS"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: assetName,
                range: NSRange(assetName.startIndex..<assetName.endIndex, in: assetName)
              ),
              let range = Range(match.range(at: 1), in: assetName),
              let value = Int(assetName[range]) else {
            return 0
        }
        return value
    }

    static func runtimeRelease(from manifest: RuntimeReleaseManifest, manifestURL: URL) throws -> RuntimeRelease {
        let baseURL = manifestURL.deletingLastPathComponent()
        guard let downloadURL = URL(string: manifest.downloadURL, relativeTo: baseURL)?.absoluteURL else {
            throw LauncherError.runtimeInstallFailed("Runtime manifest contains an invalid downloadURL.")
        }
        return RuntimeRelease(
            version: manifest.version,
            assetName: manifest.assetName ?? downloadURL.lastPathComponent,
            downloadURL: downloadURL,
            sha256: manifest.sha256,
            size: manifest.size
        )
    }
}

struct RuntimeReleaseManifest: Decodable, Equatable {
    var version: String
    var assetName: String?
    var downloadURL: String
    var sha256: String?
    var size: Int64?
}

struct GitHubRelease: Decodable {
    var tagName: String
    var assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GitHubAsset: Decodable, Equatable {
    var name: String
    var size: Int64
    var digest: String?
    var browserDownloadURL: String

    var sha256Digest: String? {
        guard let digest, digest.hasPrefix("sha256:") else {
            return nil
        }
        return String(digest.dropFirst("sha256:".count))
    }

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case digest
        case browserDownloadURL = "browser_download_url"
    }
}
