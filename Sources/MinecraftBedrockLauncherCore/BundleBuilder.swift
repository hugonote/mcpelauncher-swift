import Foundation

public struct BundleBuilder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func build(spec: BundleSpec, overwrite: Bool = false) throws -> URL {
        let appURL = normalizedAppOutputURL(spec.outputPath, appName: spec.appName)
        if fileManager.fileExists(atPath: appURL.path) {
            guard overwrite else {
                throw LauncherError.outputAlreadyExists(appURL)
            }
            try fileManager.removeItem(at: appURL)
        }

        try validateRuntime(at: spec.runtimePath)

        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let helpersURL = contentsURL.appendingPathComponent("Helpers", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let runtimeOutputURL = resourcesURL.appendingPathComponent("Minecraft Bedrock", isDirectory: true)
        let versionsOutputURL = runtimeOutputURL.appendingPathComponent("game-versions", isDirectory: true)

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: versionsOutputURL, withIntermediateDirectories: true)
        try copyDirectoryContents(from: spec.runtimePath, to: runtimeOutputURL)
        if let googleCredentialsHelperPath = spec.googleCredentialsHelperPath,
           fileManager.isExecutableFile(atPath: googleCredentialsHelperPath.path) {
            try copyItemReplacingExisting(
                from: googleCredentialsHelperPath,
                to: helpersURL.appendingPathComponent("mcpelauncher-ui-qt", isDirectory: false)
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: helpersURL.appendingPathComponent("mcpelauncher-ui-qt", isDirectory: false).path
            )
        }
        if let webViewHelperPath = spec.webViewHelperPath,
           fileManager.isExecutableFile(atPath: webViewHelperPath.path) {
            try copyItemReplacingExisting(
                from: webViewHelperPath,
                to: helpersURL.appendingPathComponent("mcpelauncher-webview", isDirectory: false)
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: helpersURL.appendingPathComponent("mcpelauncher-webview", isDirectory: false).path
            )
        }
        if let compatibilityPatchPath = spec.compatibilityPatchPath {
            try copyItemReplacingExisting(
                from: compatibilityPatchPath,
                to: runtimeOutputURL.appendingPathComponent("Compatibility/mcpelauncher-updates", isDirectory: true)
            )
        }

        let versionName = spec.gameVersionPath.lastPathComponent
        let gameOutputURL = versionsOutputURL.appendingPathComponent(versionName, isDirectory: true)
        try copyItemReplacingExisting(from: spec.gameVersionPath, to: gameOutputURL)

        let executableName = sanitizedExecutableName(spec.appName)
        let executableURL = macOSURL.appendingPathComponent(executableName, isDirectory: false)
        try writeExecutableLauncher(
            to: executableURL,
            runScriptName: runScriptName(versionName: versionName)
        )

        let runScriptURL = runtimeOutputURL.appendingPathComponent(runScriptName(versionName: versionName), isDirectory: false)
        try writeRunScript(to: runScriptURL, versionName: versionName)

        let plistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        try writeInfoPlist(
            to: plistURL,
            executableName: executableName,
            spec: spec
        )

        return appURL
    }

    private func normalizedAppOutputURL(_ outputPath: URL, appName: String) -> URL {
        if outputPath.pathExtension == "app" {
            return outputPath
        }
        return outputPath.appendingPathComponent("\(appName).app", isDirectory: true)
    }

    private func validateRuntime(at runtimeURL: URL) throws {
        _ = try RuntimeLauncher(fileManager: fileManager).runtimeExecutable(in: runtimeURL)
    }

    private func copyDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
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

    private func writeExecutableLauncher(to url: URL, runScriptName: String) throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail
        CONTENTS_DIR="${0:A:h:h}"
        RUNTIME_DIR="$CONTENTS_DIR/Resources/Minecraft Bedrock"
        cd "$RUNTIME_DIR"
        exec "$RUNTIME_DIR/\(runScriptName)"
        """
        try writeExecutableScript(script, to: url)
    }

    private func writeRunScript(to url: URL, versionName: String) throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail
        ROOT_DIR="${0:A:h}"
        HELPERS_DIR="${ROOT_DIR:h:h}/Helpers"
        cd "$ROOT_DIR"

        export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-coreaudio}"
        export AUDIO_SAMPLE_RATE="${AUDIO_SAMPLE_RATE:-48000}"
        export PATH="$HELPERS_DIR:$PATH"

        for candidate in \
          "$ROOT_DIR/MacOS/mcpelauncher-client-arm64-v8a" \
          "$ROOT_DIR/Contents/MacOS/mcpelauncher-client-arm64-v8a" \
          "$ROOT_DIR/MacOS/mcpelauncher-client" \
          "$ROOT_DIR/Contents/MacOS/mcpelauncher-client" \
          "$ROOT_DIR/Resources/Minecraft Bedrock/mcpelauncher-client/mcpelauncher-client" \
          "$ROOT_DIR/Resources/Minecraft Bedrock/mcpelauncher-client/mcpelauncher-client-arm64-v8a" \
          "$ROOT_DIR/mcpelauncher-client/mcpelauncher-client" \
          "$ROOT_DIR/bin/mcpelauncher-client" \
          "$ROOT_DIR/mcpelauncher-client"; do
          if [[ -x "$candidate" ]]; then
            exec "$candidate" --disable-fmod -fes -dg "$ROOT_DIR/game-versions/\(versionName)"
          fi
        done

        echo "mcpelauncher-client was not found in exported runtime" >&2
        exit 127
        """
        try writeExecutableScript(script, to: url)
    }

    private func writeExecutableScript(_ script: String, to url: URL) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeInfoPlist(to url: URL, executableName: String, spec: BundleSpec) throws {
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": spec.appName,
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": spec.bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": spec.appName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": spec.version,
            "CFBundleVersion": spec.version,
            "LSApplicationCategoryType": "public.app-category.games",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
            "LSSupportsGameMode": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: [.atomic])
    }

    private func sanitizedExecutableName(_ appName: String) -> String {
        let allowed = appName.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let value = String(String.UnicodeScalarView(allowed))
        return value.isEmpty ? "MinecraftBedrockLauncher" : value
    }

    private func runScriptName(versionName: String) -> String {
        "run-minecraft-\(versionName).sh"
    }
}
