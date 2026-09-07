import AppKit
import SwiftUI

extension ContentView {
    var utilityBar: some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                presentContentImportPanel()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Import Minecraft content")
            .disabled(model.isImportingContent)

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
        .frame(height: 18)
    }

    var quickLaunchHint: some View {
        Text("Press ⌥ to cancel Quick Launch")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 18)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
    }
}
