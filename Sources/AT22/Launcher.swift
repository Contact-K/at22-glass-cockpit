import Foundation

// MARK: - Claude Code の起動

/// AT22 から Claude Code のセッションを起こす。
///
/// **鍵を預からない**。認証は `claude` が既に持っているので AT22 は起こす側に回るだけで、
/// API キーも OAuth トークンも扱わない。OSS で配る以上これは好みではなく必然で、
/// 公開リポジトリに OAuth の client secret は置けない。
///
/// 引数の組み立て（`arguments`）だけを純関数として切り出してある。`Process` を起こす殻は
/// 自己チェックの外に置く——実機に `claude` が入っているかどうかに検査を依存させない
enum Launcher {

    /// stdout から拾う出来事。**String と Int だけの関連値なので Equatable を合成できる**。
    /// 読み手が明示を見て「合成可能な形」と判るようにするため、明記する。
    /// 役割の分担：
    ///
    /// **transcript**（既存）= **確定した過去**。メッセージ一覧・チップ・カードは全部これで作る。
    /// 他人が端末で回しているセッションにも効く唯一の経路なので、絶対に置き換えない。
    ///
    /// **stdout**（今回追加）= **今この瞬間だけ**。進行中の部分テキスト、ターンの開始と終了、
    /// 割り込みの受領、エラー。**確定メッセージは一切ここから作らない**。
    enum StreamEvent: Equatable {
        /// 部分テキスト。確定は transcript の担当。ここは「いま書いている途中」だけ
        case partialText(String)
        /// ターンが進んだ（assistant / result）
        case turnProgressed
        /// ターンが正常に終わった
        case turnEnded
        /// ターンが失敗して終わった。理由を載せる。司令塔に「失敗」を伝える
        case turnFailed(String)
        /// 割り込み（interrupt）を受領したことの確認。`request_id` と残件数を持ち帰る。
        /// 古い claude（v2.1.205 未満）は `response` が空オブジェクトで返り、その場合は
        /// stillQueued/cancelled とも 0 として扱う。それを「受領したが内訳は不明」と見なし、
        /// エラー扱いにはしない（新しい版が来るまで待つことの方が、誤報より害がない）
        case interruptAcknowledged(requestID: String, stillQueued: Int, cancelled: Int)
        /// API 再試行など。`message` に人間向けの文言を載せる
        case error(String)
        /// セッションが立ち上がった
        case initialized
    }

    /// 起こす時に決まるもの
    struct Config {
        var cwd: String
        var level: Gate.Level
        var prompt: String
        /// 触っていいツールの白名簿（構想ノートの権限レイヤーA）。空なら claude の既定に任せる
        var allowedTools: [String] = []
        /// Claude モデル選択（例: "opus", "sonnet", "haiku"）。空なら claude の既定に任せる
        var model: String = ""
    }

