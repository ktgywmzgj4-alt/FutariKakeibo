@preconcurrency import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
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
