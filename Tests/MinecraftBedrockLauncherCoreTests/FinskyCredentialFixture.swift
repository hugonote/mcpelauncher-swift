import Foundation
import FinskyKit
import MinecraftBedrockLauncherCore

enum FinskyCredentialFixture {
    static func credential(
        email: String = "user@example.com",
        userID: String = "user-id",
        masterToken: String = "master-token",
        authCookie: String = "androidmarket-cookie"
    ) throws -> FinskyCredential {
        let json = """
        {
          "email": "\(email)",
          "userID": "\(userID)",
          "masterToken": "\(masterToken)",
          "authCookie": "\(authCookie)",
          "device": {
            "androidID": 81985529216486895,
            "securityToken": 1147797409030816545,
            "serial": "ABC123",
            "macAddress": "aa:bb:cc:dd:ee:ff",
            "meid": "12345678901234"
          }
        }
        """
        return try JSONDecoder().decode(FinskyCredential.self, from: Data(json.utf8))
    }

    static func googleCredential(
        email: String = "user@example.com",
        userID: String = "user-id",
        masterToken: String = "master-token",
        authCookie: String = "androidmarket-cookie"
    ) throws -> GoogleCredential {
        GoogleCredential(
            email: email,
            masterToken: masterToken,
            userID: userID,
            finskyCredential: try credential(
                email: email,
                userID: userID,
                masterToken: masterToken,
                authCookie: authCookie
            )
        )
    }
}
