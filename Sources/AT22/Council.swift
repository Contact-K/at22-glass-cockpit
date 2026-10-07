import Foundation

/// 合議制レビュー（企画ノート「合議制レビューを高リスク判断だけに限定投入」）。
///
/// 司令塔が構造を大きく変えた時だけ、返事の末尾の ```` ```council ```` で頼む。AT22 は門で人に訊き（Lv.3/4 は訊かない）、
/// 司令塔と同じ worktree に**読むだけ**の席を3つ起こす（なるべく別の会社のモデル。自己レビューの偏りを避ける）。
/// 1. 各席が独立に意見 → 2. ほかの席の意見を見せて1回だけ反論 → 3. 司令塔が議長として
/// 合意点・対立点・優先対応リストにまとめる（multi-model-debate-review と同じ3段）。SwiftUI に依存しない（p0 で検査）
enum Council {
    struct Seat: Equatable, Sendable {
        let role: String
        let focus: String
        let agent: Backend
    }

    static let roles: [(role: String, focus: String)] = [
        ("批判者", "正しさ。壊れる入力や状態・取りこぼした呼び出し元・競合・計画との食い違い"),
        ("安全性", "権限・秘密・外への送出・取り消せない操作・データを失う経路"),
        ("単純化", "要らない抽象・重複・既にある部品の作り直し。削れるもの"),
    ]

    /// 席に座らせるエージェント。別の会社のモデルを先に（司令塔は claude なので claude は最後）
    static func seats(found: Set<Backend>) -> [Seat] {
        let pool = [Backend.codex, .grok, .claude].filter(found.contains)
        guard !pool.isEmpty else { return [] }
        return roles.enumerated().map { i, r in Seat(role: r.role, focus: r.focus, agent: pool[i % pool.count]) }
    }

    /// 司令塔に渡す約束（`--append-system-prompt` に足す）
    static let protocolText = """
    コードの構造を大きく変えた時（アーキテクチャの判断・分け方の変更・データの持ち方の変更など）だけ、返事の最後に
    次の囲みを書くと、AT22 が別のモデルの読むだけのレビュアー3席（批判者・安全性・単純化）にあなたの worktree を見せ、
    意見と1回の反論を集めて次のメッセージで返します。あなたは議長としてまとめます。重いので普段の変更には使わないでください。
    ```council
    何を見てほしいか（変えたこと・迷っている所）
    ```
    """

    /// 返事の最初の ```` ```council ```` の中身。空なら nil
    static func topic(in text: String) -> String? {
        guard let open = text.range(of: "```council") else { return nil }
        let after = text[open.upperBound...]
        guard let close = after.range(of: "```") else { return nil }
        let body = after[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    /// 門（`call: council` で合議と分かる。`dispatch:` は付けない——worktree は作らない）
    static func gateText(topic: String, by session: String, at: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: at)
        return "---\ncall: council\nby: \(session)\nto: 合議（読むだけの3席）\nrisk: high\nissued: \(iso)\n---\n" + topic + "\n"
    }

    /// 席が書こう・動かそうとした時に添える断り
    static let readOnlyNote = "合議の席は読むだけ。書く・動かす道具は使わず、意見だけ返して"

    /// 1巡目。独立に意見を出す
    static func opening(_ seat: Seat, topic: String) -> String {
        """
        [合議 · \(seat.role)] あなたは合議制レビューの1席です。ほかに2席が別の観点で同じものを見ています。
        観点: \(seat.focus)
        見るもの: この worktree の変更（`git status`・`git diff`・`git log --oneline -10` から読む）。
        司令塔の頼み:
        \(topic)

        — ファイルは書かない・何も動かさない。自分の観点だけで、指摘を深刻度（高・中・低）の順に、場所（ファイル:行）と理由を添えて短く。
        問題が無ければ「無し」と書く。
        """
    }

    /// 2巡目。ほかの席の意見を見せて1回だけ反論・同意・補足させる
    static func rebuttal(_ seat: Seat, others: [(seat: Seat, text: String)]) -> String {
        "[合議 · \(seat.role) · 反論] ほかの席の意見です。同意・反論・補足を1回だけ返してください。"
            + "新しく調べるのは反論の裏付けに要る所だけ。自分の指摘を直す・取り下げるならそう書く。\n\n"
            + others.map { "## \($0.seat.role)（\($0.seat.agent.title)）\n\(clip($0.text))" }.joined(separator: "\n\n")
    }

    /// 議長（司令塔）への1通。意見と反論を並べてまとめ方を指定する
    static func verdict(topic: String, opinions: [(seat: Seat, text: String)], rebuttals: [(seat: Seat, text: String)]) -> String {
        func section(_ title: String, _ items: [(seat: Seat, text: String)]) -> String {
            "# \(title)\n\n" + items.map { "## \($0.seat.role)（\($0.seat.agent.title)）\n\(clip($0.text))" }.joined(separator: "\n\n")
        }
        return """
        [合議] 3席の意見と反論が揃いました。議長として次の3つにまとめてください:
        ## 合意点 / ## 対立点（表で両論を並べ、あなたの判断を添える）/ ## 優先対応リスト（深刻度×合意の強さの順）
        直すかどうかは人と決めます。まとめを書くまでは手を動かさないでください。
        頼んだこと: \(topic)

        """ + section("意見", opinions) + "\n\n" + section("反論", rebuttals)
    }

    /// 1席の返事は長すぎたら頭を残す（結論は前に書かせている）
    static func clip(_ text: String, limit: Int = 6000) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "（返事なし）" }
        return t.count > limit ? String(t.prefix(limit)) + "\n…（以下略）" : t
    }
}
