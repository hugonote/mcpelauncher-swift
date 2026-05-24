import Foundation
import MinecraftBedrockLauncherCore

enum LauncherIssue: Equatable {
    case networkUnavailable
    case googlePlayBadToken
    case connectionInterrupted
    case minecraftNotOwned
    case downloadStalled
    case downloadDidNotStart
    case bundledHelperMissing
    case runtimeChecksumMismatch
    case runtimeFailed
    case generic

    init(error: Error) {
        if let urlError = error as? URLError {
            self = Self.issue(for: urlError)
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           let issue = Self.issue(forURLErrorCode: URLError.Code(rawValue: nsError.code)) {
            self = issue
            return
        }

        if let launcherError = error as? LauncherError {
            self = Self.issue(for: launcherError)
            return
        }

        self = Self.issue(forMessage: error.localizedDescription)
    }

    init(message: String) {
        self = Self.issue(forMessage: message)
    }

    var isNetworkUnavailable: Bool {
        self == .networkUnavailable || self == .googlePlayBadToken
    }

    var centerText: String? {
        switch self {
        case .networkUnavailable:
            return "No internet connection"
        case .googlePlayBadToken:
            return "No internet connection"
        case .connectionInterrupted:
            return "Connection interrupted"
        case .minecraftNotOwned:
            return "Minecraft not purchased"
        case .downloadStalled:
            return "Download stalled"
        case .downloadDidNotStart:
            return "Download did not start"
        case .bundledHelperMissing:
            return "Application corrupted"
        case .runtimeChecksumMismatch:
            return "Runtime checksum mismatch"
        case .runtimeFailed:
            return "Runtime failed"
        case .generic:
            return nil
        }
    }

    var shortText: String? {
        switch self {
        case .networkUnavailable, .googlePlayBadToken:
            return "Offline"
        case .connectionInterrupted:
            return "Connection interrupted"
        case .minecraftNotOwned:
            return "Purchase required"
        case .downloadStalled, .downloadDidNotStart:
            return "Download failed"
        case .bundledHelperMissing:
            return "Application corrupted"
        case .runtimeChecksumMismatch:
            return "Checksum mismatch"
        case .runtimeFailed:
            return "Runtime failed"
        case .generic:
            return nil
        }
    }

    private static func issue(for error: URLError) -> LauncherIssue {
        issue(forURLErrorCode: error.code) ?? .generic
    }

    private static func issue(forURLErrorCode code: URLError.Code) -> LauncherIssue? {
        switch code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .networkUnavailable
        case .networkConnectionLost, .timedOut:
            return .connectionInterrupted
        default:
            return nil
        }
    }

    private static func issue(for error: LauncherError) -> LauncherIssue {
        switch error {
        case .googlePlayToolNotFound:
            return .bundledHelperMissing
        case .googlePlayToolFailed(let command, let status, let output):
            if (command.localizedCaseInsensitiveContains("gplayver")
                || command.localizedCaseInsensitiveContains("gplaydl")),
               status == 1,
               output.localizedCaseInsensitiveContains("bad token") {
                return .googlePlayBadToken
            }
            return issue(forMessage: output)
        case .minecraftNotOwned:
            return .minecraftNotOwned
        case .runtimeChecksumMismatch:
            return .runtimeChecksumMismatch
        case .runtimeInstallFailed:
            return .runtimeFailed
        default:
            return issue(forMessage: error.localizedDescription)
        }
    }

    private static func issue(forMessage message: String) -> LauncherIssue {
        if message.localizedCaseInsensitiveContains("download stalled") {
            return .downloadStalled
        }
        if message.localizedCaseInsensitiveContains("download did not start") {
            return .downloadDidNotStart
        }
        if message.localizedCaseInsensitiveContains("minecraft is not purchased") {
            return .minecraftNotOwned
        }
        if isBundledHelperMissing(message) {
            return .bundledHelperMissing
        }
        if message.localizedCaseInsensitiveContains("not connected to the internet")
            || message.localizedCaseInsensitiveContains("cannot find host")
            || message.localizedCaseInsensitiveContains("could not resolve host")
            || message.localizedCaseInsensitiveContains("dns") {
            return .networkUnavailable
        }
        if message.localizedCaseInsensitiveContains("network connection was lost")
            || message.localizedCaseInsensitiveContains("timed out") {
            return .connectionInterrupted
        }
        return .generic
    }

    private static func isBundledHelperMissing(_ message: String) -> Bool {
        let helperNames = [
            "Google Play tool",
            "gplayver",
            "gplaydl",
            "mcpelauncher-ui-qt",
            "mcpelauncher-webview"
        ]
        let missingMarkers = [
            "was not found",
            "not found",
            "no such file"
        ]
        return helperNames.contains { helperName in
            message.localizedCaseInsensitiveContains(helperName)
        } && missingMarkers.contains { marker in
            message.localizedCaseInsensitiveContains(marker)
        }
    }
}
