import Foundation

// MARK: - ACP（Agent Client Protocol）

/// JSON-RPC 2.0 の1行を組み立て・仕分ける。ACP は stdio の上を1行1メッセージで流れる。
/// Grok（`grok agent stdio`）のほか、Gemini CLI・OpenCode・Hermes も同じ口を話す
enum RPC {
    /// 相手から来た1行の種類
    enum Line {
        /// こちらの問いへの返事
        case response(id: Int, result: [String: Any], error: String?)
        /// 相手からの問い（承認など）。`id` は相手の採番なので型を問わずそのまま返す
        case request(id: Any, method: String, params: [String: Any])
        /// 相手からの知らせ（`session/update` など）
        case notification(method: String, params: [String: Any])
    }

    /// 壊れた行・知らない形は nil。読み飛ばす方が落ちるより安い
    nonisolated static func classify(_ data: Data) -> Line? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let params = object["params"] as? [String: Any] ?? [:]
        if let method = object["method"] as? String {
            if let id = object["id"] { return .request(id: id, method: method, params: params) }
            return .notification(method: method, params: params)
        }
        guard let id = (object["id"] as? NSNumber)?.intValue else { return nil }
        let error = (object["error"] as? [String: Any]).map { ($0["message"] as? String) ?? "エラー" }
        return .response(id: id, result: object["result"] as? [String: Any] ?? [:], error: error)
    }

    nonisolated static func request(id: Int, method: String, params: [String: Any]) -> Data? {
        line(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    nonisolated static func notification(method: String, params: [String: Any]) -> Data? {
        line(["jsonrpc": "2.0", "method": method, "params": params])
    }

    nonisolated static func result(id: Any, _ result: [String: Any]) -> Data? {
        line(["jsonrpc": "2.0", "id": id, "result": result])
    }

    /// 知らない問いへの返事。答えないと相手はそこで待ち続ける
    nonisolated static func methodNotFound(id: Any) -> Data? {
        line(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "AT22 はこの問いに答えない"]])
    }

    private nonisolated static func line(_ object: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        else { return nil }
        data.append(0x0A)   // 1行1メッセージ。改行が無いと相手が読み始めない
        return data
    }
}

/// ACP を話すエージェントとの1本。**AT22 はファイル操作も端末も「持たない」と名乗る**——
/// そうするとエージェントは自分の道具で作業し、AT22 は読んで答えるだけのままでいられる。
///
/// 流れ（`grok agent stdio` で実測）: initialize → session/new（続きなら session/load）→
/// session/prompt。返事は session/update の知らせで流れ、prompt の返事でターンが閉じる。
/// 割り込みは session/cancel の知らせで、止めたターンは `stopReason: cancelled` で返る
@MainActor
final class ACPConnection: AgentConnection {
    private let input: FileHandle
    let process: Process
    /// AT22 側のセッションID
    private let session: String
    private let cwd: String
    /// 続きに繋ぐ相手側のセッションID（session/load）。新規なら nil
    private let resume: String?
    /// session/new の `_meta`（Grok の `yoloMode` など）
    private let meta: [String: Any]
    private let onEvent: @Sendable (AgentEvent) -> Void

    private enum Pending { case initialize, open, prompt }
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    /// 相手側のセッションID。決まるまでは言葉を溜めておく
    private(set) var remoteID: String?
    private var queued: [String] = []
    private var promptOpen = false
    /// session/load の間は履歴の送り直しが流れてくる。今のターンと混ぜない
    private var loading = false
    private var history: (human: Bool, text: String)?
    /// 今のターンの書きかけ。ターンが閉じた時に確定した発言にする
    private var reply = ""
    private var thought = ""
    /// 道具の素性。開始の知らせにしか種類や題が載らないことがあるので覚えておく
    private var tools: [String: Tool] = [:]
    /// 答え待ちの承認。返事には相手が採番した id と、選択肢の id が要る
    private var asks: [String: (id: Any, options: [[String: Any]])] = [:]

    struct Tool: Equatable, Sendable {
        var kind: WorkKind
        var title: String
        var path: String?
        var write: Bool
        var done = false
    }

    private init(process: Process, input: FileHandle, session: String, cwd: String, resume: String?,
                 meta: [String: Any], onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        self.process = process
        self.input = input
        self.session = session
        self.cwd = cwd
        self.resume = resume
        self.meta = meta
        self.onEvent = onEvent
    }

