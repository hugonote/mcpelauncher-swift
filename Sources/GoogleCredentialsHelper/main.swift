import Foundation

private struct Credential: Decodable {
    let email: String
    let masterToken: String
}

private func emitCredential(_ credential: Credential) -> Never {
    FileHandle.standardError.write(Data("CRED=\(credential.email):\(credential.masterToken)\n".utf8))
    exit(0)
}

let arguments = Set(CommandLine.arguments.dropFirst())
guard arguments.contains("--request-google-credentials") else {
    FileHandle.standardError.write(Data("mcpelauncher-ui-qt compatibility helper only supports --request-google-credentials\n".utf8))
    exit(2)
}

do {
    let environment = ProcessInfo.processInfo.environment
    if let path = environment["MCPELAUNCHER_GOOGLE_CREDENTIAL_FILE"], !path.isEmpty {
        let fileURL = URL(fileURLWithPath: path)
        let credential: Credential
        do {
            defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
            credential = try JSONDecoder().decode(Credential.self, from: Data(contentsOf: fileURL))
        }
        emitCredential(credential)
    }
    if let email = environment["MCPELAUNCHER_GOOGLE_EMAIL"],
       let token = environment["MCPELAUNCHER_GOOGLE_TOKEN"],
       !email.isEmpty,
       !token.isEmpty {
        emitCredential(Credential(email: email, masterToken: token))
    }
    FileHandle.standardError.write(Data("No Google Play credential was provided by the launcher.\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Failed to read provided Google Play credential: \(error.localizedDescription)\n".utf8))
    exit(1)
}
