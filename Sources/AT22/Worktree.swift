import Foundation

// MARK: - git worktree

/// タスクごとの作業場所（git worktree）。AT22 が作り、エージェントをそこで起こす。
///
/// 置き場は `<repo>/.claude/worktrees/<名前>`——`claude -w` と同じなので、端末で作ったものも
/// AT22 で作ったものも同じ一覧に並ぶ。git は Process で叩く薄い包みで、
/// **同期で走るので必ず `Task.detached` から呼ぶ**（画面を止めない）
enum Worktree {

    struct Entry: Equatable, Sendable {
        let path: String
        let head: String
        /// `refs/heads/` を落とした枝の名前。切り離し（detached）なら nil
        let branch: String?
        /// 先頭のブロック＝リポジトリ本体。**消してはいけない**
        let isMain: Bool
        var locked = false
        var prunable = false
    }

    struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// 置き場の相対パス。ここを無視させないと、本体の `git status` に作業場所が丸ごと出てしまう
    static let directory = ".claude/worktrees"

    // MARK: 読む（純関数）

    /// `git worktree list --porcelain` を読む。空行で区切られたブロックが1本ずつで、先頭が本体
    nonisolated static func parse(_ porcelain: String) -> [Entry] {
        porcelain.components(separatedBy: "\n\n").enumerated().compactMap { index, block in
            var path: String?, head = "", branch: String?
            var locked = false, prunable = false
            for line in block.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                switch parts.first {
                case "worktree": path = parts.count > 1 ? parts[1] : nil
                case "HEAD": head = parts.count > 1 ? parts[1] : ""
                case "branch": branch = parts.count > 1 ? parts[1].replacingOccurrences(of: "refs/heads/", with: "") : nil
                case "locked": locked = true
                case "prunable": prunable = true
                default: break
                }
            }
            guard let path else { return nil }
            return Entry(path: path, head: head, branch: branch, isMain: index == 0, locked: locked, prunable: prunable)
        }
    }

    /// 人が付けた名前を、ブランチ名にも置き場の名前にも使える形へ。
    /// 英数字・`-`・`_`・`.` 以外は `-` に寄せ、端の `-` と `.` は落とす（`..` でパスを抜けさせない）
    nonisolated static func slug(_ name: String) -> String {
        let mapped = String(name.map { $0.isLetter || $0.isNumber || "-_".contains($0) ? $0 : "-" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "task" : trimmed
    }

    nonisolated static func location(repo: String, name: String) -> String {
        (repo as NSString).appendingPathComponent(directory + "/" + slug(name))
    }

    /// AT22 が作る枝の名前
    nonisolated static func branch(for name: String) -> String { "at22/" + slug(name) }

    /// `status --porcelain` の行からファイル名だけを取る（削除の確認に並べる）
    nonisolated static func changedFiles(_ porcelain: String) -> [String] {
        porcelain.split(separator: "\n").map { String($0.dropFirst(3)) }.filter { !$0.isEmpty }
    }

    // MARK: git を叩く

    /// git を1回走らせ、stdout を返す。終了コードが 0 でなければ stderr を載せて投げる。
    /// ponytail: stdout を読み切ってから stderr を読む。git の stderr は数行なので詰まらない
    nonisolated static func git(_ arguments: [String], in directory: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", directory] + arguments
        let output = Pipe(), errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { throw Failure(message: "git を起こせない: \(error)") }
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let reason = String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw Failure(message: reason.isEmpty ? "git \(arguments.first ?? "") が失敗した" : reason)
        }
        return String(data: out, encoding: .utf8) ?? ""
    }

    /// そのパスが属するリポジトリの本体。worktree の中から呼んでも本体を返す（`--git-common-dir` の親）
    nonisolated static func root(of path: String) throws -> String {
        let common = try git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard common.hasSuffix("/.git") else { throw Failure(message: "作業ツリーを持たないリポジトリ（bare）は扱わない") }
        return String(common.dropLast("/.git".count))
    }

    nonisolated static func list(repo: String) throws -> [Entry] {
        parse(try git(["worktree", "list", "--porcelain"], in: repo))
    }

    /// 今いる枝の名前。基点の既定に使う（切り離しなら HEAD）
    nonisolated static func currentBranch(repo: String) -> String {
        (try? git(["symbolic-ref", "--short", "-q", "HEAD"], in: repo))?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "HEAD"
    }

    /// 作る。**基点はコミットの SHA で固定する**——後から元の枝が動いても、差分の基準がずれない
    nonisolated static func add(repo: String, name: String, base: String) throws -> (path: String, branch: String, baseSHA: String) {
        let sha = try git(["rev-parse", "--verify", "-q", base + "^{commit}"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty else { throw Failure(message: "基点 \(base) が見つからない（コミットが1つも無いリポジトリでは作れない）") }
        try exclude(repo: repo)
        let path = location(repo: repo, name: name)
        let branch = branch(for: name)
        guard !FileManager.default.fileExists(atPath: path) else {
            throw Failure(message: "同じ名前の作業場所が既にある: \(slug(name))")
        }
        _ = try git(["worktree", "add", "-b", branch, path, sha], in: repo)
        return (path, branch, sha)
    }

    /// 未コミットの変更（追跡していないファイルを含む）。消す前に人に見せる
    nonisolated static func dirtyFiles(_ path: String) throws -> [String] {
        changedFiles(try git(["status", "--porcelain"], in: path))
    }

    /// 消す。未コミットの変更がある時は git が断るので、**人に確認を取った後だけ `force` を立てる**。
    /// 本体と、一覧に無い場所はどんな場合も消さない
    nonisolated static func remove(repo: String, path: String, force: Bool) throws {
        guard let entry = try list(repo: repo).first(where: { $0.path == path }) else {
            throw Failure(message: "このリポジトリの作業場所ではない: \(path)")
        }
        guard !entry.isMain else { throw Failure(message: "リポジトリ本体は消さない") }
        _ = try git(["worktree", "remove"] + (force ? ["--force"] : []) + [path], in: repo)
    }

    /// 枝を消す。`-d` なのでマージされていないものは git が断る——その時は残して false を返す
    /// （人が中身を見てから消せるように）
    nonisolated static func deleteBranch(_ branch: String, repo: String) -> Bool {
        (try? git(["branch", "-d", branch], in: repo)) != nil
    }

    /// `.claude/worktrees/` を本体の `git status` から隠す。既に無視されていれば何も書かない
    nonisolated static func exclude(repo: String) throws {
        let ignored = (try? git(["check-ignore", "-q", directory + "/"], in: repo)) != nil
        guard !ignored else { return }
        let info = (repo as NSString).appendingPathComponent(".git/info")
        try? FileManager.default.createDirectory(atPath: info, withIntermediateDirectories: true)
        let file = (info as NSString).appendingPathComponent("exclude")
        let current = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        let line = "\n# AT22 の作業場所（git worktree）\n\(directory)/\n"
        do { try (current + line).write(toFile: file, atomically: true, encoding: .utf8) }
        catch { throw Failure(message: ".git/info/exclude に書けない: \(error)") }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
