import AppKit
import MinecraftBedrockLauncherCore
import SwiftUI
import UniformTypeIdentifiers

struct ModsView: View {
    @ObservedObject var model: LauncherViewModel
    @ObservedObject var library: ModLibraryModel
    @State private var isImporting = false

    private var versionName: String? {
        model.selectedVersion?.versionName
    }

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 380, height: 560)
        .task {
            library.reload(versionName: versionName)
            await library.loadCatalog()
        }
        .onChange(of: versionName) { _, newValue in
            library.reload(versionName: newValue)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip, UTType(filenameExtension: "so") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                return
            }
            importFiles(urls)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: versionName.map { "Installed · \($0)" } ?? "Installed") {
                if library.installedMods.isEmpty {
                    SettingsRow(title: "No Mod", subtitle: "Install one from the catalog or a file", systemImage: "puzzlepiece") {
                        EmptyView()
                    }
                }
                ForEach(Array(library.installedMods.enumerated()), id: \.element.id) { index, mod in
                    if index > 0 {
                        Divider()
                    }
                    installedRow(mod)
                }
            }

            SettingsSection(title: "Catalog") {
                if library.isLoadingCatalog && library.catalog.isEmpty {
                    SettingsRow(title: "Loading…", subtitle: "mcpelauncher mod catalog", systemImage: "network") {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ForEach(Array(library.catalog.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                    }
                    catalogRow(entry)
                }
            }

            HStack {
                Button("Add Mod File…") {
                    isImporting = true
                }
                Spacer()
                Button("Open Mods Folder") {
                    NSWorkspace.shared.open(model.paths.modsURL)
                }
                .buttonStyle(.link)
            }
            .font(.caption)

            if let errorText = library.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Mods are arm64 Android libraries loaded by mcpelauncher. They apply to the selected version only and are not supported by the launcher's issue tracker.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func installedRow(_ mod: InstalledMod) -> some View {
        let isCompatible = versionName.map(mod.supports(versionName:)) ?? true
        return SettingsRow(
            title: mod.name,
            subtitle: subtitle(for: mod, isCompatible: isCompatible),
            systemImage: mod.source == .local ? "doc.badge.gearshape" : "puzzlepiece.extension"
        ) {
            HStack(spacing: 8) {
                Toggle(mod.name, isOn: enabledBinding(for: mod))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(versionName == nil || !isCompatible)

                DeleteButton(help: "Remove \(mod.name)", isWorking: false, isDisabled: false) {
                    library.remove(mod, versionName: versionName)
                }
            }
        }
    }

    private func catalogRow(_ entry: ModDBEntry) -> some View {
        SettingsRow(
            title: entry.name,
            subtitle: entry.description,
            systemImage: "shippingbox"
        ) {
            if library.isBusy(entry.name) {
                ProgressView()
                    .controlSize(.small)
            } else if library.isInstalled(entry) {
                Button("Update") {
                    Task { await library.install(entry, versionName: versionName) }
                }
                .controlSize(.small)
            } else {
                Button("Install") {
                    Task { await library.install(entry, versionName: versionName) }
                }
                .controlSize(.small)
            }
        }
    }

    private func subtitle(for mod: InstalledMod, isCompatible: Bool) -> String {
        var parts = [mod.version]
        if let requirement = mod.minecraftRequirement {
            parts.append("Minecraft \(requirement)")
        }
        if !isCompatible {
            parts.append("Not compatible")
        }
        return parts.joined(separator: " · ")
    }

    private func enabledBinding(for mod: InstalledMod) -> Binding<Bool> {
        Binding(
            get: { library.enabledModNames.contains(mod.name) },
            set: { isEnabled in
                guard let versionName else {
                    return
                }
                library.setEnabled(isEnabled, mod: mod, versionName: versionName)
            }
        )
    }

    private func importFiles(_ urls: [URL]) {
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            accessed.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        library.importLocal(urls, versionName: versionName)
    }
}
