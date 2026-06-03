import SwiftUI

extension ContentView {
    var accountBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 104)

            Text(model.displayCredentialEmail ?? "Not signed in")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 250, alignment: .trailing)
                .help(model.displayCredentialEmail ?? "Not signed in")

            if model.credential == nil {
                Button("Sign in") {
                    model.showingLogin = true
                }
                .buttonStyle(.link)
                .font(.callout.weight(.semibold))
            } else {
                Button {
                    isShowingSignOutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Log out")
            }
        }
        .frame(height: 28)
    }
}
