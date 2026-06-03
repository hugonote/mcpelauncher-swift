import Foundation

extension LauncherViewModel {
    func signOutLegacyCredentialIfNeeded() {
        guard credential?.finskyCredential == nil, credential != nil else {
            return
        }
        try? credentialStore.clearCredential()
        credential = nil
        didTryLoadingStoredCredential = true
    }
}
