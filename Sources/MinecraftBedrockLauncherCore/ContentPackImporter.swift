import Foundation

public struct ContentPackImportResult: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case resourcePack = "resource pack"
        case behaviorPack = "behavior pack"
        case skinPack = "skin pack"
        case world = "world"
        case worldTemplate = "world template"
    }

    public var sourceURL: URL
    public var destinationURL: URL
    public var kind: Kind
    public var name: String
    public var compatibilityWarning: ContentPackCompatibilityWarning?

    public init(
        sourceURL: URL,
        destinationURL: URL,
        kind: Kind,
        name: String,
        compatibilityWarning: ContentPackCompatibilityWarning? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.kind = kind
        self.name = name
        self.compatibilityWarning = compatibilityWarning
    }
}

public struct ContentPackCompatibilityWarning: Equatable, Sendable {
    public var contentName: String
    public var requiredVersion: String
    public var installedVersion: String

    public init(contentName: String, requiredVersion: String, installedVersion: String) {
        self.contentName = contentName
        self.requiredVersion = requiredVersion
        self.installedVersion = installedVersion
    }
}

public struct ContentPackImporter: @unchecked Sendable {
    private let fileManager: FileManager
    private let processRunner: ProcessRunning
    private let dittoURL: URL

    public init(
        fileManager: FileManager = .default,
        processRunner: ProcessRunning = FoundationProcessRunner(),
        dittoURL: URL = URL(fileURLWithPath: "/usr/bin/ditto")
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.dittoURL = dittoURL
    }

    public static func isSupportedContentURL(_ url: URL) -> Bool {
        ContentFileType(fileURL: url) != nil
    }

    public func importContent(
        from fileURL: URL,
        paths: AppPaths,
        installedVersion: InstalledVersion? = nil
    ) throws -> [ContentPackImportResult] {
        guard fileManager.isExecutableFile(atPath: dittoURL.path) else {
            throw LauncherError.unsupportedArchiveTool(dittoURL)
        }

        let fileType = ContentFileType(fileURL: fileURL)
        guard let fileType else {
            throw LauncherError.unsupportedContentPack(fileURL)
        }

        try fileManager.createDirectory(at: paths.minecraftMojangURL, withIntermediateDirectories: true)
        let workURL = paths.baseURL
            .appendingPathComponent("ContentImports", isDirectory: true)
            .appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        let extractURL = workURL.appendingPathComponent("extract", isDirectory: true)
        defer { try? fileManager.removeItem(at: workURL) }

        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
        let result = try processRunner.run(
            executableURL: dittoURL,
            arguments: ["-x", "-k", fileURL.path, extractURL.path],
            input: nil,
            currentDirectoryURL: nil,
            environment: [:]
        )
        guard result.status == 0 else {
            throw LauncherError.contentPackImportFailed(fileURL, reason: result.stderrString)
        }

        switch fileType {
        case .world:
            let rootURL = normalizedRoot(in: extractURL)
            if isWorldRoot(rootURL) {
                return [try importWorld(from: rootURL, sourceURL: fileURL, paths: paths)]
            }
            return try importPacks(
                from: extractURL,
                sourceURL: fileURL,
                paths: paths,
                installedVersion: installedVersion,
                missingManifestReason: "level.dat was not found, and no content pack manifest.json files were found."
            )
        case .worldTemplate:
            let rootURL = normalizedRoot(in: extractURL)
            if isWorldRoot(rootURL) {
                return [try importWorldTemplate(from: rootURL, sourceURL: fileURL, paths: paths)]
            }
            return try importPacks(
                from: extractURL,
                sourceURL: fileURL,
                paths: paths,
                installedVersion: installedVersion,
                missingManifestReason: "level.dat was not found, and no content pack manifest.json files were found."
            )
        case .pack, .addon:
            return try importPacks(
                from: extractURL,
                sourceURL: fileURL,
                paths: paths,
                installedVersion: installedVersion,
                missingManifestReason: "No manifest.json files were found."
            )
        }
    }

    public func compatibilityWarnings(
        from fileURL: URL,
        paths: AppPaths,
        installedVersion: InstalledVersion?
    ) throws -> [ContentPackCompatibilityWarning] {
        guard installedVersion != nil else {
            return []
        }
        guard fileManager.isExecutableFile(atPath: dittoURL.path) else {
            throw LauncherError.unsupportedArchiveTool(dittoURL)
        }

        let fileType = ContentFileType(fileURL: fileURL)
        guard let fileType else {
            throw LauncherError.unsupportedContentPack(fileURL)
        }
        let workURL = paths.baseURL
            .appendingPathComponent("ContentImports", isDirectory: true)
            .appendingPathComponent(".preflight-\(UUID().uuidString)", isDirectory: true)
        let extractURL = workURL.appendingPathComponent("extract", isDirectory: true)
        defer { try? fileManager.removeItem(at: workURL) }

        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)
        let result = try processRunner.run(
            executableURL: dittoURL,
            arguments: ["-x", "-k", fileURL.path, extractURL.path],
            input: nil,
            currentDirectoryURL: nil,
            environment: [:]
        )
        guard result.status == 0 else {
            throw LauncherError.contentPackImportFailed(fileURL, reason: result.stderrString)
        }

