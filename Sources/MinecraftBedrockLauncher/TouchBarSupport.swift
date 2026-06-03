import AppKit
import SwiftUI

struct LauncherTouchBarConfigurator: NSViewRepresentable {
    var configuration: LauncherTouchBarConfiguration

    func makeCoordinator() -> LauncherTouchBarCoordinator {
        LauncherTouchBarCoordinator(configuration: configuration)
    }

    func makeNSView(context: Context) -> LauncherTouchBarHostView {
        let view = LauncherTouchBarHostView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(configuration)
        return view
    }

    func updateNSView(_ view: LauncherTouchBarHostView, context: Context) {
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.update(configuration)
        context.coordinator.attach(to: view.window)
    }

    static func dismantleNSView(_ view: LauncherTouchBarHostView, coordinator: LauncherTouchBarCoordinator) {
        coordinator.detach(from: view.window)
        view.windowDidChange = nil
    }
}

final class LauncherTouchBarHostView: NSView {
    var windowDidChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
    }
}
