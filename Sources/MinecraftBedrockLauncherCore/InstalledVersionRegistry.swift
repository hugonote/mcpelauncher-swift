import Foundation

public final class InstalledVersionRegistry: @unchecked Sendable {
    private let registryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(registryURL: URL, fileManager: FileManager = .default) {
        self.registryURL = registryURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public convenience init(paths: AppPaths, fileManager: FileManager = .default) {
        self.init(registryURL: paths.installedVersionsURL, fileManager: fileManager)
    }

    public func load() throws -> [InstalledVersion] {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return []
        }
        let data = try Data(contentsOf: registryURL)
        return try decoder.decode([InstalledVersion].self, from: data)
            .filter { isInstalled($0) }
            .sorted { $0.installedAt > $1.installedAt }
    }

    public func save(_ versions: [InstalledVersion]) throws {
        try fileManager.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(versions.sorted { $0.installedAt > $1.installedAt })
        try data.write(to: registryURL, options: [.atomic])
    }

    public func isInstalled(_ version: InstalledVersion) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: version.installPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let manifestURL = version.installPath.appendingPathComponent("AndroidManifest.xml", isDirectory: false)
        let libraryURL = version.installPath
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("arm64-v8a", isDirectory: true)
            .appendingPathComponent("libminecraftpe.so", isDirectory: false)

        return fileManager.fileExists(atPath: manifestURL.path)
            && fileManager.fileExists(atPath: libraryURL.path)
    }
}
