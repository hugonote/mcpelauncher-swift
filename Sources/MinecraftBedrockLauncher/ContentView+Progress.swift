import Foundation
import SwiftUI

extension ContentView {
    @ViewBuilder
    var progress: some View {
        if model.canSkipRuntimeUpdateCheck {
            runtimeProgress
        } else if isShowingDownloadProgress {
            VStack(spacing: 6) {
                if model.downloadState.phase == .extracting {
                    inlineProgressText(primary: downloadStatusText)
                } else {
                    if isDeterminateDownloadProgress {
                        ProgressView(value: model.downloadState.progress)
                        HStack(spacing: 8) {
                            progressText(primary: downloadStatusText, secondary: downloadSecondaryStatusText)
                            if model.downloadState.phase == .downloading {
                                Button {
                                    model.cancelDownload()
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Cancel download")
                            }
                        }
                    } else {
                        inlineProgressText(primary: downloadStatusText, secondary: downloadSecondaryStatusText)
                    }
                }
            }
        } else if model.isRuntimeBusy {
            runtimeProgress
        }
    }

    private var runtimeProgress: some View {
        VStack(spacing: 6) {
            if model.runtimeState.phase == .installing {
                inlineProgressText(primary: runtimeProgressText, height: 50)
            } else {
                if isDeterminateRuntimeProgress {
                    ProgressView(value: model.runtimeState.progress)
                    if model.canSkipRuntimeUpdateCheck {
                        runtimeSkipProgress
                    } else {
                        runtimeCancelableProgressText
                    }
                } else {
                    if model.runtimeState.phase == .checking {
                        runtimeSkipProgress
                    } else if model.runtimeState.phase == .downloading {
                        runtimeCancelableInlineProgress
                    } else {
                        inlineProgressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
                    }
                }
            }
        }
    }

    private var runtimeSkipProgress: some View {
        inlineProgressText(primary: runtimeProgressText)
            .overlay(alignment: .bottom) {
                Button {
                    model.skipRuntimeUpdateCheck()
                } label: {
                    Label("Skip", systemImage: "forward.end")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Skip runtime and Google Play update checks")
                .disabled(!model.canSkipRuntimeUpdateCheck)
                .opacity(model.canSkipRuntimeUpdateCheck ? 1 : 0)
                .accessibilityHidden(!model.canSkipRuntimeUpdateCheck)
                .offset(y: 14)
            }
    }

    private var runtimeCancelableProgressText: some View {
        HStack(spacing: 8) {
            progressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
            runtimeCancelButton
        }
    }

    private var runtimeCancelableInlineProgress: some View {
        HStack(spacing: 8) {
            inlineProgressText(primary: runtimeProgressText, secondary: runtimeSecondaryProgressText)
            runtimeCancelButton
        }
    }

    private var runtimeCancelButton: some View {
        Button {
            model.cancelRuntimeDownload()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Cancel runtime download")
    }

    private func inlineProgressText(primary: String, secondary: String? = nil, height: CGFloat = 31) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            compactProgressText(primary: primary, secondary: secondary)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func compactProgressText(primary: String, secondary: String?) -> some View {
        if let secondary {
            VStack(alignment: .leading, spacing: 1) {
                progressLine(primary, font: .caption, style: .secondary)
                progressLine(secondary, font: .caption2, style: .tertiary)
            }
        } else {
            progressLine(primary, font: .caption, style: .secondary)
        }
    }

    private func progressText(primary: String, secondary: String?) -> some View {
        VStack(spacing: 1) {
            progressLine(primary, font: .caption, style: .secondary)
                .frame(maxWidth: .infinity)

            progressLine(secondary ?? " ", font: .caption2, style: .tertiary)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 31)
    }

    private func progressLine(_ text: String, font: Font, style: HierarchicalShapeStyle) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(style)
            .lineLimit(1)
            .truncationMode(.middle)
            .monospacedDigit()
    }

    var isShowingProgress: Bool {
        if model.canSkipRuntimeUpdateCheck {
            return true
        }
        if isShowingDownloadProgress {
            return true
        }
        return model.isRuntimeBusy
    }

    private var isShowingDownloadProgress: Bool {
        model.downloadState.phase != .idle
            && model.downloadState.phase != .failed
            && model.downloadState.phase != .installed
    }

    private var isDeterminateDownloadProgress: Bool {
        model.downloadState.phase == .downloading || model.downloadState.phase == .extracting
    }

    private var isDeterminateRuntimeProgress: Bool {
        model.runtimeState.phase == .downloading && model.runtimeState.progress > 0
    }

    private var runtimeStatusText: String {
        switch model.runtimeState.phase {
        case .missing:
            return "Not installed"
        case .checking:
            return model.runtimeState.detail ?? "Checking"
        case .downloading:
            return model.runtimeState.detail ?? "Downloading"
        case .installing:
            return model.runtimeState.detail ?? "Installing"
        case .ready:
            let version = model.runtimeState.version ?? "installed"
            if let detail = model.runtimeState.detail, !detail.isEmpty {
                return "\(version) - \(detail)"
            }
            return version
        case .failed:
            return model.runtimeState.error ?? "Runtime update failed"
        }
    }

    private var runtimeProgressText: String {
        let state = model.runtimeState
        if state.phase == .downloading {
            var parts: [String] = []
            if let bytes = state.bytesReceived, let total = state.totalBytes, total > 0 {
                let percent = Double(bytes) / Double(total) * 100
                parts.append(String(format: "%.1f%%", percent))
                parts.append("\(Self.byteFormatter.string(fromByteCount: bytes)) / \(Self.byteFormatter.string(fromByteCount: total))")
            }
            if !parts.isEmpty {
                return parts.joined(separator: " - ")
            }
        }
        return state.detail ?? runtimeStatusText
    }

    private var runtimeSecondaryProgressText: String? {
        guard model.runtimeState.phase == .downloading else {
            return nil
        }
        return speedAndETA(speed: model.runtimeState.speedBytesPerSecond, eta: model.runtimeState.etaSeconds)
    }

    private var downloadStatusText: String {
        let state = model.downloadState
        if state.phase == .downloading {
            var parts: [String] = []
            if let bytes = state.bytesReceived, let total = state.totalBytes, total > 0 {
                let percent = Double(bytes) / Double(total) * 100
                parts.append(String(format: "%.1f%%", percent))
                parts.append("\(Self.byteFormatter.string(fromByteCount: bytes)) / \(Self.byteFormatter.string(fromByteCount: total))")
            }
            if parts.isEmpty {
                parts.append("Downloading")
            }
            return parts.joined(separator: " - ")
        }
        if let detail = state.detail {
            return detail
        }
        switch state.phase {
        case .idle:
            return "Ready"
        case .authenticating:
            return "Signing in"
        case .fetchingLatest:
            return "Checking for updates"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Extracting"
        case .preparingFirstLaunch:
            return "Preparing first launch"
        case .installed:
            return "Installed"
        case .failed:
            return state.error ?? "Failed"
        }
    }

    private var downloadSecondaryStatusText: String? {
        guard model.downloadState.phase == .downloading else {
            return nil
        }
        return speedAndETA(speed: model.downloadState.speedBytesPerSecond, eta: model.downloadState.etaSeconds)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static func formatETA(_ seconds: Double) -> String {
        let value = max(Int(seconds.rounded()), 0)
        if value >= 3600 {
            return "\(value / 3600)h \((value % 3600) / 60)m"
        }
        if value >= 60 {
            return "\(value / 60)m \(value % 60)s"
        }
        return "\(value)s"
    }

    private func speedAndETA(speed: Double?, eta: Double?) -> String? {
        var parts: [String] = []
        if let speed, speed > 1 {
            parts.append("\(Self.byteFormatter.string(fromByteCount: Int64(speed)))/s")
        }
        if let eta, eta.isFinite, eta > 0 {
            parts.append("\(Self.formatETA(eta)) left")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }
}
