import Foundation

enum DeleteAction: Identifiable {
    case runtime
    case game
    case data

    var id: String {
        buttonTitle
    }

    var buttonTitle: String {
        switch self {
        case .runtime:
            return "Delete Runtime"
        case .game:
            return "Delete Game"
        case .data:
            return "Delete Data"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .runtime:
            return "Delete runtime?"
        case .game:
            return "Delete installed game?"
        case .data:
            return "Delete Minecraft data?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .runtime:
            return "The native runtime will be removed and downloaded again when needed."
        case .game:
            return "Installed Minecraft versions and downloaded APK files will be removed."
        case .data:
            return "Minecraft data and cache will be removed, including local settings and worlds."
        }
    }
}
