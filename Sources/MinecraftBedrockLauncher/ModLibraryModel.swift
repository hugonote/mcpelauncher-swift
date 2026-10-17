import Foundation
import MinecraftBedrockLauncherCore

@MainActor
final class ModLibraryModel: ObservableObject {
    @Published private(set) var catalog: [ModDBEntry] = []
    @Published private(set) var installedMods: [InstalledMod] = []
    @Published private(set) var enabledModNames: Set<String> = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var busyModNames: Set<String> = []
    @Published var errorText: String?

    private let manager: ModManager

    init(paths: AppPaths, processRunner: ProcessRunning = FoundationProcessRunner()) {
        self.manager = ModManager(paths: paths, processRunner: processRunner)
    }

    func isInstalled(_ entry: ModDBEntry) -> Bool {
        installedMods.contains { $0.name == entry.name }
    }

    func isBusy(_ name: String) -> Bool {
        busyModNames.contains(name)
    }

    func reload(versionName: String?) {
        do {
            installedMods = try manager.installedMods()
            enabledModNames = try versionName.map { try manager.enabledModNames(for: $0) } ?? []
        } catch {
            errorText = error.localizedDescription
        }
    }

    func loadCatalog() async {
        guard !isLoadingCatalog else {
            return
        }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            catalog = ModManager.installableCatalogEntries(try await ModDBClient().fetchEntries())
        } catch {
            errorText = error.localizedDescription
        }
    }

    func install(_ entry: ModDBEntry, versionName: String?) async {
        busyModNames.insert(entry.name)
        defer { busyModNames.remove(entry.name) }
        do {
            let mod = try await manager.install(entry)
            if let versionName {
                try manager.setEnabled(true, mod: mod, versionName: versionName)
            }
            errorText = nil
            reload(versionName: versionName)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func importLocal(_ urls: [URL], versionName: String?) {
        perform {
            for url in urls {
                let mod = try manager.importLocal(url)
                if let versionName {
                    try manager.setEnabled(true, mod: mod, versionName: versionName)
                }
            }
        }
        reload(versionName: versionName)
    }

    func remove(_ mod: InstalledMod, versionName: String?) {
        perform {
            try manager.remove(mod)
        }
        reload(versionName: versionName)
    }

    func setEnabled(_ isEnabled: Bool, mod: InstalledMod, versionName: String) {
        perform {
            try manager.setEnabled(isEnabled, mod: mod, versionName: versionName)
        }
        reload(versionName: versionName)
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
