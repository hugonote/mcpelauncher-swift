import Foundation

public struct CompatibilityPatchManager: @unchecked Sendable {
    public static let defaultModDBURL = URL(string: "https://raw.githubusercontent.com/minecraft-linux/mcpelauncher-moddb/main/moddb.json")!
    public static let abi = "arm64-v8a"

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

    public func installedMetadata() -> CompatibilityPatchMetadata? {
        guard let data = try? Data(contentsOf: paths.compatibilityPatchMetadataURL) else {
            return nil
        }
        return try? decoder.decode(CompatibilityPatchMetadata.self, from: data)
    }

    public func installedPatchPath(for versionCode: Int) -> URL? {
        guard let metadata = installedMetadata(),
              metadata.supports(versionCode: versionCode),
              fileManager.isExecutableFile(atPath: metadata.installPath.appendingPathComponent("libmcpelauncher-updates.so").path) else {
            return nil
        }
        return metadata.installPath
    }

    public func applyLibraryPatches(from patchPath: URL, to version: InstalledVersion) throws {
        for patch in try libraryPatches(from: patchPath, to: version) {
            guard fileManager.fileExists(atPath: patch.destination.path),
                  try !filesIdentical(patch.source, patch.destination) else {
                continue
            }

            let backupURL = patch.destination.deletingPathExtension().appendingPathExtension("so.bck")
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.copyItem(at: patch.destination, to: backupURL)
            }
            try fileManager.removeItem(at: patch.destination)
            try fileManager.copyItem(at: patch.source, to: patch.destination)
        }
    }

    public func unappliedLibraryPatchNames(from patchPath: URL, to version: InstalledVersion) throws -> [String] {
        try libraryPatches(from: patchPath, to: version).compactMap { patch in
            guard fileManager.fileExists(atPath: patch.destination.path),
                  try !filesIdentical(patch.source, patch.destination) else {
                return nil
            }
            return patch.destination.lastPathComponent
        }
    }

    private func libraryPatches(from patchPath: URL, to version: InstalledVersion) throws -> [LibraryPatch] {
        let patchRoot = patchPath.appendingPathComponent("patches", isDirectory: true)
        guard fileManager.fileExists(atPath: patchRoot.path),
              let enumerator = fileManager.enumerator(
                at: patchRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let libraryRoot = version.installPath
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent(Self.abi, isDirectory: true)

        var patches: [LibraryPatch] = []
        for case let sourceURL as URL in enumerator {
            let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  sourceURL.pathExtension == "so",
                  sourceURL.deletingLastPathComponent().lastPathComponent == Self.abi else {
                continue
            }

            let destinationURL = libraryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
            patches.append(LibraryPatch(source: sourceURL, destination: destinationURL))
        }
        return patches
    }

    public func installedNewestSupportedVersion() -> SupportedMinecraftVersion? {
        installedMetadata()?.newestSupportedVersion
    }

    public func resolveLatestPatch() async throws -> CompatibilityPatchRelease {
        let (data, response) = try await URLSession.shared.data(from: Self.defaultModDBURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError.runtimeInstallFailed("Compatibility moddb lookup returned HTTP \(http.statusCode).")
        }
        let entries = try decoder.decode([ModDBEntry].self, from: data)
        guard let entry = entries.first(where: { $0.name == "mcpelauncher-updates" }) else {
            throw LauncherError.runtimeInstallFailed("mcpelauncher-updates was not found in moddb.")
        }
        guard let version = entry.versions
            .filter({ $0.assets[Self.abi] != nil })
            .max(by: { newestSupportedCode(in: $0) < newestSupportedCode(in: $1) }),
              let rawAssetURL = version.assets[Self.abi],
              let assetURL = URL(string: rawAssetURL) else {
            throw LauncherError.runtimeInstallFailed("mcpelauncher-updates did not contain an \(Self.abi) asset.")
        }

        let supportedVersions = version.extraVersions
            .compactMap { extra -> SupportedMinecraftVersion? in
                guard let code = extra.codes[Self.abi] else { return nil }
                return SupportedMinecraftVersion(versionName: extra.versionName, versionCode: code)
            }
            .sorted { $0.versionCode < $1.versionCode }

        return CompatibilityPatchRelease(entry: entry, version: version, assetURL: assetURL, supportedVersions: supportedVersions)
    }

    public func installLatest() async throws -> CompatibilityPatchMetadata {
        let patch = try await resolveLatestPatch()
        let installPath = paths.compatibilityPatchesURL
            .appendingPathComponent(patch.version.version, isDirectory: true)
            .appendingPathComponent(Self.abi, isDirectory: true)

        if let metadata = installedMetadata(),
           metadata.version == patch.version.version,
           fileManager.isExecutableFile(atPath: metadata.installPath.appendingPathComponent("libmcpelauncher-updates.so").path) {
            return metadata
        }

        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftBedrockCompatibility-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = tempRoot.appendingPathComponent(patch.assetURL.lastPathComponent, isDirectory: false)
        let extractURL = tempRoot.appendingPathComponent("extract", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        let (downloadedURL, response) = try await URLSession.shared.download(from: patch.assetURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError.runtimeInstallFailed("Compatibility patch download returned HTTP \(http.statusCode).")
        }
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)

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

        try replaceDirectory(at: installPath)
        try copyDirectoryContents(from: extractURL, to: installPath)
        try writeModManifest(patch, to: installPath.appendingPathComponent("mod.json", isDirectory: false))
        let patchLibraryURL = installPath.appendingPathComponent("libmcpelauncher-updates.so", isDirectory: false)
        if fileManager.fileExists(atPath: patchLibraryURL.path) {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: patchLibraryURL.path)
        }
        guard fileManager.isExecutableFile(atPath: patchLibraryURL.path) else {
            throw LauncherError.runtimeInstallFailed("Compatibility patch did not contain libmcpelauncher-updates.so.")
        }

        let metadata = CompatibilityPatchMetadata(
            version: patch.version.version,
            assetURL: patch.assetURL,
            installPath: installPath,
            supportedVersions: patch.supportedVersions
        )
        try write(metadata)
        return metadata
    }

    private func writeModManifest(_ patch: CompatibilityPatchRelease, to url: URL) throws {
        let manifest = InstalledModManifest(
            arch: Self.abi,
            metadata: InstalledModMetadata(
                description: patch.entry.description,
                image: patch.entry.image,
                name: patch.entry.name,
                url: patch.entry.url,
                versions: patch.entry.versions
            ),
            version: patch.version
        )
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    private func write(_ metadata: CompatibilityPatchMetadata) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: paths.compatibilityPatchMetadataURL, options: [.atomic])
    }

    private func filesIdentical(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsData = try Data(contentsOf: lhs)
        let rhsData = try Data(contentsOf: rhs)
        return lhsData == rhsData
    }

    private func replaceDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in contents {
            let destination = destinationURL.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: item, to: destination)
        }
    }

    private func newestSupportedCode(in version: ModDBVersion) -> Int {
        version.extraVersions.compactMap { $0.codes[Self.abi] }.max() ?? 0
    }
}

