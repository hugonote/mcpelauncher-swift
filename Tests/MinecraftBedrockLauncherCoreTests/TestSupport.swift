import Foundation
@testable import MinecraftBedrockLauncherCore

final class TemporaryDirectory {
    let url: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        url = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? fileManager.removeItem(at: url)
    }
}

func makeInstalledVersion(
    in versionsURL: URL,
    name: String,
    code: Int,
    installedAt: Date = Date(),
    fileManager: FileManager = .default
) throws -> InstalledVersion {
    let installURL = versionsURL.appendingPathComponent(name, isDirectory: true)
    let libraryURL = installURL.appendingPathComponent("lib/arm64-v8a", isDirectory: true)
    try fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
    try Data("manifest".utf8).write(to: installURL.appendingPathComponent("AndroidManifest.xml"))
    try Data("elf".utf8).write(to: libraryURL.appendingPathComponent("libminecraftpe.so"))
    return InstalledVersion(versionName: name, versionCode: code, installPath: installURL, installedAt: installedAt)
}
