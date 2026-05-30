import SwiftUI

extension ContentView {
    var touchBarConfigurator: some View {
        LauncherTouchBarInstaller(model: model)
    }
}
