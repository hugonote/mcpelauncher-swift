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
    @State private var settleTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Google Play Sign In")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    cancelLogin()
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
                completeIfReady()
            } onConsentAccepted: {
                consentAccepted = true
                completeAfterGoogleSettles()
            } onSetupFinished: {
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
        .onDisappear {
            cancelLogin()
        }
    }

    private var statusText: String {
        if isCompleting {
            return "OAuth token captured. Completing sign in"
        }
        if capturedOAuthToken.isEmpty {
            return "Finish the Google prompt. The launcher will close this window automatically."
        }
        if accountIdentifier.isEmpty {
            return "Waiting for Google account details"
        }
        if consentAccepted || setupFinished {
            return "Finishing Google sign in"
        }
        return "Google consent is ready. Finishing automatically"
    }

    private func completeAfterGoogleSettles() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            completeIfReady()
        }
    }

    private func completeIfReady() {
        guard !isCompleting,
              !capturedOAuthToken.isEmpty,
              !accountIdentifier.isEmpty,
              consentAccepted || setupFinished else {
            return
        }
        isCompleting = true
        settleTask?.cancel()
        settleTask = nil
        completionTask = Task { @MainActor in
            let succeeded = await model.completeLogin(
                email: accountIdentifier,
                userID: capturedUserID,
                oauthToken: capturedOAuthToken
            )
            guard !Task.isCancelled else {
                return
            }
            completionTask = nil
            isCompleting = false
            if succeeded {
                dismiss()
            }
        }
    }

    private func cancelLogin() {
        settleTask?.cancel()
        settleTask = nil
        completionTask?.cancel()
        completionTask = nil
        isCompleting = false
    }
}
