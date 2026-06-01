import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let projectURL = URL(string: "https://github.com/hugonote/mcpelauncher-swift")!
    private let runtimeURL = URL(string: "https://github.com/minecraft-linux/mcpelauncher-manifest")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)

            VStack(spacing: 4) {
                Text("Minecraft Bedrock Launcher")
                    .font(.title2.weight(.semibold))
                Text(versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text("Unofficial macOS launcher for Minecraft: Bedrock Edition.")
                    .multilineTextAlignment(.center)

                Text("The app is MIT licensed. The runtime and bundled helper components keep their own licenses.")
                    .multilineTextAlignment(.center)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .frame(maxWidth: 320)

            HStack(spacing: 12) {
                Link("GitHub", destination: projectURL)
                Link("Runtime", destination: runtimeURL)
                Button("Licenses") {
                    NSWorkspace.shared.open(thirdPartyNoticesURL)
                }
                .buttonStyle(.link)
            }
            .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(width: 360, height: 255)
        .background(
            Button("", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
    }

    private var thirdPartyNoticesURL: URL {
        Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
            ?? projectURL
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where version != build:
            return "Version \(version) (\(build))"
        case let (.some(version), _):
            return "Version \(version)"
        default:
            return "Version 0.1.0"
        }
    }
}