public struct CompatibilityPatchRelease: Equatable, Sendable {
    var entry: ModDBEntry
    var version: ModDBVersion
    public var assetURL: URL
    public var supportedVersions: [SupportedMinecraftVersion]
}

struct InstalledModManifest: Codable, Equatable {
    var arch: String
    var metadata: InstalledModMetadata
    var version: ModDBVersion
}

struct InstalledModMetadata: Codable, Equatable {
    var description: String
    var image: String
    var name: String
    var url: String
    var versions: [ModDBVersion]
}

struct ModDBEntry: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var url: String
    var image: String
    var versions: [ModDBVersion]
}

struct ModDBVersion: Codable, Equatable, Sendable {
    var version: String
    var assets: [String: String]
    var minecraft: String?
    var extraVersions: [ModDBExtraVersion]

    enum CodingKeys: String, CodingKey {
        case version
        case assets
        case minecraft
        case extraVersions
    }

    init(version: String, assets: [String: String], minecraft: String? = nil, extraVersions: [ModDBExtraVersion] = []) {
        self.version = version
        self.assets = assets
        self.minecraft = minecraft
        self.extraVersions = extraVersions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        assets = try container.decodeIfPresent([String: String].self, forKey: .assets) ?? [:]
        minecraft = try container.decodeIfPresent(String.self, forKey: .minecraft)
        extraVersions = try container.decodeIfPresent([ModDBExtraVersion].self, forKey: .extraVersions) ?? []
    }
}

struct ModDBExtraVersion: Codable, Equatable, Sendable {
    var versionName: String
    var codes: [String: Int]

    enum CodingKeys: String, CodingKey {
        case versionName = "version_name"
        case codes
    }
}

private struct LibraryPatch {
    var source: URL
    var destination: URL
}