    /// stdout の1行を `StreamEvent` に変換する。知らない型は nil で返す
    nonisolated static func parseStreamLine(_ data: Data) -> StreamEvent? {
        // JSON をデコード。不正な形は黙って捨てる
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // サブエージェントのメッセージ。司令塔からのものと区別し、部分テキストとしては採用しない
        if let parentToolUseID = dict["parent_tool_use_id"] as? String, !parentToolUseID.isEmpty {
            return nil
        }

        // メインイベントの型を見る
        guard let type = dict["type"] as? String else { return nil }

        switch type {
        case "stream_event":
            // content_block_delta。部分テキスト
            if let eventDict = dict["event"] as? [String: Any],
               let eventType = eventDict["type"] as? String, eventType == "content_block_delta",
               let delta = eventDict["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String, deltaType == "text_delta",
               let text = delta["text"] as? String {
                return .partialText(text)
            }
            return nil

        case "assistant":
            // ターンが進んだ
            return .turnProgressed

        case "result":
            // 正常終了と異常終了を分ける。司令塔に誤報を流さないため。
            // ここを握り潰すと、認証失敗・上限超過・実行中エラーなど、理由が全部消える
            let isError = dict["is_error"] as? Bool ?? false
            let subtype = dict["subtype"] as? String ?? ""
            if isError || (subtype != "" && subtype != "success") {
                // 失敗。理由は result フィールド、無ければ subtype をそのまま
                let reason = (dict["result"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let message = reason.isEmpty ? subtype : reason
                return .turnFailed(message.isEmpty ? "ターン失敗" : message)
            }
            return .turnEnded

        case "control_response":
            // 割り込みの受領確認。request_id を確認し、止まりきったか見る。
            // 返事が来ないままだと司令塔は待ち続けるので、無視は許されない。
            //
            // 実測（v2.1.282）の形は `{"type":"control_response","response":{"subtype":"success",
            // "request_id":"R1","response":{"still_queued":[]}}}`。**request_id も内訳も `response` の内側**で、
            // 外側だけを見ていた間は受領を1度も拾えていなかった
            let outer = dict["response"] as? [String: Any] ?? [:]
            guard let requestID = outer["request_id"] as? String else { return nil }
            if outer["subtype"] as? String == "error" {
                return .error("割り込みが通らなかった: \(outer["error"] as? String ?? "")")
            }
            let body = outer["response"] as? [String: Any] ?? [:]
            let stillQueued = (body["still_queued"] as? [Any])?.count ?? 0
            let cancelled = (body["cancelled"] as? [Any])?.count ?? 0
            return .interruptAcknowledged(requestID: requestID, stillQueued: stillQueued, cancelled: cancelled)

        case "system":
            // システムイベント。subtype を見る
            if let subtype = dict["subtype"] as? String {
                switch subtype {
                case "init":
                    return .initialized
                case "api_retry":
                    // エラー情報を組み立てる
                    let attempt = dict["attempt"] as? Int ?? 0
                    let maxRetries = dict["max_retries"] as? Int ?? 0
                    let error = (dict["error"] as? String) ?? "API エラー"
                    let message = "\(error)（\(attempt)/\(maxRetries) 回目）"
                    return .error(message)
                default:
                    return nil
                }
            }
            return nil

        default:
            return nil
        }
    }

    /// 起こした結果。セッションIDは AT22 が採番したものをそのまま返す。
    /// `input` を開いたまま持っておくのが要点——**閉じるとセッションが終わり、割り込めなくなる**
    struct Started {
        let sessionID: UUID
        let process: Process
        let input: FileHandle
    }

    // MARK: 引数

    /// `claude` に渡す引数。
    ///
    /// **UUID を AT22 が採番する**のが要点。transcript は `<プロジェクト>/<この UUID>.jsonl` に
    /// 出るので、起こしたセッションを既存の読み取り経路でそのまま追える（解析を1行も足さない）。
    ///
    /// 端末を持たない GUI から起こすので対話UIは開けない。`-p` で走らせ、進み具合は
    /// stdout ではなく transcript から読む。
    ///
    /// **最初の指示も argv ではなく stdin から渡す**（`--input-format stream-json`）。
    /// argv に置くと1往復で stdin が閉じてセッションが終わり、後から割り込めない。
    /// 送る口を1本にしておけば、最初の指示も途中の割り込みも同じ経路になる。
    /// `--verbose` は claude 側の要求（`-p` ＋ `--output-format stream-json` に必須）
    nonisolated static func arguments(sessionID: UUID, config: Config) -> [String] {
        // transcript のファイル名は小文字。合わせておかないと起こした本人を見失う
        ["--session-id", sessionID.uuidString.lowercased()] + common(config)
    }

    /// **既にある transcript の続きに繋ぐ。** AT22 が起こしていないセッション——
    /// 端末で始めたものや履歴から開いたもの——に人間が言葉を送れるようにするための口。
    ///
    /// 送る側の配管（stdin を握る・stdout を読む）は起こす時とまったく同じで、
    /// 違うのは頭の2語だけ。`--resume` は `--session-id` と排他なので、両方は渡さない
    /// （渡すと claude が弾く）。同じ `<セッションID>.jsonl` の続きが書かれるので、
    /// 会話も盤面も既存の読み取り経路のまま繋がる
    nonisolated static func resumeArguments(sessionID: String, config: Config) -> [String] {
        ["--resume", sessionID.lowercased()] + common(config)
    }

    /// 起こす時と繋ぐ時で共通の並び。片方だけ直して食い違うのを避けるため1箇所にまとめる
    private nonisolated static func common(_ config: Config) -> [String] {
        var out = ["--permission-mode", config.level.permissionMode]
        if config.level.background { out.append("--bg") }
        if !config.model.isEmpty {
            out.append("--model")
            out.append(config.model)
        }
        if !config.allowedTools.isEmpty {
            out.append("--allowedTools")
            out.append(contentsOf: config.allowedTools)
        }
        // `--include-partial-messages` が無いと部分テキストが流れてこない。
        // stdout から進行状況を読むには必須
        out.append(contentsOf: ["-p", "--verbose",
                                "--input-format", "stream-json",
                                "--output-format", "stream-json",
                                "--include-partial-messages"])
        return out
    }

    /// stdin に流す1行。`{"type":"user","message":{"role":"user","content":[{"type":"text",…}]}}`。
    /// 実測でこの形が通ることを確かめてある
    nonisolated static func messageLine(_ text: String) -> Data? {
        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)   // 1行1メッセージ。改行が無いと相手が読み始めない
        return data
    }

    /// 進行中のターンを止める1行。**プロセスは殺さない**——
    /// SIGTERM で落とすとセッションごと終わってしまい、続きを送れなくなる。
    /// 種別のキーは **`subtype`**。`type` で送ると v2.1.282 は
    /// `Unsupported control request subtype: undefined` を返してターンを止めない（実測）
    nonisolated static func interruptLine(requestID: String = UUID().uuidString) -> Data? {
        let payload: [String: Any] = [
            "type": "control_request",
            "request_id": requestID,
            "request": ["subtype": "interrupt"],
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        data.append(0x0A)   // 1行1メッセージ。改行が無いと相手が読み始めない
        return data
    }

    // MARK: claude の在り処

    /// `claude` を探した結果。PATH も一緒に持ち帰る——npm 入れの `claude` は node を必要とし、
    /// GUI アプリの PATH には node も無いため、子に渡す PATH をここで確保しておく
    struct Found: Sendable {
        let executable: URL
        let path: String?
    }

    /// GUI アプリの `PATH` は `/usr/bin:/bin:/usr/sbin:/sbin` しか無く、
    /// `~/.local/bin` も `/opt/homebrew/bin` も入っていない。**素朴に `claude` を叩くと
    /// 手元では通って配布先で落ちる**ので、ログインシェルに1回訊いて実体を突き止める。
    ///
    /// ponytail: シェルの起動を待つだけで、時間制限は付けていない。壊れた rc ファイルで
    /// 帰ってこない場合はバックグラウンドの1本が留まり、起動UIが出ないまま終わる（画面は固まらない）。
    /// 実害が出たら `Process` に締め切りを付ける
    nonisolated static func locate(override: String?) -> Found? {
        // シェルの答えは実体と PATH の2つ。**実体が空でも PATH は使う**——
        // 実測で、GUI と同じ最小環境では `command -v claude` だけが空を返すことがある。
        // そこで諦めると npm 入れの claude（node を要る）を最小 PATH で起こして落ちる
        let shell = askLoginShell()

        if let override, !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return isExecutable(url) ? Found(executable: url, path: shell.path) : nil
        }
        if let executable = shell.executable { return Found(executable: executable, path: shell.path) }

        // シェルが実体を知らなかった時だけ。入れ方ごとの既定の置き場を順に見る
        let home = NSHomeDirectory()
        for candidate in ["\(home)/.local/bin/claude",
                          "\(home)/.claude/local/claude",
                          "/opt/homebrew/bin/claude",
                          "/usr/local/bin/claude"] {
            let url = URL(fileURLWithPath: candidate)
            if isExecutable(url) { return Found(executable: url, path: shell.path) }
        }
        return nil
    }

    /// `command -v claude` と `$PATH` を1回のログインシェルで両方取る。
    /// 別々に起こすと、シェルの初期化を2回待つことになる。
    /// **どちらか片方だけ取れることがある**ので、取れた分をそのまま返す
    nonisolated static func askLoginShell() -> (executable: URL?, path: String?) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard isExecutable(URL(fileURLWithPath: shell)) else { return (nil, nil) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: shell)
        // 1行目 = claude の場所（無ければ空行）、2行目 = PATH
        task.arguments = ["-l", "-c", "command -v claude; printf '\\n%s' \"$PATH\""]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return (nil, nil) }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return parseShellReply(String(data: data, encoding: .utf8) ?? "")
    }

