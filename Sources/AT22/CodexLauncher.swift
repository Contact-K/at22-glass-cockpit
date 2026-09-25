import Foundation

// MARK: - OpenAI Codex CLI の起動

/// codex CLI を非対話モードで起こす。1ターン1プロセスで立ち上げ、resume で継続する。
/// transcript は ~/.claude に出ず、codex が所有する別チャネルに記録される。
enum CodexLauncher {

    /// 起こす時に決まるもの
    struct Config {
        var cwd: String
        var level: Gate.Level
        var prompt: String
        var model: String
    }

    /// 承認レベルに応じた sandbox フラグを生成。Launcher と同様に Gate.Level で分岐する
    nonisolated static func sandboxArguments(for level: Gate.Level) -> [String] {
        switch level {
        case .plan:
            ["--sandbox", "read-only"]
        case .each, .normal:
            ["--sandbox", "workspace-write"]
        case .auto, .unattended:
            ["--dangerously-bypass-approvals-and-sandbox"]
        }
    }

    /// `codex exec -` への argv を組む。stdin からプロンプトを読むので `-` を置く。
    /// 理由は Launcher と同じ——最初の指示も割り込みと同じ経路にしておくため。
    /// （この実装では割り込みの仕組みは持たないが、設計は統一）
    nonisolated static func launchArguments(config: Config) -> [String] {
        var out = ["exec", "-", "--json", "-m", config.model, "-C", config.cwd]
        out.append(contentsOf: sandboxArguments(for: config.level))
        out.append("--skip-git-repo-check")
        return out
    }

    /// `codex exec resume <THREAD_ID> "<prompt>"` への argv を組む。
    /// prompt は argv 経由で、stdin は使わない。
    ///
    /// **`exec resume` は `-C` も `--sandbox` も受け付けない**（codex 0.146 で実測、
    /// `unexpected argument '-C'` で即落ちて2ターン目以降が1度も通らなかった）。
    /// 作業場所は `resume()` がプロセスの cwd に置き、sandbox は設定の上書き `-c` で渡す
    nonisolated static func resumeArguments(threadID: String, prompt: String, config: Config) -> [String] {
        var out = ["exec", "resume", threadID, prompt, "--json", "-m", config.model]
        let sandbox = sandboxArguments(for: config.level)
        out.append(contentsOf: sandbox.first == "--sandbox" ? ["-c", "sandbox_mode=\"\(sandbox[1])\""] : sandbox)
        out.append("--skip-git-repo-check")
        return out
    }

    /// codex が流す JSONL イベント。Launcher の StreamEvent とは別設計——
    /// codex は独自の item 型を持つため、型の体系が異なる
    enum Event: Sendable {
        /// セッション開始。thread_id でセッションを指し示す
        case threadStarted(id: String)
        /// エージェントメッセージ
        case agentMessage(String)
        /// 推論テキスト
        case reasoning(String)
        /// コマンド実行完了（起動と完了をまとめて拾う）
        case commandRun(command: String, exitCode: Int?)
        /// ファイル変更一覧
        case fileChanged(paths: [String])
        /// ターン正常終了。token 数を返す
        case turnEnded(inputTokens: Int, outputTokens: Int)
        /// ターン失敗
        case turnFailed(String)
        /// API エラーなど
        case error(String)
    }

    /// stdout の1行を JSON パース。知らない型は nil で返す
    nonisolated static func parseStreamLine(_ data: Data) -> Event? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let type = dict["type"] as? String else { return nil }

        switch type {
        case "thread.started":
            if let threadID = dict["thread_id"] as? String {
                return .threadStarted(id: threadID)
            }
            return nil

        case "item.completed":
            if let item = dict["item"] as? [String: Any] {
                let itemType = item["type"] as? String ?? ""

                switch itemType {
                case "agent_message":
                    if let text = item["text"] as? String {
                        return .agentMessage(text)
                    }
                case "reasoning":
                    if let text = item["text"] as? String {
                        return .reasoning(text)
                    }
                case "command_execution":
                    if let command = item["command"] as? String {
                        let exitCode = item["exit_code"] as? Int
                        return .commandRun(command: command, exitCode: exitCode)
                    }
                case "file_change":
                    if let changes = item["changes"] as? [[String: Any]] {
                        let paths = changes.compactMap { $0["path"] as? String }
                        return .fileChanged(paths: paths)
                    }
                default:
                    return nil
                }
            }
            return nil

        case "turn.completed":
            let usage = dict["usage"] as? [String: Any] ?? [:]
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            return .turnEnded(inputTokens: inputTokens, outputTokens: outputTokens)

        case "turn.failed":
            if let error = dict["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .turnFailed(message)
            }
            return nil

        case "error":
            if let message = dict["message"] as? String {
                return .error(message)
            }
            return nil

        default:
            return nil
        }
    }

    /// codex を探した結果。claude と同じ形（PATH も一緒に持ち帰る）
    typealias Found = Launcher.Found

    /// `codex` を探す。探し方は claude と同じ——ログインシェルに訊き、無ければ既定の置き場を見る
    nonisolated static func find(override: String?) -> Found? {
        Launcher.locate(override: override, command: "codex")
    }

    // MARK: - 起こす

    /// 起こした結果
    struct Started {
        let process: Process
    }

    /// codex を起こす。stdin にプロンプトを流して閉じる
    nonisolated static func launch(_ config: Config, using found: Found,
                                   onExit: (@Sendable (Int32, String) -> Void)? = nil,
                                   onStream: (@Sendable (Event) -> Void)? = nil) -> Started? {
        guard let (process, input) = try? Launcher.spawn(
            found.executable, arguments: launchArguments(config: config), cwd: config.cwd, path: found.path,
            onLine: { line in if let event = parseStreamLine(line) { onStream?(event) } },
            onExit: onExit) else { return nil }
        if let line = messageLine(config.prompt) { try? input.write(contentsOf: line) }
        try? input.close()
        return Started(process: process)
    }

    /// codex を resume する。prompt は argv 経由なので stdin はすぐ閉じる
    nonisolated static func resume(threadID: String, prompt: String, config: Config,
                                   using found: Found,
                                   onExit: (@Sendable (Int32, String) -> Void)? = nil,
                                   onStream: (@Sendable (Event) -> Void)? = nil) -> Started? {
        guard let (process, input) = try? Launcher.spawn(
            found.executable, arguments: resumeArguments(threadID: threadID, prompt: prompt, config: config),
            cwd: config.cwd, path: found.path,
            onLine: { line in if let event = parseStreamLine(line) { onStream?(event) } },
            onExit: onExit) else { return nil }
        try? input.close()
        return Started(process: process)
    }

    /// stdin に流す1行。Launcher と同形
    private nonisolated static func messageLine(_ text: String) -> Data? {
        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)
        return data
    }
}
