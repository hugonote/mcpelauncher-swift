import AppKit
import SwiftUI

extension Bundle {
    static let launcherResources: Bundle? = {
        if let bundle = Bundle.main
            .url(forResource: "SwiftLauncher_MinecraftBedrockLauncher", withExtension: "bundle")
            .flatMap(Bundle.init(url:)) {
            return bundle
        }
        return Bundle.main.bundleURL.pathExtension == "app" ? nil : .module
    }()
}

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

struct WindowConfigurator: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.windowDidChange = handleWindowChange
        return view
    }

    func updateNSView(_ view: WindowAccessorView, context: Context) {
        view.windowDidChange = handleWindowChange
        configure(window: view.window)
    }

    private func handleWindowChange(_ newWindow: NSWindow?) {
        configure(window: newWindow)
        guard window !== newWindow else {
            return
        }
        window = newWindow
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.remove(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.isRestorable = false
        window.level = .normal
        window.hidesOnDeactivate = false
        StartupWindowVisibility.shared.attachLauncherWindow(window)
    }
}

final class WindowAccessorView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}

struct QuickLaunchOptionMonitor: NSViewRepresentable {
    var isActive: Bool
    var onOptionPressed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.update(isActive: isActive, onOptionPressed: onOptionPressed)
        return NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onOptionPressed: onOptionPressed)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var monitor: Any?
        private var isActive = false
        private var onOptionPressed: () -> Void = {}

        deinit {
            stop()
        }

        func update(isActive: Bool, onOptionPressed: @escaping () -> Void) {
            self.isActive = isActive
            self.onOptionPressed = onOptionPressed

            if isActive {
                startIfNeeded()
            } else {
                stop()
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startIfNeeded() {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else {
                    return event
                }
                if self.isActive,
                   event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .contains(.option) {
                    self.onOptionPressed()
                }
                return event
            }
        }
    }
}
