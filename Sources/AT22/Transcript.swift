import Foundation

// MARK: - 出来事

/// 発言の話し手。**関連値を持たない enum なので Swift が Equatable を自動合成するが、
/// 読み手が迷うので明示する。司令塔との窓口として使うので、人間の発言が出ないと会話にならない**
enum Speaker: Sendable, Equatable {
    case human
    case model
}

/// ファイルへの触り方。読むか、書くか
enum TouchKind: Sendable {
    case read
    case write
}

/// エージェントの作業の種類。実測でツール呼び出しの45%はファイル軸に載らないので、
/// 「何をしているか」はファイル名ではなくこの分類でしか出せない
enum WorkKind: String, Sendable, CaseIterable {
    case edit = "編集"
    /// Read ツールと、`cat` / `head` のようにファイルの中身を出す Bash の両方。
    /// 実測 Read 3096件 に対し Bash 側が 2379件あり、分けて数えると
    /// 「何度も読み返している」が2つのバケツに割れて順位から消える
    case read = "読取"
    case search = "検索"
    case build = "ビルド"
    case git = "git"
    case spawn = "起動"
    case wait = "待機"
    case other = "他"

    /// 待機（sleep / true）は作業ではない。実測でメインセッションの Bash の16.3%を占め、
    /// 労働量を水増ししていたので数に入れない
    var counts: Bool { self != .wait }
}

/// 進行表の1件の状態。実測で `TaskUpdate` に来るのは in_progress と completed の2つだけ
enum TaskStatus: Sendable {
    case pending
    case inProgress
    case completed
}

/// transcript の1行から取り出す出来事。
enum TranscriptEvent: Sendable {
    case touchStarted(id: String, session: String, agent: String, path: String, kind: TouchKind, at: Date)
    case touchFinished(id: String, added: Int, removed: Int, at: Date)
    /// エージェントが行を書いた印。存在・モデル・最終活動時刻の登録
    case agentActivity(agent: String, session: String, model: String?, at: Date)
    /// ツール呼び出し1回ぶんの作業。ファイル軸に載らない Bash も含めて全部ここを通る
    case agentAction(id: String, agent: String, session: String, kind: WorkKind, detail: String, at: Date)
    /// サブエージェントの素性。`meta.json` 由来
    case agentMeta(agent: String, session: String, role: String, depth: Int, parentCall: String)
    /// サブエージェントの終了。労働量の確定値がここで来る（同期実行のみ）
    case agentDone(agent: String, session: String, role: String, model: String, toolCalls: Int, at: Date)
    /// サブエージェント自身が答えを返して止まった印。
    /// バックグラウンド実行だと親側に機械可読な完了記録が残らないので、こちらでしか終了が分からない
    case agentEnded(agent: String, at: Date)
    /// 誰がサブエージェントを起こしたか。`meta.json.parentCall` と突き合わせて親子を繋ぐ。
    ///
    /// `type` は `subagent_type`、`title` は Agent ツールの `description`（作業内容の1行）。
    /// **`description` は以前まで捨てていた**——会話の側に「誰を何のために呼んだか」を
    /// 出す手掛かりがこれしか無いので拾う（実体の作業は盤面のエージェント帯が持つ）
    case agentSpawn(call: String, by: String, session: String,
                    type: String, title: String, at: Date)
    /// 進行表に1件積まれた。本文は tool_use 側、番号は結果側に来るので touchStarted と同じ二段構え
    case taskDeclared(call: String, session: String, subject: String, activeForm: String, detail: String, at: Date)
    /// `toolUseResult.task.id`。ここで初めて番号が決まる（順番から推測しない）
    case taskNumbered(call: String, id: String)
    case taskStatus(session: String, id: String, status: TaskStatus, at: Date)
    /// MCP は呼び出し側に本文、結果側にスレッドIDが来るので、タスクと同じく二段で結ぶ
    case mcpCalled(call: String, session: String, by: String, server: String, tool: String,
                   prompt: String, at: Date)
    case mcpThread(call: String, thread: String)
    /// 誰かが書いた言葉。**ツール呼び出しではない部分**。
    /// 人間か司令塔かで話し手が異なり、モデル側は text 256件 / thinking 297件あるのに
    /// tool_use しか見ていなかったため、これまで1文字も画面に出ていなかった
    case said(agent: String, session: String, text: String, speaker: Speaker, thinking: Bool, at: Date)
    /// 文脈の大きさ。`message.usage` から1ターンぶん。
    /// 膨らむと推論が鈍る（lost-in-the-middle）ので、鈍ってから気づかないように出す
    /// - `agent`: 誰がこのターンを出したか。メインセッションなら `== session`、サブエージェントなら hex
    /// - `spend`: そのターンで消費した量（重み付き）。**`tokens` とは別物**——文脈は「今どれだけ読んでいるか」
    case context(session: String, agent: String, tokens: Int, spend: Double, at: Date)
    /// 文脈が圧縮された。積み上がりがここで落ちる
    case compacted(session: String, before: Int, after: Int, at: Date)
}

