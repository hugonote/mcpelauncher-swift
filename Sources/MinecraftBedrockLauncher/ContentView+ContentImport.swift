import AppKit
import MinecraftBedrockLauncherCore
import SwiftUI

struct ContentImportDescription: Equatable {
    enum Kind: Equatable {
        case resourcePack
        case addOn
        case world
        case worldTemplate
        case mixed
    }

    var kind: Kind
    var count: Int

    init?(urls: [URL]) {
        let supportedKinds = urls.compactMap(Self.kind(for:))
        let kinds = Set(supportedKinds)
        guard !kinds.isEmpty else {
            return nil
        }
        kind = kinds.count == 1 ? kinds.first ?? .mixed : .mixed
        count = supportedKinds.count
    }

    var releaseText: String {
        "Release to import \(phrase)"
    }

    var importingText: String {
        "Importing \(phrase)"
    }

    private var phrase: String {
        if count == 1 {
            switch kind {
            case .resourcePack:
                return "resource pack"
            case .addOn:
                return "add-on"
            case .world:
                return "world"
            case .worldTemplate:
                return "world template"
            case .mixed:
                return "content file"
            }
        }

        switch kind {
        case .resourcePack:
            return "\(count) resource packs"
        case .addOn:
            return "\(count) add-ons"
        case .world:
            return "\(count) worlds"
        case .worldTemplate:
            return "\(count) world templates"
        case .mixed:
            return "\(count) content files"
        }
    }

    private static func kind(for url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "mcpack":
            return .resourcePack
        case "mcaddon":
            return .addOn
        case "mcworld":
            return .world
        case "mctemplate":
            return .worldTemplate
        default:
            return nil
        }
    }
}

typealias ContentImportDropPreview = ContentImportDescription

struct ContentImportProgress: Equatable {
    var completed: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else {
            return 0
        }
        return Double(completed) / Double(total)
    }

    var text: String {
        "Processed \(completed) of \(total)"
    }
}

extension ContentView {
    var isContentDropTargeted: Bool {
        contentImportDropPreview != nil
    }

