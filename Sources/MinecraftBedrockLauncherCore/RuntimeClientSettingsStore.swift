import Foundation

public struct RuntimeClientSettingsStore {
    public static let fileName = "mcpelauncher-client-settings.txt"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func setInGameStatusBarEnabled(_ isEnabled: Bool, dataPath: URL) throws {
        try set("enable_menubar", value: isEnabled ? "true" : "false", dataPath: dataPath)
    }

    public func inGameStatusBarEnabled(dataPath: URL) throws -> Bool? {
        try boolValue(for: "enable_menubar", dataPath: dataPath)
    }

    public func settingsURL(dataPath: URL) -> URL {
        dataPath.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    private func boolValue(for key: String, dataPath: URL) throws -> Bool? {
        let url = settingsURL(dataPath: dataPath)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let prefix = "\(key)="
        guard let line = text.components(separatedBy: "\n").last(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }

        let value = line.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }

    private func set(_ key: String, value: String, dataPath: URL) throws {
        try fileManager.createDirectory(at: dataPath, withIntermediateDirectories: true)

        let url = settingsURL(dataPath: dataPath)
        let text: String
        if fileManager.fileExists(atPath: url.path) {
            text = try String(contentsOf: url, encoding: .utf8)
        } else {
            text = ""
        }

        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if text.hasSuffix("\n") {
            lines.removeLast()
        }

        var didSetValue = false
        let updatedLines = lines.compactMap { line -> String? in
            guard line.hasPrefix("\(key)=") else {
                return line
            }
            guard !didSetValue else {
                return nil
            }
            didSetValue = true
            return "\(key)=\(value)"
        }

        let outputLines = didSetValue ? updatedLines : updatedLines + ["\(key)=\(value)"]
        try (outputLines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
