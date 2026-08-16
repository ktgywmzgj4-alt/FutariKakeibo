@preconcurrency import CloudKit
import Foundation

final class CloudShareInbox: @unchecked Sendable {
    static let shared = CloudShareInbox()

    private let lock = NSLock()
    private var pendingMetadata: CKShare.Metadata?

    private init() {}

    func store(_ metadata: CKShare.Metadata) {
        lock.lock()
        pendingMetadata = metadata
        lock.unlock()
    }

    func take() -> CKShare.Metadata? {
        lock.lock()
        defer { lock.unlock() }
        let value = pendingMetadata
        pendingMetadata = nil
        return value
    }
}

extension Notification.Name {
    static let didReceiveCloudKitShare = Notification.Name("didReceiveCloudKitShare")
}
