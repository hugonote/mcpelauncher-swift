import Foundation
import MinecraftBedrockLauncherCore

extension LauncherViewModel {
    func saveRuntimeClientPreferences() {
        do {
            try applyRuntimeClientPreferences(dataPath: paths.minecraftDataURL)
        } catch {
            show(error)
        }
    }

    func applyRuntimeClientPreferences(dataPath: URL) throws {
        let settingsStore = RuntimeClientSettingsStore()
        try settingsStore.setInGameStatusBarEnabled(
            LauncherPreferences.showInGameStatusBar,
            dataPath: dataPath
        )
        try settingsStore.setFPSHUDVisibility(
            LauncherPreferences.fpsCounterVisibility,
            dataPath: dataPath
        )
        try settingsStore.setVSyncEnabled(
            LauncherPreferences.vSyncEnabled,
            dataPath: dataPath
        )
    }

    func syncRuntimeClientPreferencesFromDisk() throws {
        let settingsStore = RuntimeClientSettingsStore()
        if let isEnabled = try settingsStore.inGameStatusBarEnabled(dataPath: paths.minecraftDataURL) {
            UserDefaults.standard.set(isEnabled, forKey: LauncherPreferences.showInGameStatusBarKey)
        }
        if let fpsHUDVisibility = try settingsStore.fpsHUDVisibility(dataPath: paths.minecraftDataURL) {
            UserDefaults.standard.set(fpsHUDVisibility.rawValue, forKey: LauncherPreferences.fpsCounterVisibilityKey)
        }
        if let vSyncEnabled = try settingsStore.vSyncEnabled(dataPath: paths.minecraftDataURL) {
            UserDefaults.standard.set(vSyncEnabled, forKey: LauncherPreferences.vSyncEnabledKey)
        }
    }
}