// MARK: - 行パーサ

/// 行の JSON は `type` ごとに形が違い、`toolUseResult` は辞書だったり文字列だったりする。
/// Codable で全部を型付けすると1行の型崩れで丸ごと落ちるので、JSONSerialization で必要なキーだけ抜く。
/// ponytail: 未知の type / 壊れた行は黙って捨てる。読み飛ばす方が落ちるより安い
enum TranscriptParser {

    static let writeTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    static let readTools: Set<String> = ["Read"]
    /// ファイルを開かずに探すツール。実測では0件だが（検索は100% Bash 経由）、
    /// 使われた時に「他」へ落として検索の数から漏らさない
    static let searchTools: Set<String> = ["Grep", "Glob", "WebSearch"]

    /// 「何のツールで、何を相手に」を1つの札にする。相手が取れなければツール名だけ
    nonisolated static func label(_ tool: String, _ target: String) -> String {
        target.isEmpty ? tool : "\(tool) \(target)"
    }

    /// そのターンでモデルが読んだ文脈の量。
    ///
    /// **`cache_read_input_tokens` が本体**——実測でここが 236,780 に対し `input_tokens` は 1 だった。
    /// キャッシュに乗っている分も読んでいることに変わりはないので、3つを足したものが文脈の大きさ。
    /// `output_tokens` は入れない（次のターンの入力になるまでは文脈ではない）
    nonisolated static func contextTokens(_ usage: [String: Any]) -> Int {
        func number(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        return number("input_tokens")
            + number("cache_read_input_tokens")
            + number("cache_creation_input_tokens")
    }

    /// そのターンで消費した量。**`contextTokens` とは別物**——あちらは「今どれだけ読んでいるか」の
    /// スナップショットで、こちらは「どれだけ使ったか」の累積の1ターンぶん。
    /// 出力も数える（次のターンの入力になる前に、それ自体が消費されている）。
    ///
    /// レートリミットの実際の計算式は非公開なので、価格比を代理指標として使っている。
    /// ずれていたらここだけ動かせばいい。（`Snowman` の `rollingAt` / `heavyAt` / `warningAt`
    /// と同じ作法で外から触れる場所に置いている）
    nonisolated static func spend(_ usage: [String: Any]) -> Double {
        func number(_ key: String) -> Double { Double((usage[key] as? NSNumber)?.intValue ?? 0) }
        // 重み。入力を基準にした相対値
        let input = number("input_tokens") * 1.0
        let cacheCreation = number("cache_creation_input_tokens") * 1.25
        let cacheRead = number("cache_read_input_tokens") * 0.1
        let output = number("output_tokens") * 5.0
        return max(0, input + cacheCreation + cacheRead + output)
    }
    /// サブエージェントを起こすツール。版によって名前が違うので両方見る
    static let spawnTools: Set<String> = ["Agent", "Task"]
    /// 進行表の帳簿づけ。作業そのものではないので労働量には数えない
    static let taskTools: Set<String> = ["TaskCreate", "TaskUpdate", "TaskList"]

    /// 実測: 全268体のうち186体が `general-purpose`。オーケストレーターを回すと
    /// 実装もレビューも全部 `general-purpose` になり、役割名として役に立たない。
    /// 本当の役割は呼び出し時の description（「Haiku 実装ワーカー」「Sonnet レビュー Round 2」）にある
    static let genericTypes: Set<String> = ["general-purpose", "claude", "workflow-subagent"]

    static func roleName(type: String, description: String?) -> String {
        guard genericTypes.contains(type),
              let description, !description.isEmpty else { return type }
        return description
    }

    /// `cd` や `rtk proxy` の後ろに本命が来るので読み飛ばす
    static let bashPrefixes: Set<String> = ["cd", "env", "export", "sudo", "time", "nohup", "rtk", "proxy", "command"]

    static let bashKinds: [String: WorkKind] = [
        "xcodebuild": .build, "xcrun": .build, "swift": .build, "swiftc": .build,
        "simctl": .build, "npm": .build, "npx": .build, "pytest": .build, "make": .build, "cargo": .build,
        "git": .git, "gh": .git,
        "grep": .search, "rg": .search, "find": .search, "jq": .search,
        "awk": .search, "sed": .search, "ag": .search,
        // ls は「何があるか探す」行為なので find と同じ側。中身を出すものだけが読取
        "ls": .search,
        "cat": .read, "head": .read, "tail": .read, "wc": .read,
        "diff": .read, "open": .read, "less": .read, "more": .read, "bat": .read,
        "sleep": .wait, "true": .wait,
    ]

    /// Bash コマンドを作業の種類に分ける。実測 4148件の分類で、
    /// 検索 51.4% / 閲覧 14.5% / ビルド 12.4% / git 9.7% という内訳になったのと同じ規則。
    /// ponytail: 先頭語だけ見る。`xcodebuild | grep` を検索に誤分類しないための順序でもある
    static func classifyBash(_ command: String) -> (WorkKind, String, String) {
        // 実測で Bash の80%が連結コマンド。区切って、各区画の先頭語で見る
        let normalized = command
            .replacingOccurrences(of: "&&", with: "\n")
            .replacingOccurrences(of: "||", with: "\n")
        let segments = normalized.split(whereSeparator: { $0 == ";" || $0 == "|" || $0 == "\n" })

        var fallback: (String, String)?
        for segment in segments {
            var words = segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            while let first = words.first {
                let head = (first as NSString).lastPathComponent
                if first.contains("=") { words.removeFirst(); continue }   // FOO=1 cmd
                if head == "cd" {                                          // cd は引数も一緒に落とす
                    words.removeFirst()
                    if !words.isEmpty { words.removeFirst() }
                    continue
                }
                if bashPrefixes.contains(head) { words.removeFirst(); continue }
                break
            }
            guard let head = words.first.map({ ($0 as NSString).lastPathComponent }),
                  !head.isEmpty else { continue }
            let target = bashTarget(Array(words.dropFirst()))
            if let kind = bashKinds[head] { return (kind, head, target) }
            if fallback == nil { fallback = (head, target) }
        }
        return (.other, fallback?.0 ?? "", fallback?.1 ?? "")
    }

    /// コマンドが**何を相手にしているか**。`検索 grep` だけだと何を探したのか分からない。
    ///
    /// ponytail: 旗を飛ばして最初の実引数を取るだけ。パスなら末尾の要素に縮める。
    /// これは**表示用の札**で、ファイルへの線を引くための解決ではない——
    /// 実在するパスを取れるのは実測24.5%だけなので、そちらは元々諦めてある。
    /// 札なら実在しなくても「何を相手にしたか」は伝わる
    /// この旗の**値そのものが相手**。`find -name '*.swift'` で欲しいのは `.` ではなく `*.swift`
    static let valueIsTarget: Set<String> = ["-name", "-iname", "-path", "-e", "--include",
                                             "--glob", "--exclude", "-regex"]
    /// 相手として出しても何も伝わらない語。ここで落とさないと `find .` が「.」になる
    static let emptyTargets: Set<String> = [".", "./", "..", "-", "*", "$@"]

    nonisolated static func bashTarget(_ arguments: [String]) -> String {
        func unquote(_ s: String) -> String {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "'\"`"))
        }
        var words = arguments
        while let first = words.first {
            words.removeFirst()
            if first.hasPrefix("-") {
                // 値そのものが相手になる旗
                if valueIsTarget.contains(first), let value = words.first {
                    words.removeFirst()
                    let target = unquote(value)
                    if !target.isEmpty, !emptyTargets.contains(target) { return shorten(target) }
                    continue
                }
                // `-C 5` のような数の旗だけ値を落とす。**旗の名前では決めない**——
                // `grep -n パターン` の `-n` は値を取らないので、名前で決めると相手を食う
                if let next = words.first, next.allSatisfy(\.isNumber), !next.isEmpty {
                    words.removeFirst()
                }
                continue
            }
            let target = unquote(first)
            if target.isEmpty || emptyTargets.contains(target) { continue }
            return shorten(target)
        }
        return ""
    }

    /// パスらしければ末尾だけ。フルパスは紙にもチップにも入らない。
    /// `ls dir/` のように末尾が `/` でも畳む——実測でこれを外すと、
    /// `~/.claude/projects/` のようなよくある引数がフルパスのまま40字で切れて出ていた
    private nonisolated static func shorten(_ raw: String) -> String {
        var target = raw
        if target.contains("/") {
            let trailing = target.hasSuffix("/")
            let last = ((trailing ? String(target.dropLast()) : target) as NSString).lastPathComponent
            if !last.isEmpty { target = trailing ? last + "/" : last }
        }
        return String(target.prefix(40))
    }

    /// ファイル軸に載らないツールが**何を相手にしているか**。
    /// 実測でツール呼び出しの45%はここを通る。名前だけ出しても「Grep した」以上が分からない
    nonisolated static func toolTarget(name: String, input: [String: Any]) -> String {
        func text(_ key: String) -> String? {
            (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let raw = text("pattern") ?? text("query") ?? text("url") ?? text("prompt")
            ?? text("description") ?? text("command") ?? text("path") ?? text("file_path")
        guard let raw else { return "" }
        // URL はホストだけ。全部出すとチップの1行が丸ごと埋まる
        if raw.hasPrefix("http"), let host = URL(string: raw)?.host { return host }
        return String(raw.prefix(40))
    }

    static func taskStatus(_ raw: String?) -> TaskStatus? {
        switch raw {
        case "in_progress": return .inProgress
        case "completed":   return .completed
        case "pending":     return .pending
        default:            return nil     // 知らない状態は捨てる。勝手に完了扱いにしない
        }
    }

    /// transcript の user 行から人間の発言を抽出する。
    /// **人間の発言ではないもの**（tool_result のみ・isMeta・toolUseResult）は `nil` を返す。
    /// `content` は素の文字列か配列で、配列なら type=="text" のブロックのテキストを連結する。
    /// 空白のみになる場合も `nil` を返す
    nonisolated static func humanText(from message: [String: Any]) -> String? {
        // メッセージが無い、または isMeta フラグが立っていれば発言ではない
        if message["isMeta"] as? Bool == true { return nil }

        guard let content = message["content"] else { return nil }

        // content が素の文字列なら、それをそのまま使う
        if let text = content as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        // content が配列なら、type=="text" のブロックを集める
        guard let blocks = content as? [[String: Any]] else { return nil }

        // 配列が空、または tool_result のみなら発言ではない
        let textBlocks = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text",
                  let text = block["text"] as? String else { return nil }
            return text.isEmpty ? nil : text
        }

        guard !textBlocks.isEmpty else { return nil }
        let joined = textBlocks.joined(separator: "")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `claude-haiku-4-5-20251001` → `haiku-4.5`。チップに入る長さにする
    static func shortModel(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        return version.isEmpty ? family : family + "-" + version.joined(separator: ".")
    }

    // ponytail: 生成コストを避けて使い回す。根拠は date(from:) がスレッドセーフであること
    // （Apple ドキュメント）**だけ**。過去セッションの一括読み込み（Cockpit.replay）が
    // Task.detached から parse を叩くので、0.4秒ごとの MainActor のポーリングと実際に並行する。
    // 「呼び出しは MainActor 一本」という前提で書き換えないこと
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 同じファイルが別の表記で記録されると、参照回数が分散してフラグ判定が壊れる。
    /// 相対パスはその行の cwd で絶対化し、`./` や `..` も畳んでから鍵にする。
    static func normalize(_ path: String, cwd: String?) -> String {
        let absolute = path.hasPrefix("/")
            ? path
            : (cwd.map { ($0 as NSString).appendingPathComponent(path) } ?? path)
        return URL(fileURLWithPath: absolute).standardizedFileURL.path
    }

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// 1行分の JSON バイト列を解釈する。該当が無ければ空配列。
    static func parse(_ line: Data, fallbackSession: String) -> [TranscriptEvent] {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let at = date(obj["timestamp"])
        else { return [] }

        let session = obj["sessionId"] as? String ?? fallbackSession
        // サブエージェントの行だけ agentId を持つ。メインセッションは null なので session を代用する
        let agent = obj["agentId"] as? String ?? session
        let cwd = obj["cwd"] as? String

        switch obj["type"] as? String {
        case "assistant":
            guard let message = obj["message"] as? [String: Any] else { return [] }
            var events: [TranscriptEvent] = []
            let content = message["content"] as? [[String: Any]] ?? []
            let model = (message["model"] as? String).map(shortModel)
            events.append(.agentActivity(agent: agent, session: session, model: model, at: at))
            // サブエージェントが答えを返して止まった行。メインセッションは毎ターンここを通るので
            // 対象外にする（`agentId` を持つのはサブエージェントの行だけ）
            if obj["agentId"] is String, message["stop_reason"] as? String == "end_turn" {
                events.append(.agentEnded(agent: agent, at: at))
            }

            // 文脈の大きさ。cache_read が本体で、実測1セッションで 39k → 997k まで伸びた
            if let usage = message["usage"] as? [String: Any] {
                let tokens = contextTokens(usage)
                if tokens > 0 {
                    let consumed = spend(usage)
                    events.append(.context(session: session, agent: agent, tokens: tokens, spend: consumed, at: at))
                }
            }

            for block in content {
                // モデルの言葉。ツール呼び出しの隙間にあるこれが、これまで1件も出ていなかった
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty {
                        events.append(.said(agent: agent, session: session, text: text,
                                            speaker: .model, thinking: false, at: at))
                    }
                case "thinking":
                    // **本文が空でも出す。** 実測で全12セッション458件すべて `thinking` は空文字で、
                    // 残っているのは `signature` だけだった。本文が条件だと「考えた」印が
                    // 実データで一度も立たず、司令塔が思考中もアイドルに見える元の症状に戻る
                    events.append(.said(agent: agent, session: session,
                                        text: block["thinking"] as? String ?? "",
                                        speaker: .model, thinking: true, at: at))
                default: break
                }

                guard block["type"] as? String == "tool_use",
                      let name = block["name"] as? String,
                      let id = block["id"] as? String
                else { continue }
                let input = block["input"] as? [String: Any] ?? [:]

                if spawnTools.contains(name) {
                    let type = input["subagent_type"] as? String ?? ""
                    events.append(.agentSpawn(call: id, by: agent, session: session, type: type,
                                              title: input["description"] as? String ?? "", at: at))
                    events.append(.agentAction(id: id, agent: agent, session: session, kind: .spawn,
                                               detail: type, at: at))
                    continue
                }

                let mcp = name.components(separatedBy: "__")
                if mcp.count >= 3, mcp[0] == "mcp" {
                    events.append(.mcpCalled(call: id, session: session, by: agent,
                                             server: mcp[1], tool: mcp.dropFirst(2).joined(separator: "__"),
                                             prompt: input["prompt"] as? String ?? "", at: at))
                    // reply は結果を待つ前から既存スレッドだと確定している。ここで結ばないと
                    // 応答待ちの間だけ同じワーカーが2体に分裂して見える
                    if let thread = input["threadId"] as? String, !thread.isEmpty {
                        events.append(.mcpThread(call: id, thread: thread))
                    }
                    events.append(.agentAction(id: id, agent: agent, session: session, kind: .spawn,
                                               detail: mcp[1], at: at))
                    continue
                }

                if name == "Bash" {
                    let (kind, word, target) = classifyBash(input["command"] as? String ?? "")
                    events.append(.agentAction(id: id, agent: agent, session: session, kind: kind,
                                               detail: label(word, target), at: at))
                    continue
                }

                // 進行表。実測でタスクを作るのはメインセッションだけ（agent-*.jsonl では0件）。
                // 帳簿づけ自体は労働量に数えない。進行表として独立した帯に出るので二重計上になるうえ、
                // 実測で司令塔の労働331のうち58件（17.5%）を占めて本当の作業を順位から押し出す
                if taskTools.contains(name) {
                    if name == "TaskCreate", let subject = input["subject"] as? String {
                        events.append(.taskDeclared(call: id, session: session, subject: subject,
                                                    activeForm: input["activeForm"] as? String ?? "",
                                                    detail: input["description"] as? String ?? "", at: at))
                    } else if name == "TaskUpdate", let taskId = input["taskId"] as? String,
                              let status = taskStatus(input["status"] as? String) {
                        events.append(.taskStatus(session: session, id: taskId, status: status, at: at))
                    }
                    continue
                }

                guard let path = (input["file_path"] ?? input["notebook_path"]) as? String else {
                    // Grep も Glob も WebFetch もここを通る。名前だけ出しても
                    // 「Grep した」以上が分からないので、相手を添える
                    events.append(.agentAction(id: id, agent: agent, session: session,
                                               kind: searchTools.contains(name) ? .search : .other,
                                               detail: label(name, toolTarget(name: name, input: input)),
                                               at: at))
                    continue
                }

                let touch: TouchKind
                if writeTools.contains(name) { touch = .write }
                else if readTools.contains(name) { touch = .read }
                else {
                    events.append(.agentAction(id: id, agent: agent, session: session,
                                               kind: .other,
                                               detail: label(name, (path as NSString).lastPathComponent),
                                               at: at))
                    continue
                }

                let full = normalize(path, cwd: cwd)
                events.append(.touchStarted(id: id, session: session, agent: agent,
                                            path: full, kind: touch, at: at))
                events.append(.agentAction(id: id, agent: agent, session: session,
                                           kind: touch == .write ? .edit : .read,
                                           detail: (full as NSString).lastPathComponent, at: at))
            }
            return events

        case "system":
            // 文脈が圧縮された印。ここで積み上がりが落ちる（実測 999,564 → 15,178）。
            // これを拾わないと、雪だるまが一度育ったきり溶けない
            guard obj["subtype"] as? String == "compact_boundary",
                  let meta = obj["compactMetadata"] as? [String: Any] else { return [] }
            func number(_ key: String) -> Int { (meta[key] as? NSNumber)?.intValue ?? 0 }
            return [.compacted(session: session, before: number("preTokens"),
                               after: number("postTokens"), at: at)]

        case "user":
            guard let message = obj["message"] as? [String: Any] else { return [] }

            var events: [TranscriptEvent] = []
            // **人間の発言を拾う。** 会話として成立するには自分の言葉が画面に出ないといけない。
            // toolUseResult を持つ行（ツール結果の運び屋）は発言として出さない。
            // `isMeta` は行の直下に付くことも `message` の中に入ることもあるので、両方見る
            // （実データでの形はまだ実測していない。広めに構えて、混ざるより落とす方を選ぶ）
            if obj["toolUseResult"] == nil, obj["isMeta"] as? Bool != true,
               let text = humanText(from: message) {
                events.append(.said(agent: session, session: session, text: text,
                                    speaker: .human, thinking: false, at: at))
            }

            // tool_result はどのツールでも出るので、対応する touch を知らなければ受け手が捨てる。
            // ここで絞り込まないことで Read（structuredPatch を持たない）も確実に閉じられる
            guard let content = message["content"] as? [[String: Any]],
                  let resultBlock = content.first(where: { $0["type"] as? String == "tool_result" }),
                  let id = resultBlock["tool_use_id"] as? String
            else { return events }
            if let result = obj["toolUseResult"] as? [String: Any],
               let sub = result["agentId"] as? String {
                let model = (result["resolvedModel"] as? String).map(shortModel)
                // バックグラウンド起動は `status:"async_launched"` で、まだ何もしていない。
                // agentId があるだけで終了とみなすと、起動した瞬間に灰色＋労働0になる
                if let calls = result["totalToolUseCount"] as? Int {
                    events.append(.agentDone(agent: sub,
                                             session: session,
                                             role: roleName(type: result["agentType"] as? String ?? "",
                                                            description: result["description"] as? String),
                                             model: model ?? "",
                                             toolCalls: calls,
                                             at: at))
                } else {
                    // 起動しただけ。存在とモデルだけ台帳に載せる
                    events.append(.agentActivity(agent: sub, session: session, model: model, at: at))
                }
            }

            // MCP 以外は辞書や配列も返す。文字列の中が JSON で threadId を持つ時だけ拾う。
            if let raw = (obj["toolUseResult"] as? String) ?? (resultBlock["content"] as? String),
               let data = raw.data(using: .utf8),
               let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let thread = result["threadId"] as? String, !thread.isEmpty {
                events.append(.mcpThread(call: id, thread: thread))
            }

            // TaskCreate の番号は結果にしか無い: {"task":{"id":"1","subject":"…"}}
            if let result = obj["toolUseResult"] as? [String: Any],
               let task = result["task"] as? [String: Any],
               let number = task["id"] as? String {
                events.append(.taskNumbered(call: id, id: number))
            }

            var added = 0, removed = 0
            if let result = obj["toolUseResult"] as? [String: Any] {
                let patch = result["structuredPatch"] as? [[String: Any]] ?? []
                for hunk in patch {
                    for l in (hunk["lines"] as? [String] ?? []) {
                        if l.hasPrefix("+") { added += 1 } else if l.hasPrefix("-") { removed += 1 }
                    }
                }
                // Write の新規作成は structuredPatch が空で、本文は content にしか無い。
                // ここを拾わないと「200行のファイルを新規で書いた」が最小の重みになってしまう
                if patch.isEmpty, result["type"] as? String == "create",
                   let body = result["content"] as? String {
                    added = body.isEmpty ? 0 : body.split(separator: "\n", omittingEmptySubsequences: false).count
                }
            }
            events.append(.touchFinished(id: id, added: added, removed: removed, at: at))
            return events

        default:
            return []
        }
    }

    /// 過去セッションの一括読み込みと追記監視で役割の解釈を揃える
    static func parseMeta(_ data: Data, agent: String, session: String) -> TranscriptEvent? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["agentType"] as? String else { return nil }
        return .agentMeta(agent: agent, session: session,
                          role: roleName(type: type, description: obj["description"] as? String),
                          depth: obj["spawnDepth"] as? Int ?? 1,
                          parentCall: obj["toolUseId"] as? String ?? "")
    }
}

