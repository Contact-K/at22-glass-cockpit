import Foundation

// MARK: - エージェントとの接続

/// どのエージェントから来ても同じ形の出来事。Cockpit はこれだけを見る。
///
/// Claude は transcript が正（確定した発言・道具・触ったファイルは `TranscriptWatcher` が拾う）なので、
/// ここに来るのは書きかけ・ターンの区切り・承認・割り込みの受領だけ。
/// AT22 が transcript を読まない Codex / ACP は、確定した発言と道具もここで運ぶ
enum AgentEvent: Equatable, Sendable {
    /// 相手側の ID が決まった（Codex の thread、ACP の sessionId）。続きに繋ぐ時に使う
    case ready(remoteID: String)
    /// 書きかけ。ターン終了で消える
    case partial(String)
    /// 確定した発言
    case message(String, thinking: Bool)
    /// 人の発言。繋ぎ直した時に相手が送り直す履歴（ACP の session/load）でだけ来る
    case said(String)
    /// 道具の呼び出し。`path` があればファイルの触りとして盤面に出す。
    /// `done` が偽の間は触っている最中（ACP は開始と完了が別々に来る。Codex は完了だけ）
    case tool(id: String, kind: WorkKind, title: String, path: String?, write: Bool, done: Bool)
    /// 人の返事を待つ依頼
    case approval(Approval)
    case turnEnded(tokens: Int?)
    case turnFailed(String)
    case interruptAcknowledged(requestID: String, stillQueued: Int, cancelled: Int)
    case error(String)
}

/// 承認の依頼。**答えるのは人のクリックだけ**
struct Approval: Identifiable, Equatable, Sendable {
    /// 返事に添える ID（Claude の request_id / ACP の JSON-RPC id）
    let id: String
    let session: String
    /// 道具の名前（Bash / Edit …）
    let tool: String
    /// 人が読む1行（何をしようとしているか）
    let detail: String
    /// 道具への入力（JSON）。書き換えてから許可すると、書き換えた方が実行される（Claude で実測）
    let input: String
    /// 届いた時刻。待たせている長さをパネルに出す（相手は答えるまで本当に止まっている）
    var at = Date()
    /// 入力を書き換えて許可できるか。ACP には書き換えの口が無い
    var canRevise = true
}

/// 接続の共通の形。実装は Claude（stream-json）・Codex（exec / resume）・ACP の3つ。
/// Cockpit は相手が誰かを見ずに、送る・止める・答える・閉じるだけを行う
@MainActor
protocol AgentConnection: AnyObject {
    /// 次の言葉を受けられるか。Codex は1ターン1プロセスなので、走っている間は受けない
    var acceptsInput: Bool { get }
    /// 1件送る。相手が終わっていたら false
    func send(_ text: String) -> Bool
    /// 今のターンだけ止める。受領確認と照合する ID を返す（照合しない相手は空文字）。
    /// 止められなければ nil
    func interrupt() -> String?
    /// 承認に答える。`input` を渡すと書き換えた入力で許可する。
    /// **送れなかったら false**——黙って消すと、相手は答えを待ったまま止まり続ける
    func answer(_ approval: Approval, allow: Bool, input: String?) -> Bool
    /// 閉じる。以後は送れない（走っているターンは相手に任せる）
    func close()
}

// MARK: - Claude Code（stream-json）

/// `claude -p --input-format stream-json` の1本。**stdin を開けたまま持つ**のが要点で、
/// 閉じるとセッションが終わり、割り込みも続きの言葉も通らなくなる
@MainActor
final class ClaudeConnection: AgentConnection {
    let process: Process
    private let input: FileHandle

    private init(started: Launcher.Started) {
        process = started.process
        input = started.input
    }

    /// 起こす。`resuming` を渡すと、新しく採番せずにそのセッションの続きへ繋ぐ
    static func start(_ config: Launcher.Config, using found: Launcher.Found,
                      session: String, sessionID: UUID = UUID(), resuming: String? = nil,
                      onEvent: @escaping @Sendable (AgentEvent) -> Void,
                      onExit: @escaping @Sendable (Int32, String) -> Void) throws -> ClaudeConnection {
        let started = try Launcher.launch(config, using: found, sessionID: sessionID, resuming: resuming,
                                          onExit: onExit,
                                          onStream: { event in
                                              if let mapped = agentEvent(event, session: session) { onEvent(mapped) }
                                          })
        return ClaudeConnection(started: started)
    }

    var acceptsInput: Bool { true }
    func send(_ text: String) -> Bool { Launcher.send(text, to: input) }
    func interrupt() -> String? { Launcher.interrupt(input) }

    func answer(_ approval: Approval, allow: Bool, input edited: String?) -> Bool {
        // 書き換えた入力が JSON として読めなければ送らない（何が走るか分からないまま許可しない）
        guard let line = Launcher.permissionLine(requestID: approval.id, allow: allow,
                                                 input: edited ?? approval.input) else { return false }
        return (try? input.write(contentsOf: line)) != nil
    }

    func close() { try? input.close() }

