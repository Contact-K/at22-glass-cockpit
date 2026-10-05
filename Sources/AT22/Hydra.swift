import Foundation

/// 司令塔が別のエージェントに並列で仕事を回す（Droppy Code の Hydra と同じ往復の形）。
///
/// 司令塔は返事の末尾に ```` ```hydra ```` の囲みで頼みたい相手を並べるだけ。AT22 が head ごとに
/// **采配の門**（`dispatch:` 付きの門）を立て、人が許可すると worktree を作ってそのエージェントを起こし、
/// 最初の報告を**司令塔への次のメッセージ**として返す。司令塔は待ちループを回さない。
/// Lv.3 / Lv.4 は人に訊かずに起こす。マージ・push・PR は人が REVIEW / GIT で決める（自動では混ぜない）。
/// SwiftUI に依存しない（p0 で検査）
enum Hydra {
    /// 頼まれた1体
    struct Head: Equatable, Sendable {
        let name: String
        let agent: Backend
        let model: String
        let task: String
        let prompt: String
    }

    /// 暴走止め（設定の 07 で変える）。数えるのは**一系統**——head がさらに Hydra を呼んでも、根の司令塔で数える。
    /// 既定は Droppy Code と同じ 3ラウンド・同時8体・1体160回・35分
    static let maxHeadsKey = "hydraMaxHeads"
    static let maxRoundsKey = "hydraMaxRounds"
    static let maxToolsKey = "hydraMaxTools"
    static let maxMinutesKey = "hydraMaxMinutes"
    nonisolated static var maxHeads: Int { setting(maxHeadsKey, 8) }
    nonisolated static var maxRounds: Int { setting(maxRoundsKey, 3) }
    nonisolated static var maxTools: Int { setting(maxToolsKey, 160) }
    nonisolated static var maxMinutes: Int { setting(maxMinutesKey, 35) }
    private nonisolated static func setting(_ key: String, _ fallback: Int) -> Int {
        (UserDefaults.standard.object(forKey: key) as? Int).map { max(1, $0) } ?? fallback
    }

    /// 司令塔に渡す約束（`--append-system-prompt` に足す）
    static var protocolText: String { """
    ほかのエージェントに並列で任せたい仕事がある時は、返事の最後に次の形の囲みを書いてください（最大\(maxHeads)体）:
    ```hydra
    [{"name":"短い英数字の名前","agent":"codex","model":"","task":"一言で","prompt":"渡す指示の全文"}]
    ```
    agent は claude / codex / grok / hermes。AT22 が人の許可を取ってから head ごとに worktree を作って起こし、
    それぞれの最初の報告を次のメッセージで返します。報告を待つためにループを回す必要はありません。
    段が Lv.3/4 なら、全員の報告が揃った時に AT22 が各 head の枝をあなたの worktree に取り込み、結果を知らせます
    （ぶつかった枝は取り込まずに残します）。Lv.1/2 では、マージするかは人が決めます。push と PR はいつも人です。
    """ }

    /// 返事から ```` ```hydra ```` の囲みを拾う。壊れた JSON・知らないエージェント・空の指示は捨てる
    static func heads(in text: String) -> [Head] {
        var out: [Head] = []
        var rest = Substring(text)
        while let open = rest.range(of: "```hydra") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "```") else { break }
            let body = after[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            rest = after[close.upperBound...]
            guard let data = body.data(using: .utf8),
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
            for item in list {
                guard let agent = (item["agent"] as? String).flatMap({ Backend(rawValue: $0.lowercased()) }),
                      let prompt = (item["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !prompt.isEmpty else { continue }
                let raw = (item["name"] as? String) ?? (item["task"] as? String) ?? agent.rawValue
                out.append(Head(name: slug(raw), agent: agent, model: item["model"] as? String ?? "",
                                task: item["task"] as? String ?? "", prompt: prompt))
            }
        }
        return Array(out.prefix(maxHeads))
    }

    /// 取り込みの結果を司令塔へ返す1通
    static func landReport(merged: [String], conflicted: [String], failed: [(name: String, reason: String)]) -> String {
        var lines = ["[Hydra] 全員の報告が揃ったので、AT22 が head の枝をあなたの worktree に取り込みました。"]
        if !merged.isEmpty { lines.append("取り込んだ: " + merged.joined(separator: ", ")) }
        if !conflicted.isEmpty { lines.append("ぶつかったので取り込んでいない（枝は残っている・人に相談）: " + conflicted.joined(separator: ", ")) }
        for f in failed { lines.append("取り込めなかった: \(f.name) — \(String(f.reason.prefix(200)))") }
        lines.append(merged.isEmpty ? "取り込めたものはありません。どう進めるか人に相談してください。"
                     : "取り込んだ変更を読み、ビルドとテストを走らせて結果を報告してください。push と PR は人が決めます。")
        return lines.joined(separator: "\n")
    }

    /// worktree の名前に使える形（英数字とハイフン、32字まで）
    static func slug(_ raw: String) -> String {
        let mapped = raw.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
        let joined = String(mapped).split(separator: "-").joined(separator: "-")
        return String((joined.isEmpty ? "head" : joined).prefix(32))
    }

    /// head ごとの門（gate.sh の采配と同じ書式。`call: hydra-…` で Hydra 由来と分かる）
    static func gateText(_ head: Head, by session: String, at: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: at)
        var front = ["call: hydra-\(head.name)", "by: \(session)", "to: \(head.name)", "risk: high",
                     "issued: \(iso)", "dispatch: \(head.agent.rawValue)", "name: \(head.name)"]
        if !head.model.isEmpty { front.append("model: \(head.model)") }
        let task = head.task.isEmpty ? "" : "# \(head.task)\n\n"
        return "---\n" + front.joined(separator: "\n") + "\n---\n" + task + head.prompt + "\n"
    }

    /// 司令塔へ返す報告の1通
    static func report(name: String, agent: String, status: String, workspace: String, branch: String,
                       reply: String, landing: Bool = false) -> String {
        let state = ["done": "終わりました", "failed": "起こせませんでした", "stopped": "人が止めました",
                     "limit": "上限で止めました"][status] ?? status
        return """
        [Hydra] head「\(name)」（\(agent)）の報告です。\(state)。
        workspace: \(workspace)
        branch: \(branch)
        変更はこの worktree に残っています（`git -C \(workspace) diff` で読めます）。\(landing ? "全員の報告が揃ったら AT22 があなたの worktree に取り込みます。" : "マージは人が決めます。")

        \(reply.isEmpty ? "（返事はありません）" : String(reply.suffix(4000)))
        """
    }
}