    /// 起こして挨拶まで済ませる。言葉は `send` で渡す（繋がるまでは溜めておく）
    static func start(_ executable: URL, arguments: [String], cwd: String, path: String?,
                      session: String, resume: String? = nil, meta: [String: Any] = [:],
                      onEvent: @escaping @Sendable (AgentEvent) -> Void,
                      onExit: @escaping @Sendable (Int32, String) -> Void) throws -> ACPConnection {
        let box = Box()
        let (process, input) = try Launcher.spawn(
            executable, arguments: arguments, cwd: cwd, path: path,
            onLine: { line in Task { @MainActor in box.connection?.receive(line) } },
            onExit: onExit)
        let connection = ACPConnection(process: process, input: input, session: session, cwd: cwd,
                                       resume: resume, meta: meta, onEvent: onEvent)
        // 相手は挨拶を受けるまで何も話さないので、ここで結んでから送れば取りこぼさない
        box.connection = connection
        connection.call(.initialize, "initialize", [
            "protocolVersion": 1,
            "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false],
            "clientInfo": ["name": "AT22", "version": "0.2"],
        ])
        return connection
    }

    @MainActor private final class Box { weak var connection: ACPConnection? }

    // MARK: 送る

    /// 繋がるのを待たせている言葉がある間も受けない。受けると後ろに積まれ、人の知らない順で流れる
    var acceptsInput: Bool { !promptOpen && queued.isEmpty }

    func send(_ text: String) -> Bool {
        guard acceptsInput else { return false }
        guard remoteID != nil else {
            queued.append(text)     // まだ繋がっていない。繋がった時に流す
            return true
        }
        return prompt(text)
    }

    @discardableResult
    private func prompt(_ text: String) -> Bool {
        guard let remoteID else { return false }
        promptOpen = true
        reply = ""
        thought = ""
        return call(.prompt, "session/prompt", ["sessionId": remoteID, "prompt": [["type": "text", "text": text]]])
    }

    func interrupt() -> String? {
        guard promptOpen, let remoteID,
              let line = RPC.notification(method: "session/cancel", params: ["sessionId": remoteID]),
              (try? input.write(contentsOf: line)) != nil else { return nil }
        return ""       // ACP の割り込みは知らせなので、照合する受領確認は無い
    }

    func answer(_ approval: Approval, allow: Bool, input: String?) -> Bool {
        guard let ask = asks.removeValue(forKey: approval.id) else { return false }
        // 選択肢の種類は allow_once / allow_always / reject_once / reject_always。
        // **一度きりの方を選ぶ**——「以後ずっと」を AT22 が勝手に選ぶと、人が知らないまま次から通る
        let option = Self.option(ask.options, allow: allow)
        let outcome: [String: Any] = option.map { ["outcome": "selected", "optionId": $0] } ?? ["outcome": "cancelled"]
        guard let line = RPC.result(id: ask.id, ["outcome": outcome]) else { return false }
        return (try? self.input.write(contentsOf: line)) != nil
    }

    func close() { try? input.close() }

    @discardableResult
    private func call(_ kind: Pending, _ method: String, _ params: [String: Any]) -> Bool {
        nextID += 1
        pending[nextID] = kind
        guard let line = RPC.request(id: nextID, method: method, params: params),
              (try? input.write(contentsOf: line)) != nil else { return false }
        return true
    }

    // MARK: 受ける

    private func receive(_ data: Data) {
        switch RPC.classify(data) {
        case let .response(id, result, error)?:
            guard let kind = pending.removeValue(forKey: id) else { return }
            answered(kind, result: result, error: error)
        case let .request(id, method, params)?:
            asked(id: id, method: method, params: params)
        case let .notification(method, params)?:
            if method == "session/update", let update = params["update"] as? [String: Any] { updated(update) }
        case nil:
            break
        }
    }

    private func answered(_ kind: Pending, result: [String: Any], error: String?) {
        switch kind {
        case .initialize:
            if let error { return onEvent(.turnFailed("繋げなかった: \(error)")) }
            var params: [String: Any] = ["cwd": cwd, "mcpServers": [Any]()]
            if !meta.isEmpty { params["_meta"] = meta }
            if let resume {
                params["sessionId"] = resume
                loading = true
                call(.open, "session/load", params)
            } else {
                call(.open, "session/new", params)
            }

        case .open:
            loading = false
            flushHistory()
            if let error { return onEvent(.turnFailed("セッションを開けなかった: \(error)")) }
            guard let id = (result["sessionId"] as? String) ?? resume else {
                return onEvent(.turnFailed("相手がセッションIDを返さなかった"))
            }
            remoteID = id
            onEvent(.ready(remoteID: id))
            if !queued.isEmpty { prompt(queued.removeFirst()) }

        case .prompt:
            promptOpen = false
            if !thought.isEmpty { onEvent(.message(thought, thinking: true)) }
            if !reply.isEmpty { onEvent(.message(reply, thinking: false)) }
            thought = ""
            reply = ""
            if let error { onEvent(.turnFailed(error)) }
            else { onEvent(Self.turnEnd(result)) }
        }
    }

    private func asked(id: Any, method: String, params: [String: Any]) {
        guard method == "session/request_permission" else {
            // ファイル操作も端末も「持たない」と名乗っているので、来ても答えない
            if let line = RPC.methodNotFound(id: id) { try? input.write(contentsOf: line) }
            return
        }
        let key = "\(id)"
        asks[key] = (id, params["options"] as? [[String: Any]] ?? [])
        onEvent(.approval(Self.approval(key, session: session, params: params)))
    }

