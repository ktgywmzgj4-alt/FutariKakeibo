import SwiftUI
import UIKit

struct CloudSharingView: UIViewControllerRepresentable {
    let configuration: AppStore.ShareConfiguration
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        configuration.share.publicPermission = .none
        let controller = UICloudSharingController(
            share: configuration.share,
            container: configuration.container
        )
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: (String) -> Void

        init(onError: @escaping (String) -> Void) {
            self.onError = onError
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "ふたり家計簿"
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onError("共有招待を保存できませんでした。\n\(error.localizedDescription)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
