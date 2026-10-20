import Foundation

public struct InstalledMod: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case catalog
        case local
    }

    public var id: String { name }

    public var name: String
    public var version: String
    public var summary: String?
    public var minecraftRequirement: String?
    public var source: Source
    public var installPath: URL
    public var installedAt: Date

    public init(
        name: String,
        version: String,
        summary: String? = nil,
        minecraftRequirement: String? = nil,
        source: Source,
        installPath: URL,
        installedAt: Date = Date()
    ) {
        self.name = name
        self.version = version
        self.summary = summary
        self.minecraftRequirement = minecraftRequirement
        self.source = source
        self.installPath = installPath
        self.installedAt = installedAt
    }

    public func supports(versionName: String) -> Bool {
        minecraftRequirement.flatMap(MinecraftVersionRequirement.init)?.isSatisfied(by: versionName) ?? true
    }
}

public struct ModManager: @unchecked Sendable {
    public typealias Downloader = @Sendable (URL) async throws -> URL

    public static let abi = CompatibilityPatchManager.abi

    private let paths: AppPaths
    private let fileManager: FileManager
    private let extractor: ZipArchiveExtractor
    private let downloader: Downloader
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(
        paths: AppPaths,
        processRunner: ProcessRunning = FoundationProcessRunner(),
        fileManager: FileManager = .default,
        downloader: @escaping Downloader = ModManager.urlSessionDownload
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.extractor = ZipArchiveExtractor(processRunner: processRunner)
        self.downloader = downloader
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func installableCatalogEntries(_ entries: [ModDBEntry]) -> [ModDBEntry] {
        entries
            .filter { $0.name != CompatibilityPatchManager.patchModName && $0.newestVersion(for: abi) != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func installedMods() throws -> [InstalledMod] {
        guard fileManager.fileExists(atPath: paths.installedModsURL.path) else {
            return []
        }
        return try decoder.decode([InstalledMod].self, from: Data(contentsOf: paths.installedModsURL))
            .filter { !libraryURLs(in: $0.installPath).isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func install(_ entry: ModDBEntry) async throws -> InstalledMod {
        guard let version = entry.newestVersion(for: Self.abi),
              let assetURL = version.assetURL(for: Self.abi) else {
            throw LauncherError.modInstallFailed(entry.name, reason: "No \(Self.abi) build is available.")
        }
        let archiveURL = try await downloader(assetURL)
        defer {
            try? fileManager.removeItem(at: archiveURL)
        }
        return try installArchive(
            archiveURL,
            mod: InstalledMod(
                name: entry.name,
                version: version.version,
                summary: entry.description,
                minecraftRequirement: version.minecraft,
                source: .catalog,
                installPath: installPath(name: entry.name, version: version.version)
            )
        )
    }

    public func importLocal(_ url: URL) throws -> InstalledMod {
        let name = url.deletingPathExtension().lastPathComponent
        let mod = InstalledMod(
            name: name,
            version: InstalledMod.Source.local.rawValue,
            source: .local,
            installPath: installPath(name: name, version: InstalledMod.Source.local.rawValue)
        )
        switch url.pathExtension.lowercased() {
        case "so":
            return try installLibraries([url], mod: mod)
        case "zip":
            return try installArchive(url, mod: mod)
        default:
            throw LauncherError.modInstallFailed(url.lastPathComponent, reason: "Choose a .so library or a .zip archive.")
        }
    }

    public func remove(_ mod: InstalledMod) throws {
        let modRoot = paths.modsURL.appendingPathComponent(Self.directoryName(for: mod.name), isDirectory: true)
        if fileManager.fileExists(atPath: modRoot.path) {
            try fileManager.removeItem(at: modRoot)
        }
        try saveInstalledMods(try installedMods().filter { $0.name != mod.name })
        var enabled = try enabledModNames()
        for versionName in enabled.keys {
            enabled[versionName]?.removeAll { $0 == mod.name }
        }
        try saveEnabledModNames(enabled)
    }

    public func enabledModNames(for versionName: String) throws -> Set<String> {
        Set(try enabledModNames()[versionName] ?? [])
    }

    public func setEnabled(_ isEnabled: Bool, mod: InstalledMod, versionName: String) throws {
        var enabled = try enabledModNames()
        var names = Set(enabled[versionName] ?? [])
        if isEnabled {
            names.insert(mod.name)
        } else {
            names.remove(mod.name)
        }
        enabled[versionName] = names.sorted()
        try saveEnabledModNames(enabled)
    }

    public func enabledModPaths(for versionName: String) throws -> [URL] {
        let enabled = try enabledModNames(for: versionName)
        return try installedMods()
            .filter { enabled.contains($0.name) && $0.supports(versionName: versionName) }
            .map(\.installPath)
    }

    private func installArchive(_ archiveURL: URL, mod: InstalledMod) throws -> InstalledMod {
        let extractURL = fileManager.temporaryDirectory
            .appendingPathComponent("MinecraftBedrockMod-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: extractURL)
        }
        try extractor.extract(archiveURL, to: extractURL)
        guard let libraryDirectory = libraryDirectory(in: extractURL) else {
            throw LauncherError.modInstallFailed(mod.name, reason: "The archive does not contain an \(Self.abi) .so library.")
        }
        return try installLibraries(libraryURLs(in: libraryDirectory), mod: mod)
    }

    private func installLibraries(_ libraries: [URL], mod: InstalledMod) throws -> InstalledMod {
        let modRoot = paths.modsURL.appendingPathComponent(Self.directoryName(for: mod.name), isDirectory: true)
        if fileManager.fileExists(atPath: modRoot.path) {
            try fileManager.removeItem(at: modRoot)
        }
        try fileManager.createDirectory(at: mod.installPath, withIntermediateDirectories: true)
        for library in libraries {
            let destination = mod.installPath.appendingPathComponent(library.lastPathComponent, isDirectory: false)
            try fileManager.copyItem(at: library, to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
        try saveInstalledMods(try installedMods().filter { $0.name != mod.name } + [mod])
        return mod
    }

    private func libraryDirectory(in rootURL: URL) -> URL? {
        if !libraryURLs(in: rootURL).isEmpty {
            return rootURL
        }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let directories = enumerator
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let abiDirectory = directories.first { $0.lastPathComponent == Self.abi && !libraryURLs(in: $0).isEmpty }
        return abiDirectory ?? directories.first { !libraryURLs(in: $0).isEmpty }
    }

    private func libraryURLs(in directoryURL: URL) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "so" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func installPath(name: String, version: String) -> URL {
        paths.modsURL
            .appendingPathComponent(Self.directoryName(for: name), isDirectory: true)
            .appendingPathComponent(Self.directoryName(for: version), isDirectory: true)
            .appendingPathComponent(Self.abi, isDirectory: true)
    }

    private func enabledModNames() throws -> [String: [String]] {
        guard fileManager.fileExists(atPath: paths.enabledModsURL.path) else {
            return [:]
        }
        return try decoder.decode([String: [String]].self, from: Data(contentsOf: paths.enabledModsURL))
    }

    private func saveInstalledMods(_ mods: [InstalledMod]) throws {
        try write(mods.sorted { $0.name < $1.name }, to: paths.installedModsURL)
    }

    private func saveEnabledModNames(_ enabled: [String: [String]]) throws {
        try write(enabled.filter { !$0.value.isEmpty }, to: paths.enabledModsURL)
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: [.atomic])
    }

    static func directoryName(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return sanitized.isEmpty || sanitized.hasPrefix(".") ? "mod-\(sanitized)" : sanitized
    }

    public static func urlSessionDownload(_ url: URL) async throws -> URL {
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError.modInstallFailed(url.lastPathComponent, reason: "Download returned HTTP \(http.statusCode).")
        }
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinecraftBedrockModDownload-\(UUID().uuidString).zip", isDirectory: false)
        try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
        return archiveURL
    }
}