        switch fileType {
        case .world, .worldTemplate:
            if isWorldRoot(normalizedRoot(in: extractURL)) {
                return []
            }
        case .pack, .addon:
            break
        }
        let packRoots = try findPackRoots(in: extractURL)
        guard !packRoots.isEmpty else {
            throw LauncherError.contentPackImportFailed(fileURL, reason: "No manifest.json files were found.")
        }
        return try packRoots.compactMap { root in
            let manifest = try readManifest(at: root)
            _ = try packKind(for: manifest, sourceURL: fileURL)
            return compatibilityWarning(for: manifest, installedVersion: installedVersion)
        }
    }

    private func importPacks(
        from extractURL: URL,
        sourceURL: URL,
        paths: AppPaths,
        installedVersion: InstalledVersion?,
        missingManifestReason: String
    ) throws -> [ContentPackImportResult] {
        let packRoots = try findPackRoots(in: extractURL)
        guard !packRoots.isEmpty else {
            throw LauncherError.contentPackImportFailed(sourceURL, reason: missingManifestReason)
        }
        return try packRoots.map { root in
            try importPack(from: root, sourceURL: sourceURL, paths: paths, installedVersion: installedVersion)
        }
    }

    private func importPack(
        from rootURL: URL,
        sourceURL: URL,
        paths: AppPaths,
        installedVersion: InstalledVersion?
    ) throws -> ContentPackImportResult {
        let manifest = try readManifest(at: rootURL)
        let kind = try packKind(for: manifest, sourceURL: sourceURL)
        let containerURL = paths.minecraftMojangURL.appendingPathComponent(kind.directoryName, isDirectory: true)
        let destinationURL = try destinationURL(
            in: containerURL,
            preferredName: manifest.header.name,
            uuid: manifest.header.uuid
        )
        try copyDirectoryReplacingExisting(from: rootURL, to: destinationURL)
        return ContentPackImportResult(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            kind: kind.resultKind,
            name: manifest.header.name,
            compatibilityWarning: compatibilityWarning(for: manifest, installedVersion: installedVersion)
        )
    }

    private func importWorld(from rootURL: URL, sourceURL: URL, paths: AppPaths) throws -> ContentPackImportResult {
        guard isWorldRoot(rootURL) else {
            throw LauncherError.contentPackImportFailed(sourceURL, reason: "level.dat was not found.")
        }
        let name = try worldName(at: rootURL) ?? rootURL.lastPathComponent
        let containerURL = paths.minecraftMojangURL.appendingPathComponent("minecraftWorlds", isDirectory: true)
        let destinationURL = try uniqueDestinationURL(in: containerURL, preferredName: name)
        try copyDirectoryReplacingExisting(from: rootURL, to: destinationURL)
        return ContentPackImportResult(sourceURL: sourceURL, destinationURL: destinationURL, kind: .world, name: name)
    }

    private func importWorldTemplate(from rootURL: URL, sourceURL: URL, paths: AppPaths) throws -> ContentPackImportResult {
        guard isWorldRoot(rootURL) else {
            throw LauncherError.contentPackImportFailed(sourceURL, reason: "level.dat was not found.")
        }
        let name = try worldName(at: rootURL) ?? rootURL.lastPathComponent
        let containerURL = paths.minecraftMojangURL.appendingPathComponent("world_templates", isDirectory: true)
        let destinationURL = try destinationURL(in: containerURL, preferredName: name, uuid: nil)
        try copyDirectoryReplacingExisting(from: rootURL, to: destinationURL)
        return ContentPackImportResult(sourceURL: sourceURL, destinationURL: destinationURL, kind: .worldTemplate, name: name)
    }

    private func findPackRoots(in rootURL: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var roots: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "manifest.json" else {
                continue
            }
            let parent = url.deletingLastPathComponent()
            roots.append(parent)
            enumerator.skipDescendants()
        }
        return roots.sorted { $0.path < $1.path }
    }

    private func normalizedRoot(in extractURL: URL) -> URL {
        if isWorldRoot(extractURL) {
            return extractURL
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: extractURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ), contents.count == 1, let onlyItem = contents.first else {
            return extractURL
        }
        let values = try? onlyItem.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true ? onlyItem : extractURL
    }

    private func readManifest(at rootURL: URL) throws -> ContentManifest {
        let manifestURL = rootURL.appendingPathComponent("manifest.json", isDirectory: false)
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(ContentManifest.self, from: data)
        } catch {
            throw LauncherError.contentPackImportFailed(rootURL, reason: "manifest.json could not be read.")
        }
    }

    private func packKind(for manifest: ContentManifest, sourceURL: URL) throws -> PackKind {
        let moduleTypes = Set(manifest.modules.map(\.type))
        if moduleTypes.contains("resources") {
            return .resource
        }
        if moduleTypes.contains("data") {
            return .behavior
        }
        if moduleTypes.contains("skin_pack") {
            return .skin
        }
        throw LauncherError.contentPackImportFailed(sourceURL, reason: "manifest.json does not describe a supported pack type.")
    }

    private func compatibilityWarning(
        for manifest: ContentManifest,
        installedVersion: InstalledVersion?
    ) -> ContentPackCompatibilityWarning? {
        guard let installedVersion,
              let required = manifest.header.minEngineVersion.flatMap(MinecraftContentVersion.init(manifestComponents:)),
              let installed = MinecraftContentVersion(versionName: installedVersion.versionName),
              installed < required else {
            return nil
        }
        return ContentPackCompatibilityWarning(
            contentName: manifest.header.name,
            requiredVersion: required.description,
            installedVersion: installedVersion.versionName
        )
    }

    private func destinationURL(in containerURL: URL, preferredName: String, uuid: String?) throws -> URL {
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        if let uuid, let existingURL = try existingPackURL(with: uuid, in: containerURL) {
            return existingURL
        }
        return try uniqueDestinationURL(in: containerURL, preferredName: preferredName)
    }

    private func existingPackURL(with uuid: String, in containerURL: URL) throws -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for url in contents {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }
            guard let manifest = try? readManifest(at: url),
                  manifest.header.uuid == uuid else {
                continue
            }
            return url
        }
        return nil
    }

    private func uniqueDestinationURL(in containerURL: URL, preferredName: String) throws -> URL {
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let baseName = sanitizedFolderName(preferredName)
        var candidate = containerURL.appendingPathComponent(baseName, isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = containerURL.appendingPathComponent("\(baseName) \(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func sanitizedFolderName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported Content" : cleaned
    }

    private func copyDirectoryReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func isWorldRoot(_ rootURL: URL) -> Bool {
        fileManager.fileExists(atPath: rootURL.appendingPathComponent("level.dat", isDirectory: false).path)
    }

    private func worldName(at rootURL: URL) throws -> String? {
        let levelNameURL = rootURL.appendingPathComponent("levelname.txt", isDirectory: false)
        guard fileManager.fileExists(atPath: levelNameURL.path) else {
            return nil
        }
        return try String(contentsOf: levelNameURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ContentFileType {
    case pack
    case addon
    case world
    case worldTemplate

    init?(fileURL: URL) {
        switch fileURL.pathExtension.lowercased() {
        case "mcpack":
            self = .pack
        case "mcaddon":
            self = .addon
        case "mcworld":
            self = .world
        case "mctemplate":
            self = .worldTemplate
        default:
            return nil
        }
    }
}

private enum PackKind {
    case resource
    case behavior
    case skin

    var directoryName: String {
        switch self {
        case .resource:
            return "resource_packs"
        case .behavior:
            return "behavior_packs"
        case .skin:
            return "skin_packs"
        }
    }

    var resultKind: ContentPackImportResult.Kind {
        switch self {
        case .resource:
            return .resourcePack
        case .behavior:
            return .behaviorPack
        case .skin:
            return .skinPack
        }
    }
}

private struct ContentManifest: Decodable {
    struct Header: Decodable {
        var name: String
        var uuid: String
        var minEngineVersion: [Int]?

        enum CodingKeys: String, CodingKey {
            case name
            case uuid
            case minEngineVersion = "min_engine_version"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            uuid = try container.decode(String.self, forKey: .uuid)
            minEngineVersion = try? container.decode([Int].self, forKey: .minEngineVersion)
        }
    }

    struct Module: Decodable {
        var type: String
    }

    var header: Header
    var modules: [Module]
}

private struct MinecraftContentVersion: Comparable, CustomStringConvertible {
    var components: [Int]

    init?(manifestComponents: [Int]) {
        let components = manifestComponents.prefix(4)
        guard !components.isEmpty, components.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        self.components = Array(components)
    }

    init?(versionName: String) {
        let components = versionName
            .split(separator: ".")
            .compactMap { part -> Int? in
                let digits = part.prefix { $0.isNumber }
                guard !digits.isEmpty else {
                    return nil
                }
                return Int(digits)
            }
        guard !components.isEmpty else {
            return nil
        }
        self.components = components
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: MinecraftContentVersion, rhs: MinecraftContentVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
