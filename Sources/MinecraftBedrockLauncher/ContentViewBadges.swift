import SwiftUI

enum TitleIconBadge: Equatable {
    case missing
    case working
    case updateAvailable

    var accessibilityLabel: String {
        switch self {
        case .missing:
            return "Version missing"
        case .working:
            return "Working"
        case .updateAvailable:
            return "Update available"
        }
    }
}

struct OfflineGlobeView: View {
    var body: some View {
        DrawOnSymbolView(systemName: "network.slash", size: 54)
            .frame(width: 68, height: 68)
    }
}

struct DrawOnSymbolView: View {
    var systemName: String
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                ZStack {
                    if isVisible {
                        icon
                            .transition(.symbolEffect(.drawOn.byLayer))
                    }
                }
                .onAppear {
                    guard !isVisible else {
                        return
                    }
                    if reduceMotion {
                        isVisible = true
                        return
                    }
                    withAnimation {
                        isVisible = true
                    }
                }
            } else {
                icon
            }
        }
    }

    private var icon: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
    }
}

struct TitleIconBadgeView: View {
    var kind: TitleIconBadge

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        Group {
            switch kind {
            case .missing:
                missingBadge
            case .working:
                workingBadge
            case .updateAvailable:
                updateAvailableBadge
            }
        }
        .frame(width: 18, height: 18)
        .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
        .accessibilityLabel(kind.accessibilityLabel)
        .help(kind.accessibilityLabel)
    }

    private var missingBadge: some View {
        ZStack {
            Circle()
                .fill(.orange)

            Image(systemName: "questionmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var workingBadge: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .opacity(0.85)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isRotating && !reduceMotion ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 3.4).repeatForever(autoreverses: false),
                    value: isRotating
                )
                .onAppear {
                    guard !reduceMotion else {
                        return
                    }
                    isRotating = true
                }
                .onDisappear {
                    isRotating = false
                }
        }
    }

    private var updateAvailableBadge: some View {
        ZStack {
            Circle()
                .fill(.orange)

            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
        }
    }
}