    private func updated(_ update: [String: Any]) {
        let kind = update["sessionUpdate"] as? String ?? ""
        let text = ((update["content"] as? [String: Any])?["text"] as? String) ?? ""
        if loading {
            // 履歴の送り直し。会話の履歴としてだけ出す（道具は今の出来事と混ざるので出さない）
            switch kind {
            case "user_message_chunk": appendHistory(human: true, text)
            case "agent_message_chunk": appendHistory(human: false, text)
            default: break
            }
            return
        }
        switch kind {
        case "agent_message_chunk":
            reply += text
            onEvent(.partial(text))
        case "agent_thought_chunk":
            thought += text
        case "tool_call", "tool_call_update":
            guard let id = update["toolCallId"] as? String else { return }
            let before = tools[id]
            let merged = Self.tool(update, known: before)
            tools[id] = merged
            // 開始と完了の2回だけ出す。途中経過（出力の追記など）まで流すと労働量が水増しになる
            guard before == nil || (merged.done && before?.done != true) else { return }
            onEvent(.tool(id: id, kind: merged.kind, title: merged.title, path: merged.path,
                          write: merged.write, done: merged.done))
        default:
            break       // Grok 独自の `_x.ai/...` やフックの実行記録は読み飛ばす
        }
    }

    private func appendHistory(human: Bool, _ text: String) {
        if let current = history, current.human == human {
            history = (human, current.text + text)
        } else {
            flushHistory()
            history = (human, text)
        }
    }

    private func flushHistory() {
        guard let current = history, !current.text.isEmpty else { return }
        history = nil
        onEvent(current.human ? .said(current.text) : .message(current.text, thinking: false))
    }

    // MARK: 変換（自己チェックが直接叩く）

    /// prompt の返事でターンを閉じる。人が止めたターン（cancelled）は失敗ではない
    nonisolated static func turnEnd(_ result: [String: Any]) -> AgentEvent {
        let reason = result["stopReason"] as? String ?? "end_turn"
        let tokens = ((result["_meta"] as? [String: Any])?["inputTokens"] as? NSNumber)?.intValue
        switch reason {
        case "end_turn", "cancelled": return .turnEnded(tokens: tokens)
        default: return .turnFailed(reason)     // max_tokens / max_turn_requests / refusal
        }
    }

    /// tool_call / tool_call_update を道具の素性に直す。後から来る知らせは種類や題を欠くことがあるので、
    /// 知っている分（`known`）に重ねる
    nonisolated static func tool(_ update: [String: Any], known: Tool?) -> Tool {
        let meta = (update["_meta"] as? [String: Any])?["x.ai/tool"] as? [String: Any]
        let acpKind = (update["kind"] as? String) ?? (meta?["kind"] as? String)
        let raw = update["rawInput"] as? [String: Any] ?? [:]
        let command = raw["command"] as? String
        let path = ((update["locations"] as? [[String: Any]])?.first?["path"] as? String)
            ?? (raw["path"] as? String) ?? (raw["file_path"] as? String)

        var tool = known ?? Tool(kind: .other, title: "", path: nil, write: false)
        if let acpKind {
            switch acpKind {
            case "read": tool.kind = .read
            case "edit", "delete", "move": tool.kind = .edit; tool.write = true
            case "search", "fetch": tool.kind = .search
            case "execute": tool.kind = command.map { TranscriptParser.classifyBash($0).0 } ?? .build
            default: break
            }
        }
        if let command {
            let (_, word, target) = TranscriptParser.classifyBash(command)
            tool.title = [word, target].filter { !$0.isEmpty }.joined(separator: " ")
        } else if let title = update["title"] as? String, !title.isEmpty, tool.title.isEmpty || known != nil {
            tool.title = title
        }
        if let path { tool.path = path }
        if let status = update["status"] as? String, status == "completed" || status == "failed" { tool.done = true }
        return tool
    }

    /// 承認の問いを、どのエージェントでも同じ承認の依頼に直す
    nonisolated static func approval(_ id: String, session: String, params: [String: Any]) -> Approval {
        let call = params["toolCall"] as? [String: Any] ?? [:]
        let raw = call["rawInput"] ?? [String: Any]()
        let input = (try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let title = (call["title"] as? String) ?? "道具"
        return Approval(id: id, session: session, tool: (call["kind"] as? String) ?? title, detail: title, input: input,
                        canRevise: false)
    }

    /// 選ぶ選択肢。許可も却下も「一度きり」を先に探す
    nonisolated static func option(_ options: [[String: Any]], allow: Bool) -> String? {
        let prefix = allow ? "allow" : "reject"
        let once = options.first { $0["kind"] as? String == "\(prefix)_once" }
        let any = options.first { ($0["kind"] as? String)?.hasPrefix(prefix) == true }
        return (once ?? any)?["optionId"] as? String
    }
}
