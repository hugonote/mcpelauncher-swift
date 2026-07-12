import Darwin
import Foundation

protocol RuntimeProcessGroupSupervisionSystem {
    func waitForProcessExit(pid: pid_t, timeout: TimeInterval) -> Bool
    func sleep(for interval: TimeInterval)
    func processIdentifiers(inProcessGroup processGroupID: pid_t, executablePath: String) -> [pid_t]
    func sendSignal(_ signal: Int32, toProcess processID: pid_t)
    func sendSignal(_ signal: Int32, toProcessGroup processGroupID: pid_t) -> Bool
}

public struct RuntimeProcessGroupSupervisor {
    private let system: any RuntimeProcessGroupSupervisionSystem
    private let runtimeChildCheckInterval: TimeInterval
    private let shutdownGracePeriod: TimeInterval
    private let terminationGracePeriod: TimeInterval

    public init(
        runtimeChildCheckInterval: TimeInterval = 2,
        shutdownGracePeriod: TimeInterval = 5,
        terminationGracePeriod: TimeInterval = 3
    ) {
        self.init(
            system: DarwinRuntimeProcessGroupSupervisionSystem(),
            runtimeChildCheckInterval: runtimeChildCheckInterval,
            shutdownGracePeriod: shutdownGracePeriod,
            terminationGracePeriod: terminationGracePeriod
        )
    }

    init(
        system: any RuntimeProcessGroupSupervisionSystem,
        runtimeChildCheckInterval: TimeInterval = 2,
        shutdownGracePeriod: TimeInterval = 5,
        terminationGracePeriod: TimeInterval = 3
    ) {
        self.system = system
        self.runtimeChildCheckInterval = runtimeChildCheckInterval
        self.shutdownGracePeriod = shutdownGracePeriod
        self.terminationGracePeriod = terminationGracePeriod
    }

    public func supervise(
        runtimeProcessID: pid_t,
        runtimeProcessGroupID: pid_t,
        runtimeExecutablePath: String,
        onRuntimeExit: () -> Void = {}
    ) {
        let resolvedRuntimeExecutablePath = URL(fileURLWithPath: runtimeExecutablePath)
            .resolvingSymlinksInPath()
            .path
        while !system.waitForProcessExit(
            pid: runtimeProcessID,
            timeout: runtimeChildCheckInterval
        ) {
            terminateForkedRuntimeProcesses(
                excluding: runtimeProcessID,
                inProcessGroup: runtimeProcessGroupID,
                executablePath: resolvedRuntimeExecutablePath
            )
        }

        onRuntimeExit()
        system.sleep(for: shutdownGracePeriod)
        guard system.sendSignal(SIGTERM, toProcessGroup: runtimeProcessGroupID) else {
            return
        }
        system.sleep(for: terminationGracePeriod)
        _ = system.sendSignal(SIGKILL, toProcessGroup: runtimeProcessGroupID)
    }

    private func terminateForkedRuntimeProcesses(
        excluding runtimeProcessID: pid_t,
        inProcessGroup processGroupID: pid_t,
        executablePath: String
    ) {
        for processID in system.processIdentifiers(
            inProcessGroup: processGroupID,
            executablePath: executablePath
        ) where processID != runtimeProcessID {
            system.sendSignal(SIGKILL, toProcess: processID)
        }
    }
}

private struct DarwinRuntimeProcessGroupSupervisionSystem: RuntimeProcessGroupSupervisionSystem {
    func waitForProcessExit(pid: pid_t, timeout: TimeInterval) -> Bool {
        let queue = kqueue()
        guard queue >= 0 else {
            return waitForProcessExitByPolling(pid: pid, timeout: timeout)
        }
        defer {
            close(queue)
        }

        var event = kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: UInt32(NOTE_EXIT),
            data: 0,
            udata: nil
        )
        let registration = withUnsafePointer(to: &event) { pointer in
            pointer.withMemoryRebound(to: kevent.self, capacity: 1) { reboundPointer in
                kevent(queue, reboundPointer, 1, nil, 0, nil)
            }
        }
        guard registration == 0 else {
            return errno == ESRCH
                || waitForProcessExitByPolling(pid: pid, timeout: timeout)
        }

        var exitEvent = kevent()
        var timeoutSpec = timespec(
            tv_sec: Int(timeout.rounded(.down)),
            tv_nsec: Int((timeout - timeout.rounded(.down)) * 1_000_000_000)
        )
        let eventCount = withUnsafeMutablePointer(to: &exitEvent) { pointer in
            pointer.withMemoryRebound(to: kevent.self, capacity: 1) { reboundPointer in
                kevent(queue, nil, 0, reboundPointer, 1, &timeoutSpec)
            }
        }
        if eventCount > 0 {
            return true
        }
        if eventCount == 0 {
            return false
        }
        return waitForProcessExitByPolling(pid: pid, timeout: timeout)
    }

    func sleep(for interval: TimeInterval) {
        Thread.sleep(forTimeInterval: interval)
    }

    func processIdentifiers(inProcessGroup processGroupID: pid_t, executablePath expectedExecutablePath: String) -> [pid_t] {
        guard processGroupID > 0 else {
            return []
        }

        var capacity = 16
        while capacity <= 1_024 {
            var processIDs = [pid_t](repeating: 0, count: capacity)
            let byteCount = processIDs.withUnsafeMutableBytes { buffer in
                proc_listpids(
                    UInt32(PROC_PGRP_ONLY),
                    UInt32(processGroupID),
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
            guard byteCount > 0 else {
                return []
            }

            let processCount = Int(byteCount) / MemoryLayout<pid_t>.stride
            if processCount < capacity {
                return processIDs.prefix(processCount).filter {
                    $0 > 0 && executablePath(for: $0) == expectedExecutablePath
                }
            }
            capacity *= 2
        }
        return []
    }

    func sendSignal(_ signal: Int32, toProcess processID: pid_t) {
        guard processID > 0 else {
            return
        }
        _ = kill(processID, signal)
    }

    func sendSignal(_ signal: Int32, toProcessGroup processGroupID: pid_t) -> Bool {
        guard processGroupID > 0 else {
            return false
        }
        return killpg(processGroupID, signal) == 0
    }

    private func waitForProcessExitByPolling(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while kill(pid, 0) == 0 || errno == EPERM {
            let remainingInterval = deadline.timeIntervalSinceNow
            guard remainingInterval > 0 else {
                return false
            }
            Thread.sleep(forTimeInterval: min(0.1, remainingInterval))
        }
        return true
    }

    private func executablePath(for processID: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(processID, &path, UInt32(path.count)) > 0 else {
            return nil
        }
        return String(
            decoding: path.map { UInt8(bitPattern: $0) }.prefix { $0 != 0 },
            as: UTF8.self
        )
    }
}
