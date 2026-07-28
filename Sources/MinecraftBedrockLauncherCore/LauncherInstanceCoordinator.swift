import CoreFoundation
import Foundation

public final class LauncherInstanceCoordinator: @unchecked Sendable {
    public enum Role: Equatable, Sendable {
        case primary
        case secondary
        case failed(String)

        public var isPrimary: Bool {
            self == .primary
        }
    }

    public typealias RequestHandler = @Sendable ([URL]) -> Void

    public private(set) var role: Role = .failed("Instance coordinator has not started.")

    private let portName: String
    private let requestState = LauncherInstanceRequestState()
    private let lifecycleLock = NSLock()
    private var localPort: CFMessagePort?

    public convenience init() {
        self.init(portName: "local.minecraft.bedrock.swiftlauncher.instance")
    }

    init(portName: String) {
        self.portName = portName

        if CFMessagePortCreateRemote(nil, portName as CFString) != nil {
            role = .secondary
            return
        }

        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(requestState).toOpaque(),
            retain: launcherInstanceRetainState,
            release: launcherInstanceReleaseState,
            copyDescription: nil
        )
        var shouldFreeInfo = DarwinBoolean(false)
        let port = CFMessagePortCreateLocal(
            nil,
            portName as CFString,
            launcherInstanceMessagePortCallback,
            &context,
            &shouldFreeInfo
        )
        guard let port else {
            role = CFMessagePortCreateRemote(nil, portName as CFString) == nil
                ? .failed("Could not create the instance message port.")
                : .secondary
            return
        }
        guard !shouldFreeInfo.boolValue else {
            role = .secondary
            return
        }

        localPort = port
        CFMessagePortSetDispatchQueue(
            port,
            DispatchQueue(label: "MinecraftBedrockLauncher.InstanceMessagePort")
        )
        role = .primary
    }

    public func setRequestHandler(_ handler: @escaping RequestHandler) {
        requestState.setHandler(handler)
    }

    public func forward(_ urls: [URL], timeout: TimeInterval = 3) async -> Bool {
        let portName = self.portName
        return await Task.detached(priority: .userInitiated) {
            LauncherInstanceMessagePortClient.send(
                urls: urls,
                portName: portName,
                timeout: timeout
            )
        }.value
    }

    public func shutdown() {
        requestState.clear()

        lifecycleLock.lock()
        let port = localPort
        localPort = nil
        lifecycleLock.unlock()

        if let port {
            CFMessagePortInvalidate(port)
        }
    }

    deinit {
        shutdown()
    }
}

private struct LauncherInstanceWireRequest: Codable {
    static let maximumPayloadSize = 1024 * 1024

    var paths: [String]
}

private final class LauncherInstanceRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: LauncherInstanceCoordinator.RequestHandler?
    private var pendingRequests: [[URL]] = []

    func setHandler(_ handler: @escaping LauncherInstanceCoordinator.RequestHandler) {
        lock.lock()
        self.handler = handler
        let requests = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        requests.forEach(handler)
    }

    func receive(_ urls: [URL]) {
        lock.lock()
        guard let handler else {
            pendingRequests.append(urls)
            lock.unlock()
            return
        }
        lock.unlock()
        handler(urls)
    }

    func clear() {
        lock.lock()
        handler = nil
        pendingRequests.removeAll()
        lock.unlock()
    }
}

private func launcherInstanceRetainState(_ info: UnsafeRawPointer?) -> UnsafeRawPointer? {
    guard let info else {
        return nil
    }
    return UnsafeRawPointer(
        Unmanaged<LauncherInstanceRequestState>.fromOpaque(info).retain().toOpaque()
    )
}

private func launcherInstanceReleaseState(_ info: UnsafeRawPointer?) {
    guard let info else {
        return
    }
    Unmanaged<LauncherInstanceRequestState>.fromOpaque(info).release()
}

private func launcherInstanceMessagePortCallback(
    _ local: CFMessagePort?,
    _ messageID: Int32,
    _ data: CFData?,
    _ info: UnsafeMutableRawPointer?
) -> Unmanaged<CFData>? {
    guard let data,
          CFDataGetLength(data) <= LauncherInstanceWireRequest.maximumPayloadSize,
          let info,
          let request = try? PropertyListDecoder().decode(
              LauncherInstanceWireRequest.self,
              from: data as Data
          ) else {
        return nil
    }

    let state = Unmanaged<LauncherInstanceRequestState>
        .fromOpaque(info)
        .takeUnretainedValue()
    state.receive(request.paths.map(URL.init(fileURLWithPath:)))
    return Unmanaged.passRetained(Data([1]) as CFData)
}

private enum LauncherInstanceMessagePortClient {
    static func send(urls: [URL], portName: String, timeout: TimeInterval) -> Bool {
        let request = LauncherInstanceWireRequest(
            paths: urls.filter(\.isFileURL).map(\.path)
        )
        guard let payload = try? PropertyListEncoder().encode(request),
              !payload.isEmpty,
              payload.count <= LauncherInstanceWireRequest.maximumPayloadSize,
              let remotePort = CFMessagePortCreateRemote(nil, portName as CFString) else {
            return false
        }

        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remotePort,
            0,
            payload as CFData,
            timeout,
            timeout,
            CFRunLoopMode.defaultMode.rawValue,
            &reply
        )
        guard status == kCFMessagePortSuccess,
              let reply else {
            return false
        }
        return reply.takeRetainedValue() as Data == Data([1])
    }
}
