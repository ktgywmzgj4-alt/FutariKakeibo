import Foundation

/// アプリ自身の版と、画面に出す1行。
///
/// **ここを決め打ちで書かないこと。** 設定画面には長いあいだ
/// `Text("Version 0.1.0 (1)")` と直接書き込まれていて、どのビルドを入れても
/// **最初のビルド番号**が出ていた。TestFlightの自動アップデートで最新が入っても
/// 画面の表示は変わらないので、**最初の版に戻ったように見えた**
/// （2026-10-13 利用者の報告）。
///
/// 版は `Info.plist` の `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` から
/// 入るので、束から読めば必ず実物と一致する。
struct AppVersion {
    /// `CFBundleShortVersionString`。**TestFlightが版をまとめる単位。**
    /// これが変わらないと、何回配信しても同じ版の中でビルドが増えるだけになる。
    let version: String

    /// `CFBundleVersion`。同じ版の中でビルドを並べる番号。
    /// CIが `date -u '+%Y.%m%d.%H%M'` で作るので、配信ごとに必ず増える。
    let build: String

    /// 束から読む。読めなければ空にして、`displayText` の判断に任せる。
    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// テストから組み立てるため。
    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// 設定画面に出す1行。
    ///
    /// **利用者がどのビルドを使っているかを伝えるための行。**
    /// 不具合の報告を受けたとき、ここを読んでもらえば配信のどれか分かる。
    ///
    /// 読めなかった側は出さない。`Version 0.1.0 ()` のような形は、
    /// 壊れて見えるだけで何も伝えないため。
    var displayText: String {
        let shownVersion = version.trimmingCharacters(in: .whitespaces)
        let shownBuild = build.trimmingCharacters(in: .whitespaces)

        switch (shownVersion.isEmpty, shownBuild.isEmpty) {
        case (false, false): return "Version \(shownVersion) (\(shownBuild))"
        case (false, true): return "Version \(shownVersion)"
        case (true, false): return "Build \(shownBuild)"
        case (true, true): return "Version 不明"
        }
    }
}
