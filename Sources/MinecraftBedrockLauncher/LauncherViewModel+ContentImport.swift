import Foundation
import MinecraftBedrockLauncherCore

struct ContentImportAlertResult: Equatable {
    var title: String
    var message: String
}

private struct ContentImportFailure: Equatable {
    var url: URL
    var reason: String
}

typealias ContentImportCompatibilityDecision = @MainActor ([ContentPackCompatibilityWarning]) async -> Bool

extension LauncherViewModel {
    func enqueueContentFilesForActiveImport(_ urls: [URL]) -> Bool {
        let supportedURLs = urls.filter(ContentImportOpenFileQueue.isSupportedContentURL)
        guard isImportingContent, !supportedURLs.isEmpty else {
            return false
        }
        appendContentImportURLs(supportedURLs)
        return true
    }

    func importContentFiles(
        _ urls: [URL],
        shouldImportIncompatibleContent: ContentImportCompatibilityDecision? = nil
    ) async -> ContentImportAlertResult? {
        let supportedURLs = urls.filter(ContentImportOpenFileQueue.isSupportedContentURL)
        guard !supportedURLs.isEmpty else {
            return nil
        }
        if isImportingContent {
            appendContentImportURLs(supportedURLs)
            return nil
        }

        activeContentImportURLs = supportedURLs
        pendingContentImportURLs = supportedURLs
        completedContentImportFileCount = 0
        refreshContentImportPresentation()
        isImportingContent = true
        defer {
            isImportingContent = false
            importingContentDescription = nil
            contentImportProgress = nil
            activeContentImportURLs.removeAll()
            pendingContentImportURLs.removeAll()
            completedContentImportFileCount = 0
        }

        errorText = nil
        isBlockingNetworkUnavailable = false
        let appPaths = self.paths
        let installedVersion = selectedVersion
        let importer = ContentPackImporter()
        var imported: [ContentPackImportResult] = []
        var failures: [ContentImportFailure] = []
        var skippedCompatibilityWarnings: [ContentPackCompatibilityWarning] = []
        var successfulFileCount = 0
        var skippedFileCount = 0
        imported.reserveCapacity(activeContentImportURLs.count)
        failures.reserveCapacity(activeContentImportURLs.count)
        while !pendingContentImportURLs.isEmpty {
            let url = pendingContentImportURLs.removeFirst()
            do {
                let warnings = try await Task.detached(priority: .userInitiated) {
                    try importer.compatibilityWarnings(from: url, paths: appPaths, installedVersion: installedVersion)
                }.value
                let shouldImport: Bool
                if warnings.isEmpty {
                    shouldImport = true
                } else if let shouldImportIncompatibleContent {
                    shouldImport = await shouldImportIncompatibleContent(warnings)
                } else {
                    shouldImport = true
                }
                if shouldImport {
                    let results = try await Task.detached(priority: .userInitiated) {
                        try importer.importContent(from: url, paths: appPaths, installedVersion: installedVersion)
                    }.value
                    imported.append(contentsOf: results)
                    successfulFileCount += 1
                } else {
                    skippedCompatibilityWarnings.append(contentsOf: warnings)
                    skippedFileCount += 1
                }
            } catch {
                writeLastErrorLog(error)
                failures.append(ContentImportFailure(url: url, reason: Self.contentImportFailureReason(for: error)))
            }
            completedContentImportFileCount += 1
            refreshContentImportPresentation()
        }
        return Self.contentImportAlert(
            for: imported,
            failures: failures,
            skippedCompatibilityWarnings: skippedCompatibilityWarnings,
            successfulFileCount: successfulFileCount,
            skippedFileCount: skippedFileCount,
            totalFileCount: activeContentImportURLs.count
        )
    }

    private func appendContentImportURLs(_ urls: [URL]) {
        activeContentImportURLs.append(contentsOf: urls)
        pendingContentImportURLs.append(contentsOf: urls)
        refreshContentImportPresentation()
    }

    private func refreshContentImportPresentation() {
        importingContentDescription = ContentImportDescription(urls: activeContentImportURLs)
        contentImportProgress = activeContentImportURLs.count > 1
            ? ContentImportProgress(completed: completedContentImportFileCount, total: activeContentImportURLs.count)
            : nil
    }

    private static func contentImportAlert(
        for results: [ContentPackImportResult],
        failures: [ContentImportFailure],
        skippedCompatibilityWarnings: [ContentPackCompatibilityWarning],
        successfulFileCount: Int,
        skippedFileCount: Int,
        totalFileCount: Int
    ) -> ContentImportAlertResult {
        let warnings = results.compactMap(\.compatibilityWarning)
        if failures.isEmpty, skippedFileCount == 0 {
            return ContentImportAlertResult(
                title: warnings.isEmpty ? "Minecraft content imported" : "Minecraft content imported with warnings",
                message: contentImportSummary(for: results, warnings: warnings)
            )
        }

        let title: String
        if !failures.isEmpty {
            title = successfulFileCount == 0
                ? "Could not import Minecraft content"
                : "Some Minecraft content could not be imported"
        } else {
            title = successfulFileCount == 0
                ? "Incompatible content skipped"
                : "Some Minecraft content was skipped"
        }
        return ContentImportAlertResult(
            title: title,
            message: contentImportIssueSummary(
                successfulFileCount: successfulFileCount,
                failures: failures,
                skippedCompatibilityWarnings: skippedCompatibilityWarnings,
                totalFileCount: totalFileCount,
                warnings: warnings
            )
        )
    }

