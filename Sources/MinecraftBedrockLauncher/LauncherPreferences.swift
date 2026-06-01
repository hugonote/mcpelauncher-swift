import Foundation
import MinecraftBedrockLauncherCore

enum LauncherPreferences {
    static let quickLaunchKey = "quickLaunch"
    static let automaticallyCheckRuntimeUpdatesKey = "automaticallyCheckRuntimeUpdates"
    static let automaticallyCheckGameUpdatesKey = "automaticallyCheckGameUpdates"
    static let automaticallyCheckLauncherUpdatesKey = "automaticallyCheckLauncherUpdates"
    static let showInGameStatusBarKey = "showInGameStatusBar"
    static let fpsCounterVisibilityKey = "fpsCounterVisibility"
    static let vSyncEnabledKey = "vSyncEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            quickLaunchKey: false,
            automaticallyCheckRuntimeUpdatesKey: true,
            automaticallyCheckGameUpdatesKey: true,
            automaticallyCheckLauncherUpdatesKey: true,
            showInGameStatusBarKey: false,
            fpsCounterVisibilityKey: RuntimeHUDVisibility.off.rawValue,
            vSyncEnabledKey: true
        ])
    }

    static var quickLaunch: Bool {
        UserDefaults.standard.bool(forKey: quickLaunchKey)
    }

    static var automaticallyCheckRuntimeUpdates: Bool {
        UserDefaults.standard.bool(forKey: automaticallyCheckRuntimeUpdatesKey)
    }

    static var automaticallyCheckGameUpdates: Bool {
        UserDefaults.standard.bool(forKey: automaticallyCheckGameUpdatesKey)
    }

    static var automaticallyCheckLauncherUpdates: Bool {
        UserDefaults.standard.bool(forKey: automaticallyCheckLauncherUpdatesKey)
    }

    static var showInGameStatusBar: Bool {
        UserDefaults.standard.bool(forKey: showInGameStatusBarKey)
    }

    static var fpsCounterVisibility: RuntimeHUDVisibility {
        RuntimeHUDVisibility(rawValue: UserDefaults.standard.integer(forKey: fpsCounterVisibilityKey)) ?? .off
    }

    static var vSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: vSyncEnabledKey)
    }
}
