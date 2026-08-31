import SwiftUI
import UIKit
import VisionKit

struct ReceiptScannerView: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let completion: (Result<[UIImage], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCancel: onCancel, completion: completion)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCancel: () -> Void
        let completion: (Result<[UIImage], Error>) -> Void

        init(
            onCancel: @escaping () -> Void,
            completion: @escaping (Result<[UIImage], Error>) -> Void
        ) {
            self.onCancel = onCancel
            self.completion = completion
        }

        // VisionKitのデリゲートはメインスレッドから呼ばれるが、
        // その保証がコンパイラに伝わらないため、明示してから画面を閉じる。
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
            MainActor.assumeIsolated { controller.dismiss(animated: true) }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            completion(.failure(error))
            MainActor.assumeIsolated { controller.dismiss(animated: true) }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map(scan.imageOfPage(at:))
            completion(.success(images))
            MainActor.assumeIsolated { controller.dismiss(animated: true) }
        }
    }
}
