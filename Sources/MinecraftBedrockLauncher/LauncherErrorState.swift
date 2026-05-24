import Foundation

struct LauncherErrorState: Equatable {
    var activeIssue: LauncherIssue?
    var errorText: String?
    var isBlockingNetworkUnavailable = false
}

enum LauncherErrorAction {
    case clear
    case setIssue(LauncherIssue?)
    case setMessage(String?)
    case present(error: Error, blocksNetworkUnavailable: Bool)
    case fail(message: String, issue: LauncherIssue, blocksNetworkUnavailable: Bool)
    case setBlockingNetworkUnavailable(Bool)
}

enum LauncherErrorReducer {
    static func reduce(_ state: inout LauncherErrorState, action: LauncherErrorAction) {
        switch action {
        case .clear:
            state.activeIssue = nil
            state.errorText = nil
            state.isBlockingNetworkUnavailable = false
        case .setIssue(let issue):
            state.activeIssue = issue
        case .setMessage(let message):
            state.errorText = message
            if let message {
                state.activeIssue = LauncherIssue(message: message)
            } else {
                state.activeIssue = nil
            }
        case .present(let error, let blocksNetworkUnavailable):
            let issue = LauncherIssue(error: error)
            state.activeIssue = issue
            state.errorText = error.localizedDescription
            state.isBlockingNetworkUnavailable = blocksNetworkUnavailable && issue.isNetworkUnavailable
        case .fail(let message, let issue, let blocksNetworkUnavailable):
            state.activeIssue = issue
            state.errorText = message
            state.isBlockingNetworkUnavailable = blocksNetworkUnavailable && issue.isNetworkUnavailable
        case .setBlockingNetworkUnavailable(let isBlocking):
            state.isBlockingNetworkUnavailable = isBlocking
        }
    }
}
