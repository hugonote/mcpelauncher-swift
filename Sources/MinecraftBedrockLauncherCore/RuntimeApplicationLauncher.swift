import AppKit
import Foundation

public protocol RuntimeApplicationLaunching: Sendable {
    func launchApplication(at appURL: URL, arguments: [String], environment: [String: String]) throws
}

public struct NSWorkspaceRuntimeApplicationLauncher: RuntimeApplicationLaunching {
    public init() {}

    public func launchApplication(at appURL: URL, arguments: [String], environment: [String: String]) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.environment = environment
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        let result = RuntimeApplicationLaunchResult()
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            result.error = error
            semaphore.signal()
        }
        semaphore.wait()

        if let error = result.error {
            throw error
        }
    }
}

private final class RuntimeApplicationLaunchResult: @unchecked Sendable {
    var error: Error?
}