// MARK: - 追記の監視

/// `~/.claude/projects/**/*.jsonl` を追いかけて `TranscriptEvent` に変換する。
/// transcript は厳密に append-only なので、ファイルごとのオフセットを覚えて末尾差分だけ読む。
@MainActor
final class TranscriptWatcher {

    nonisolated static let defaultTailBytes: UInt64 = 16_000_000
    nonisolated static let defaultTotalBudget: UInt64 = 48_000_000

    /// 起動時に1ファイルあたり遡って読む上限。
    /// 実測で単一 transcript の最大は 10.9MB なので、これで既存のどれも丸ごと入る。
    /// 小さすぎると起動前の履歴が黙って窓から落ち、参照回数が減ってフラグが消える
    private let tailBytes: UInt64
    /// 起動時に読む総量の上限。ファイル数 × tailBytes が青天井にならないよう、
    /// 新しいものから予算を使う。実測 35MB/s なので 48MB ≒ 1.4秒
    private let initialTotalBudget: UInt64
    /// 起動時に対象にするファイルの新しさ。これより古いものは以後の追記だけ拾う
    private let initialWindow: TimeInterval = 24 * 60 * 60

    private let root: URL
    private var offsets: [String: UInt64] = [:]
    private var carry: [String: Data] = [:]       // 改行で切れなかった端数
    private var skipPartial: Set<String> = []     // 途中から読み始めた分の先頭1行は捨てる
    private var labeled: Set<String> = []         // meta.json を読み終えたサブエージェント
    private var awaitingMeta: [String: URL] = [:] // meta.json がまだ書かれていないサブエージェント
    private var loop: Task<Void, Never>?

