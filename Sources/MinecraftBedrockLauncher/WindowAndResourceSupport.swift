import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

enum LauncherResourceLoader {
    static func image(named name: String, fileExtension: String) -> NSImage? {
        for url in candidateURLs(named: name, fileExtension: fileExtension) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private static func candidateURLs(named name: String, fileExtension: String) -> [URL] {
        let fileName = "\(name).\(fileExtension)"
        var urls: [URL] = []

        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            urls.append(url)
        }

        let resourceURL = Bundle.main.resourceURL
        let bundleNames = [
            "SwiftLauncher_MinecraftBedrockLauncher.bundle",
            "MinecraftBedrockLauncher_MinecraftBedrockLauncher.bundle"
        ]
        for bundleName in bundleNames {
            if let url = resourceURL?
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false) {
                urls.append(url)
            }
        }

        if let executableURL = Bundle.main.executableURL {
            let buildDirectoryURL = executableURL.deletingLastPathComponent()
            for bundleName in bundleNames {
                urls.append(
                    buildDirectoryURL
                        .appendingPathComponent(bundleName, isDirectory: true)
                        .appendingPathComponent(fileName, isDirectory: false)
                )
            }
        }

        return urls
    }
}

struct WindowConfigurator: NSViewRepresentable {
    @Binding var window: NSWindow?
    var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window, isVisible: isVisible, coordinator: context.coordinator)
            window = view.window
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window, isVisible: isVisible, coordinator: context.coordinator)
            window = view.window
        }
    }

    private func configure(window: NSWindow?, isVisible: Bool, coordinator: Coordinator) {
        guard let window else {
            return
        }
        coordinator.observeClose(of: window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.remove(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.level = .normal
        window.hidesOnDeactivate = false
        StartupWindowVisibility.shared.hideIfNeeded(window)
        let wasHidden = window.alphaValue == 0
        window.alphaValue = isVisible ? 1 : 0
        if isVisible && wasHidden {
            StartupWindowVisibility.shared.reveal(window)
        } else if isVisible {
            window.ignoresMouseEvents = false
        }
    }

    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }

        func observeClose(of window: NSWindow) {
            guard observedWindow !== window else {
                return
            }

            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }

            observedWindow = window
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
