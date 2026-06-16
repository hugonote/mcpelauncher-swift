import SwiftUI

extension ContentView {
    var keychainErrorView: some View {
        VStack(spacing: 12) {
            DrawOnSymbolView(systemName: "key.slash", size: 36)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Keychain Access Needed")
                    .font(.title3.weight(.semibold))
                Text("Authorization lets the launcher check Google Play and download Minecraft")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
            }

            Button {
                Task {
                    let wasQuickLaunch = pendingQuickLaunch && !hasQueuedOrActiveContentImport
                    pendingQuickLaunch = false
                    await model.retryStoredCredentialAccess(forQuickLaunch: wasQuickLaunch)
                    if wasQuickLaunch {
                        await runQuickLaunchIfReady()
                    }
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: compactButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .offset(y: -18)
    }

    var corruptedAppView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.yellow)
                .primaryIconBounce(id: "corrupted-app")
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Application Corrupted")
                    .font(.title3.weight(.semibold))
                Text("Reinstall the launcher and try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
            }

            Button {
                window?.close()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: compactButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .offset(y: -18)
    }

    var networkUnavailableView: some View {
        VStack(spacing: 12) {
            OfflineGlobeView()
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("No Internet Connection")
                    .font(.title3.weight(.semibold))
                Text(networkUnavailableMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 276)
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for connection")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 32)
        }
        .offset(y: -26)
    }

    private var networkUnavailableMessage: String {
        if model.selectedVersion == nil {
            return "Connect to download Minecraft"
        }
        return "Connect to download the runtime"
    }

    private var compactButtonWidth: CGFloat {
        96
    }
}
