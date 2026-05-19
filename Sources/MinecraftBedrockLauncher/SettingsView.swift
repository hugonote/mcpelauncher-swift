import MinecraftBedrockLauncherCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(LauncherPreferences.automaticallyCheckRuntimeUpdatesKey)
    private var automaticallyCheckRuntimeUpdates = true

    @AppStorage(LauncherPreferences.automaticallyCheckGameUpdatesKey)
    private var automaticallyCheckGameUpdates = true

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Automatic Checks")
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
                        subtitle: "Keep native launcher files current",
                        systemImage: "cpu",
                        isOn: $automaticallyCheckRuntimeUpdates
                    )
                    Divider()
                    ToggleRow(
                        title: "Minecraft",
                        subtitle: "Check Google Play automatically",
                        systemImage: "cube",
                        isOn: $automaticallyCheckGameUpdates
                    )
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Game")
                    .font(.headline)

                VStack(spacing: 0) {
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
                        action: { pendingDeleteAction = .runtime }
                    )
                    Divider()
                    DeleteRow(
                        title: "Delete Game",
                        subtitle: "Remove installed versions and APKs",
                        systemImage: "cube",
                        isWorking: model.isDeletingGame,
                        isComplete: completedAction == .game,
                        action: { pendingDeleteAction = .game }
                    )
                    Divider()
                    DeleteRow(
                        title: "Delete Data",
                        subtitle: "Remove saves, settings, and cache",
                        systemImage: "externaldrive",
                        isWorking: model.isDeletingData,
                        isComplete: completedAction == .data,
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
            KeyboardShortcutBridge(keyCode: 53) {
                dismiss()
            }
        )
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
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAction = nil
            }
        } message: {
            if let pendingDeleteAction {
                Text(pendingDeleteAction.confirmationMessage)
            }
        }
    }

    private func perform(_ action: DeleteAction) {
        Task {
            switch action {
            case .runtime:
                await model.deleteRuntime()
            case .game:
                await model.deleteInstalledGames()
            case .data:
                await model.deleteMinecraftData()
            }
            completedAction = action
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if completedAction == action {
                completedAction = nil
            }
        }
    }
}

private struct ToggleRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .primaryIconBounce(id: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

private struct SegmentedRow: View {
    struct Option: Identifiable {
        var title: String
        var value: Int

        var id: Int {
            value
        }
    }

    var title: String
    var subtitle: String
    var systemImage: String
    @Binding var selection: Int
    var options: [Option]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .primaryIconBounce(id: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title)
                        .tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 176)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

private struct DeleteRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isWorking: Bool
    var isComplete: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .primaryIconBounce(id: systemImage)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(role: .destructive, action: action) {
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isWorking ? 1 : 0)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .opacity(isComplete && !isWorking ? 1 : 0)
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .opacity(!isWorking && !isComplete ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .animation(.easeInOut(duration: 0.18), value: isWorking)
                .animation(.easeInOut(duration: 0.18), value: isComplete)
            }
            .buttonStyle(.borderless)
            .disabled(isWorking)
            .help(title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

private enum DeleteAction: Identifiable {
    case runtime
    case game
    case data

    var id: String {
        buttonTitle
    }

    var buttonTitle: String {
        switch self {
        case .runtime:
            return "Delete Runtime"
        case .game:
            return "Delete Game"
        case .data:
            return "Delete Data"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .runtime:
            return "Delete runtime?"
        case .game:
            return "Delete installed game?"
        case .data:
            return "Delete Minecraft data?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .runtime:
            return "The native runtime will be removed and downloaded again when needed."
        case .game:
            return "Installed Minecraft versions and downloaded APK files will be removed."
        case .data:
            return "Minecraft data and cache will be removed, including local settings and worlds."
        }
    }
}

private struct KeyboardShortcutBridge: NSViewRepresentable {
    var keyCode: UInt16
    var action: () -> Void

    func makeNSView(context: Context) -> ShortcutView {
        let view = ShortcutView()
        view.keyCode = keyCode
        view.action = action
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: ShortcutView, context: Context) {
        view.keyCode = keyCode
        view.action = action
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class ShortcutView: NSView {
        var keyCode: UInt16 = 0
        var action: () -> Void = {}

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == keyCode {
                action()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
