import UIKit
import SwiftUI

// 主入口：手机端是 SwiftUI 设置页，CarPlay 端是仪表场景
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == UISceneSession.Role.carTemplateApplication {
            let cfg = UISceneConfiguration(name: "CarPlay", sessionRole: .carTemplateApplication)
            cfg.delegateClass = CarPlaySceneDelegate.self
            return cfg
        }
        let cfg = UISceneConfiguration(name: "Phone", sessionRole: .windowApplication)
        cfg.delegateClass = PhoneSceneDelegate.self
        return cfg
    }
}

final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: ws)
        window.rootViewController = UIHostingController(rootView: ContentView())
        self.window = window
        window.makeKeyAndVisible()
    }
}
