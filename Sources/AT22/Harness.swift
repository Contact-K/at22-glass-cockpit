import Foundation

// MARK: - 5段の許可制

/// 構想ノート「モード設計（5段階）」の実体。**段**（人が選ぶ）と**リスク**（道具と入力から AT22 が見積もる。
/// 門は司令塔の自己申告）の2つで、AT22 が道具の実行と門を裁く。
///
/// | 段 | 低 | 高 | 致命的 |
/// |---|---|---|---|
/// | Lv.1 壁打ち | 読むだけ通す／書くなら拒む | 拒む | 拒む |
/// | Lv.2 隣で見てる | 通す（門は veto 窓：すぐ発行し、猶予のうちは止められる） | 人に訊く | 人に訊く |
/// | Lv.3 気にかけてる | 通す | 人に訊く | 人に訊く |
/// | Lv.4 任せてる | 通す | 通す | 拒む（静的な安全網） |
/// | Lv.5 留守番 | 通す | 要判断に積んで飛ばす | 要判断に積んで飛ばす |
///
/// Lv.5 が Lv.4 より固いのは企画どおり——人が居ないので「勝手に踏み込む」のも「全体を止める」のも避け、
/// 飛ばして続けさせ、戻った人に「要判断」として見せる
enum Harness {
    enum Risk: Int, Comparable, Sendable {
        case low, high, critical
        static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    }

    enum Verdict: Equatable, Sendable {
        /// すぐ通す
        case allow
        /// **すぐ通し**、「保留中」として板に出す。猶予のうちなら人が止められる（何もしなければゼロクリックで進む）
        case veto(TimeInterval)
        /// 人の答えを待つ（hard gate）
        case ask
        /// 通さない。理由は相手に返す
        case deny(String)
        /// 通さず「要判断」に積み、飛ばして続けさせる
        case postpone(String)
    }

    /// 見積もり。`readOnly` は Lv.1 で通してよいか（何も書き換えない）
    struct Assessment: Equatable, Sendable {
        let risk: Risk
        let readOnly: Bool
        /// 人が読む一言（なぜその重さか）
        let reason: String
    }

    /// Lv.2 の veto 窓の長さ。ponytail: 固定。好みが分かれたら設定に出す
    nonisolated(unsafe) static var vetoWindow: TimeInterval = 10

    /// - Parameter instruction: 門（司令塔→実装/評価への指示の発行）か。veto 窓は**指示にだけ**掛ける——
    ///   企画の Lv.2 は「指示の発行そのもの」をゲートする段で、道具の実行は Lv.3 と同じ扱い。
    ///   道具1件ずつに窓を掛けると、編集のたびに待たされて承認地獄の別の形になる
    nonisolated static func decide(_ level: Gate.Level, _ found: Assessment, instruction: Bool = false) -> Verdict {
        switch (level, found.risk) {
        case (.plan, _):
            found.readOnly && found.risk < .critical ? .allow : .deny("壁打ち（Lv.1）なので、ファイルにもコマンドにも手を出さない。読むだけで進めて")
        case (.each, .low):           instruction ? .veto(vetoWindow) : .allow
        case (.each, _):              .ask
        case (.normal, .low):         .allow
        case (.normal, _):            .ask
        case (.auto, .critical):      .deny("任せてる（Lv.4）でも静的な安全網で止めた: \(found.reason)。別の手で進めて")
        case (.auto, _):              .allow
        case (.unattended, .low):     .allow
        case (.unattended, _):
            .postpone("留守番中（Lv.5）なので見送り、要判断に積んだ（\(found.reason)）。この工程は飛ばして続け、最後の報告に要判断として書いて")
        }
    }

    // MARK: 門

    /// 門のリスクは司令塔の自己申告（`risk:`）。**書いていなければ高**——
    /// 申告漏れで veto 窓や自動の許可に落ちると、止めるべき指示が素通りする
    nonisolated static func assess(gateRisk: String) -> Assessment {
        switch gateRisk.lowercased().trimmingCharacters(in: .whitespaces) {
        case "low":      Assessment(risk: .low, readOnly: false, reason: "司令塔の申告: 低")
        case "critical": Assessment(risk: .critical, readOnly: false, reason: "司令塔の申告: 致命的")
        default:         Assessment(risk: .high, readOnly: false, reason: gateRisk.isEmpty ? "リスクの申告が無い" : "司令塔の申告: \(gateRisk)")
        }
    }

