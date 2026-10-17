import Foundation

public enum RuntimeGraphicsBackend: Int, CaseIterable, Sendable {
    case vulkan = 0
    case metal = 1
}

public struct RuntimePerformanceSettings: Equatable, Sendable {
    public static let anglePlatformOverrideLibraryName = "libangle-platform-override.dylib"
    public static let requestedAnglePlatformKey = "MCPELAUNCHER_ANGLE_PLATFORM"

    public var showsMetalHUD: Bool
    public var graphicsBackend: RuntimeGraphicsBackend
    public var anglePlatformOverrideURL: URL?

    public init(
        showsMetalHUD: Bool = false,
        graphicsBackend: RuntimeGraphicsBackend = .vulkan,
        anglePlatformOverrideURL: URL? = nil
    ) {
        self.showsMetalHUD = showsMetalHUD
        self.graphicsBackend = graphicsBackend
        self.anglePlatformOverrideURL = anglePlatformOverrideURL
    }

    public var environment: [String: String] {
        var environment: [String: String] = [:]
        if showsMetalHUD {
            environment["MTL_HUD_ENABLED"] = "1"
        }
        if graphicsBackend == .metal, let anglePlatformOverrideURL {
            environment["DYLD_INSERT_LIBRARIES"] = anglePlatformOverrideURL.path
            environment[Self.requestedAnglePlatformKey] = "metal"
        }
        return environment
    }
}
