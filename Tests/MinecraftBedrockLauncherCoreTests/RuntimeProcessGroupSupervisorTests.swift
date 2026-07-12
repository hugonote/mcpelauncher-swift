import Darwin
@testable import MinecraftBedrockClientWrapperSupport
import XCTest

final class RuntimeProcessGroupSupervisorTests: XCTestCase {
    func testSupervisorTerminatesForkedRuntimeChildWhileRootIsRunning() {
        let system = MockRuntimeProcessGroupSupervisionSystem(
            processIdentifiers: [[70, 71]],
            processExitResults: [false, true]
        )
        let supervisor = RuntimeProcessGroupSupervisor(
            system: system,
            runtimeChildCheckInterval: 2,
            shutdownGracePeriod: 5,
            terminationGracePeriod: 3
        )

        supervisor.supervise(
            runtimeProcessID: 70,
            runtimeProcessGroupID: 70,
            runtimeExecutablePath: "/Runtime/bin/mcpelauncher-client"
        )

        XCTAssertEqual(system.waitedProcessIdentifiers, [70, 70])
        XCTAssertEqual(system.waitTimeouts, [2, 2])
        XCTAssertEqual(system.sleepIntervals, [5])
        XCTAssertEqual(system.signals, [
            Signal(processID: 71, value: SIGKILL)
        ])
    }

    func testSupervisorKillsEveryForkedRuntimeChildFoundDuringLiveCheck() {
        let system = MockRuntimeProcessGroupSupervisionSystem(
            processIdentifiers: [[70, 71, 72]],
            processExitResults: [false, true]
        )
        let supervisor = RuntimeProcessGroupSupervisor(system: system)

        supervisor.supervise(
            runtimeProcessID: 70,
            runtimeProcessGroupID: 70,
            runtimeExecutablePath: "/Runtime/bin/mcpelauncher-client"
        )

        XCTAssertEqual(system.signals, [
            Signal(processID: 71, value: SIGKILL),
            Signal(processID: 72, value: SIGKILL)
        ])
    }

    func testSupervisorTerminatesRuntimeProcessGroupAfterRootExits() {
        let system = MockRuntimeProcessGroupSupervisionSystem(
            processIdentifiers: [],
            processGroupSignalResults: [true, true]
        )
        let supervisor = RuntimeProcessGroupSupervisor(
            system: system,
            shutdownGracePeriod: 5,
            terminationGracePeriod: 3
        )

        supervisor.supervise(
            runtimeProcessID: 70,
            runtimeProcessGroupID: 70,
            runtimeExecutablePath: "/Runtime/bin/mcpelauncher-client"
        )

        XCTAssertEqual(system.waitedProcessIdentifiers, [70])
        XCTAssertEqual(system.sleepIntervals, [5, 3])
        XCTAssertEqual(system.processGroupSignals, [
            GroupSignal(processGroupID: 70, value: SIGTERM),
            GroupSignal(processGroupID: 70, value: SIGKILL)
        ])
    }

    func testSupervisorSkipsKillGracePeriodWhenRuntimeGroupNoLongerExists() {
        let system = MockRuntimeProcessGroupSupervisionSystem(processIdentifiers: [[]])
        let supervisor = RuntimeProcessGroupSupervisor(system: system)

        supervisor.supervise(
            runtimeProcessID: 70,
            runtimeProcessGroupID: 70,
            runtimeExecutablePath: "/Runtime/bin/mcpelauncher-client"
        )

        XCTAssertEqual(system.waitedProcessIdentifiers, [70])
        XCTAssertEqual(system.sleepIntervals, [5])
        XCTAssertTrue(system.signals.isEmpty)
        XCTAssertEqual(system.processGroupSignals, [
            GroupSignal(processGroupID: 70, value: SIGTERM)
        ])
    }

    func testSupervisorRunsExitHandlerBeforeWaitingForResidualProcesses() {
        let system = MockRuntimeProcessGroupSupervisionSystem(processIdentifiers: [[]])
        let supervisor = RuntimeProcessGroupSupervisor(system: system)
        var didRunExitHandler = false

        supervisor.supervise(
            runtimeProcessID: 70,
            runtimeProcessGroupID: 70,
            runtimeExecutablePath: "/Runtime/bin/mcpelauncher-client",
            onRuntimeExit: {
                didRunExitHandler = true
            }
        )

        XCTAssertTrue(didRunExitHandler)
        XCTAssertEqual(system.sleepIntervals, [5])
    }
}

private struct Signal: Equatable {
    let processID: pid_t
    let value: Int32
}

private struct GroupSignal: Equatable {
    let processGroupID: pid_t
    let value: Int32
}

private final class MockRuntimeProcessGroupSupervisionSystem: RuntimeProcessGroupSupervisionSystem {
    private var processIdentifiersToReturn: [[pid_t]]
    private var processExitResultsToReturn: [Bool]
    private var processGroupSignalResultsToReturn: [Bool]
    private(set) var waitedProcessIdentifiers: [pid_t] = []
    private(set) var waitTimeouts: [TimeInterval] = []
    private(set) var sleepIntervals: [TimeInterval] = []
    private(set) var signals: [Signal] = []
    private(set) var processGroupSignals: [GroupSignal] = []

    init(
        processIdentifiers: [[pid_t]],
        processExitResults: [Bool] = [true],
        processGroupSignalResults: [Bool] = [false]
    ) {
        self.processIdentifiersToReturn = processIdentifiers
        self.processExitResultsToReturn = processExitResults
        self.processGroupSignalResultsToReturn = processGroupSignalResults
    }

    func waitForProcessExit(pid: pid_t, timeout: TimeInterval) -> Bool {
        waitedProcessIdentifiers.append(pid)
        waitTimeouts.append(timeout)
        guard !processExitResultsToReturn.isEmpty else {
            return true
        }
        return processExitResultsToReturn.removeFirst()
    }

    func sleep(for interval: TimeInterval) {
        sleepIntervals.append(interval)
    }

    func processIdentifiers(inProcessGroup processGroupID: pid_t, executablePath: String) -> [pid_t] {
        guard !processIdentifiersToReturn.isEmpty else {
            return []
        }
        return processIdentifiersToReturn.removeFirst()
    }

    func sendSignal(_ signal: Int32, toProcess processID: pid_t) {
        signals.append(Signal(processID: processID, value: signal))
    }

    func sendSignal(_ signal: Int32, toProcessGroup processGroupID: pid_t) -> Bool {
        processGroupSignals.append(GroupSignal(processGroupID: processGroupID, value: signal))
        guard !processGroupSignalResultsToReturn.isEmpty else {
            return false
        }
        return processGroupSignalResultsToReturn.removeFirst()
    }
}
