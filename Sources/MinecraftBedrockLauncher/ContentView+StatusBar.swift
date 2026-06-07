import AppKit
import SwiftUI

extension ContentView {
    var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Text(shortStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                NSWorkspace.shared.open(model.dataFolderURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open data folder")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    var quickLaunchHint: some View {
        Text("Press ⌥ to cancel Quick Launch")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 16)
    }

    private var statusColor: Color {
        if model.isBlockingNetworkUnavailable {
            return .red
        }
        if model.errorText != nil || model.runtimeState.phase == .failed || model.downloadState.phase == .failed {
            return .red
        }
        if model.updateWarningText != nil {
            return .orange
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return .orange
        }
        if isMinecraftUpdateAvailable {
            return .orange
        }
        if model.canUseSelectedVersion && model.isRuntimeReady {
            return .green
        }
        return .secondary
    }

    private var shortStatusText: String {
        if model.isBlockingNetworkUnavailable {
            return "No internet connection"
        }
        if model.activeIssue?.isNetworkUnavailable == true {
            return "Offline"
        }
        if model.isRuntimeBusy && isRuntimeUpdateWork {
            return "Runtime update"
        }
        if model.isGooglePlayBusy || model.isRuntimeBusy {
            return "Working"
        }
        if model.downloadState.phase == .failed {
            return "Download failed"
        }
        if model.runtimeState.phase == .failed {
            return "Runtime failed"
        }
        if let errorText = model.errorText {
            return shortErrorText(for: errorText)
        }
        if let updateWarningText = model.updateWarningText {
            return updateWarningText
        }
        if shouldFocusRuntime {
            return "Runtime missing"
        }
        if isMinecraftUpdateAvailable {
            return "Update available"
        }
        if model.canUseSelectedVersion && model.isRuntimeReady {
            return "Ready"
        }
        if model.credential == nil {
            return "Not signed in"
        }
        if model.latestVersion == nil {
            return "Ready to check"
        }
        return "Not installed"
    }

    private func shortErrorText(for error: String) -> String {
        if model.isBlockingNetworkUnavailable {
            return "No internet connection"
        }
        if let shortText = model.activeIssue?.shortText {
            return shortText
        }
        return error
    }
}
