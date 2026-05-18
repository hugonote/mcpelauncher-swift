import SwiftUI

private struct PrimaryIconBounceModifier<ID: Hashable>: ViewModifier {
    var id: ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.72)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                play()
            }
            .onChange(of: id) { _, _ in
                play()
            }
    }

    private func play() {
        isVisible = false

        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.16)
            : .interpolatingSpring(mass: 0.42, stiffness: 190, damping: 9.5, initialVelocity: 5)

        DispatchQueue.main.async {
            withAnimation(animation) {
                isVisible = true
            }
        }
    }
}

extension View {
    func primaryIconBounce<ID: Hashable>(id: ID) -> some View {
        modifier(PrimaryIconBounceModifier(id: id))
    }
}
