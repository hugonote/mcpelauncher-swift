import Foundation

public struct LastLaunchedVersion: Codable, Equatable, Sendable {
    public var versionName: String
    public var versionCode: Int
    public var launchedAt: Date

    public init(versionName: String, versionCode: Int, launchedAt: Date = Date()) {
        self.versionName = versionName
        self.versionCode = versionCode
        self.launchedAt = launchedAt
    }
}

public struct WorldBackupManager: @unchecked Sendable {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let maximumBackupCount: Int
    private let now: @Sendable () -> Date

    public init(
        paths: AppPaths,
        fileManager: FileManager = .default,
        maximumBackupCount: Int = 5,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.maximumBackupCount = maximumBackupCount
        self.now = now
    }

    public func lastLaunchedVersion() -> LastLaunchedVersion? {
        guard let data = try? Data(contentsOf: paths.lastLaunchedVersionURL) else {
            return nil
        }
        return try? JSONDecoder().decode(LastLaunchedVersion.self, from: data)
    }

    public func recordLaunch(of version: InstalledVersion) throws {
        let record = LastLaunchedVersion(versionName: version.versionName, versionCode: version.versionCode, launchedAt: now())
        try fileManager.createDirectory(at: paths.baseURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: paths.lastLaunchedVersionURL, options: [.atomic])
    }

    public func isDowngrade(to version: InstalledVersion) -> Bool {
        guard let last = lastLaunchedVersion() else {
            return false
        }
        return version.versionCode < last.versionCode
    }

    @discardableResult
    public func backupWorldsIfDowngrading(to version: InstalledVersion) throws -> URL? {
        guard isDowngrade(to: version), let last = lastLaunchedVersion(), hasWorlds() else {
            return nil
        }
        let backupURL = paths.worldBackupsURL.appendingPathComponent(
            "\(Self.timestamp(now())) \(last.versionName) to \(version.versionName)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: paths.minecraftWorldsURL,
            to: backupURL.appendingPathComponent(paths.minecraftWorldsURL.lastPathComponent, isDirectory: true)
        )
        try pruneOldBackups()
        return backupURL
    }

    public func backups() throws -> [URL] {
        guard fileManager.fileExists(atPath: paths.worldBackupsURL.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: paths.worldBackupsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func hasWorlds() -> Bool {
        let worlds = (try? fileManager.contentsOfDirectory(
            at: paths.minecraftWorldsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return !worlds.isEmpty
    }

    private func pruneOldBackups() throws {
        for backup in try backups().dropFirst(maximumBackupCount) {
            try fileManager.removeItem(at: backup)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter.string(from: date)
    }
}
