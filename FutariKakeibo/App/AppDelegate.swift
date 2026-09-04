@preconcurrency import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureTabBarAppearance()
        return true
    }

    /// 下部ナビ。選ばれているものだけブルーにし、そうでないものは黒にする。
    /// 背景は端末の既定のままにして、iOSごとの見た目を壊さない。
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ] {
            layout.normal.iconColor = .black
            layout.normal.titleTextAttributes = [.foregroundColor: UIColor.black]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudShareInbox.shared.store(cloudKitShareMetadata)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .didReceiveCloudKitShare, object: nil)
        }
    }
}
