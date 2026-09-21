import SwiftUI

@main
struct KDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 跟随系统自动切换浅色/深色模式
                .preferredColorScheme(nil)
        }
    }
}
