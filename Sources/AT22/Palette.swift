import SwiftUI

/// デザイン案 5a（ペダル筐体・DS準拠）のトークン層。
///
/// 5a の規律は3つだけ:
///   1. **色は意味のときだけ**。地・線・文字はすべて無彩色で、色が付くのは
///      「いま」（accent＝赤）と、成功・注意・危険の3つのセマンティック色だけ。
///      ファイルのカテゴリは色ではなく刻印記号（実・検・ノ・設）で語る。
///   2. **余白は固定スケール**（4 / 8 / 16 / 24 / 32 / 48 / 64）。
///      半段（2 / 6 / 12）は部品の内側にだけ使う。
///   3. **奥行きは線と明度差で出す**。柔らかい影で浮かせない。
///
/// ここは SwiftUI に依存する側なので `CockpitLayout` からは参照しないこと。
/// `CockpitLayout` / `Category` / `Cockpit` / `Gate` は SwiftUI を
/// リンクせずに p0-selfcheck からコンパイルされる（README の自己チェック）。
enum Palette {

    // MARK: 地（すべて不透明・平ら）

    /// キャンバスの地。カーボン黒
    static let field = Color(red: 0.055, green: 0.055, blue: 0.055)          // #0E0E0E
    /// 一段持ち上げた面（サイドバー・カード）
    static let fieldSubtle = Color(red: 0.078, green: 0.078, blue: 0.075)    // #141413
    /// 部品の地（ファイルセル・チップ）
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.075)        // #141413
    /// もう一段持ち上げた面（レールのキー・押せるもの）
    static let surfaceRaised = Color(red: 0.102, green: 0.102, blue: 0.098)  // #1A1A19
    /// 沈めた面（入力欄・選択中のキー）
    static let surfaceSunken = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A
    /// 紙。暗い地の上に置く唯一の明るい面（門の指示・流れる指示）
    static let paper = Color(red: 0.914, green: 0.914, blue: 0.906)          // #E9E9E7
    static let paperInk = Color(red: 0.102, green: 0.102, blue: 0.098)       // #1A1A19
    static let paperInkDim = Color(red: 0.380, green: 0.380, blue: 0.349)    // #616159

    // MARK: 線（構造はここで見せる）

    /// ごく細い区切り。行と行のあいだ。**既に半透明（10%）なので、呼び出し側でさらに
    /// `.opacity()` を掛けないこと。`Color.opacity` は乗算なので二重に薄まる。**
    /// 掛け算する前提で描く線が要るなら、不透明の `inkTertiary` / `inkDisabled` を使うこと
    static let hairline = Color.white.opacity(0.10)
    /// ふつうの枠線。**既に半透明（16%）なので、呼び出し側でさらに `.opacity()` を
    /// 掛けないこと。`Color.opacity` は乗算なので二重に薄まる。**
    /// 掛け算する前提で描く線が要るなら、不透明の `inkTertiary` / `inkDisabled` を使うこと
    static let border = Color.white.opacity(0.16)
    /// 章の切れ目に引く太い罫（2pt で引く）
    static let rule = Color.white.opacity(0.92)

    // MARK: 文字（4段。段は明度だけで作る）

    static let ink = Color(red: 0.957, green: 0.957, blue: 0.953)            // #F4F4F3
    static let inkSecondary = Color(red: 0.698, green: 0.698, blue: 0.678)   // #B2B2AD
    static let inkTertiary = Color(red: 0.525, green: 0.525, blue: 0.498)    // #86867F
    static let inkDisabled = Color(red: 0.271, green: 0.271, blue: 0.247)    // #45453F

    // MARK: 意味を運ぶ唯一の色

    /// 「いま」。書き込み中・実行中・門の停止・進行中のタスク。**画面に1系統だけ**
    static let accent = Color(red: 0.910, green: 0.220, blue: 0.169)         // #E8382B
    /// 暗い地の上で読ませる赤（文字・数字用に明度を上げてある）
    static let accentText = Color(red: 1.000, green: 0.416, blue: 0.369)     // #FF6A5E
    /// 計器の数字。赤の中でいちばん明るく、桁が動くところにだけ使う
    static let readout = Color(red: 1.000, green: 0.231, blue: 0.184)        // #FF3B2F
    static let accentSubtle = Color(red: 0.910, green: 0.220, blue: 0.169).opacity(0.16)

    // MARK: 状態（意味のときだけ・くすませてある）

    /// 増えた行数など、「良い方向の差分」だけ
    static let success = Color(red: 0.298, green: 0.612, blue: 0.455)        // #4C9C74
    /// フラグ（読みすぎ）。注意であって危険ではない
    static let warning = Color(red: 0.816, green: 0.604, blue: 0.306)        // #D09A4E
    /// 失敗・エラー
    static let danger = Color(red: 1.000, green: 0.333, blue: 0.282)         // #FF5548

    // MARK: 余白（この値だけを使う）

    enum Space {
        /// 部品の内側にだけ使う半段
        static let hair: CGFloat = 2
        static let tiny: CGFloat = 6
        static let small: CGFloat = 12
        /// 固定スケール本体
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 16
        static let s4: CGFloat = 24
        static let s5: CGFloat = 32
        static let s6: CGFloat = 48
        static let s7: CGFloat = 64
    }

    // MARK: 角丸（技術的な範囲に留める。Apple のピル形にしない）

    enum Radius {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 5
        static let md: CGFloat = 7
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
    }

    // MARK: 線幅

    enum Stroke {
        /// 区切り。1px を狙う（Retina で 0.5pt にすると消える機種がある）
        static let hair: CGFloat = 1
        /// 枠
        static let border: CGFloat = 1
        /// 章の切れ目・選択中のタブ
        static let rule: CGFloat = 2
        /// 状態を出す枠（書き込み中のセル・稼働中のチップ）
        static let state: CGFloat = 1.4
    }

    // MARK: 文字（サイズは 5a の実寸。等幅が既定）

    enum FontSize {
        /// 刻印（レールのラベル・ステータスバー）
        static let etch: CGFloat = 8
        /// 章番号・章名・小さい注記
        static let label: CGFloat = 9
        /// 計器の数字・エージェント行のID
        static let readout: CGFloat = 10
        /// ファイル名・タブ名
        static let body: CGFloat = 11
        /// 人が読む文章
        static let prose: CGFloat = 12
    }

    /// 等幅のラベルは字間を開ける（Swiss / 計器のオーバーライン）
    enum Tracking {
        static let wide: CGFloat = 0.8
        static let wider: CGFloat = 1.6
    }

    // MARK: 金属（tokens/instrument.css）

    /// 筐体の面。**50% で硬く割れる二段**が 2011年代の金属で、柔らかいランプにすると
    /// 途端に霧に見える。値幅は一枚あたり10%以内に収め、
    /// 縁は必ず「上に1pt の白・下に1pt の黒」だけで出す（ぼかしは押し込んだ時にしか使わない）。
    enum Metal {
        /// タイトルバー・ステータスバー（--metal-black）
        static let black = LinearGradient(
            stops: [.init(color: Color(red: 0.149, green: 0.149, blue: 0.149), location: 0),      // #262626
                    .init(color: Color(red: 0.125, green: 0.125, blue: 0.125), location: 0.499), // #202020
                    .init(color: Color(red: 0.090, green: 0.090, blue: 0.090), location: 0.5),   // #171717
                    .init(color: Color(red: 0.063, green: 0.063, blue: 0.063), location: 1)],    // #101010
            startPoint: .top, endPoint: .bottom)

        /// レールのキー・押せる部品（--metal-gunmetal）
        static let gunmetal = LinearGradient(
            stops: [.init(color: Color(red: 0.333, green: 0.345, blue: 0.361), location: 0),     // #55585C
                    .init(color: Color(red: 0.294, green: 0.306, blue: 0.322), location: 0.499), // #4B4E52
                    .init(color: Color(red: 0.247, green: 0.259, blue: 0.275), location: 0.5),   // #3F4246
                    .init(color: Color(red: 0.204, green: 0.216, blue: 0.227), location: 1)],    // #34373A
            startPoint: .top, endPoint: .bottom)

        /// 門のパネルだけが使う明るい面（--metal-silver）。暗い地の上で唯一光る面なので、
        /// **画面に1枚だけ**。増やすと「いま答えるのはここ」が指せなくなる
        static let silver = LinearGradient(
            stops: [.init(color: Color(red: 0.863, green: 0.871, blue: 0.867), location: 0),     // #DCDEDD
                    .init(color: Color(red: 0.812, green: 0.820, blue: 0.816), location: 0.499), // #CFD1D0
                    .init(color: Color(red: 0.753, green: 0.765, blue: 0.761), location: 0.5),   // #C0C3C2
                    .init(color: Color(red: 0.698, green: 0.710, blue: 0.706), location: 1)],    // #B2B5B4
            startPoint: .top, endPoint: .bottom)

        /// 上端の1pt（--metal-edge-light）
        static let bevelLight = Color.white.opacity(0.28)
        /// 下端の1pt（--metal-edge-dark）
        static let bevelDark = Color.black.opacity(0.55)
        /// 明るい面の上では縁が反転する（.mt-light）
        static let bevelLightOnSilver = Color.white.opacity(0.85)
        static let bevelDarkOnSilver = Color.black.opacity(0.22)
        /// 押し込んだ面。**金属でぼかしを使っていいのはここだけ**（--metal-pressed）
        static let pressedShadow = Color.black.opacity(0.55)
        static let pressedRadius: CGFloat = 5
        /// 天板の白い映り込み。上半分だけに掛けて 48% で切る（--gloss-dark）
        static let gloss = LinearGradient(
            stops: [.init(color: Color.white.opacity(0.20), location: 0),
                    .init(color: Color.white.opacity(0.08), location: 0.30),
                    .init(color: Color.white.opacity(0.02), location: 0.48),
                    .init(color: Color.white.opacity(0.00), location: 0.49),
                    .init(color: Color.white.opacity(0.04), location: 1)],
            startPoint: .top, endPoint: .bottom)
        /// 小さい丸い部品は白を弱める。26pt の円に 60% の白を載せるとプラスチックの球になる（--gloss-part）
        static let glossPart = LinearGradient(
            stops: [.init(color: Color.white.opacity(0.22), location: 0),
                    .init(color: Color.white.opacity(0.09), location: 0.44),
                    .init(color: Color.white.opacity(0.01), location: 0.46),
                    .init(color: Color.black.opacity(0.05), location: 0.92),
                    .init(color: Color.black.opacity(0.10), location: 1)],
            startPoint: .top, endPoint: .bottom)
    }

    // MARK: 刻印（.mt-etch）

    /// 金属に彫った文字。等幅・大文字・字間を開け、**上に影を落として凹ませる**。
    /// 明るい面では ink と shadow が入れ替わる（`onLight`）
    enum Etch {
        static let ink = Color.white.opacity(0.74)
        static let shadow = Color.black.opacity(0.70)
        static let inkOnLight = Color.black.opacity(0.70)
        static let shadowOnLight = Color.white.opacity(0.80)
        /// 0.14em。9pt なら 1.26pt（--etch-tracking）
        static let trackingEm: CGFloat = 0.14
        static func tracking(_ size: CGFloat) -> CGFloat { size * trackingEm }
    }

    // MARK: 製図の線（tokens/blueprint.css の .carbon）

    /// 金属の上に敷く座標グリッド。**線であって面ではない**ので、
    /// 濃くすると地の模様になって情報が乗らなくなる
    enum Blueprint {
        static let line = Color.white.opacity(0.05)
        static let lineMajor = Color.white.opacity(0.11)
        static let tick = Color.white.opacity(0.40)
        static let cell: CGFloat = 24
    }

    /// 赤い点。**一画面に1つ**、面としては絶対に使わない（--dot-red）
    static let dotRed = Color(red: 0.886, green: 0.024, blue: 0.071)              // #E20612
}
