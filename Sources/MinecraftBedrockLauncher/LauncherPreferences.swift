import Foundation
import MinecraftBedrockLauncherCore

enum LauncherPreferences {
    static let quickLaunchKey = "quickLaunch"
    static let automaticallyCheckRuntimeUpdatesKey = "automaticallyCheckRuntimeUpdates"
    static let automaticallyCheckGameUpdatesKey = "automaticallyCheckGameUpdates"
    static let automaticallyInstallGameUpdatesKey = "automaticallyInstallGameUpdates"
    static let allowUnsupportedMinecraftVersionsKey = "allowUnsupportedMinecraftVersions"
    static let automaticallyCheckLauncherUpdatesKey = "automaticallyCheckLauncherUpdates"
    static let runtimeVersionKey = "runtimeVersion"
    static let showInGameStatusBarKey = "showInGameStatusBar"
    static let fpsCounterVisibilityKey = "fpsCounterVisibility"
    static let vSyncEnabledKey = "vSyncEnabled"

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        let hasAutomaticInstallPreference = defaults.object(forKey: automaticallyInstallGameUpdatesKey) != nil

        defaults.register(defaults: [
            quickLaunchKey: false,
            automaticallyCheckRuntimeUpdatesKey: true,
            automaticallyCheckGameUpdatesKey: true,
            automaticallyInstallGameUpdatesKey: false,
            allowUnsupportedMinecraftVersionsKey: false,
            automaticallyCheckLauncherUpdatesKey: true,
            showInGameStatusBarKey: false,
            fpsCounterVisibilityKey: RuntimeHUDVisibility.off.rawValue,
            vSyncEnabledKey: true
        ])

        if !hasAutomaticInstallPreference {
            let shouldInstallGameUpdates =
                defaults.bool(forKey: automaticallyCheckLauncherUpdatesKey)
                && defaults.bool(forKey: automaticallyCheckRuntimeUpdatesKey)
                && defaults.bool(forKey: automaticallyCheckGameUpdatesKey)
            defaults.set(shouldInstallGameUpdates, forKey: automaticallyInstallGameUpdatesKey)
        }
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

    static var automaticallyInstallGameUpdates: Bool {
        UserDefaults.standard.bool(forKey: automaticallyInstallGameUpdatesKey)
    }

    static var canAutomaticallyCheckGameUpdates: Bool {
        automaticallyCheckRuntimeUpdates && automaticallyCheckGameUpdates
    }

    static var canAutomaticallyInstallGameUpdates: Bool {
        canAutomaticallyCheckGameUpdates && automaticallyInstallGameUpdates
    }

    static var allowsUnsupportedMinecraftVersions: Bool {
        UserDefaults.standard.bool(forKey: allowUnsupportedMinecraftVersionsKey)
    }

    static var automaticallyCheckLauncherUpdates: Bool {
        UserDefaults.standard.bool(forKey: automaticallyCheckLauncherUpdatesKey)
    }

    static var runtimeVersion: String? {
        get { UserDefaults.standard.string(forKey: runtimeVersionKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: runtimeVersionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: runtimeVersionKey)
            }
        }
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
