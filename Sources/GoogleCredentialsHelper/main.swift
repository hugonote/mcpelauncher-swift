import Foundation
import MinecraftBedrockLauncherCore

func emitCredential(_ credential: GoogleCredential) -> Never {
    FileHandle.standardError.write(Data("CRED=\(credential.email):\(credential.masterToken)\n".utf8))
    exit(0)
}

let arguments = Set(CommandLine.arguments.dropFirst())
guard arguments.contains("--request-google-credentials") else {
    FileHandle.standardError.write(Data("mcpelauncher-ui-qt compatibility helper only supports --request-google-credentials\n".utf8))
    exit(2)
}

let environment = ProcessInfo.processInfo.environment
if let email = environment["MCPELAUNCHER_GOOGLE_EMAIL"],
   let token = environment["MCPELAUNCHER_GOOGLE_TOKEN"],
   !email.isEmpty,
   !token.isEmpty {
    emitCredential(GoogleCredential(email: email, masterToken: token))
}

do {
    if let credential = try KeychainCredentialStore().loadCredential() {
        emitCredential(credential)
    }
    FileHandle.standardError.write(Data("No Google Play credential is available.\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Failed to read Google Play credential: \(error.localizedDescription)\n".utf8))
    exit(1)
}
