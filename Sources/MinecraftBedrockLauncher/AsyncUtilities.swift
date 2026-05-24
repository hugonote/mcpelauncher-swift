import Foundation

func runOffMain<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .userInitiated) {
        try operation()
    }.value
}
