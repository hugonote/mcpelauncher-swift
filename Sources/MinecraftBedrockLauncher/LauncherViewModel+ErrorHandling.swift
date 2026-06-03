import Foundation

extension LauncherViewModel {
    func show(_ error: Error) {
        writeLastErrorLog(error)
        let issue = LauncherIssue(error: error)
        reduceError(.present(
            error: error,
            blocksNetworkUnavailable: shouldShowBlockingNetworkUnavailable(for: issue)
        ))
    }

    func writeLastErrorLog(_ error: Error) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let content = """
        \(stamp)
        \(type(of: error))
        \(error.localizedDescription)

        """
        do {
            try FileManager.default.createDirectory(at: paths.logsURL, withIntermediateDirectories: true)
            try Data(content.utf8).write(
                to: paths.logsURL.appendingPathComponent("last-error.log", isDirectory: false),
                options: [.atomic]
            )
        } catch {
        }
    }

    private func shouldShowBlockingNetworkUnavailable(for issue: LauncherIssue) -> Bool {
        guard selectedVersion == nil || !isRuntimeReady else {
            return false
        }
        return issue.isNetworkUnavailable
    }

    func reduceError(_ action: LauncherErrorAction) {
        LauncherErrorReducer.reduce(&errorState, action: action)
    }
}
