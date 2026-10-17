import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class ModManagerTests: XCTestCase {
    func testImportLocalLibraryEnablesPerVersion() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let manager = ModManager(paths: paths)
        let libraryURL = try writeLibrary(named: "libzoom.so", in: temp.url.appendingPathComponent("input", isDirectory: true))

        let mod = try manager.importLocal(libraryURL)
        try manager.setEnabled(true, mod: mod, versionName: "1.26.10")

        XCTAssertEqual(try manager.installedMods().map(\.name), ["libzoom"])
        XCTAssertEqual(try manager.enabledModPaths(for: "1.26.10"), [mod.installPath])
        XCTAssertEqual(try manager.enabledModPaths(for: "1.21.130"), [])
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: mod.installPath.appendingPathComponent("libzoom.so").path))
    }

    func testInstallFromCatalogFindsNestedABIDirectory() async throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto"), "ditto is required for archive fixture")
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let archiveRoot = temp.url.appendingPathComponent("archive", isDirectory: true)
        try writeLibrary(named: "libfullbright.so", in: archiveRoot.appendingPathComponent("fullbright/arm64-v8a", isDirectory: true))
        try writeLibrary(named: "libfullbright.so", in: archiveRoot.appendingPathComponent("fullbright/x86_64", isDirectory: true))
        let archiveURL = temp.url.appendingPathComponent("fullbright.zip")
        try zip(archiveRoot, to: archiveURL)
        let downloadedURL = temp.url.appendingPathComponent("downloaded.zip")
        let manager = ModManager(paths: paths) { _ in
            try FileManager.default.copyItem(at: archiveURL, to: downloadedURL)
            return downloadedURL
        }
        let entry = ModDBEntry(
            name: "mcpelauncher-fullbright",
            description: "Fullbright",
            url: "https://example.invalid",
            image: "",
            versions: [
                ModDBVersion(version: "1.0.0", assets: ["x86_64": "https://example.invalid/old.zip"]),
                ModDBVersion(version: "2.0.0", assets: ["arm64-v8a": "https://example.invalid/fullbright.zip"], minecraft: ">= 1.21.0")
            ]
        )

        let mod = try await manager.install(entry)

        XCTAssertEqual(mod.version, "2.0.0")
        XCTAssertEqual(mod.minecraftRequirement, ">= 1.21.0")
        XCTAssertEqual(mod.installPath.lastPathComponent, "arm64-v8a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mod.installPath.appendingPathComponent("libfullbright.so").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadedURL.path))
    }

    func testModSupportFollowsMinecraftRequirement() {
        var mod = InstalledMod(name: "new", version: "1", source: .catalog, installPath: URL(fileURLWithPath: "/tmp/new"))
        XCTAssertTrue(mod.supports(versionName: "1.21.130"))

        mod.minecraftRequirement = ">= 1.26.0"
        XCTAssertFalse(mod.supports(versionName: "1.21.130"))
        XCTAssertTrue(mod.supports(versionName: "1.26.10"))
    }

    func testRemoveClearsFilesAndEnabledState() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let manager = ModManager(paths: paths)
        let libraryURL = try writeLibrary(named: "libzoom.so", in: temp.url.appendingPathComponent("input", isDirectory: true))
        let mod = try manager.importLocal(libraryURL)
        try manager.setEnabled(true, mod: mod, versionName: "1.26.10")

        try manager.remove(mod)

        XCTAssertEqual(try manager.installedMods(), [])
        XCTAssertEqual(try manager.enabledModNames(for: "1.26.10"), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mod.installPath.path))
    }

    func testImportRejectsUnsupportedFile() throws {
        let temp = try TemporaryDirectory()
        let manager = ModManager(paths: AppPaths(baseURL: temp.url))
        let fileURL = temp.url.appendingPathComponent("readme.txt")
        try Data("text".utf8).write(to: fileURL)

        XCTAssertThrowsError(try manager.importLocal(fileURL))
    }

    func testInstallableCatalogEntriesExcludesPatchAndOtherABIs() {
        let entries = [
            ModDBEntry(name: "zoom", description: "", url: "", image: "", versions: [ModDBVersion(version: "1", assets: ["arm64-v8a": "https://a/zoom.zip"])]),
            ModDBEntry(name: CompatibilityPatchManager.patchModName, description: "", url: "", image: "", versions: [ModDBVersion(version: "1", assets: ["arm64-v8a": "https://a/u.zip"])]),
            ModDBEntry(name: "intel-only", description: "", url: "", image: "", versions: [ModDBVersion(version: "1", assets: ["x86_64": "https://a/i.zip"])]),
            ModDBEntry(name: "BuildLimitChanger", description: "", url: "", image: "", versions: [ModDBVersion(version: "1", assets: ["arm64-v8a": "https://a/b.zip"])])
        ]

        XCTAssertEqual(ModManager.installableCatalogEntries(entries).map(\.name), ["BuildLimitChanger", "zoom"])
    }

    func testDirectoryNameIsSanitized() {
        let cases: [(input: String, expected: String)] = [
            ("mcpelauncher-zoom", "mcpelauncher-zoom"),
            ("my mod/1,2", "my-mod-1-2"),
            ("..", "mod-..")
        ]
        for testCase in cases {
            XCTAssertEqual(ModManager.directoryName(for: testCase.input), testCase.expected)
        }
    }

    @discardableResult
    private func writeLibrary(named name: String, in directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent(name)
        try Data("elf".utf8).write(to: url)
        return url
    }

    private func zip(_ directoryURL: URL, to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", directoryURL.path, archiveURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
