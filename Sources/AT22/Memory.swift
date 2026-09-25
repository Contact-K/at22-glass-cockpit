import Foundation

// MARK: - 記憶DB

/// エージェントと人間が相互に書き足すテキストDB。AT22 は表示と、人間による既存ノートの編集だけを担う。
///
/// 置き場は `~/.claude/projects/<プロジェクト>/memory/`。
/// Vault の中に置く案は捨てた——AT22 は配布物なので、入れた人の誰にでもある場所でないと成立せず、
/// PARA の `02-Projects/` は作った人の環境にしか無い。
/// 書式も新しく作らない。Claude Code が既に書いている Markdown をそのまま使う。
enum Memory {

    /// 入れ子の形。**リンクではなくフォルダで階層を作る**——
    /// 線で結ぶと交差して読めず、リンクは書き手の気分で増減して構造が安定しない。
    /// ディレクトリなら人間もエージェントも同じものを見る
    ///
    /// ```
    /// memory/
    ///   PROJECT.md              大前提の企画書
    ///   sessions/
    ///     SHARED.md             セッション全体の共有メモ
    ///     each/
    ///       <セッションID>.md   セッションごとのメモ
    /// ```
    static let projectNotes: Set<String> = ["PROJECT.md", "MEMORY.md"]
    static let sessionsDir = "sessions"
    static let eachDir = "each"
    static let sharedNote = "SHARED.md"

    struct Node: Identifiable, Sendable {
        let id: String              // 絶対パス
        let file: String            // ファイル名
        /// frontmatter の `name`。無ければファイル名を使う
        let name: String
        let summary: String         // description
        let kind: String            // metadata.type（project / feedback / reference / user / progress）
        /// どのセッションが書いたか。ノートの来歴として3行目に出す
        let session: String?
        /// 引き継ぎとフルオートの復帰点。持たないノートの方が多い
        let state: [(key: String, value: String)]
        let lines: Int
        /// frontmatter を除いた本文。中身を md として読ませるので持っておく。
        /// 実測5〜36行なので、抱えても差し支えない
        let body: String
        let modified: Date
        /// `memory/` からの相対パス。入れ子の深さと並び順はここで決まる
        let relative: String
        let isIndex: Bool

        var hasState: Bool { !state.isEmpty }
    }

    // MARK: 読む

    /// `<プロジェクト>/memory/` を**入れ子のまま**読む。無ければ空。
    /// AT22 は `~/.claude/projects/` を既に歩いているので、セッションのディレクトリから直に辿れる
    nonisolated static func load(projectRoot: URL) -> [Node] {
        let root = projectRoot.appendingPathComponent("memory").standardizedFileURL
        let prefix = root.path + "/"
        var out: [Node] = []
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }

        for case let url as URL in walker {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            // `gate/` は門の受け渡しに使う作業領域。ノートとして並べても答えられないうえ、
            // 一覧の頭に居座る。門は自分の見せ場（線の上の紙）を持っている
            guard !String(path.dropFirst(prefix.count)).hasPrefix(Gate.directory + "/") else { continue }
            let modified = (try? url.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast
            let relative = String(path.dropFirst(prefix.count))
            if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                out.append(node(path: path, relative: relative, text: text, modified: modified))
            } else {
                // 読めないノートも一覧から消さず、直すべき場所を見える形で残す
                let file = url.lastPathComponent
                out.append(Node(id: path, file: file,
                                name: (file as NSString).deletingPathExtension,
                                summary: "UTF-8として読めません", kind: "", session: nil,
                                state: [], lines: 0, body: "", modified: modified,
                                relative: relative, isIndex: projectNotes.contains(file)))
            }
        }
        return out
    }

    /// 1本ぶんを起こす。frontmatter が無い・壊れていても落とさない——
    /// 人間が直接直せることを優先した書式なので、途中の形も普通に現れる
    nonisolated static func node(path: String, relative: String = "", text: String,
                                 modified: Date) -> Node {
        let file = (path as NSString).lastPathComponent
        let front = frontMatter(text)
        let fallbackName = (file as NSString).deletingPathExtension
        return Node(id: path,
                    file: file,
                    name: front["name"] ?? fallbackName,
                    summary: front["description"] ?? "",
                    kind: front["type"] ?? "",
                    session: front["originSessionId"],
                    state: stateBlock(text),
                    lines: text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 },
                    body: body(text),
                    modified: modified,
                    relative: relative.isEmpty ? file : relative,
                    isIndex: projectNotes.contains(file))
    }

    // MARK: 字句

    /// `---` で挟まれた頭。入れ子（`metadata:` の下）は同じ辞書に畳む——
    /// 読みたいのは name / description / type / originSessionId の4つだけで、階層に意味が無い
    nonisolated static func frontMatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }

        var out: [String: String] = [:]
        for raw in lines.dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            // 先に書かれた方を残す。入れ子で同じ鍵が二度出ても頭の意味を上書きしない
            if out[key] == nil { out[key] = value }
        }
        return out
    }

    /// frontmatter を落とした本文
    nonisolated static func body(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return text }
        return lines[(close + 1)...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ```state で囲われた引き継ぎの状態。
    /// ponytail: `key: value` の行だけ拾う。YAML を丸ごと解釈しない——
    /// 人間が手で直す前提の場所なので、崩れた行があっても読める分だけ出す方が使える
    nonisolated static func stateBlock(_ text: String) -> [(key: String, value: String)] {
        var out: [(String, String)] = []
        var inside = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                // 開くのは ```state だけ。本文の ```json や ```swift を状態と取り違えない
                if inside { break }
                inside = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "state"
                continue
            }
            guard inside, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty { out.append((key, value)) }
        }
        return out
    }

    // MARK: 階層

    /// 字下げの1行。フォルダも1行として出す
    struct Row: Sendable {
        let node: Node?             // フォルダの見出しは実体を持たない
        let label: String
        let kind: String
        let depth: Int
        var isFolder: Bool { node == nil }
    }

    /// 完了した進捗かどうか。状態ブロックの `stage` で見る。
    /// 進捗は溜まる一方なので、終わったものは件数に畳んで場所を空ける
    nonisolated static func isDone(_ node: Node) -> Bool {
        guard let stage = node.state.first(where: { $0.key.lowercased() == "stage" })?.value else { return false }
        return ["done", "completed", "finished", "完了"].contains(stage.lowercased())
    }

    /// **プロジェクト / セッション全体 / セッションごと** の3段を必ず出す。
    ///
    /// フォルダ任せにすると、実物が平置きのうちは段が1つも出ず「どれがどの範囲の記憶か」が読めない。
    /// AT22 が構造を明示する側に回る——見出しは常に出し、中身が無ければ空のまま示す。
    /// 種別は書き手によって揺れるため使わず、置き場だけで振り分ける。
    nonisolated static func outline(_ nodes: [Node]) -> (rows: [Row], done: Int) {
        let live = nodes.filter { !isDone($0) }
        let done = nodes.count - live.count

        enum Place { case project, shared, each }
        func place(_ node: Node) -> Place {
            let parts = node.relative.split(separator: "/")
            if parts.count >= 3, parts[0] == Substring(sessionsDir), parts[1] == Substring(eachDir) {
                return .each
            }
            if parts.count == 2, parts[0] == Substring(sessionsDir) { return .shared }
            return .project
        }

        // 大前提 → 共有ノート → その他。寿命の長いものを各段の先頭に固定する
        func rank(_ node: Node) -> Int {
            node.isIndex ? 0 : (node.file == sharedNote ? 1 : 2)
        }
        func sorted(_ list: [Node]) -> [Node] {
            list.sorted { (rank($0), $0.relative) < (rank($1), $1.relative) }
        }

        var rows: [Row] = []
        // 3段とも同じ形（名前＋件数）で出す。片方だけ件数が付くと、
        // 付いていない段が「数えていない」のか「0件」なのか読めない
        let project = sorted(live.filter { place($0) == .project })
        rows.append(Row(node: nil, label: "プロジェクト  \(project.count)", kind: "", depth: 0))
        for node in project {
            rows.append(Row(node: node, label: node.file, kind: node.kind, depth: 1))
        }

        let shared = sorted(live.filter { place($0) == .shared })
        rows.append(Row(node: nil, label: "セッション全体  \(shared.count)", kind: "", depth: 0))
        for node in shared {
            rows.append(Row(node: node, label: node.file, kind: node.kind, depth: 1))
        }

        let each = sorted(live.filter { place($0) == .each })
        rows.append(Row(node: nil, label: "セッションごと  \(each.count)", kind: "", depth: 0))
        for node in each {
            let id = (node.file as NSString).deletingPathExtension
            rows.append(Row(node: node, label: id, kind: node.kind, depth: 1))
        }
        return (rows, done)
    }
}
