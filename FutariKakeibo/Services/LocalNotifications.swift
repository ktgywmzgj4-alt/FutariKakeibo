import UserNotifications

/// iPhoneの通知の許可。
enum NotificationPermission: Equatable, Sendable {
    /// まだ聞いていない（ONにしたときに確認が出る）
    case notDetermined
    /// 許可されていない（iPhoneの「設定」で変える）
    case denied
    /// 許可されている
    case allowed

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .provisional, .ephemeral: self = .allowed
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// この端末の通知（ローカル通知）を出す。
///
/// **通知の文はこの iPhone の中で作る。** 同期で届いた支出を見て決める（`PartnerExpenseAlert`）。
/// サーバーから通知の文を送ることはしない（金額や店名をAppleのプッシュに乗せない）。
struct LocalNotifications: Sendable {
    func permission() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermission(settings.authorizationStatus)
    }

    /// 許可を求める。**利用者が通知をONにしたときだけ呼ぶ**（起動したときには聞かない）。
    func requestPermission() async -> NotificationPermission {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await permission()
    }

    func post(_ content: PartnerExpenseAlert.Content) async {
        let notification = UNMutableNotificationContent()
        notification.body = content.body
        notification.sound = .default
        notification.threadIdentifier = PartnerExpenseAlert.threadIdentifier
        if let expenseID = content.expenseID {
            notification.userInfo = [PartnerExpenseAlert.expenseIDKey: expenseID.uuidString]
        }
        let request = UNNotificationRequest(identifier: content.identifier, content: notification, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
