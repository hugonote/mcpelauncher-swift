import AppKit
import MinecraftBedrockLauncherCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(LauncherPreferences.quickLaunchKey)
    private var quickLaunch = false

    @AppStorage(LauncherPreferences.automaticallyCheckRuntimeUpdatesKey)
    private var automaticallyCheckRuntimeUpdates = true

    @AppStorage(LauncherPreferences.automaticallyCheckGameUpdatesKey)
    private var automaticallyCheckGameUpdates = true

    @AppStorage(LauncherPreferences.automaticallyInstallGameUpdatesKey)
    private var automaticallyInstallGameUpdates = false

    @AppStorage(LauncherPreferences.automaticallyCheckLauncherUpdatesKey)
    private var automaticallyCheckLauncherUpdates = true

    @AppStorage(LauncherPreferences.showInGameStatusBarKey)
    private var showInGameStatusBar = false

    @AppStorage(LauncherPreferences.fpsCounterVisibilityKey)
    private var fpsCounterVisibility = RuntimeHUDVisibility.off.rawValue

    @AppStorage(LauncherPreferences.vSyncEnabledKey)
    private var vSyncEnabled = true

    @State private var pendingDeleteAction: DeleteAction?
    @State private var completedAction: DeleteAction?
    @State private var isPresentingQuickLaunchWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Updates")
                    .font(.headline)

                VStack(spacing: 0) {
                    ToggleRow(
                        title: "Launcher",
                        subtitle: "Keep this app current",
                        systemImage: "arrow.down.app",
                        isOn: $automaticallyCheckLauncherUpdates
                    )
                    Divider()
                    ToggleRow(
                        title: "Runtime",
                        subtitle: "Keep native components current",
                        systemImage: "cpu",
                        isOn: $automaticallyCheckRuntimeUpdates
                    )
                    Divider()
                    SegmentedRow(
                        title: "Minecraft",
                        subtitle: "Game updates",
                        systemImage: "cube",
                        selection: minecraftUpdateModeBinding,
                        options: [
                            .init(title: "Off", value: MinecraftUpdateMode.off.rawValue),
                            .init(title: "Check", value: MinecraftUpdateMode.onlyCheck.rawValue),
                            .init(title: "Install", value: MinecraftUpdateMode.checkAndInstall.rawValue)
                        ],
                        isDisabled: !automaticallyCheckRuntimeUpdates
                    )
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Game")
                    .font(.headline)

                VStack(spacing: 0) {
                    ToggleRow(
                        title: "Quick Launch",
                        subtitle: "Start Minecraft automatically",
                        systemImage: "bolt.fill",
                        isOn: quickLaunchBinding
                    )
                    Divider()
                    ToggleRow(
                        title: "Status Bar",
                        subtitle: "Show runtime controls in Minecraft",
                        systemImage: "menubar.rectangle",
                        isOn: $showInGameStatusBar
                    )
                    Divider()
                    ToggleRow(
                        title: "VSync",
                        subtitle: "Synchronize frame pacing",
                        systemImage: "display",
                        isOn: $vSyncEnabled
                    )
                    Divider()
                    SegmentedRow(
                        title: "FPS Counter",
                        subtitle: "Frame rate overlay",
                        systemImage: "speedometer",
                        selection: $fpsCounterVisibility,
                        options: [
                            .init(title: "Off", value: RuntimeHUDVisibility.off.rawValue),
                            .init(title: "In Game", value: RuntimeHUDVisibility.inGame.rawValue),
                            .init(title: "Always", value: RuntimeHUDVisibility.always.rawValue)
                        ]
                    )
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Storage")
                    .font(.headline)

                VStack(spacing: 0) {
                    DeleteRow(
                        title: "Delete Runtime",
                        subtitle: "Remove native launcher files",
                        systemImage: "cpu",
                        isWorking: model.isDeletingRuntime,
                        isComplete: completedAction == .runtime,
                        isDisabled: model.isStorageActionBusy,
                        action: { pendingDeleteAction = .runtime }
                    )
                    Divider()
                    DeleteRow(
                        title: "Delete Game",
                        subtitle: "Remove installed version",
                        systemImage: "cube",
                        isWorking: model.isDeletingGame,
                        isComplete: completedAction == .game,
                        isDisabled: model.isStorageActionBusy,
                        action: { pendingDeleteAction = .game }
                    )
                    Divider()
                    DeleteRow(
                        title: "Delete Data",
                        subtitle: "Remove saves, settings, and cache",
                        systemImage: "externaldrive",
                        isWorking: model.isDeletingData,
                        isComplete: completedAction == .data,
                        isDisabled: model.isStorageActionBusy,
                        action: { pendingDeleteAction = .data }
                    )
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(width: 390)
        .onExitCommand {
            dismiss()
        }
        .background(
            Button("", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
        .onChange(of: showInGameStatusBar) { _, _ in
            model.saveRuntimeClientPreferences()
        }
        .onChange(of: fpsCounterVisibility) { _, _ in
            model.saveRuntimeClientPreferences()
        }
        .onChange(of: vSyncEnabled) { _, _ in
            model.saveRuntimeClientPreferences()
        }
        .confirmationDialog(
            pendingDeleteAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingDeleteAction != nil },
                set: { if !$0 { pendingDeleteAction = nil } }
            )
        ) {
            if let pendingDeleteAction {
                Button(pendingDeleteAction.buttonTitle, role: .destructive) {
                    perform(pendingDeleteAction)
                    self.pendingDeleteAction = nil
                }
                .disabled(model.isStorageActionBusy)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAction = nil
            }
        } message: {
            if let pendingDeleteAction {
                Text(pendingDeleteAction.confirmationMessage)
            }
        }
        .alert("Enable Quick Launch?", isPresented: $isPresentingQuickLaunchWarning) {
            Button("Enable") { quickLaunch = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Minecraft will start automatically.\n\nHold Option (⌥) during startup to cancel Quick Launch.")
        }
    }

    private var quickLaunchBinding: Binding<Bool> {
        Binding(
            get: { quickLaunch },
            set: { isEnabled in
                if isEnabled {
                    isPresentingQuickLaunchWarning = true
                } else {
                    quickLaunch = false
                }
            }
        )
    }

    private var minecraftUpdateModeBinding: Binding<Int> {
        Binding(
            get: {
                guard automaticallyCheckGameUpdates else {
                    return MinecraftUpdateMode.off.rawValue
                }
                return automaticallyInstallGameUpdates
                    ? MinecraftUpdateMode.checkAndInstall.rawValue
                    : MinecraftUpdateMode.onlyCheck.rawValue
            },
            set: { rawValue in
                let mode = MinecraftUpdateMode(rawValue: rawValue) ?? .onlyCheck
                automaticallyCheckGameUpdates = mode != .off
                automaticallyInstallGameUpdates = mode == .checkAndInstall
            }
        )
    }

    private func perform(_ action: DeleteAction) {
        guard !model.isStorageActionBusy else {
            return
        }
        completedAction = nil
        Task {
            let succeeded: Bool
            switch action {
            case .runtime:
                succeeded = await model.deleteRuntime()
            case .game:
                succeeded = await model.deleteInstalledGames()
            case .data:
                succeeded = await model.deleteMinecraftData()
            }
            guard succeeded else {
                return
            }
            completedAction = action
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if completedAction == action {
                completedAction = nil
            }
        }
    }
}

private enum MinecraftUpdateMode: Int {
    case off
    case onlyCheck
    case checkAndInstall
}
