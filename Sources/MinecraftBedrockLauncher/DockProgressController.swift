import AppKit
import MinecraftBedrockLauncherCore

@MainActor
final class DockProgressController {
    static let shared = DockProgressController()

    private let tileView = DockProgressTileView()

    private init() {}

    func update(downloadState: DownloadState) {
        guard downloadState.phase == .downloading || downloadState.phase == .extracting else {
            clear()
            return
        }

        tileView.progress = min(max(downloadState.progress, 0), 1)
        NSApp.dockTile.contentView = tileView
        NSApp.dockTile.display()
    }

    func clear() {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }
}

private final class DockProgressTileView: NSView {
    var progress: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }

    private let appIcon = NSApp.applicationIconImage

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var isFlipped: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        appIcon?.draw(in: bounds)

        let horizontalInset = bounds.width * 0.16
        let barHeight = max(bounds.height * 0.08, 6)
        let barRect = NSRect(
            x: horizontalInset,
            y: bounds.height * 0.10,
            width: bounds.width - horizontalInset * 2,
            height: barHeight
        )
        let radius = barHeight / 2
        let backgroundPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.42).setFill()
        backgroundPath.fill()

        let fillWidth = max(barRect.width * progress, progress > 0 ? barHeight : 0)
        guard fillWidth > 0 else {
            return
        }

        let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        NSColor.controlAccentColor.setFill()
        fillPath.fill()
    }
}
