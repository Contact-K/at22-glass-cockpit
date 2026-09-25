import Foundation

// MARK: - 指示の門

/// 司令塔がワーカーを起こす直前に、人間が指示に口を挟む仕組み。
///
/// **止めているのは AT22 ではなく司令塔**。AT22 は Claude Code に干渉しないので、
/// 司令塔が自分から Bash の待ちループに入り、AT22 が置いた答え（verdict）で抜ける。
///
/// ```
/// 司令塔:  gate/<id>.md を書く → until [ -f <id>.verdict ]; do sleep 2; done → 従う
/// AT22 :  門を見せる → 人間が答える → gate/<id>.verdict を書く
/// ```
///
/// 置き場は `memory/gate/`。`Cockpit.saveNote` の書き込みガード（`/memory/` の内側だけ）に
/// そのまま収まるので、AT22 が書ける範囲は増えない
enum Gate {

    static let directory = "gate"
    static let levelFile = "LEVEL"

    /// 承認の強さ。**指示ごとの判断ではなくモードで決まる**。
    /// 視点のモード（作業／構造／壁打ち）とは別軸——
    /// モードは「何を見るか」、こちらは「どこで止めるか」。表示名が衝突するので Lv 番号を付ける。
    ///
    /// **`rawValue` は変えない。** `memory/gate/LEVEL` に書かれた値を司令塔も読むので、
    /// 名前を変えると既に置かれたファイルが黙って既定に落ちる
    enum Level: String, CaseIterable, Sendable {
        case plan        // 壁打ち：司令塔だけ。ファイルに触らないので門も立たない
        case each        // 隣で見てる：サブエージェント到達前に全部止める
        case normal      // 気にかけてる：高リスクだけ止める
        case auto        // 任せてる：全部通す
        case unattended  // 留守番：全部通す（無人）

        var title: String {
            switch self {
            case .plan:       "Lv.1 壁打ち"
            case .each:       "Lv.2 隣で見てる"
            case .normal:     "Lv.3 気にかけてる"
            case .auto:       "Lv.4 任せてる"
            case .unattended: "Lv.5 留守番"
            }
        }

        /// この強さで、そのリスクの指示を止めるか
        func stops(risk: String) -> Bool {
            switch self {
            case .plan:              false      // そもそも指示を発行しない
            case .each:              true
            case .normal:            risk.lowercased() == "high"
            case .auto, .unattended: false
            }
        }

        /// `claude --permission-mode` のどれで起こすか。
        ///
        /// 訊く相手は AT22 の承認パネル（`--permission-prompt-tool stdio`）。
        /// Lv.2 は道具ごとに全部訊く（`default`）、Lv.3 は編集だけ任せてそれ以外を訊く（`acceptEdits`）。
        /// 以前は訊く相手が居なかったので Lv.2 も `acceptEdits` に寄せ、段の違いを門だけが持っていた。
        /// サブエージェントを起こす Agent ツールはどの段でも訊かれない（実測）ので、そこは今も門が持つ
        var permissionMode: String {
            switch self {
            case .plan:                   "plan"
            case .each:                   "default"
            case .normal:                 "acceptEdits"
            case .auto, .unattended:      "bypassPermissions"
            }
        }

        /// 人間が居ない前提で走らせるか（`--bg`）
        var background: Bool { self == .unattended }

        /// 人間の承認なしにファイルを書き換える段。**入れた人の環境で効く**ので、
        /// 選ぶ時に一度だけ断りを入れる
        var needsConfirmation: Bool { self == .auto || self == .unattended }
    }

    /// 既定は通常承認。各個承認を既定にすると、構想ノートが警告している
    /// 「毎回強制ブロックで承認地獄」になる
    static let defaultLevel = Level.normal

    /// 止まっている指示1件
    struct Request: Identifiable, Sendable {
        let id: String              // gate/<id>.md の絶対パス
        let call: String            // Agent ツールの tool_use id
        let by: String              // 出した司令塔のエージェントID
        let to: String              // 起こそうとしている相手
        let risk: String
        let issued: Date
        /// 指示の全文。押すとこれを編集できる
        let instruction: String

        /// 待たせている時間。司令塔は Bash の中で止まっているので、必ず出す
        func waited(now: Date) -> TimeInterval { max(0, now.timeIntervalSince(issued)) }
    }

    enum Verdict: String, Sendable {
        case allow      // そのまま発行
        case deny       // 発行せず記録して次へ
        case revise     // 書き換えた指示で発行。**口を挟むの本体**
    }

    // MARK: 読む

    /// `memory/gate/` の未処理の門。**verdict が既にあるものは閉じている**ので出さない。
    /// 発行順に並べる（並列に投げた分が同時に開くことがある）
    nonisolated static func pending(memoryRoot: URL) -> [Request] {
        let dir = memoryRoot.appendingPathComponent(directory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }

        var out: [Request] = []
        for url in entries where url.pathExtension == "md" {
            let answered = url.deletingPathExtension().appendingPathExtension("verdict")
            guard !FileManager.default.fileExists(atPath: answered.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let request = parse(path: url.standardizedFileURL.path, text: text) {
                out.append(request)
            }
        }
        return out.sorted { ($0.issued, $0.id) < ($1.issued, $1.id) }
    }

    /// 1件ぶんを起こす。書式は記憶DBと同じ frontmatter なので `Memory.frontMatter` を使い回す。
    /// `call` が無い門は司令塔と結びつけられないので捨てる——
    /// 相手の分からない門を出すと、誰を待たせているのか分からないまま画面に居座る
    nonisolated static func parse(path: String, text: String) -> Request? {
        let front = Memory.frontMatter(text)
        guard let call = front["call"], !call.isEmpty else { return nil }
        return Request(id: path,
                       call: call,
                       by: front["by"] ?? "",
                       to: front["to"] ?? call,
                       risk: front["risk"] ?? "",
                       issued: front["issued"].flatMap(date) ?? .distantPast,
                       instruction: Memory.body(text))
    }

    /// ISO8601。壊れていたら nil を返して `distantPast` に落とす（経過時間が伸び続けるだけで落ちない）
    nonisolated static func date(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw) ?? {
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: raw)
        }()
    }

    // MARK: 書く

    /// 答えの中身。書き込み自体は `Cockpit.saveNote` に通す（アトミック書き込みと
    /// 置き場のガードが1箇所に集まっている方が、壊れた状態を残す経路が減る）
    nonisolated static func verdictText(_ verdict: Verdict, at: Date, revised: String = "") -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var out = "---\nverdict: \(verdict.rawValue)\nat: \(iso.string(from: at))\n---\n"
        // revise の時だけ本文を持つ。司令塔は元の指示ではなくこちらを使う
        if verdict == .revise { out += revised.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" }
        return out
    }

    /// `gate/<id>.md` に対する答えの置き場
    nonisolated static func verdictPath(for request: Request) -> String {
        (request.id as NSString).deletingPathExtension + ".verdict"
    }

    // MARK: 承認モード

    nonisolated static func levelPath(memoryRoot: URL) -> String {
        memoryRoot.appendingPathComponent(directory).appendingPathComponent(levelFile).path
    }

    /// 壊れた値・空ファイル・ファイル無しは既定に落とす。
    /// ここで落ちると司令塔が読む値も決まらないので、必ず何か返す
    nonisolated static func level(memoryRoot: URL) -> Level {
        let raw = (try? String(contentsOfFile: levelPath(memoryRoot: memoryRoot), encoding: .utf8)) ?? ""
        return Level(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? defaultLevel
    }
}
