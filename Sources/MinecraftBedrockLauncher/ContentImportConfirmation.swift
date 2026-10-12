import Foundation
import MinecraftBedrockLauncherCore
import Observation

@MainActor
@Observable
final class ContentImportConfirmation {
    private(set) var warnings: [ContentPackCompatibilityWarning] = []
    private var continuation: CheckedContinuation<Bool, Never>?
    private var requestID: UUID?

    var isPresented: Bool { continuation != nil }

    func confirm(_ warnings: [ContentPackCompatibilityWarning]) async -> Bool {
        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                precondition(self.continuation == nil)
                self.warnings = warnings
                self.requestID = requestID
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                if self.requestID == requestID {
                    self.resolve(false)
                }
            }
        }
    }

    func resolve(_ shouldImport: Bool) {
        let pending = continuation
        continuation = nil
        requestID = nil
        warnings = []
        pending?.resume(returning: shouldImport)
    }
}
