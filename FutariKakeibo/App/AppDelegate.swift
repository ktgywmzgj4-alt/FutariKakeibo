@preconcurrency import CloudKit
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureTabBarAppearance()
        // 通知を押したとき・アプリを開いているときの通知の出し方を受け持つ。
        // 通知を押してアプリが起動したときに間に合うよう、起動の途中で決める。
        // （CloudKitには触らない。`AppStore.loadIfNeeded` のコメント）
        UNUserNotificationCenter.current().delegate = self
        // 相手の支出の通知がONのときだけ、CloudKitの合図（サイレントプッシュ）を受けるために
        // Appleへ端末を登録する（通知の許可とは別で、画面には何も出ない）。OFFなら登録しない。
        if UserDefaults.standard.bool(forKey: AppStore.notifyPartnerExpensesKey) {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await AppStore.shared.remoteNotificationsRegistered() }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // プッシュの権限（`aps-environment`）が無いビルドではここに来る。開いているあいだの通知は今までどおり。
        #if DEBUG
        print("[通知] Appleへの端末の登録が失敗: \(error.localizedDescription)")
        #endif
    }

    /// CloudKitからの合図。アプリが閉じていれば、iOSが裏で起こしてここを呼ぶ（30秒まで）。
    /// 同期して、相手の新しい支出があればこの端末で知らせる。合図そのものに中身は無い。
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard PartnerExpenseAlert.isCloudKitPush(userInfo) else { return .noData }
        return await AppStore.shared.refreshForCloudKitPush()
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// アプリを開いているときも、相手の支出の通知を上に出す。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 通知を押したら、その支出を開く。何件かまとめた通知なら履歴を開く。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let expenseID = PartnerExpenseAlert.expenseID(from: response.notification.request.content.userInfo)
        await MainActor.run {
            AppStore.shared.pendingNotificationRoute = expenseID.map { AppStore.NotificationRoute.expense($0) }
                ?? AppStore.NotificationRoute.history
        }
    }
}
