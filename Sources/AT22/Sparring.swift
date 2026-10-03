import Foundation

/// 03 SPARRING の約束事。壁打ちは**読むだけのセッション**（claude の plan モード）と話し、
/// 返事の末尾の決まった形の行を「採れる案」と「訊きたいこと」として拾う。SwiftUI に依存しない（p0 で検査）
enum Sparring {
    enum Mode: String, CaseIterable, Sendable {
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
    static func planMessage(_ steps: [String]) -> String {
        "壁打ちで合意した手順です。この順でタスク（TaskCreate）に積んでください。まだ書き始めなくて構いません。\n"
            + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    /// HANDOFF に足す節
    static func handoff(_ decided: [(text: String, why: String)], at: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "\n\n## 壁打ちで決めたこと（\(f.string(from: at))）\n"
            + decided.map { "- " + $0.text + ($0.why.isEmpty ? "" : " — " + $0.why) }.joined(separator: "\n") + "\n"
    }
}
