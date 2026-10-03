import Foundation

// MARK: - Codex（app-server）

/// `codex app-server` の1本（stdio の JSON-RPC、1行1メッセージ）。`codex exec` の1ターン1プロセスと違い、
/// **繋いだまま**送れて、止められて（`turn/interrupt`）、承認を人に訊ける（`item/*/requestApproval`）。
/// 形は openai/codex の `codex-rs/app-server-protocol`（v2）と Orca の実装に合わせた。
/// `"jsonrpc":"2.0"` は付けない——app-server は送らないし、来ることも期待しない
///
/// ponytail: codex が手元に無いまま書いた。形は p0 で固定してあるが、本物との通しは未確認
@MainActor
final class CodexServerConnection: AgentConnection {
    private let process: Process
    private let input: FileHandle
    private let session: String
    private let cwd: String
    private let model: String
    private let effort: String
    private let level: Gate.Level
    private let resume: String?
    private let onEvent: @Sendable (AgentEvent) -> Void

    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    private(set) var threadID: String?
    private var turnID: String?
    private var turnOpen = false
    private var queued: [String] = []
    private var reply = ""
    private var tokens: Int?
    /// 答え待ちの承認（AT22 の鍵 → 相手の id）
    private var asks: [String: Any] = [:]
    /// 道具の項目（itemId → ファイルの変更のパス）。承認の板にパスを出すため
    private var changes: [String: [String]] = [:]

    enum Pending { case initialize, open, turn, other }

    private init(process: Process, input: FileHandle, session: String, cwd: String, model: String, effort: String,
                 level: Gate.Level, resume: String?, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        self.process = process
        self.input = input
        self.session = session
        self.cwd = cwd
        self.model = model
        self.effort = effort
        self.level = level
        self.resume = resume
        self.onEvent = onEvent
    }

    static func start(_ executable: URL, path: String?, cwd: String, session: String, model: String, effort: String,
                      level: Gate.Level, resume: String?,
                      onEvent: @escaping @Sendable (AgentEvent) -> Void,
                      onExit: @escaping @Sendable (Int32, String) -> Void) throws -> CodexServerConnection {
        let box = Box()
        let (process, input) = try Launcher.spawn(
            executable, arguments: ["app-server"], cwd: cwd, path: path,
            onLine: { line in Task { @MainActor in box.connection?.receive(line) } },
            onExit: onExit)
        let connection = CodexServerConnection(process: process, input: input, session: session, cwd: cwd, model: model,
                                               effort: effort, level: level, resume: resume, onEvent: onEvent)
        box.connection = connection
        connection.call(.initialize, "initialize", [
            "clientInfo": ["name": "at22", "title": "AT22", "version": "0.2"],
            "capabilities": ["experimentalApi": true],
        ])
        return connection
    }

    @MainActor private final class Box { weak var connection: CodexServerConnection? }

    // MARK: 段 → codex の承認とサンドボックス（`codex exec` の時と同じ対応）

    nonisolated static func policy(_ level: Gate.Level) -> (approval: String, sandbox: String) {
        switch level {
        case .plan: ("on-request", "read-only")
        case .each: ("untrusted", "workspace-write")
        case .normal: ("on-request", "workspace-write")
        case .auto, .unattended: ("never", "danger-full-access")
        }
    }

    // MARK: 送る

    var acceptsInput: Bool { !turnOpen && queued.isEmpty }

    func send(_ text: String) -> Bool {
        guard acceptsInput else { return false }
        guard threadID != nil else { queued.append(text); return true }
        return startTurn(text)
    }

    @discardableResult
    private func startTurn(_ text: String) -> Bool {
        guard let threadID else { return false }
        turnOpen = true
        reply = ""
        var params: [String: Any] = ["threadId": threadID, "input": [["type": "text", "text": text]]]
        if !effort.isEmpty { params["effort"] = effort }
        return call(.turn, "turn/start", params)
    }

    func interrupt() -> String? {
        guard turnOpen, let threadID, let turnID else { return nil }
        return call(.other, "turn/interrupt", ["threadId": threadID, "turnId": turnID]) ? "" : nil
    }

    func answer(_ approval: Approval, allow: Bool, input: String?) -> Bool {
        guard let id = asks.removeValue(forKey: approval.id) else { return false }
        // 一度きり（accept）を選ぶ。「この会話の間ずっと」を AT22 が勝手に選ぶと、人が知らないまま次から通る
        return write(["id": id, "result": ["decision": allow ? "accept" : "decline"]])
    }

    func close() {
        try? input.close()
        process.terminate()
    }

    @discardableResult
    private func call(_ kind: Pending, _ method: String, _ params: [String: Any]) -> Bool {
        nextID += 1
        pending[nextID] = kind
        return write(["id": nextID, "method": method, "params": params])
    }

    @discardableResult
    private func write(_ object: [String: Any]) -> Bool {
        guard let line = Self.line(object) else { return false }
        return (try? input.write(contentsOf: line)) != nil
    }

