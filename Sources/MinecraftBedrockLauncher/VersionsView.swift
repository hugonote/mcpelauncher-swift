import AppKit
import MinecraftBedrockLauncherCore
import SwiftUI

struct VersionsView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var supportedVersions: [SupportedMinecraftVersion] = []
    @State private var isLoadingSupportedVersions = false
    @State private var pendingDeletion: InstalledVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Installed") {
                if model.installedVersions.isEmpty {
                    emptyRow
                }
                ForEach(Array(model.installedVersions.enumerated()), id: \.element.id) { index, version in
                    if index > 0 {
                        Divider()
                    }
                    installedRow(version)
                }
            }

            SettingsSection(title: "Install") {
                SettingsRow(
                    title: "Another Version",
                    subtitle: installSubtitle,
                    systemImage: "arrow.down.circle"
                ) {
                    installMenu
                }
            }

            Text("Worlds are shared between versions. Launching an older version first backs up your worlds.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open World Backups") {
                NSWorkspace.shared.open(model.paths.worldBackupsURL)
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(!FileManager.default.fileExists(atPath: model.paths.worldBackupsURL.path))
        }
        .padding(16)
        .frame(width: 350)
        .task {
            await loadSupportedVersions()
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.versionName ?? "")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            if let pendingDeletion {
                Button("Delete Version", role: .destructive) {
                    Task { await model.deleteVersion(pendingDeletion) }
                    self.pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("The game files of this version are removed. Worlds and settings are kept.")
        }
    }

    private var emptyRow: some View {
        SettingsRow(title: "No Version", subtitle: "Install a version below", systemImage: "cube") {
            EmptyView()
        }
    }

    private func installedRow(_ version: InstalledVersion) -> some View {
        let isSelected = model.selectedVersion?.versionName == version.versionName
        return SettingsRow(
            title: version.versionName,
            subtitle: subtitle(for: version, isSelected: isSelected),
            systemImage: isSelected ? "checkmark.circle.fill" : "circle"
        ) {
            HStack(spacing: 8) {
                Button("Select") {
                    model.selectVersion(version)
                }
                .controlSize(.small)
                .disabled(isSelected || !model.canManageVersions)

                DeleteButton(
                    help: "Delete \(version.versionName)",
                    isWorking: false,
                    isDisabled: !model.canManageVersions
                ) {
                    pendingDeletion = version
                }
            }
        }
    }

    private func subtitle(for version: InstalledVersion, isSelected: Bool) -> String {
        var parts = [String(version.versionCode)]
        if isSelected {
            parts.append("Selected")
        }
        if !supportedVersions.isEmpty,
           !supportedVersions.contains(where: { $0.versionCode == version.versionCode }) {
            parts.append("Unsupported")
        }
        return parts.joined(separator: " · ")
    }

    private var installableVersions: [SupportedMinecraftVersion] {
        model.installableVersions(from: supportedVersions)
    }

    private var installSubtitle: String {
        if let installing = model.installingVersionName {
            return "Installing \(installing)… \(Int(model.downloadState.progress * 100))%"
        }
        if model.credential == nil {
            return "Sign in to download versions"
        }
        return "Versions supported on macOS"
    }

    private var installMenu: some View {
        Menu {
            if isLoadingSupportedVersions {
                Button("Loading…") {}
                    .disabled(true)
            } else if installableVersions.isEmpty {
                Button("All supported versions installed") {}
                    .disabled(true)
            } else {
                ForEach(installableVersions, id: \.versionCode) { version in
                    Button(version.versionName) {
                        model.installVersion(version)
                    }
                }
            }
        } label: {
            if model.installingVersionName != nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Choose")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.credential == nil || !model.canManageVersions)
    }

    private func loadSupportedVersions() async {
        isLoadingSupportedVersions = true
        defer { isLoadingSupportedVersions = false }
        supportedVersions = await model.supportedMinecraftVersions()
    }
}
