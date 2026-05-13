import SwiftUI

@main
struct MacESP32ConsoleApp: App {
    var body: some Scene {
        WindowGroup("Mac-esp32控制台") {
            ContentView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 760)
    }
}
