import Foundation

public extension AppPaths {
    var legacyGooglePlayStateURL: URL {
        baseURL.appendingPathComponent("GooglePlay", isDirectory: true)
    }

    func removeLegacyGooglePlayState(fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: legacyGooglePlayStateURL.path) {
            try fileManager.removeItem(at: legacyGooglePlayStateURL)
        }
    }
}
