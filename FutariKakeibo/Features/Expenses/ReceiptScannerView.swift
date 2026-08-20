import SwiftUI
import UIKit
@preconcurrency import VisionKit

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

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onCancel: () -> Void
        let completion: (Result<[UIImage], Error>) -> Void

        init(
            onCancel: @escaping () -> Void,
            completion: @escaping (Result<[UIImage], Error>) -> Void
        ) {
            self.onCancel = onCancel
            self.completion = completion
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            completion(.failure(error))
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map(scan.imageOfPage(at:))
            completion(.success(images))
            controller.dismiss(animated: true)
        }
    }
}