    /// シェルの返事を分ける。`command -v` が空振りすると1行目が空になる
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

    /// stdout / stderr バッファ。別スレッドの readabilityHandler から安全に捕捉・追記できるよう、
    /// NSLock で直列化する。@unchecked Sendable は、内部を必ずロックで直列化しているため安全
    final class StreamBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private let maxTailBytes: Int?

        init(maxTailBytes: Int? = nil) {
            self.maxTailBytes = maxTailBytes
        }

        /// Data を足す。stderr の場合、末尾 N バイト以上は削除
        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)

            if let max = maxTailBytes, buffer.count > max {
                buffer.removeFirst(buffer.count - max)
            }
        }

        /// 改行で分かれた行を取り出す。未完了な末尾は buffer に残す
        func takeCompleteLines() -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            let (lines, remaining) = Self.extractLines(from: buffer)
            buffer = remaining
            return lines
        }

        /// 残っているバッファを全部返す（ハンドラ終了時用）
        func takeRest() -> Data {
            lock.lock()
            defer { lock.unlock() }
            let rest = buffer
            buffer = Data()
            return rest
        }

        /// 改行で分かれた完全な行を取り出す純粋な処理。Data バッファから、
        /// 完全な行の配列と末尾の未完了部分を返す。
        ///
        /// **`private` にしない。** 1行が分割して届く／改行が末尾に無い、といった取りこぼしは
        /// 画面上は「たまに発言が抜ける」としか見えず、司令塔との窓口では致命的になる。
        /// 検査から直に叩けるようにしておく（`Launcher.swift` は p0 のコンパイル対象）
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

    // MARK: 起こす

    /// 実際に起こす。**採番した UUID を返すことが仕事の半分**——これが無いと、
    /// 起こしたセッションと画面に出ているセッションを結びつけられない
    /// - Parameter resuming: 既にあるセッションIDを渡すと、新しく採番せずその続きに繋ぐ。
    ///   配管は同じで、渡すのは `--session-id` ではなく `--resume` になる
    @discardableResult
    nonisolated static func launch(_ config: Config, using found: Found,
                                   sessionID: UUID = UUID(),
                                   resuming: String? = nil,
                                   onExit: (@Sendable (Int32, String) -> Void)? = nil,
                                   onStream: (@Sendable (StreamEvent) -> Void)? = nil) throws -> Started {
        let task = Process()
        task.executableURL = found.executable
        task.arguments = resuming.map { resumeArguments(sessionID: $0, config: config) }
                      ?? arguments(sessionID: sessionID, config: config)
        task.currentDirectoryURL = URL(fileURLWithPath: config.cwd)
        if let path = found.path {
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = path
            task.environment = env
        }

        // stdout を読む（部分テキスト・ターン進行・割り込み受領など）。
        // 読まないと 64KB のパイプバッファが詰まり、claude がブロックして固まる
        let output = Pipe()
        let outBuffer = StreamBuffer()
        let outQueue = DispatchQueue(label: "at22.launcher.stdout", qos: .utility)

        // stderr も継続的に吸い出す（既存バグ修正）。
        // 読まないと 64KB で固まる。末尾 8KB だけ保持
        let errors = Pipe()
        let errBuffer = StreamBuffer(maxTailBytes: 8 * 1024)

        let stdin = Pipe()
        task.standardInput = stdin
        task.standardOutput = output
        task.standardError = errors

        // stdout を行単位で読む
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            outQueue.async {
                outBuffer.append(data)

                // 改行で分かれた完全な行を取り出す
                for lineData in outBuffer.takeCompleteLines() {
                    // 各行を JSON パース
                    if let event = Launcher.parseStreamLine(lineData) {
                        onStream?(event)
                    }
                }
            }
        }

        // stderr も継続的に吸い出す。末尾 8KB を保持する
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            outQueue.async {
                errBuffer.append(data)
            }
        }

        if let onExit {
            task.terminationHandler = { finished in
                // stdout / stderr の readabilityHandler が走り終わるまで待つ
                outQueue.sync {
                    // 末尾の改行が無い行があれば処理
                    let restData = outBuffer.takeRest()
                    if !restData.isEmpty, let event = Launcher.parseStreamLine(restData) {
                        onStream?(event)
                    }
                    // stderr を返す
                    let text = String(data: errBuffer.takeRest(), encoding: .utf8) ?? ""
                    onExit(finished.terminationStatus, text)
                }

                // ハンドラを外さないと、プロセスが終わってもハンドラとそれが握っているオブジェクトが残り続ける
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                task.terminationHandler = nil
            }
        }
        try task.run()

        let input = stdin.fileHandleForWriting
        // 最初の指示も割り込みと同じ経路で送る。ここを argv に戻すと、
        // 1往復で stdin が閉じてセッションごと終わる。
        // **空なら何も書かない**——既存セッションへ繋ぐだけの時（`resuming`）は、
        // 言葉は呼び出し側があとから流す。空のメッセージを1件送ると相手が空ターンを回す
        if !config.prompt.isEmpty, let line = messageLine(config.prompt) {
            try? input.write(contentsOf: line)
        }
        return Started(sessionID: sessionID, process: task, input: input)
    }

    /// 走っているセッションに1件割り込む。**stdin が開いている間だけ通る**
    nonisolated static func send(_ text: String, to input: FileHandle) -> Bool {
        guard let line = messageLine(text) else { return false }
        do { try input.write(contentsOf: line); return true } catch { return false }
    }

    /// 進行中のターンだけ止める。**プロセスは殺さずに、セッションは開いたままにする**。
    /// request_id を返す。`onStream` ハンドラを設定すれば、`control_response`（受領確認）が
    /// `interruptAcknowledged` イベントとして流れてくるので、この ID で照合できる
    nonisolated static func interrupt(_ input: FileHandle) -> String? {
        let requestID = UUID().uuidString
        guard let line = interruptLine(requestID: requestID) else { return nil }
        do { try input.write(contentsOf: line); return requestID } catch { return nil }
    }
}
