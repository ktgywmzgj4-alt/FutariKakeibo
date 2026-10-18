import XCTest
@testable import FutariKakeibo

/// 支出の画面の入力例。利用者が文言を指定した（2026-10-19、2回目の依頼）。
///
/// 1回目の依頼は会話の中だけで受けて台帳に書かず、要約で消えて直らなかった。
/// 同じことが起きないよう、文言をテストで押さえる。変えるなら先に利用者に確かめること。
final class ExpenseEditorTextTests: XCTestCase {
    func testTheShopExampleIsAGasStation() {
        XCTAssertEqual(ExpenseEditorText.merchantExample, "例：ガソリンスタンド")
    }

    func testTheDescriptionExampleIsTheGasCost() {
        XCTAssertEqual(ExpenseEditorText.titleExample, "例：ガソリン代")
    }
}