    private static func contentImportSummary(
        for results: [ContentPackImportResult],
        warnings: [ContentPackCompatibilityWarning]
    ) -> String {
        let summary: String
        if results.isEmpty {
            summary = "No content imported"
        } else if results.count == 1, let result = results.first {
            summary = "Imported \(result.kind.rawValue): \(result.name)"
        } else {
            summary = "Imported \(results.count) content items"
        }
        return appendCompatibilityWarnings(warnings, to: summary)
    }

    private static func contentImportIssueSummary(
        successfulFileCount: Int,
        failures: [ContentImportFailure],
        skippedCompatibilityWarnings: [ContentPackCompatibilityWarning],
        totalFileCount: Int,
        warnings: [ContentPackCompatibilityWarning]
    ) -> String {
        if successfulFileCount == 0, failures.isEmpty, skippedCompatibilityWarnings.count == 1,
           let warning = skippedCompatibilityWarnings.first {
            return compatibilityWarningSentence(for: warning)
        }

        let summary: String
        if successfulFileCount > 0 {
            summary = "Imported \(successfulFileCount) of \(totalFileCount) content files."
        } else if !failures.isEmpty {
            summary = "No content files were imported."
        } else {
            summary = skippedCompatibilityWarnings.isEmpty
                ? "No content files were imported."
                : "Skipped \(incompatibleContentItemsText(skippedCompatibilityWarnings.count))."
        }

        var lines = [summary]
        if !skippedCompatibilityWarnings.isEmpty {
            lines += ["", "Skipped:"]
            lines += compatibilityWarningLines(
                skippedCompatibilityWarnings,
                remainingText: "more skipped."
            )
        }

        let failureLines = failures
            .prefix(5)
            .map {
                $0.reason.isEmpty
                    ? "- \($0.url.lastPathComponent)"
                    : "- \($0.url.lastPathComponent): \($0.reason)"
            }
        let remainingCount = failures.count - failureLines.count
        let remainingLine = remainingCount > 0 ? ["- \(remainingCount) more failed."] : []
        if !failureLines.isEmpty || !remainingLine.isEmpty {
            lines += ["", "Could not import:"]
            lines += failureLines + remainingLine
        }
        return appendCompatibilityWarnings(warnings, to: lines.joined(separator: "\n"))
    }

    private static func appendCompatibilityWarnings(
        _ warnings: [ContentPackCompatibilityWarning],
        to summary: String
    ) -> String {
        guard !warnings.isEmpty else {
            return summary
        }
        return ([summary, "Compatibility warnings:"]
            + compatibilityWarningLines(warnings, remainingText: "more compatibility warnings."))
            .joined(separator: "\n")
    }

    private static func compatibilityWarningLines(
        _ warnings: [ContentPackCompatibilityWarning],
        remainingText: String
    ) -> [String] {
        let warningLines = warnings
            .prefix(5)
            .map {
                "- \(cleanMinecraftFormattingCodes($0.contentName)) requires Minecraft \($0.requiredVersion) or newer. Installed: \($0.installedVersion)."
            }
        let remainingCount = warnings.count - warningLines.count
        let remainingLine = remainingCount > 0 ? ["- \(remainingCount) \(remainingText)"] : []
        return warningLines + remainingLine
    }

    private static func compatibilityWarningSentence(for warning: ContentPackCompatibilityWarning) -> String {
        [
            "\(cleanMinecraftFormattingCodes(warning.contentName)) requires Minecraft \(warning.requiredVersion) or newer.",
            "Installed: \(warning.installedVersion)."
        ].joined(separator: "\n")
    }

    private static func incompatibleContentItemsText(_ count: Int) -> String {
        "\(count) incompatible content \(count == 1 ? "item" : "items")"
    }

    private static func contentImportFailureReason(for error: Error) -> String {
        if let launcherError = error as? LauncherError {
            switch launcherError {
            case .contentPackImportFailed(_, let reason):
                return reason
            default:
                return launcherError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private static func cleanMinecraftFormattingCodes(_ value: String) -> String {
        var result = ""
        var shouldSkipNext = false
        for character in value {
            if shouldSkipNext {
                shouldSkipNext = false
                continue
            }
            if character == "§" {
                shouldSkipNext = true
                continue
            }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
