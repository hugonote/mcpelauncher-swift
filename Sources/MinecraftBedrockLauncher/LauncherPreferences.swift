import Foundation

enum LauncherPreferences {
    static let automaticallyCheckRuntimeUpdatesKey = "automaticallyCheckRuntimeUpdates"
    static let automaticallyCheckGameUpdatesKey = "automaticallyCheckGameUpdates"
    static let automaticallyCheckLauncherUpdatesKey = "automaticallyCheckLauncherUpdates"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            automaticallyCheckRuntimeUpdatesKey: true,
            automaticallyCheckGameUpdatesKey: true,
            automaticallyCheckLauncherUpdatesKey: true
        ])
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
}