    var contentDropStateAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }

    var contentDropTitleTransition: AnyTransition {
        guard !reduceMotion else {
            return .identity
        }
        return .opacity
    }

    var contentImportDropTarget: some View {
        ContentImportDropTarget(preview: $contentImportDropPreview) { urls in
            Task {
                await showContentImportResult(for: urls)
            }
        }
    }

    func importQueuedContentFiles() {
        if appendQueuedContentFilesToActiveImport() {
            revealLauncherForContentImportIfNeeded()
            return
        }
        guard ContentImportOpenFileQueue.shared.hasPendingURLs else {
            return
        }
        guard !isProcessingQueuedContentImport else {
            return
        }
        cancelQuickLaunchForContentImportIfNeeded()
        isProcessingQueuedContentImport = true
        revealLauncherForContentImportIfNeeded()
        Task {
            await processQueuedContentImports()
        }
    }

    func presentContentImportPanel() {
        let panel = NSOpenPanel()
        let panelDelegate = ContentImportOpenPanelDelegate()
        contentImportPanelDelegate = panelDelegate
        panel.delegate = panelDelegate
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose Minecraft Bedrock content files to import."
        panel.prompt = "Import"

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else {
                contentImportPanelDelegate = nil
                return
            }
            Task {
                await showContentImportResult(for: panel.urls)
                contentImportPanelDelegate = nil
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }

    private func appendQueuedContentFilesToActiveImport() -> Bool {
        guard model.isImportingContent else {
            return false
        }
        let urls = ContentImportOpenFileQueue.shared.takePendingURLs()
        guard !urls.isEmpty else {
            return false
        }
        return model.enqueueContentFilesForActiveImport(urls)
    }

    private func showContentImportResult(for urls: [URL]) async {
        guard let result = await model.importContentFiles(
            urls,
            shouldImportIncompatibleContent: { warnings in
                await confirmIncompatibleContentImport(warnings)
            }
        ) else {
            return
        }
        showContentImportAlert(title: result.title, message: result.message)
    }

    @MainActor
    private func confirmIncompatibleContentImport(_ warnings: [ContentPackCompatibilityWarning]) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = warnings.count == 1
            ? "Minecraft content may be incompatible"
            : "Some Minecraft content may be incompatible"
        alert.informativeText = incompatibleContentMessage(for: warnings)
        if let icon = NSImage(named: NSImage.cautionName) {
            alert.icon = icon
        }
        let skipButton = alert.addButton(withTitle: "Skip")
        skipButton.keyEquivalent = "\r"
        let importButton = alert.addButton(withTitle: "Import Anyway")
        importButton.keyEquivalent = ""
        importButton.hasDestructiveAction = true

        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { modalResponse in
                    continuation.resume(returning: modalResponse)
                }
            }
        } else {
            response = alert.runModal()
        }
        return response == .alertSecondButtonReturn
    }

    private func incompatibleContentMessage(for warnings: [ContentPackCompatibilityWarning]) -> String {
        let summary = warnings.count == 1
            ? "This content requires a newer Minecraft version and may not appear in Minecraft."
            : "These content items require a newer Minecraft version and may not appear in Minecraft."
        if warnings.count == 1, let warning = warnings.first {
            return [
                summary,
                "",
                "\(cleanMinecraftFormattingCodes(warning.contentName)) requires Minecraft \(warning.requiredVersion) or newer.",
                "Installed: \(warning.installedVersion)."
            ].joined(separator: "\n")
        }
        let warningLines = warnings
            .prefix(5)
            .map {
                "- \(cleanMinecraftFormattingCodes($0.contentName)) requires Minecraft \($0.requiredVersion) or newer. Installed: \($0.installedVersion)."
            }
        let remainingCount = warnings.count - warningLines.count
        let remainingItem = remainingCount == 1 ? "item" : "items"
        let remainingLine = remainingCount > 0 ? ["- \(remainingCount) more incompatible content \(remainingItem)."] : []
        return ([summary, ""] + warningLines + remainingLine)
            .joined(separator: "\n")
    }

    private func cleanMinecraftFormattingCodes(_ value: String) -> String {
        var result = ""
        var shouldSkipNext = false
        for character in value {
            if shouldSkipNext {
                shouldSkipNext = false
                continue
            }
            if character == "§" {
                shouldSkipNext = true
                continue
            }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func processQueuedContentImports() async {
        revealLauncherForContentImportIfNeeded()
        try? await Task.sleep(nanoseconds: 150_000_000)
        revealLauncherForContentImportIfNeeded()
        let urls = ContentImportOpenFileQueue.shared.takePendingURLs()
        if !urls.isEmpty {
            await showContentImportResult(for: urls)
        }

        isProcessingQueuedContentImport = false
        if ContentImportOpenFileQueue.shared.hasPendingURLs {
            importQueuedContentFiles()
        }
    }

    private func showContentImportAlert(title: String, message: String) {
        isStartupComplete = true
        revealLauncherWindow()
        contentImportResultTitle = title
        contentImportResultMessage = message
        isShowingContentImportResult = true
    }
}

private struct ContentImportDropTarget: NSViewRepresentable {
    @Binding var preview: ContentImportDropPreview?
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> ContentImportDropTargetView {
        let view = ContentImportDropTargetView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ContentImportDropTargetView, context: Context) {
        let previewBinding = $preview
        nsView.onPreviewChanged = { preview in
            previewBinding.wrappedValue = preview
        }
        nsView.onDrop = onDrop
    }
}

private final class ContentImportDropTargetView: NSView {
    var onPreviewChanged: (ContentImportDropPreview?) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    private var preview: ContentImportDropPreview? {
        didSet {
            guard preview != oldValue else {
                return
            }
            onPreviewChanged(preview)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        preview = nil
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        preview = nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = supportedContentURLs(from: sender)
        preview = nil
        guard !urls.isEmpty else {
            return false
        }
        onDrop(urls)
        return true
    }

    private func dragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        let preview = ContentImportDropPreview(urls: supportedContentURLs(from: sender))
        self.preview = preview
        return preview == nil ? [] : .copy
    }

    private func supportedContentURLs(from sender: any NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])
        let urls = (objects as? [URL]) ?? (objects as? [NSURL])?.map { $0 as URL } ?? []
        return urls.filter(ContentImportOpenFileQueue.isSupportedContentURL)
    }
}

final class ContentImportOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return true
        }
        return ContentImportOpenFileQueue.isSupportedContentURL(url)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard ContentImportOpenFileQueue.isSupportedContentURL(url) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }
}