    // MARK: 道具

    /// 道具の呼び出し1件を見積もる。`tool` は Claude の道具名（Bash / Edit …）か ACP の kind（execute / edit …）。
    /// `cwd` はそのセッションの作業場所（ワークスペース）。書き込みはこの内側だけを低と見る
    nonisolated static func assess(tool: String, input: String, cwd: String) -> Assessment {
        let fields = (input.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        let path = ["file_path", "notebook_path", "path", "abs_path"].lazy.compactMap { fields[$0] as? String }.first

        switch tool {
        case "Read", "Glob", "Grep", "LS", "WebSearch", "read", "search", "think":
            if let path, isSecret(path) { return Assessment(risk: .critical, readOnly: true, reason: "秘密のファイルを読む: \(path)") }
            return Assessment(risk: .low, readOnly: true, reason: "読むだけ")
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "edit":
            guard let path else { return Assessment(risk: .high, readOnly: false, reason: "書く先が分からない") }
            if isSecret(path) { return Assessment(risk: .critical, readOnly: false, reason: "秘密のファイルを書く: \(path)") }
            guard inside(path, cwd) else { return Assessment(risk: .critical, readOnly: false, reason: "作業場所の外に書く: \(path)") }
            return Assessment(risk: .low, readOnly: false, reason: "作業場所の中を書く")
        case "Bash", "execute":
            return assess(command: fields["command"] as? String ?? "", cwd: cwd)
        case "WebFetch", "fetch":
            // 手元は書き換えないが、URL に載せて外へ出せる。壁打ち（Lv.1）の調べ物には通す
            return Assessment(risk: .high, readOnly: true, reason: "外から取ってくる")
        default:
            // 取ってくる・消す・動かす・MCP の道具・知らない道具。どれも中身を読み切れない
            return Assessment(risk: .high, readOnly: false, reason: "\(tool) は中身を見積もれない")
        }
    }

    /// シェルのコマンド。**全部の区切りが読むだけ・組み立てるだけの手に収まる時だけ低**。
    /// ponytail: 字面で見る。`$(…)` やクォートの中の区切りまでは解かないので、読み切れない形は高に倒す
    nonisolated static func assess(command: String, cwd: String) -> Assessment {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Assessment(risk: .high, readOnly: false, reason: "コマンドが空") }
        if let floor = critical(text, cwd: cwd) { return Assessment(risk: .critical, readOnly: false, reason: floor) }
        if text.contains("$(") || text.contains("`") || text.contains("<(") {
            return Assessment(risk: .high, readOnly: false, reason: "組み立てたコマンドは読み切れない")
        }
        // > /dev/null と 2>&1 だけは書き込みに数えない
        let stripped = text.replacingOccurrences(of: "2>&1", with: "")
            .replacingOccurrences(of: #"\d?>\s*/dev/null"#, with: "", options: .regularExpression)
        if stripped.contains(">") { return Assessment(risk: .high, readOnly: false, reason: "ファイルへ書き出す") }

        let segments = stripped.components(separatedBy: CharacterSet(charactersIn: ";|&\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var readOnly = true
        for segment in segments {
            let words = segment.split(separator: " ").map(String.init).filter { !$0.contains("=") || $0.hasPrefix("-") }
            guard let head = words.first.map({ ($0 as NSString).lastPathComponent }) else { continue }
            let rest = Array(words.dropFirst())
            if readers.contains(head) || (head == "git" && rest.first.map(gitReaders.contains) == true) {
                if head == "find", rest.contains(where: { ["-delete", "-exec", "-execdir", "-ok"].contains($0) }) {
                    return Assessment(risk: .high, readOnly: false, reason: "find で消す・走らせる")
                }
                if head == "sed", rest.contains(where: { $0.hasPrefix("-i") }) {
                    return Assessment(risk: .high, readOnly: false, reason: "sed -i で書き換える")
                }
                continue
            }
            if head == "cd", rest.allSatisfy({ inside($0, cwd) }) { continue }
            if let allowed = builders[head], allowed.isEmpty || rest.first.map(allowed.contains) == true {
                readOnly = false
                continue
            }
            return Assessment(risk: .high, readOnly: false, reason: "\(head) は許可リストに無い")
        }
        return Assessment(risk: .low, readOnly: readOnly, reason: readOnly ? "読むだけのコマンド" : "組み立て・検査のコマンド")
    }

    /// どの段でも自動では通さないもの（Lv.4 の「静的な安全網」）。当たれば理由を返す
    nonisolated static func critical(_ command: String, cwd: String) -> String? {
        let words = command.split(whereSeparator: { " \t\n;|&".contains($0) }).map(String.init)
        if words.contains("sudo") { return "sudo" }
        if command.range(of: #"(curl|wget)[^|]*\|\s*(ba|z)?sh"#, options: .regularExpression) != nil { return "取ってきたものをそのまま走らせる" }
        if command.range(of: #"git\s+push\b[^;&|]*(\s-f\b|--force|\s\+)"#, options: .regularExpression) != nil { return "git push --force" }
        if command.range(of: #"git\s+push\b[^;&|]*\s(main|master)\b"#, options: .regularExpression) != nil { return "main / master へ push" }
        if command.range(of: #"\b(mkfs|diskutil\s+erase|dd\s+[^;]*of=/dev/)"#, options: .regularExpression) != nil { return "ディスクを消す" }
        // rm -r は作業場所の内側だけ。外（絶対パス・~・..）に向いているか、先に外へ cd していれば致命的
        if let rm = words.firstIndex(of: "rm"),
           words[(rm + 1)...].contains(where: { $0.hasPrefix("-") && ($0.contains("r") || $0.contains("R")) }) {
            if let cd = words.firstIndex(of: "cd"), cd < rm, words.indices.contains(cd + 1), !inside(words[cd + 1], cwd) {
                return "作業場所の外へ cd してから rm -r"
            }
            for target in words[(rm + 1)...] where !target.hasPrefix("-") {
                if target.hasPrefix("$") || !inside(target, cwd) { return "作業場所の外を rm -r: \(target)" }
            }
        }
        if let secret = words.first(where: isSecret) { return "秘密のファイルに触る: \(secret)" }
        return nil
    }

    /// 読むだけのコマンド
    nonisolated static let readers: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "pwd", "echo", "which", "file", "stat", "du", "df",
        "tree", "sort", "uniq", "diff", "cut", "tr", "sed", "jq", "true", "date", "basename", "dirname", "realpath",
    ]
    /// git の読むだけの手
    nonisolated static let gitReaders: Set<String> = [
        "status", "diff", "log", "show", "branch", "rev-parse", "ls-files", "blame", "remote", "describe", "worktree",
    ]
    /// 組み立て・検査（作業場所の中に成果物を書くだけ）。空の集合は引数を問わない
    nonisolated static let builders: [String: Set<String>] = [
        "swift": ["build", "test"], "npm": ["test"], "pnpm": ["test"], "yarn": ["test"],
        "cargo": ["build", "test", "check"], "go": ["build", "test", "vet"], "make": ["test", "check"],
        "xcodebuild": ["build", "test"], "pytest": [],
    ]

    /// `.env`・鍵・認証情報。読めただけで要約やログから漏れる（構想ノート「サンドボックス外への読み書き分離」）
    nonisolated static func isSecret(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name == ".env" || name.hasPrefix(".env.") { return !name.hasSuffix(".example") && !name.hasSuffix(".sample") }
        if ["id_rsa", "id_ed25519", "id_ecdsa", "credentials", ".netrc", ".npmrc", ".pypirc"].contains(name) { return true }
        if [".pem", ".key", ".p12", ".keychain", ".keychain-db"].contains(where: name.hasSuffix) { return true }
        return ["/.ssh/", "/.aws/", "/.gnupg/", "/Keychains/"].contains { path.contains($0) }
    }

    /// `path` が `cwd` の内側か。相対パスは `cwd` から、`..` は畳んでから比べる
    nonisolated static func inside(_ path: String, _ cwd: String) -> Bool {
        guard !cwd.isEmpty else { return false }
        let expanded = (path as NSString).expandingTildeInPath
        let base = URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath().path
        let target = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded)
                      : URL(fileURLWithPath: cwd).appendingPathComponent(expanded))
            .standardizedFileURL.resolvingSymlinksInPath().path
        return target == base || target.hasPrefix(base + "/")
    }
}
