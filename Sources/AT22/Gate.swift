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
        case each        // 隣で見てる：道具も門も全部訊く
        case normal      // 気にかけてる：低リスクの道具は猶予の後に通す・高リスクは訊く
        case auto        // 任せてる：低リスクの道具はすぐ通す・高リスクは訊く
        case unattended  // 留守番：低リスクはすぐ通す・高リスクは「要判断」に積んで断り、先へ進ませる

        /// 段として選べるもの（壁打ち＝plan は別のトグル）
        static let ladder: [Level] = [.each, .normal, .auto, .unattended]

        var title: String {
            switch self {
            // 壁打ちは段ではなく別のトグル（会話画面の「壁打ち」）。値 plan は門の受け渡しのため残す
            case .plan:       "壁打ち"
            case .each:       "Lv.1 隣で見てる"
            case .normal:     "Lv.2 気にかけてる"
            case .auto:       "Lv.3 任せてる"
            case .unattended: "Lv.4 留守番"
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
        /// 段の違いは claude ではなく **AT22 が持つ**（`decide`）。どの段も `default` で起こし、
        /// 道具の承認を全部 AT22 の承認パネル（`--permission-prompt-tool stdio`）に通す。
        /// `acceptEdits` は worktree の中の `rm` まで訊かずに通した（2026-10-05 agents-check で実測）ので使わない。
        /// `bypassPermissions` と `--bg` も使わない——留守番でも AT22 が承認を見て「要判断」に積む。
        /// サブエージェントを起こす Agent ツールはどの段でも訊かれない（実測）ので、そこは今も門が持つ
        var permissionMode: String { self == .plan ? "plan" : "default" }

        /// 道具の承認をどう扱うか（`Gate.risk` で決めた危険度ごと）
        func decide(_ risk: Risk) -> Decision {
            switch (self, risk) {
            case (.plan, _), (.each, _):           .ask
            case (.normal, .low):                  .graceAllow(Gate.grace)
            case (.auto, .low), (.unattended, .low): .allow
            case (.normal, .high), (.auto, .high): .ask
            case (.unattended, .high):             .queue
            }
        }

        /// 人間の承認なしにファイルを書き換える段。**入れた人の環境で効く**ので、
        /// 選ぶ時に一度だけ断りを入れる
        var needsConfirmation: Bool { self == .auto || self == .unattended }
    }

    // MARK: 道具の危険度（承認を段で決める）

    enum Risk: String, Sendable { case low, high }
    enum Decision: Equatable, Sendable { case ask, graceAllow(TimeInterval), allow, queue }

    /// claude に足す設定。Bash は claude が自分で通さず、必ず AT22 に訊かせる
    static let askSettings = #"{"permissions":{"ask":["Bash"]}}"#

    /// 気にかけてる（Lv.2）で低リスクの道具を通すまでの猶予。調整の口
    static let grace: TimeInterval = 10
    /// 人にしか答えられない問い。どの段でも自動で答えない
    static let humanOnly: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    /// 留守番で高リスクを断る時に添える文（claude にだけ届く。codex・ACP は素の却下）
    static let queuedMessage = "人の判断待ち（要判断）に積んだ。この手順は飛ばして、ほかの手順を先に進めて。やり直してよい時は人から伝える"

    /// 触ると高リスクにする場所（読むだけでも）
    static let secretMarks = [".ssh/", ".aws/", ".gnupg/", ".env", "id_rsa", "id_ed25519", "credentials", "Keychains", ".netrc"]
    private static let readTools: Set<String> = ["Read", "Glob", "Grep", "LS", "NotebookRead", "WebSearch", "WebFetch",
                                                 "TodoWrite", "Task", "Agent", "BashOutput", "KillShell", "ToolSearch",
                                                 "read", "search", "think", "fetch"]
    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit", "edit"]
    private static let shellTools: Set<String> = ["Bash", "execute"]

    /// 道具1回の危険度。**分からないものは高**。claude の道具名・codex（Bash / Edit）・ACP の kind を同じ表で見る
    nonisolated static func risk(tool: String, input: String, cwd: String) -> Risk {
        let json = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] ?? [:]
        if readTools.contains(tool) {
            return secretMarks.contains(where: input.contains) ? .high : .low
        }
        if editTools.contains(tool) {
            guard let path = (json["file_path"] ?? json["notebook_path"] ?? json["path"] ?? json["abs_path"]) as? String,
                  !path.isEmpty, !cwd.isEmpty else { return .high }
            let root = unaliased(URL(fileURLWithPath: cwd).standardizedFileURL.path)
            let target = unaliased(URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: root + "/")).standardizedFileURL.path)
            guard target.hasPrefix(root + "/") else { return .high }
            let inside = String(target.dropFirst(root.count))
            if ["/.git/", "/.claude/", "/.github/workflows/"].contains(where: inside.contains) { return .high }
            return secretMarks.contains(where: inside.contains) ? .high : .low
        }
        if shellTools.contains(tool) {
            let command = json["command"] as? String ?? (json["command"] as? [String])?.joined(separator: " ") ?? ""
            return bashRisk(command)
        }
        return .high
    }

    /// macOS の /tmp・/var・/etc は /private の下の別名。claude は実体の方で書いてくるので揃える
    nonisolated static func unaliased(_ path: String) -> String {
        for alias in ["/tmp", "/var", "/etc"] where path.hasPrefix("/private" + alias + "/") || path == "/private" + alias {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    private static let readCommands: Set<String> = ["ls", "cat", "head", "tail", "wc", "pwd", "echo", "grep", "rg", "tree",
                                                    "file", "stat", "du", "sort", "uniq", "cut", "diff", "which", "date", "cd"]
    private static let gitReads: Set<String> = ["status", "diff", "log", "show", "rev-parse", "ls-files", "blame", "grep"]

    /// シェルの1行。区切った**全部の段**が読むだけの許可の並びに入っている時だけ低。
    /// 引用符を見ずに区切るので、段が増えることはあっても高が低になることはない
    nonisolated static func bashRisk(_ command: String) -> Risk {
        let c = command.replacingOccurrences(of: "2>&1", with: " ").replacingOccurrences(of: "2>/dev/null", with: " ")
        if c.contains(where: { "`$<>\n".contains($0) }) { return .high }
        if c.replacingOccurrences(of: "&&", with: " ").contains("&") { return .high }
        let segments = c.replacingOccurrences(of: "&&", with: ";").replacingOccurrences(of: "||", with: ";")
            .split(whereSeparator: { $0 == ";" || $0 == "|" })
            .map { $0.split(whereSeparator: \.isWhitespace).map { $0.filter { !"'\"\\".contains($0) } }.filter { !$0.isEmpty } }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return .high }
        for words in segments {
            if words.contains(where: { word in secretMarks.contains(where: word.contains) }) { return .high }
            let head = words[0], rest = Array(words.dropFirst())
            switch head {
            case _ where readCommands.contains(head):
                continue
            case "find":
                if rest.contains(where: { ["-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fls"].contains($0) }) { return .high }
            case "git":
                guard let sub = rest.first, !rest.contains(where: { $0.hasPrefix("--output") }) else { return .high }
                if gitReads.contains(sub) { continue }
                if sub == "branch", rest.dropFirst().allSatisfy({ ["-a", "-r", "-v", "--list", "--show-current"].contains($0) }) { continue }
                return .high
            case "swift":
                guard let sub = rest.first, sub == "build" || sub == "test" else { return .high }
            case "xcodebuild":
                guard rest.contains("build") || rest.contains("test"),
                      !rest.contains(where: { ["archive", "install", "-exportArchive"].contains($0) }) else { return .high }
            default:
                return .high
            }
        }
        return .low
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
        /// 采配（dispatch）。司令塔が「このエージェントでワーカーを起こして」と頼む時だけ入る。
        /// 人が許可すると AT22 がワークスペースを作り、そこでこのエージェントを起こす
        var dispatch: Backend? = nil
        /// 采配で作るワークスペースの名前と基点
        var name = ""
        var base = ""
        /// 采配で起こすモデル（Hydra の head が指定した時だけ）
        var model = ""

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
                       instruction: Memory.body(text),
                       dispatch: front["dispatch"].flatMap(Backend.init(rawValue:)),
                       name: front["name"] ?? front["to"] ?? call,
                       base: front["base"] ?? "HEAD",
                       model: front["model"] ?? "")
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

    /// 采配したワーカーの結果の置き場。司令塔は .verdict の後にこれを待つ
    nonisolated static func resultPath(for gatePath: String) -> String {
        (gatePath as NSString).deletingPathExtension + ".result"
    }

    /// ワーカーの最初のターンが終わった時の結果。本文はワーカーの最後の発言
    nonisolated static func resultText(status: String, fields: [(String, String)], summary: String, at: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let lines = ([("status", status), ("at", iso.string(from: at))] + fields).map { "\($0.0): \($0.1)\n" }.joined()
        return "---\n\(lines)---\n" + summary.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// `…/projects/<slug>/memory/gate/<id>.md` → `…/projects/<slug>`。
    /// 答えは**門が置かれたプロジェクト**へ書く（その間に選択が別のセッションへ移っていても）
    nonisolated static func projectDirectory(of gatePath: String) -> String? {
        guard let range = gatePath.range(of: "/memory/" + directory + "/") else { return nil }
        return String(gatePath[..<range.lowerBound])
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
