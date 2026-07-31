import Foundation

// MARK: - 出来事

/// ファイルへの触り方。読むか、書くか
enum TouchKind: Sendable {
    case read
    case write
}

/// エージェントの作業の種類。実測でツール呼び出しの45%はファイル軸に載らないので、
/// 「何をしているか」はファイル名ではなくこの分類でしか出せない
enum WorkKind: String, Sendable, CaseIterable {
    case edit = "編集"
    case read = "読取"
    case search = "検索"
    case build = "ビルド"
    case git = "git"
    case view = "閲覧"
    case spawn = "起動"
    case wait = "待機"
    case other = "他"

    /// 待機（sleep / true）は作業ではない。実測でメインセッションの Bash の16.3%を占め、
    /// 労働量を水増ししていたので数に入れない
    var counts: Bool { self != .wait }
}

/// transcript の1行から取り出す出来事。
enum TranscriptEvent {
    case touchStarted(id: String, session: String, agent: String, path: String, kind: TouchKind, at: Date)
    case touchFinished(id: String, added: Int, removed: Int, at: Date)
    /// エージェントが行を書いた印。存在・モデル・最終活動時刻の登録
    case agentActivity(agent: String, session: String, model: String?, at: Date)
    /// ツール呼び出し1回ぶんの作業。ファイル軸に載らない Bash も含めて全部ここを通る
    case agentAction(agent: String, session: String, kind: WorkKind, detail: String, at: Date)
    /// サブエージェントの素性。`meta.json` 由来
    case agentMeta(agent: String, session: String, role: String, depth: Int, parentCall: String)
    /// サブエージェントの終了。労働量の確定値がここで来る（同期実行のみ）
    case agentDone(agent: String, session: String, role: String, model: String, toolCalls: Int, at: Date)
    /// サブエージェント自身が答えを返して止まった印。
    /// バックグラウンド実行だと親側に機械可読な完了記録が残らないので、こちらでしか終了が分からない
    case agentEnded(agent: String, at: Date)
    /// 誰がサブエージェントを起こしたか。`meta.json.parentCall` と突き合わせて親子を繋ぐ
    case agentSpawn(call: String, by: String)
}

// MARK: - 行パーサ

/// 行の JSON は `type` ごとに形が違い、`toolUseResult` は辞書だったり文字列だったりする。
/// Codable で全部を型付けすると1行の型崩れで丸ごと落ちるので、JSONSerialization で必要なキーだけ抜く。
/// ponytail: 未知の type / 壊れた行は黙って捨てる。読み飛ばす方が落ちるより安い
enum TranscriptParser {

    static let writeTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    static let readTools: Set<String> = ["Read"]
    /// サブエージェントを起こすツール。版によって名前が違うので両方見る
    static let spawnTools: Set<String> = ["Agent", "Task"]

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
        "cat": .view, "head": .view, "tail": .view, "ls": .view, "wc": .view, "diff": .view, "open": .view,
        "sleep": .wait, "true": .wait,
    ]

    /// Bash コマンドを作業の種類に分ける。実測 4148件の分類で、
    /// 検索 51.4% / 閲覧 14.5% / ビルド 12.4% / git 9.7% という内訳になったのと同じ規則。
    /// ponytail: 先頭語だけ見る。`xcodebuild | grep` を検索に誤分類しないための順序でもある
    static func classifyBash(_ command: String) -> (WorkKind, String) {
        // 実測で Bash の80%が連結コマンド。区切って、各区画の先頭語で見る
        let normalized = command
            .replacingOccurrences(of: "&&", with: "\n")
            .replacingOccurrences(of: "||", with: "\n")
        let segments = normalized.split(whereSeparator: { $0 == ";" || $0 == "|" || $0 == "\n" })

        var fallback: String?
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
            if let kind = bashKinds[head] { return (kind, head) }
            if fallback == nil { fallback = head }
        }
        return (.other, fallback ?? "")
    }

    /// `claude-haiku-4-5-20251001` → `haiku-4.5`。チップに入る長さにする
    static func shortModel(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        return version.isEmpty ? family : family + "-" + version.joined(separator: ".")
    }

    // ponytail: ISO8601DateFormatter の date(from:) はスレッドセーフ（Apple ドキュメント）。
    // 実際の呼び出しは MainActor 一本なので、生成コストを避けて使い回す
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

            for block in content {
                guard block["type"] as? String == "tool_use",
                      let name = block["name"] as? String,
                      let id = block["id"] as? String
                else { continue }
                let input = block["input"] as? [String: Any] ?? [:]

                if spawnTools.contains(name) {
                    events.append(.agentSpawn(call: id, by: agent))
                    events.append(.agentAction(agent: agent, session: session, kind: .spawn,
                                               detail: input["subagent_type"] as? String ?? "", at: at))
                    continue
                }

                if name == "Bash" {
                    let (kind, word) = classifyBash(input["command"] as? String ?? "")
                    events.append(.agentAction(agent: agent, session: session,
                                               kind: kind, detail: word, at: at))
                    continue
                }

                guard let path = (input["file_path"] ?? input["notebook_path"]) as? String else {
                    events.append(.agentAction(agent: agent, session: session,
                                               kind: .other, detail: name, at: at))
                    continue
                }

                let touch: TouchKind
                if writeTools.contains(name) { touch = .write }
                else if readTools.contains(name) { touch = .read }
                else {
                    events.append(.agentAction(agent: agent, session: session,
                                               kind: .other, detail: name, at: at))
                    continue
                }

                let full = normalize(path, cwd: cwd)
                events.append(.touchStarted(id: id, session: session, agent: agent,
                                            path: full, kind: touch, at: at))
                events.append(.agentAction(agent: agent, session: session,
                                           kind: touch == .write ? .edit : .read,
                                           detail: (full as NSString).lastPathComponent, at: at))
            }
            return events

        case "user":
            // tool_result はどのツールでも出るので、対応する touch を知らなければ受け手が捨てる。
            // ここで絞り込まないことで Read（structuredPatch を持たない）も確実に閉じられる
            guard let content = obj["message"].flatMap({ ($0 as? [String: Any])?["content"] }) as? [[String: Any]],
                  let id = content.first(where: { $0["type"] as? String == "tool_result" })?["tool_use_id"] as? String
            else { return [] }

            var events: [TranscriptEvent] = []
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
}

// MARK: - 追記の監視

/// `~/.claude/projects/**/*.jsonl` を追いかけて `TranscriptEvent` に変換する。
/// transcript は厳密に append-only なので、ファイルごとのオフセットを覚えて末尾差分だけ読む。
@MainActor
final class TranscriptWatcher {

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
         tailBytes: UInt64 = 16_000_000,
         initialTotalBudget: UInt64 = 48_000_000) {
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
        guard let data = try? Data(contentsOf: meta),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["agentType"] as? String
        else {
            awaitingMeta[id] = url          // まだ無い。次の走査で読み直す
            return []
        }
        labeled.insert(id)
        awaitingMeta[id] = nil
        // <project>/<sessionUUID>/subagents/agent-x.jsonl → 親セッションはディレクトリ名から取れる
        let session = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        return [.agentMeta(agent: id,
                           session: session,
                           role: TranscriptParser.roleName(type: type, description: obj["description"] as? String),
                           depth: obj["spawnDepth"] as? Int ?? 1,
                           parentCall: obj["toolUseId"] as? String ?? "")]
    }
}