    var onEvents: (([TranscriptEvent]) -> Void)?

    init(root: URL? = nil,
         tailBytes: UInt64 = TranscriptWatcher.defaultTailBytes,
         initialTotalBudget: UInt64 = TranscriptWatcher.defaultTotalBudget) {
        self.root = root ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        self.tailBytes = tailBytes
        self.initialTotalBudget = initialTotalBudget
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { @MainActor in
            var first = true
            while !Task.isCancelled {
                poll(initial: first)
                first = false
                // ponytail: 0.4秒ポーリング。監視対象が数千ファイルを超えたら FSEvents に差し替え
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: 走査

    private func scan() -> [(url: URL, size: UInt64, mtime: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: root,
                                                     includingPropertiesForKeys: Array(keys),
                                                     options: [.skipsHiddenFiles])
        else { return [] }

        var out: [(URL, UInt64, Date)] = []
        for case let url as URL in e {
            guard url.pathExtension == "jsonl",
                  let v = try? url.resourceValues(forKeys: keys),
                  v.isRegularFile == true,
                  let size = v.fileSize, let mtime = v.contentModificationDate
            else { continue }
            out.append((url, UInt64(size), mtime))
        }
        return out
    }

    /// 1回分の走査。ループから呼ばれるほか、セルフチェックが直接叩く
    func poll(initial: Bool) {
        var events: [TranscriptEvent] = []
        var budget = initial ? initialTotalBudget : UInt64.max

        // meta.json は .jsonl より後に書かれることがある（実測 273体中62体、遅れの中央値341秒）。
        // 初見の1回で諦めると、その分のチップが hex の羅列のまま親子も繋がらない
        // ponytail: 最後まで来ないケースは実測で0件。仮に来なくても140バイトの空振りが増えるだけ
        for url in Array(awaitingMeta.values) { events += label(for: url) }

        var files = scan()
        // 起動時は新しいものから予算を使う。切り詰めるなら古い方から
        if initial { files.sort { $0.mtime > $1.mtime } }

        for (url, size, mtime) in files {
            let key = url.path

            if offsets[key] == nil {
                // 初見のファイル。起動直後は最近のものだけ遡り、それ以外は末尾に付ける
                let recent = !initial || Date().timeIntervalSince(mtime) < initialWindow
                var start = size
                if recent {
                    let want = min(tailBytes, budget)
                    start = size > want ? size - want : 0
                    budget -= min(budget, size - start)
                }
                offsets[key] = start
                if start > 0 { skipPartial.insert(key) }
                if recent { events += label(for: url) }
            }

            let offset = offsets[key]!
            if size < offset {              // 切り詰められた（通常起きない）→ 読み直す
                offsets[key] = 0
                carry[key] = nil
                continue
            }
            guard size > offset else { continue }

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { continue }
            offsets[key] = offset + UInt64(chunk.count)

            let buffer = (carry[key] ?? Data()) + chunk
            guard let lastNewline = buffer.lastIndex(of: 0x0A) else {
                carry[key] = buffer                     // まだ1行も完成していない
                continue
            }
            let complete = buffer[buffer.startIndex..<lastNewline]
            carry[key] = Data(buffer[buffer.index(after: lastNewline)...])

            let fallback = url.deletingPathExtension().lastPathComponent
            var lines = complete.split(separator: 0x0A, omittingEmptySubsequences: true)
            if skipPartial.remove(key) != nil, !lines.isEmpty {
                lines.removeFirst()                     // 途中から読んだ先頭は壊れている
            }
            for line in lines {
                events += TranscriptParser.parse(Data(line), fallbackSession: fallback)
            }
        }

        if !events.isEmpty { onEvents?(events) }
    }

    /// `subagents/agent-<id>.jsonl` の隣にある meta.json から役割・階層・親の呼び出しIDを拾う。
    /// これが無いとチップが hex の羅列になり、親子も繋がらない。
    private func label(for url: URL) -> [TranscriptEvent] {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("agent-") else { return [] }
        let id = String(name.dropFirst("agent-".count))
        guard !labeled.contains(id) else { return [] }

        let meta = url.deletingPathExtension().appendingPathExtension("meta.json")
        // <project>/<sessionUUID>/subagents/agent-x.jsonl → 親セッションはディレクトリ名から取れる
        let session = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        guard let data = try? Data(contentsOf: meta),
              let event = TranscriptParser.parseMeta(data, agent: id, session: session)
        else {
            awaitingMeta[id] = url          // まだ無い。次の走査で読み直す
            return []
        }
        labeled.insert(id)
        awaitingMeta[id] = nil
        return [event]
    }
}
