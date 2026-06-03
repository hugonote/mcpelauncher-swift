import AppKit
import Foundation
import MinecraftBedrockLauncherCore

private struct SignOutLegacyGooglePlayStateCleanupError: LocalizedError {
    var url: URL
    var underlyingError: Error

    var errorDescription: String? {
        "Signed out, but legacy Google Play state could not be removed at \(url.path): \(underlyingError.localizedDescription)"
    }
}

extension LauncherViewModel {
    func loadStoredCredentialAndFetchLatest() async {
        await loadStoredCredential(fetchLatestAfterLoad: true)
    }

    func loadStoredCredential() async {
        await loadStoredCredential(fetchLatestAfterLoad: false)
    }

    private func loadStoredCredential(fetchLatestAfterLoad: Bool) async {
        do {
            credentialAccessDenied = false
            guard try loadStoredCredentialIfNeeded() != nil else {
                return
            }
            if fetchLatestAfterLoad && LauncherPreferences.canAutomaticallyCheckGameUpdates {
                await fetchLatest()
            }
        } catch KeychainError.accessDenied {
            credentialAccessDenied = true
            errorText = "Keychain access was denied."
        } catch {
            show(error)
        }
    }

    func retryStoredCredentialAccess(forQuickLaunch: Bool = false) async {
        didTryLoadingStoredCredential = false
        credentialAccessDenied = false
        errorText = nil
        updateWarningText = nil
        if forQuickLaunch {
            beginQuickLaunch()
        }
        await loadStoredCredential()
        if forQuickLaunch && canStartQuickLaunch {
            await continueStartupForQuickLaunch()
        } else {
            if forQuickLaunch {
                finishQuickLaunch()
            }
            await continueStartupAfterWindowReveal()
        }
    }

    func signOut() {
        do {
            try credentialStore.clearCredential()
            let legacyStateCleanupSucceeded = clearLegacyGooglePlayStateForSignOut()
            credential = nil
            didTryLoadingStoredCredential = false
            credentialAccessDenied = false
            latestVersion = nil
            googlePlayLatestVersion = nil
            downloadState = DownloadState()
            errorText = nil
            if legacyStateCleanupSucceeded {
                updateWarningText = nil
            } else {
                updateWarningText = "Signed out, but old Google Play state could not be fully removed. Sign in will recreate it."
            }
        } catch {
            show(error)
        }
    }

    func completeLogin(email: String, userID: String, oauthToken: String) async -> Bool {
        do {
            try Task.checkCancellation()
            errorText = nil
            updateWarningText = nil
            downloadState = DownloadState(phase: .authenticating)
            let coordinator = LoginCoordinator(
                googlePlay: makeGooglePlayClient(),
                credentialStore: credentialStore
            )
            let savedCredential = try await coordinator.completeLogin(
                email: email,
                userID: userID,
                oauthToken: oauthToken
            )
            try Task.checkCancellation()
            credential = savedCredential
            credentialAccessDenied = false
            didTryLoadingStoredCredential = true
            downloadState = DownloadState()
            errorText = nil
            await fetchLatest()
            return true
        } catch is CancellationError {
            if downloadState.phase == .authenticating {
                downloadState = DownloadState()
            }
            return false
        } catch {
            downloadState = DownloadState(versionName: latestVersion?.versionName, phase: .failed, error: error.localizedDescription)
            show(error)
            return false
        }
    }

    func loadStoredCredentialIfNeeded() throws -> GoogleCredential? {
        if let credential {
            return credential
        }
        guard !didTryLoadingStoredCredential else {
            return nil
        }
        didTryLoadingStoredCredential = true
        let storedCredential = try credentialStore.loadCredential()
        credential = storedCredential
        return storedCredential
    }

    func makeGooglePlayClient() -> any GooglePlayDownloading {
        FinskyGooglePlayClient()
    }

    private func clearLegacyGooglePlayStateForSignOut() -> Bool {
        do {
            try paths.removeLegacyGooglePlayState()
            return true
        } catch {
            let cleanupError = SignOutLegacyGooglePlayStateCleanupError(
                url: paths.legacyGooglePlayStateURL,
                underlyingError: error
            )
            NSLog("%@", cleanupError.localizedDescription)
            writeLastErrorLog(cleanupError)
            return false
        }
    }
}
