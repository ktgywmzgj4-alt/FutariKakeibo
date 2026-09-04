import XCTest
import UIKit
@testable import FutariKakeibo

/// レシート画像の「縮める」「置く」「片付ける」を確かめる。
///
/// 画像を無制限に持たないことが、この機能でいちばん壊れてはいけないところ。
final class ReceiptImageTests: XCTestCase {
    // MARK: - 縮小と圧縮

    func testFittedSizeShrinksLongEdgeAndKeepsAspectRatio() {
        let size = ReceiptImageProcessor.fittedSize(
            for: CGSize(width: 3024, height: 4032),
            maxLongEdge: 1600
        )

        XCTAssertEqual(size.height, 1600)
        XCTAssertEqual(size.width, 1200)
    }

    func testFittedSizeDoesNotEnlargeSmallImages() {
        let size = ReceiptImageProcessor.fittedSize(
            for: CGSize(width: 800, height: 600),
            maxLongEdge: 1600
        )

        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    func testProcessShrinksToDisplaySizeAndStaysSmall() async throws {
        let original = makeReceiptLikeImage(width: 3024, height: 4032)

        let result = await ReceiptImageProcessor.process(image: original)
        let processed = try XCTUnwrap(result)

        XCTAssertEqual(max(processed.pixelWidth, processed.pixelHeight), 1600)
        // 1枚あたり数百KBに収まること。原寸のままなら数MBになる。
        XCTAssertLessThan(processed.display.count, 1_500_000)
        XCTAssertLessThan(processed.thumbnail.count, 80_000)

        let thumbnail = try XCTUnwrap(UIImage(data: processed.thumbnail))
        XCTAssertEqual(max(thumbnail.size.width, thumbnail.size.height), 240, accuracy: 1)
    }

    // MARK: - 置き場所

    func testStoreRoundTripAndRemove() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReceiptImageStore(directoryURL: directory)
        let id = UUID()
        let image = makeStoredImage(displayBytes: 2_048, thumbnailBytes: 128)

        try await store.save(image, id: id)

        let display = await store.displayData(for: id)
        XCTAssertEqual(display, image.display)
        let thumbnail = await store.thumbnailData(for: id)
        XCTAssertEqual(thumbnail, image.thumbnail)
        let ids = await store.storedIDs()
        XCTAssertEqual(ids, [id])
        let bytes = await store.totalBytes()
        XCTAssertEqual(bytes, 2_048 + 128)
        let fileURL = await store.displayFileURLIfExists(for: id)
        XCTAssertNotNil(fileURL)

        await store.remove(id: id)

        let removedDisplay = await store.displayData(for: id)
        XCTAssertNil(removedDisplay)
        let remaining = await store.storedIDs()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPruneOrphansRemovesImagesNoExpensePointsAt() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReceiptImageStore(directoryURL: directory)
        let kept = UUID()
        let orphan = UUID()
        let image = makeStoredImage(displayBytes: 512, thumbnailBytes: 64)
        try await store.save(image, id: kept)
        try await store.save(image, id: orphan)

        let removed = await store.pruneOrphans(keeping: [kept])

        XCTAssertEqual(removed, 1)
        let ids = await store.storedIDs()
        XCTAssertEqual(ids, [kept])
    }

    /// まだiCloudへ送れていない画像は、端末内が唯一の原本なので消さない。
    func testEnforceLimitKeepsImagesThatAreNotUploadedYet() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReceiptImageStore(directoryURL: directory)
        let notUploaded = UUID()
        let uploaded = UUID()
        let image = makeStoredImage(displayBytes: 4_096, thumbnailBytes: 64)
        try await store.save(image, id: notUploaded)
        try await store.save(image, id: uploaded)

        let removed = await store.enforceLimit(maxBytes: 5_000, protecting: [notUploaded])

        XCTAssertEqual(removed, 1)
        let survivor = await store.displayData(for: notUploaded)
        XCTAssertNotNil(survivor)
        let evicted = await store.displayData(for: uploaded)
        XCTAssertNil(evicted)
    }

    func testEnforceLimitDoesNothingWhenUnderTheLimit() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReceiptImageStore(directoryURL: directory)
        try await store.save(makeStoredImage(displayBytes: 512, thumbnailBytes: 64), id: UUID())

        let removed = await store.enforceLimit(maxBytes: 100_000, protecting: [])

        XCTAssertEqual(removed, 0)
    }

    // MARK: - 支出との紐付け

    func testExpenseKeepsOnlyTheReferenceNotTheImage() throws {
        let imageID = UUID()
        let expense = Expense(
            title: "食材",
            amount: 1_280,
            category: .groceries,
            paidByMemberID: UUID(),
            receiptImageID: imageID
        )

        let data = try JSONEncoder().encode(expense)
        let decoded = try JSONDecoder().decode(Expense.self, from: data)

        XCTAssertEqual(decoded.receiptImageID, imageID)
        XCTAssertTrue(decoded.hasReceiptImage)
        // 支出1件のJSONに画像が混ざっていないこと。
        XCTAssertLessThan(data.count, 1_024)
    }

    /// レシート画像を入れる前に保存したデータも、そのまま読めること。
    func testOldExpenseJSONHasNoReceipt() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "食材",
          "amount": 1280,
          "date": 700000000,
          "category": "groceries",
          "paidByMemberID": "\(UUID().uuidString)",
          "splitMethod": "equally",
          "note": "",
          "createdAt": 700000000,
          "updatedAt": 700000000
        }
        """

        let expense = try JSONDecoder().decode(Expense.self, from: Data(json.utf8))

        XCTAssertNil(expense.receiptImageID)
        XCTAssertFalse(expense.hasReceiptImage)
    }

    func testOldSnapshotJSONHasNoPendingUploads() throws {
        let json = """
        {
          "schemaVersion": 3,
          "expenses": [],
          "incomes": []
        }
        """

        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(json.utf8))

        XCTAssertTrue(snapshot.pendingReceiptImageIDs.isEmpty)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeStoredImage(displayBytes: Int, thumbnailBytes: Int) -> ReceiptImageData {
        ReceiptImageData(
            display: Data(repeating: 0xAB, count: displayBytes),
            thumbnail: Data(repeating: 0xCD, count: thumbnailBytes),
            pixelWidth: 1_200,
            pixelHeight: 1_600
        )
    }

    /// レシートに近い絵を作る。真っ白だと圧縮が効きすぎて、容量の確認にならない。
    private func makeReceiptLikeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            var y: CGFloat = 40
            while y < height - 40 {
                context.fill(CGRect(x: 40, y: y, width: width - 80, height: 12))
                y += 36
            }
        }
    }
}