    /// stdout の出来事を共通の形へ。立ち上がり・ターンの途中経過は Cockpit が要らないので落とす
    nonisolated static func agentEvent(_ event: Launcher.StreamEvent, session: String) -> AgentEvent? {
        switch event {
        case let .partialText(text): .partial(text)
        case .turnEnded: .turnEnded(tokens: nil)
        case let .turnFailed(reason): .turnFailed(reason)
        case let .interruptAcknowledged(id, stillQueued, cancelled):
            .interruptAcknowledged(requestID: id, stillQueued: stillQueued, cancelled: cancelled)
        case let .error(message): .error(message)
        case let .permissionRequest(requestID, tool, detail, input):
            .approval(Approval(id: requestID, session: session, tool: tool, detail: detail, input: input))
        case .turnProgressed, .initialized: nil
        }
    }
}

// MARK: - Codex（exec / resume）

/// `codex exec` を1ターン1プロセスで回す。thread ID で続きに繋ぐ。
/// ponytail: 割り込みはプロセスを落とすだけ、承認の口も無い。app-server へ移す時（P7）に両方入る
@MainActor
final class CodexConnection: AgentConnection {
    private let found: CodexLauncher.Found
    private let config: CodexLauncher.Config
    private(set) var threadID: String?
    private var process: Process?
    /// ターンを回している間は真。**ターン終了の出来事か、プロセスの終了の早い方で**受け付けに戻す——
    /// codex は失敗の後も記憶の書き出しや MCP の後始末で数十秒居残る（実測）。
    /// 終了だけを待っていた版では、その間ずっと次を送れなかった
    private var turnOpen = false
    /// 今のターンの印。居残った前のターンのプロセスが、次のターンの状態を触らないため
    private var turn = UUID()
    /// 人が止めたターン。落としたプロセスの終了を失敗として出さないため
    private var stoppedByUser = false
    private let onEvent: @Sendable (AgentEvent) -> Void

    init(found: CodexLauncher.Found, config: CodexLauncher.Config, threadID: String?,
         onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        self.found = found
        self.config = config
        self.threadID = threadID
        self.onEvent = onEvent
    }

    var acceptsInput: Bool { !turnOpen }

    func send(_ text: String) -> Bool {
        guard !turnOpen else { return false }
        var turnConfig = config
        turnConfig.prompt = text
        stoppedByUser = false
        let mine = UUID()
        turn = mine
        let forward = onEvent
        let onStream: @Sendable (CodexLauncher.Event) -> Void = { [weak self] event in
            if case let .threadStarted(id) = event {
                Task { @MainActor in self?.threadID = id }
            }
            let mapped = Self.agentEvents(event)
            for event in mapped { forward(event) }
            if mapped.contains(where: Self.closesTurn) {
                Task { @MainActor in if self?.turn == mine { self?.turnOpen = false } }
            }
        }
        // ターン終了の出来事が来ないまま落ちることもあるので、終了でも必ず閉じる。
        // 以前は終了を拾っておらず、落ちると処理中のまま固まって以後何も送れなかった
        let onExit: @Sendable (Int32, String) -> Void = { [weak self] status, errors in
            Task { @MainActor in
                guard let self, self.turn == mine else { return }
                self.process = nil
                guard self.turnOpen else { return }     // ターンはもう閉じている（居残っていただけ）
                self.turnOpen = false
                if self.stoppedByUser || status == 0 {
                    forward(.turnEnded(tokens: nil))
                } else {
                    forward(.turnFailed(errors.isEmpty ? "codex が終了コード \(status) で終わった" : errors))
                }
            }
        }
        let started = threadID.map {
            CodexLauncher.resume(threadID: $0, prompt: text, config: turnConfig, using: found,
                                 onExit: onExit, onStream: onStream)
        } ?? CodexLauncher.launch(turnConfig, using: found, onExit: onExit, onStream: onStream)
        process = started?.process
        turnOpen = started != nil
        return started != nil
    }

    func interrupt() -> String? {
        guard turnOpen, let process else { return nil }
        stoppedByUser = true
        process.terminate()
        return ""
    }

    nonisolated static func closesTurn(_ event: AgentEvent) -> Bool {
        switch event {
        case .turnEnded, .turnFailed: true
        default: false
        }
    }

    func answer(_ approval: Approval, allow: Bool, input: String?) -> Bool { false }
    func close() {}

    /// codex の JSONL イベントを共通の形へ。ファイル変更は1件ずつ触りとして出す
    nonisolated static func agentEvents(_ event: CodexLauncher.Event) -> [AgentEvent] {
        switch event {
        case let .threadStarted(id): return [.ready(remoteID: id)]
        case let .agentMessage(text): return [.message(text, thinking: false)]
        case let .reasoning(text): return [.message(text, thinking: true)]
        case let .commandRun(command, _):
            let (kind, word, target) = TranscriptParser.classifyBash(command)
            let title = [word, target].filter { !$0.isEmpty }.joined(separator: " ")
            return [.tool(id: UUID().uuidString, kind: kind, title: title.isEmpty ? command : title,
                          path: nil, write: false, done: true)]
        case let .fileChanged(paths):
            return paths.map { .tool(id: UUID().uuidString, kind: .edit,
                                     title: ($0 as NSString).lastPathComponent, path: $0, write: true,
                                     done: true) }
        case let .turnEnded(inputTokens, _): return [.turnEnded(tokens: inputTokens)]
        case let .turnFailed(message): return [.turnFailed(message)]
        case let .error(message): return [.error(message)]
        }
    }
}
