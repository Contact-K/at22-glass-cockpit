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
    /// prompt は argv 経由で、stdin は使わない
    nonisolated static func resumeArguments(threadID: String, prompt: String, config: Config) -> [String] {
        var out = ["exec", "resume", threadID, prompt, "--json", "-m", config.model, "-C", config.cwd]
        out.append(contentsOf: sandboxArguments(for: config.level))
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

    /// codex を探した結果。PATH も一緒に持ち帰る
    struct Found: Sendable {
        let executable: URL
        let path: String?
    }

    /// `codex` バイナリを探す。Launcher.locate の流儀をそのまま踏襲。
    /// GUI の PATH は限定的なので、ログインシェルに訊く
    nonisolated static func find(override: String?) -> Found? {
        let shell = askLoginShell()

        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return isExecutable(url) ? Found(executable: url, path: shell.path) : nil
        }
        if let executable = shell.executable { return Found(executable: executable, path: shell.path) }

        let home = NSHomeDirectory()
        for candidate in ["\(home)/.local/bin/codex",
                          "\(home)/.codex/local/codex",
                          "/opt/homebrew/bin/codex",
                          "/usr/local/bin/codex"] {
            let url = URL(fileURLWithPath: candidate)
            if isExecutable(url) { return Found(executable: url, path: shell.path) }
        }
        return nil
    }

    /// `command -v codex` と `$PATH` を1回のログインシェルで取る。
    nonisolated static func askLoginShell() -> (executable: URL?, path: String?) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard isExecutable(URL(fileURLWithPath: shell)) else { return (nil, nil) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        task.arguments = ["-l", "-c", "command -v codex; printf '\\n%s' \"$PATH\""]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return (nil, nil) }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parseShellReply(String(data: data, encoding: .utf8) ?? "")
    }

    /// シェルの返事を分ける
    nonisolated static func parseShellReply(_ reply: String) -> (executable: URL?, path: String?) {
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let first = lines.first ?? ""
        let url = URL(fileURLWithPath: first)
        let path = lines.dropFirst().first(where: { !$0.isEmpty })
        return (first.isEmpty || !isExecutable(url) ? nil : url, path)
    }

    private nonisolated static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    // MARK: - バッファ管理

    /// stdout / stderr バッファ。Launcher の StreamBuffer と同等。
    /// 別スレッドの readabilityHandler から安全に捕捉・追記できるよう NSLock で直列化
    final class StreamBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private let maxTailBytes: Int?

        init(maxTailBytes: Int? = nil) {
            self.maxTailBytes = maxTailBytes
        }

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)

            if let max = maxTailBytes, buffer.count > max {
                buffer.removeFirst(buffer.count - max)
            }
        }

        func takeCompleteLines() -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            let (lines, remaining) = Self.extractLines(from: buffer)
            buffer = remaining
            return lines
        }

        func takeRest() -> Data {
            lock.lock()
            defer { lock.unlock() }
            let rest = buffer
            buffer = Data()
            return rest
        }

        nonisolated static func extractLines(from buffer: Data) -> (lines: [Data], remaining: Data) {
            var lines: [Data] = []
            var remaining = buffer

            while let newlineIndex = remaining.firstIndex(of: 0x0A) {
                lines.append(remaining.subdata(in: remaining.startIndex..<newlineIndex))
                remaining.removeFirst(newlineIndex + 1 - remaining.startIndex)
            }

            return (lines, remaining)
        }
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
        let task = Process()
        task.executableURL = found.executable
        task.arguments = launchArguments(config: config)
        task.currentDirectoryURL = URL(fileURLWithPath: config.cwd)
        if let path = found.path {
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = path
            task.environment = env
        }

        let output = Pipe()
        let outBuffer = StreamBuffer()
        let outQueue = DispatchQueue(label: "at22.codex.stdout", qos: .utility)

        let errors = Pipe()
        let errBuffer = StreamBuffer(maxTailBytes: 8 * 1024)

        let stdin = Pipe()
        task.standardInput = stdin
        task.standardOutput = output
        task.standardError = errors

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            outQueue.async {
                outBuffer.append(data)

                for lineData in outBuffer.takeCompleteLines() {
                    if let event = CodexLauncher.parseStreamLine(lineData) {
                        onStream?(event)
                    }
                }
            }
        }

        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            outQueue.async {
                errBuffer.append(data)
            }
        }

        if let onExit {
            task.terminationHandler = { finished in
                outQueue.sync {
                    let restData = outBuffer.takeRest()
                    if !restData.isEmpty, let event = CodexLauncher.parseStreamLine(restData) {
                        onStream?(event)
                    }
                    let text = String(data: errBuffer.takeRest(), encoding: .utf8) ?? ""
                    onExit(finished.terminationStatus, text)
                }

                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                task.terminationHandler = nil
            }
        }

        guard (try? task.run()) != nil else { return nil }

        let input = stdin.fileHandleForWriting
        if let line = messageLine(config.prompt) { try? input.write(contentsOf: line) }
        try? input.close()

        return Started(process: task)
    }

    /// codex を resume する。stdin は使わない（prompt は argv 経由）
    nonisolated static func resume(threadID: String, prompt: String, config: Config,
                                   using found: Found,
                                   onExit: (@Sendable (Int32, String) -> Void)? = nil,
                                   onStream: (@Sendable (Event) -> Void)? = nil) -> Started? {
        let task = Process()
        task.executableURL = found.executable
        task.arguments = resumeArguments(threadID: threadID, prompt: prompt, config: config)
        task.currentDirectoryURL = URL(fileURLWithPath: config.cwd)
        if let path = found.path {
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = path
            task.environment = env
        }

        let output = Pipe()
        let outBuffer = StreamBuffer()
        let outQueue = DispatchQueue(label: "at22.codex.stdout", qos: .utility)

        let errors = Pipe()
        let errBuffer = StreamBuffer(maxTailBytes: 8 * 1024)

        task.standardOutput = output
        task.standardError = errors

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            outQueue.async {
                outBuffer.append(data)

                for lineData in outBuffer.takeCompleteLines() {
                    if let event = CodexLauncher.parseStreamLine(lineData) {
                        onStream?(event)
                    }
                }
            }
        }

        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            outQueue.async {
                errBuffer.append(data)
            }
        }

        if let onExit {
            task.terminationHandler = { finished in
                outQueue.sync {
                    let restData = outBuffer.takeRest()
                    if !restData.isEmpty, let event = CodexLauncher.parseStreamLine(restData) {
                        onStream?(event)
                    }
                    let text = String(data: errBuffer.takeRest(), encoding: .utf8) ?? ""
                    onExit(finished.terminationStatus, text)
                }

                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                task.terminationHandler = nil
            }
        }

        guard (try? task.run()) != nil else { return nil }

        return Started(process: task)
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
