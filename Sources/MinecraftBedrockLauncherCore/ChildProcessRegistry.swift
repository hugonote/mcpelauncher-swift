import Darwin
import Foundation

public final class ChildProcessRegistry: @unchecked Sendable {
    public static let shared = ChildProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    private init() {}

    public func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    public func unregister(_ process: Process) {
        lock.lock()
        processes.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
    }

    public func terminateAll() {
        lock.lock()
        let running = Array(processes.values)
        lock.unlock()

        for process in running where process.isRunning {
            process.terminate()
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
