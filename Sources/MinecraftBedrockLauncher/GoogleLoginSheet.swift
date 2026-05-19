import SwiftUI

struct GoogleLoginSheet: View {
    @ObservedObject var model: LauncherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var accountIdentifier = ""
    @State private var capturedUserID = ""
    @State private var capturedOAuthToken = ""
    @State private var consentAccepted = false
    @State private var setupFinished = false
    @State private var isCompleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Google Play Sign In")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            WebLoginView { token, userID in
                capturedOAuthToken = token
                capturedUserID = userID
                completeIfReady()
            } onAccountIdentifier: { identifier in
                accountIdentifier = identifier
            } onConsentAccepted: {
                consentAccepted = true
                completeAfterGoogleSettles()
            } onSetupFinished: {
                guard !capturedOAuthToken.isEmpty else {
                    return
                }
                setupFinished = true
                completeAfterGoogleSettles()
            }
            .frame(minWidth: 520, minHeight: 560)

            HStack {
                Text(statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                if isCompleting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
    }

    private var statusText: String {
        if isCompleting {
            return "OAuth token captured. Completing sign in"
        }
        if capturedOAuthToken.isEmpty {
            return "Finish the Google prompt. The launcher will close this window automatically."
        }
        if consentAccepted || setupFinished {
            return "Finishing Google sign in"
        }
        return "Google consent is ready. Finishing automatically"
    }

    private func completeAfterGoogleSettles() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            completeIfReady()
        }
    }

    private func completeIfReady() {
        guard !isCompleting, !capturedOAuthToken.isEmpty, consentAccepted || setupFinished else {
            return
        }
        isCompleting = true
        Task {
            await model.completeLogin(
                email: accountIdentifier,
                userID: capturedUserID,
                oauthToken: capturedOAuthToken
            )
        }
    }
}