    nonisolated static func line(_ object: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        data.append(0x0A)
        return data
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
            for event in Self.events(method: method, params: params, changes: &changes, reply: &reply, tokens: &tokens) {
                if case .turnEnded = event { turnOpen = false; turnID = nil }
                if case .turnFailed = event { turnOpen = false; turnID = nil }
                onEvent(event)
            }
            if method == "turn/started", let id = (params["turn"] as? [String: Any])?["id"] as? String { turnID = id }
        case nil:
            break
        }
    }

    private func answered(_ kind: Pending, result: [String: Any], error: String?) {
        switch kind {
        case .initialize:
            if let error { return onEvent(.turnFailed("codex に繋げなかった: \(error)")) }
            write(["method": "initialized"])
            let policy = Self.policy(level)
            var params: [String: Any] = ["cwd": cwd, "approvalPolicy": policy.approval, "sandbox": policy.sandbox]
            if let resume {
                // 続きの時はモデルを渡さない（渡すと保存済みのモデル・エフォートが無視される・Orca の実測）
                params["threadId"] = resume
                call(.open, "thread/resume", params)
            } else {
                if !model.isEmpty { params["model"] = model }
                call(.open, "thread/start", params)
            }
        case .open:
            if let error { return onEvent(.turnFailed("スレッドを開けなかった: \(error)")) }
            guard let id = (result["thread"] as? [String: Any])?["id"] as? String ?? resume else {
                return onEvent(.turnFailed("codex がスレッドIDを返さなかった"))
            }
            threadID = id
            onEvent(.ready(remoteID: id))
            if !queued.isEmpty { startTurn(queued.removeFirst()) }
        case .turn:
            if let error {
                turnOpen = false
                return onEvent(.turnFailed(error))
            }
            if let id = (result["turn"] as? [String: Any])?["id"] as? String { turnID = id }
        case .other:
            if let error { onEvent(.error(error)) }
        }
    }

    private func asked(id: Any, method: String, params: [String: Any]) {
        if let approval = Self.approval(method: method, params: params, key: "\(id)", session: session, changes: changes) {
            asks["\(id)"] = id
            onEvent(.approval(approval))
            return
        }
        // 旧形式の承認は断る（Orca と同じ）。知らない問いにも答える——答えないと相手はそこで待ち続ける
        if method == "execCommandApproval" || method == "applyPatchApproval" {
            write(["id": id, "result": ["decision": "abort"]])
        } else {
            write(["id": id, "error": ["code": -32601, "message": "AT22 はこの問いに答えない"]])
        }
    }

    // MARK: 純関数（p0 で形を固定する）

    /// 知らせを AT22 の出来事へ。`reply` は書きかけ、`changes` は itemId → パス、`tokens` は直近の文脈の大きさ
    nonisolated static func events(method: String, params: [String: Any], changes: inout [String: [String]],
                                   reply: inout String, tokens: inout Int?) -> [AgentEvent] {
        switch method {
        case "item/agentMessage/delta":
            // `.partial` は Cockpit が足し込むので、差分だけを渡す
            let delta = params["delta"] as? String ?? ""
            reply += delta
            return delta.isEmpty ? [] : [.partial(delta)]
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any], let type = item["type"] as? String else { return [] }
            let id = item["id"] as? String ?? UUID().uuidString
            let done = method == "item/completed"
            switch type {
            case "agentMessage":
                guard done, let text = item["text"] as? String, !text.isEmpty else { return [] }
                reply = ""
                return [.message(text, thinking: false)]
            case "commandExecution":
                let command = item["command"] as? String ?? ""
                return [.tool(id: id, kind: TranscriptParser.classifyBash(command).0, title: command,
                              path: nil, write: false, done: done)]
            case "fileChange":
                let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                changes[id] = paths
                return paths.map { .tool(id: id + ":" + $0, kind: .edit, title: ($0 as NSString).lastPathComponent,
                                         path: $0, write: true, done: done) }
            default:
                return []
            }
        case "thread/tokenUsage/updated":
            let last = (params["tokenUsage"] as? [String: Any])?["last"] as? [String: Any]
            if let input = last?["inputTokens"] as? Int { tokens = input }
            return []
        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            let status = turn["status"] as? String ?? "completed"
            if status == "failed" {
                let message = (turn["error"] as? [String: Any])?["message"] as? String ?? "codex のターンが失敗した"
                return [.turnFailed(message)]
            }
            return [.turnEnded(tokens: tokens)]
        case "error":
            guard (params["willRetry"] as? Bool) != true else { return [] }
            let message = (params["error"] as? [String: Any])?["message"] as? String ?? "codex のエラー"
            return [.error(message)]
        default:
            return []
        }
    }

    /// 承認の問いを AT22 の承認へ。知らない問いは nil
    nonisolated static func approval(method: String, params: [String: Any], key: String, session: String,
                                     changes: [String: [String]]) -> Approval? {
        let input = (try? JSONSerialization.data(withJSONObject: params, options: [.withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        switch method {
        case "item/commandExecution/requestApproval":
            let command = params["command"] as? String ?? (params["reason"] as? String ?? "コマンド")
            return Approval(id: key, session: session, tool: "Bash", detail: command, input: input, canRevise: false)
        case "item/fileChange/requestApproval":
            let paths = changes[params["itemId"] as? String ?? ""] ?? []
            let detail = paths.isEmpty ? (params["reason"] as? String ?? "ファイルの変更")
                : paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return Approval(id: key, session: session, tool: "Edit", detail: detail, input: input, canRevise: false)
        default:
            return nil
        }
    }
}
