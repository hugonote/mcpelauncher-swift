import Foundation
@testable import MinecraftBedrockLauncherCore
import XCTest

final class ContentPackImporterTests: XCTestCase {
    func testImportsResourcePackIntoMojangResourcePacksDirectory() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for import")
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("App", isDirectory: true))
        let packURL = try makePackArchive(
            in: temp.url,
            extension: "mcpack",
            name: "Clean Textures",
            uuid: "11111111-1111-1111-1111-111111111111",
            moduleType: "resources"
        )

        let results = try ContentPackImporter().importContent(from: packURL, paths: paths)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .resourcePack)
        let targetURL = paths.minecraftMojangURL.appendingPathComponent("resource_packs/Clean Textures", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("textures/blocks/stone.png").path))
    }

    func testImportsResourcePackAndWarnsWhenMinEngineVersionExceedsInstalledVersion() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for import")
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("App", isDirectory: true))
        let packURL = try makePackArchive(
            in: temp.url,
            extension: "mcpack",
            name: "Future Textures",
            uuid: "44444444-4444-4444-4444-444444444444",
            moduleType: "resources",
            minEngineVersion: [1, 21, 0]
        )
        let installedVersion = InstalledVersion(
            versionName: "1.20.80",
            versionCode: 1,
            installPath: temp.url.appendingPathComponent("Installed", isDirectory: true)
        )
        let importer = ContentPackImporter()
        let targetURL = paths.minecraftMojangURL.appendingPathComponent("resource_packs/Future Textures", isDirectory: true)

        let warnings = try importer.compatibilityWarnings(
            from: packURL,
            paths: paths,
            installedVersion: installedVersion
        )

        XCTAssertEqual(warnings, [ContentPackCompatibilityWarning(
            contentName: "Future Textures",
            requiredVersion: "1.21.0",
            installedVersion: "1.20.80"
        )])
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))

        let results = try importer.importContent(
            from: packURL,
            paths: paths,
            installedVersion: installedVersion
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.compatibilityWarning, ContentPackCompatibilityWarning(
            contentName: "Future Textures",
            requiredVersion: "1.21.0",
            installedVersion: "1.20.80"
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("manifest.json").path))
    }

    func testImportsResourcePackRenamedAsWorldByInspectingManifest() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for import")
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("App", isDirectory: true))
        let packURL = try makePackArchive(
            in: temp.url,
            extension: "mcworld",
            name: "Renamed Textures",
            uuid: "55555555-5555-5555-5555-555555555555",
            moduleType: "resources",
            minEngineVersion: [1, 21, 0]
        )
        let installedVersion = InstalledVersion(
            versionName: "1.20.80",
            versionCode: 1,
            installPath: temp.url.appendingPathComponent("Installed", isDirectory: true)
        )
        let importer = ContentPackImporter()

        let warnings = try importer.compatibilityWarnings(
            from: packURL,
            paths: paths,
            installedVersion: installedVersion
        )
        let results = try importer.importContent(
            from: packURL,
            paths: paths,
            installedVersion: installedVersion
        )

        XCTAssertEqual(warnings.first?.contentName, "Renamed Textures")
        XCTAssertEqual(results.first?.kind, .resourcePack)
        let targetURL = paths.minecraftMojangURL.appendingPathComponent("resource_packs/Renamed Textures", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("manifest.json").path))
    }

    func testImportsAddonPacksAndReplacesExistingPackWithSameUUID() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for import")
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("App", isDirectory: true))
        let resourceUUID = "22222222-2222-2222-2222-222222222222"
        let behaviorUUID = "33333333-3333-3333-3333-333333333333"
        let addonURL = try makeAddonArchive(
            in: temp.url,
            resourceUUID: resourceUUID,
            behaviorUUID: behaviorUUID,
            resourceVersion: "old"
        )

        let firstResults = try ContentPackImporter().importContent(from: addonURL, paths: paths)
        XCTAssertEqual(firstResults.count, 2)
        let resourceURL = paths.minecraftMojangURL.appendingPathComponent("resource_packs/Addon Resources", isDirectory: true)
        XCTAssertEqual(try String(contentsOf: resourceURL.appendingPathComponent("marker.txt")), "old")

        let updatedAddonURL = try makeAddonArchive(
            in: temp.url,
            resourceUUID: resourceUUID,
            behaviorUUID: behaviorUUID,
            resourceVersion: "new"
        )
        _ = try ContentPackImporter().importContent(from: updatedAddonURL, paths: paths)

        XCTAssertEqual(try String(contentsOf: resourceURL.appendingPathComponent("marker.txt")), "new")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths.minecraftMojangURL.appendingPathComponent("behavior_packs/Addon Behavior/manifest.json").path
        ))
    }

    func testImportsWorldIntoMinecraftWorldsDirectory() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for import")
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("App", isDirectory: true))
        let worldURL = try makeWorldArchive(in: temp.url, name: "Survival Base")

        let results = try ContentPackImporter().importContent(from: worldURL, paths: paths)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .world)
        let targetURL = paths.minecraftMojangURL.appendingPathComponent("minecraftWorlds/Survival Base", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.appendingPathComponent("level.dat").path))
        XCTAssertEqual(try String(contentsOf: targetURL.appendingPathComponent("levelname.txt")), "Survival Base")
    }

    private func makePackArchive(
        in rootURL: URL,
        extension fileExtension: String,
        name: String,
        uuid: String,
        moduleType: String,
        minEngineVersion: [Int] = [1, 20, 0]
    ) throws -> URL {
        let sourceURL = rootURL.appendingPathComponent("pack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceURL.appendingPathComponent("textures/blocks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try manifest(name: name, uuid: uuid, moduleType: moduleType, minEngineVersion: minEngineVersion).write(
            to: sourceURL.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data("png".utf8).write(to: sourceURL.appendingPathComponent("textures/blocks/stone.png"))
        return try zipDirectory(sourceURL, to: rootURL.appendingPathComponent("\(UUID().uuidString).\(fileExtension)"))
    }

    private func makeAddonArchive(
        in rootURL: URL,
        resourceUUID: String,
        behaviorUUID: String,
        resourceVersion: String
    ) throws -> URL {
        let sourceURL = rootURL.appendingPathComponent("addon-\(UUID().uuidString)", isDirectory: true)
        let resourceURL = sourceURL.appendingPathComponent("resources", isDirectory: true)
        let behaviorURL = sourceURL.appendingPathComponent("behavior", isDirectory: true)
        try FileManager.default.createDirectory(at: resourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: behaviorURL, withIntermediateDirectories: true)
        try manifest(name: "Addon Resources", uuid: resourceUUID, moduleType: "resources").write(
            to: resourceURL.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try manifest(name: "Addon Behavior", uuid: behaviorUUID, moduleType: "data").write(
            to: behaviorURL.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try resourceVersion.write(to: resourceURL.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        return try zipDirectory(sourceURL, to: rootURL.appendingPathComponent("\(UUID().uuidString).mcaddon"))
    }

    private func makeWorldArchive(in rootURL: URL, name: String) throws -> URL {
        let sourceURL = rootURL.appendingPathComponent("world-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try Data("level".utf8).write(to: sourceURL.appendingPathComponent("level.dat"))
        try name.write(to: sourceURL.appendingPathComponent("levelname.txt"), atomically: true, encoding: .utf8)
        return try zipDirectory(sourceURL, to: rootURL.appendingPathComponent("\(UUID().uuidString).mcworld"))
    }

    private func manifest(
        name: String,
        uuid: String,
        moduleType: String,
        minEngineVersion: [Int] = [1, 20, 0]
    ) -> String {
        let minEngineVersionText = minEngineVersion.map(String.init).joined(separator: ", ")
        return """
        {
          "format_version": 2,
          "header": {
            "name": "\(name)",
            "description": "Test",
            "uuid": "\(uuid)",
            "version": [1, 0, 0],
            "min_engine_version": [\(minEngineVersionText)]
          },
          "modules": [
            {
              "type": "\(moduleType)",
              "uuid": "\(UUID().uuidString)",
              "version": [1, 0, 0]
            }
          ]
        }
        """
    }

    private func zipDirectory(_ sourceURL: URL, to archiveURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", archiveURL.path, "."]
        process.currentDirectoryURL = sourceURL
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archiveURL
    }
}
