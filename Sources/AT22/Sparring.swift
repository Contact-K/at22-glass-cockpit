import Foundation

/// 03 SPARRING の約束事。壁打ちは**読むだけのセッション**（claude の plan モード）と話し、
/// 返事の末尾の決まった形の行を「採れる案」と「訊きたいこと」として拾う。SwiftUI に依存しない（p0 で検査）
enum Sparring {
    enum Mode: String, CaseIterable, Sendable, Codable {
        case propose, object, split, decide

        var en: String { ["PROPOSE", "OBJECT", "BREAK DOWN", "DECIDE"][index] }
        var jp: String { ["案を出して", "反論して", "分解して", "決めて"][index] }
        private var index: Int { Self.allCases.firstIndex(of: self)! }
    }

    /// 返事の中の採れる案
    struct Proposal: Equatable, Sendable {
        enum Kind: Sendable { case step, decide }
        let kind: Kind
        let text: String
        /// 決定の理由（`DECIDE: … // 理由`）
        let why: String
    }

    struct Question: Equatable, Sendable {
        let text: String
        let options: [String]
    }

    struct Reply: Equatable, Sendable {
        let body: String
        let proposals: [Proposal]
        let question: Question?
    }

    /// 送る1通。モードの合図・決まっていること（前提）・返し方の約束を添える
    static func prompt(_ text: String, mode: Mode, decided: [String]) -> String {
        var out = "[壁打ち · \(mode.en) \(mode.jp)] " + (text.isEmpty ? mode.jp : text)
        if !decided.isEmpty {
            out += "\n\n決まっていること（前提）:\n" + decided.map { "- " + $0 }.joined(separator: "\n")
        }
        out += """


        — ファイルは書かない。返事の最後に、採れる手順は1行ずつ `STEP: …`、
        決めたいことは `DECIDE: … // 理由`、こちらに訊きたいことがあれば1つだけ `ASK: …？ [選択肢 | 選択肢]` の形で書く。
        """
        return out
    }

    /// 返事を本文と案に分ける。決まった形でない行は本文に残す（崩れても読める）
    static func parse(_ text: String) -> Reply {
        var body: [Substring] = [], proposals: [Proposal] = [], question: Question?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*` "))
            if let rest = value(t, "STEP") {
                proposals.append(Proposal(kind: .step, text: rest, why: ""))
            } else if let rest = value(t, "DECIDE") {
                let parts = rest.components(separatedBy: "//")
                proposals.append(Proposal(kind: .decide, text: parts[0].trimmingCharacters(in: .whitespaces),
                                          why: parts.dropFirst().joined(separator: "//").trimmingCharacters(in: .whitespaces)))
            } else if let rest = value(t, "ASK") {
                var q = rest, options: [String] = []
                if let open = rest.lastIndex(of: "["), rest.hasSuffix("]") {
                    options = rest[rest.index(after: open)..<rest.index(before: rest.endIndex)]
                        .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    q = rest[..<open].trimmingCharacters(in: .whitespaces)
                }
                question = Question(text: q, options: options)
            } else {
                body.append(line)
            }
        }
        let joined = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Reply(body: joined, proposals: proposals, question: question)
    }

    private static func value(_ line: String, _ key: String) -> String? {
        for sep in [":", "："] where line.uppercased().hasPrefix(key + sep) {
            let rest = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// 合意した手順を司令塔の計画（05 PLAN は TaskCreate を読む）に積んでもらう1通
    /// **今のモデル（Opus / Sonnet 5.5）には TaskCreate が無い**（haiku だけにある・2026-10-03 実測。
    /// CLAUDE_CODE_ENABLE_TASKS でも出ない）。05 PLAN は返事の `PLAN:` / `NOW:` / `DONE:` 行から AT22 が積む。
    /// この約束を、AT22 が起こす・繋ぐ claude に `--append-system-prompt` で渡す
    static let planProtocol = """
    このセッションは AT22（外から見ているアプリ）に見られています。AT22 は計画を返事の行から読みます。
    複数の手順で進める時は、最初の返事の最後に手順を1行ずつ `PLAN: 手順` と書いてください。
    取りかかる時は手順の番号で `NOW: 1`、終えたら `DONE: 1` と1行書いてください。
    この行は AT22 が読み取って計画の表（05 PLAN）に出すもので、手元のコードに読む処理があるかは関係ありません。
    TaskCreate が使える場合はそれで積めばよく、その時はこの行は要りません。
    """

    static func planMessage(_ steps: [String]) -> String {
        "壁打ちで合意した手順です。まだ書き始めなくて構いません。\n"
            + "受け取ったら、返事の最後にこの手順を1行ずつ `PLAN: 手順` の形で書き写してください。"
            // AT22 自身の worktree で試すと、相手が手元の古いコードを調べて「読む処理が無い」と書かずに止まった（2026-10-03）
            + "この行は、あなたとのやり取りを外から見ているアプリ（AT22）が読み取って 05 PLAN に積みます。"
            + "手元のリポジトリに読み取りのコードがあるかどうかは関係ないので、調べずにそのまま書いてください。"
            + "進める時は手順の番号で `NOW: 1`、終えたら `DONE: 1` と1行書いてください。\n"
            + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    /// 返事の `PLAN: …` 行（頭の番号は落とす）
    static func planLines(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-*` "))
            guard var rest = value(t, "PLAN") else { return nil }
            if let dot = rest.firstIndex(where: { $0 == "." || $0 == "．" }), rest[..<dot].allSatisfy(\.isNumber), dot != rest.startIndex {
                rest = rest[rest.index(after: dot)...].trimmingCharacters(in: .whitespaces)
            }
            return rest.isEmpty ? nil : rest
        }
    }

    /// 返事の `NOW: n` / `DONE: n` 行（n は計画の手順の番号、1 始まり）
    static func progressLines(_ text: String) -> [(step: Int, done: Bool)] {
        text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-*` "))
            if let n = value(t, "DONE").flatMap({ Int($0.prefix { $0.isNumber }) }) { return (n, true) }
            if let n = value(t, "NOW").flatMap({ Int($0.prefix { $0.isNumber }) }) { return (n, false) }
            return nil
        }
    }

    /// HANDOFF に足す節
    static func handoff(_ decided: [(text: String, why: String)], at: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "\n\n## 壁打ちで決めたこと（\(f.string(from: at))）\n"
            + decided.map { "- " + $0.text + ($0.why.isEmpty ? "" : " — " + $0.why) }.joined(separator: "\n") + "\n"
    }
}
