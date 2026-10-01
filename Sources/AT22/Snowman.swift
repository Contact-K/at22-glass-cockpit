import Foundation

// MARK: - 文脈の膨らみ

/// 長引いたセッションで推論が鈍るのを、雪だるまが育つ形で出す。
///
/// 鈍りは時間ではなく**文脈の量**で起きる（lost-in-the-middle）。量は `message.usage` から
/// 実測が取れるので、経過時間から推測しない。実測で1セッションが 39k → 997,520 まで伸び、
/// 自動圧縮で 15,178 へ落ちていた。転がるほど育ち、圧縮されると溶ける。
///
/// **ハルシネーションそのものを検知するものではない。** 出力の正しさは AT22 からは見えない。
/// これは「鈍りやすい状態に入った」ことを、鈍ってから気づく前に見せるための目安
enum Snowman {

    /// 文脈の窓。**そのセッション自身のモデル名からは決められない**——実測で、1M 版で動いていた
    /// セッションでも `message.model` は `claude-opus-5` としか書かれていない
    /// （`[1m]` が付くのはサブエージェントの結果に入る `resolvedModel` だけで、本人の行には無い）。
    ///
    /// そこで観測した最大値から決める。200k を超えて動いている時点で 1M 版だと確定するし、
    /// 200k に届いていない間はどちらの窓でも警報の出方は変わらない
    static let smallWindow = 200_000
    static let largeWindow = 1_000_000

    nonisolated static func window(observed: Int) -> Int {
        observed > smallWindow ? largeWindow : smallWindow
    }

    /// 育ち具合。0…1
    nonisolated static func growth(tokens: Int, window: Int) -> Double {
        guard window > 0, tokens > 0 else { return 0 }
        return min(1, Double(tokens) / Double(window))
    }

    /// 雪だるまの大きさ。段の切れ目は環境と作業の粒度で動くので、外から触れる場所に置く。
    /// ponytail: 実測の裏付けがあるのは「窓の何割か」までで、何割から鈍るかは経験則。
    /// 使っていて早すぎる／遅すぎると感じたらこの3つの数だけ動かす
    static let rollingAt = 0.50
    static let heavyAt = 0.70
    static let warningAt = 0.85

    enum Stage: Int, CaseIterable, Sendable {
        case fresh      // まだ小さい
        case rolling    // 転がって育ってきた
        case heavy      // 重い。区切りを考える頃
        case warning    // 警報。鈍りやすい

        var title: String {
            switch self {
            case .fresh:   "文脈 軽い"
            case .rolling: "文脈 育ち中"
            case .heavy:   "文脈 重い"
            case .warning: "文脈 警報"
            }
        }

        /// 何をすればいいか。警報だけ出して手が無いと、見た人が困る
        var advice: String {
            switch self {
            case .fresh:   ""
            case .rolling: ""
            case .heavy:   "区切って引き継ぐか、圧縮を挟む頃"
            case .warning: "推論が鈍りやすい。引き継いで新しいセッションに移す"
            }
        }
    }

    nonisolated static func stage(_ growth: Double) -> Stage {
        switch growth {
        case ..<rollingAt: .fresh
        case ..<heavyAt:   .rolling
        case ..<warningAt: .heavy
        default:           .warning
        }
    }

    /// `236780` → `237k`、`1000000` → `1.0M`。チップにも凡例にも入る長さにする
    nonisolated static func short(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000:     "\(max(0, tokens))"
        case ..<1_000_000: "\(tokens / 1_000)k"
        default:           String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }

    /// 見たままの一行。「237k / 1.0M（24%）」
    nonisolated static func caption(tokens: Int, window: Int) -> String {
        let percent = Int((growth(tokens: tokens, window: window) * 100).rounded())
        return "\(short(tokens)) / \(short(window))（\(percent)%）"
    }

    // MARK: 溜まり具合

    /// セッション1本ぶんの実測。圧縮を挟んでも**通しの経過**が分かるように回数も持つ
    struct Reading: Sendable, Equatable {
        var tokens = 0          // 直近のターンの文脈
        var peak = 0            // このセッションで見た最大。窓の判定に使う
        var compactions = 0     // 圧縮された回数。長さそのものの目安
        var droppedTotal = 0    // 圧縮で落ちた合計。「どれだけ忘れたか」

        var window: Int { Snowman.window(observed: peak) }
        var growth: Double { Snowman.growth(tokens: tokens, window: window) }
        var stage: Stage { Snowman.stage(growth) }
        var caption: String { Snowman.caption(tokens: tokens, window: window) }
    }

    /// 1ターンぶんを取り込む
    nonisolated static func observe(_ reading: inout Reading, tokens: Int) {
        guard tokens > 0 else { return }
        reading.tokens = tokens
        reading.peak = max(reading.peak, tokens)
    }

    /// 圧縮された。**peak は下げない**——窓の大きさの判定材料なので、
    /// 下げると次の圧縮まで小さい窓で測ってしまう
    nonisolated static func compact(_ reading: inout Reading, before: Int, after: Int) {
        reading.compactions += 1
        reading.droppedTotal += max(0, before - after)
        reading.peak = max(reading.peak, before)
        reading.tokens = after
    }
}
