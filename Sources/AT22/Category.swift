import Foundation

/// ファイルの役割を6種類に分類する。レイアウトのセルで表示・スタイリングの根拠になる。
///
/// パス文字列だけで決まる純関数。ファイルシステムには一切触らず、
/// 同じ入力に必ず同じ出力を返すので、キャッシュと相性がいい
enum FileCategory: String, CaseIterable, Sendable {
    case source  // 実装
    case test    // 検査
    case note    // ノート
    case config  // 設定
    case asset   // 資材
    case other   // 他

    var title: String {
        switch self {
        case .source: "実装"
        case .test:   "検査"
        case .note:   "ノート"
        case .config: "設定"
        case .asset:  "資材"
        case .other:  "他"
        }
    }

    /// セルの左端に打つ刻印。**カテゴリを色で語るのをやめた代わり**の記号。
    ///
    /// 色を6色ぶん使うと、状態の色（書き込み中・フラグ・稼働中）と同じ画面で
    /// competing してしまい、「色が付いている＝何か起きている」が読めなくなる。
    /// 記号は無彩色で置けるので、色の予算を状態だけに残せる。
    ///
    /// `title` の1文字目をそのまま採る規則にしてある（ノート＝ノ、資材＝資）。
    /// 別の文字を当てると凡例と突き合わせられない。
    /// **`.other` だけは例外**——1文字目を採ると「他 他」と同じ字が凡例に2つ並ぶので、
    /// 「分類が付かなかった」と読める中黒を当てる
    var mark: String {
        self == .other ? "・" : String(title.prefix(1))
    }

    /// ファイルパス（絶対・相対・ファイル名のみ）からカテゴリを決める。
    ///
    /// 末尾のファイル名だけで完結する。同じ入力に必ず同じ出力を返す。
    /// **語の切れ目を見て判定する**——`test` / `spec` / `selfcheck` は
    /// 単語の組み立てに含まれる時だけ拾う。`latest.swift` の `test` や
    /// `contest.md` の `test`、`testament.txt` の `test` は検査ではなく、
    /// 拡張子で判定される（.source または .note）
    nonisolated static func classify(path: String) -> FileCategory {
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return .other }

        // 1. ファイル名が `test` / `spec` / `selfcheck` を含むかをチェック（語の切れ目）
        // CamelCase 判定が必要なので、ここでは lowercased() を使わない
        let testPatterns = ["test", "spec", "selfcheck"]
        for pattern in testPatterns {
            if isWordIn(name, pattern: pattern) {
                return .test
            }
        }

        // 設定の拡張子（先頭ドット判定でも使うため先に定義）
        let configExtensions: Set<String> = [
            "json", "yaml", "yml", "toml", "plist", "xcconfig", "entitlements",
            "cfg", "ini", "lock", "resolved"
        ]

        // 先頭がドットの隠しファイル判定（pathExtension の挙動を版に依存させない）
        // `.gitignore` のように先頭ドットで残りにドットが無い場合、
        // 先頭ドットを除いた文字列が拡張子相当として扱われる隠し設定ファイル
        if name.hasPrefix(".") {
            let withoutDot = String(name.dropFirst())
            if !withoutDot.contains(".") {
                // 先頭ドットを除いた部分が設定拡張子に該当するか確認
                if configExtensions.contains(withoutDot) {
                    return .config
                }
                // リストになくても、先頭ドットの隠しファイルはメタ・設定の類。既定で .config
                // （`.DS_Store` や `.env` のように設定・メタ情報しか来ない）
                return .config
            }
            // 残りにドットがある場合（`.swiftlint.yml` など）は通常どおり拡張子処理へ
        }

        // 2. 拡張子で振り分け。既存リストを参照（再定義しない）
        let nameLower = name.lowercased()
        let ext = (nameLower as NSString).pathExtension.lowercased()

        if Structure.sourceExtensions.contains(ext) {
            return .source
        }
        if Structure.noteExtensions.contains(ext) {
            return .note
        }

        // 3. 設定の拡張子
        if configExtensions.contains(ext) {
            return .config
        }

        // 4. 資材の拡張子
        let assetExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "svg", "pdf", "icns", "html", "css",
            "xcassets", "ttf", "otf", "wav", "mp3", "mp4"
        ]
        if assetExtensions.contains(ext) {
            return .asset
        }

        // 5. 拡張子が無いファイルの既知の設定っぽい名前
        if ext.isEmpty {
            let configNames: Set<String> = [
                "makefile", "dockerfile", "license", "package",
                "gemfile", "rakefile", "procfile", "podfile"
            ]
            if configNames.contains(nameLower) {
                return .config
            }
        }

        // 6. どれにも当たらなければ他
        return .other
    }

    /// パターンが**語**として `name` に含まれているか判定する。
    ///
    /// `CamelCase`・`snake_case`・`-separated-` など言語の慣例で語の切れ目を見る。
    /// アンダースコアは `_` は語の区切り文字。すべての出現位置を走査し、1つでも語として成立すれば true。
    /// CamelCase 境界は「小文字の直後に大文字」で判定する
    private nonisolated static func isWordIn(_ name: String, pattern: String) -> Bool {
        let nameLower = name.lowercased()
        var searchRange = nameLower.startIndex..<nameLower.endIndex

        while let range = nameLower.range(of: pattern, range: searchRange) {
            let start = nameLower.distance(from: nameLower.startIndex, to: range.lowerBound)
            let end = start + pattern.count
            let chars = Array(name)

            // 語頭の判定：位置0 || 前の文字が識別子ではない || CamelCase 境界
            let isStartBoundary: Bool
            if start == 0 {
                isStartBoundary = true
            } else {
                let prev = chars[start - 1]
                let curr = chars[start]
                let prevIsIdent = prev.isLetter || prev.isNumber
                // 前が識別子ではない || CamelCase 境界（小文字の後に大文字）
                isStartBoundary = !prevIsIdent || (prev.isLowercase && curr.isUppercase)
            }

            // 語末の判定：マッチの直後から小文字または大文字の's'を1文字読み飛ばしてよい
            let isEndBoundary: Bool
            var checkPos = end
            // 小文字または大文字の 's' を読み飛ばす
            if checkPos < chars.count && (chars[checkPos] == "s" || chars[checkPos] == "S") {
                checkPos += 1
            }
            // その後の文字を確認
            if checkPos >= chars.count {
                // 文字列の終端
                isEndBoundary = true
            } else {
                let nextChar = chars[checkPos]
                let isIdent = nextChar.isLetter || nextChar.isNumber
                let isUpper = nextChar.isUppercase
                // 英数字でない || 大文字（CamelCase で次の語が始まっている）
                isEndBoundary = !isIdent || isUpper
            }

            if isStartBoundary && isEndBoundary {
                return true
            }

            // 次の検索位置を設定
            searchRange = range.upperBound..<nameLower.endIndex
        }

        return false
    }
}
