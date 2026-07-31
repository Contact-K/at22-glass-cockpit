import Foundation
import Observation

// MARK: - 描画用スナップショット

/// ファイルの見え方。書き込み中 > 読み取り中 > フラグ付き > アイドル の優先順
enum FileState {
    case writing
    case reading
    case flagged
    case idle
}

struct FileCell: Identifiable {
    let id: String            // 絶対パス
    let name: String
    var reads = 0             // 全エージェント合計の参照回数
    var added = 0
    var removed = 0
    var state: FileState = .idle
    var lastAt: Date
    /// 最後に書かれた時刻。書かれた瞬間に光の帯を1回流すのに使う
    var lastWriteAt: Date?
    /// フラグを立てた原因のエージェント名（「これが何度も参照している」の主語）
    var flaggedBy: String?
}

struct DirCard: Identifiable {
    let id: String            // 絶対パス（別プロジェクトの同名ディレクトリを混ぜないための鍵）
    let dir: String           // 表示用の短縮名
    var files: [FileCell]
}

struct AgentChip: Identifiable {
    let id: String
    var role: String          // 司令塔 / Explore / general-purpose …
    var model: String         // opus-5 / haiku-4.5 …
    var depth: Int            // 0 = 司令塔、1 以降がサブエージェント
    var parent: String?       // 親エージェントのID
    /// 労働量＝ツール呼び出し回数。終了後は報告された確定値、進行中は観測できたぶん。
    /// Bash しか使わないエージェントもここには出る
    var work: Int
    /// 動いている時は「今していること」、止まっている時は「何をしてきたか」。
    /// 実測でツール呼び出しの45%はファイル軸に載らないので、線では出せない部分がここに出る
    var doing: String
    var done: Bool            // 終了済み。グレーアウトして残す
    var busy: Bool            // いまファイルを触っている
    var target: String?       // いま触っているファイルの絶対パス
    var kind: TouchKind?
    var lastAt: Date
}

struct CockpitSnapshot {
    var chips: [AgentChip] = []
    var cards: [DirCard] = []
    var flagCount = 0
}

struct LiveSession: Identifiable, Hashable {
    let id: String
    let name: String
    let cwd: String
    let busy: Bool
}

// MARK: - 状態

/// transcript から起こした「触った記録」を溜め、描画時に畳み込む。
/// 派生状態を持たないので、セッション切り替えもフラグのしきい値変更も畳み込み側だけで済む。
@MainActor @Observable
final class Cockpit {

    struct Touch {
        let session: String
        let agent: String
        let path: String
        let kind: TouchKind
        let started: Date
        var finished: Date?
        var added = 0
        var removed = 0
    }

    /// 同じエージェントがこの回数以上読み、かつ一度も書いていないファイルにフラグを立てる。
    /// 実 transcript 2478組の分布から決めた値（3回以上＋編集ゼロ＝全体の1.4%）。
    /// ponytail: 環境や使い方で最適値は動くので、決め打ちにせず外から変えられる形にしてある
    var flagReadThreshold = 3

    /// 画面に並べるファイル数の上限（最終接触が新しい順）
    static let maxFiles = 48
    /// チップの上限。終了したエージェントは「クリア」まで残す設計なので、
    /// 溜まりすぎた時の保険としてだけ効かせる（労働量の少ない方から落ちる）
    static let maxChips = 24
    /// 完了しない触りをいつまで「進行中」とみなすか
    static let stuckAfter: TimeInterval = 120
    /// エージェントが動いていると見なす無音の上限。
    /// 稼働をファイルの触りだけで判定すると、実測で45%を占める Bash 作業（検索・ビルド）が
    /// 全部「待機」に見える。transcript が伸びていること自体を稼働の印にする
    static let activeWindow: TimeInterval = 15
    /// 触り終わった後もこの秒数はビームと色を残す。
    /// Read も Edit も0.1秒で終わるのに監視は0.4秒間隔なので、
    /// 「進行中」の瞬間だけを描いていると一度も光らない
    static let afterglow: TimeInterval = 3

    private let maxTouches = 5000

    /// 階層の一番上の呼び名。オーケストレーターを回すとここが司令塔になる
    static let rootRole = "司令塔"

    /// エージェント1体の台帳。ファイルを一度も触らなくてもここには載る
    struct AgentRecord {
        var session: String
        var role: String?
        var model: String?
        var depth: Int?
        var parentCall: String?
        var reportedWork: Int?    // 終了報告に入っていた確定のツール呼び出し回数
        var counts: [WorkKind: Int] = [:]
        var latest: (kind: WorkKind, detail: String)?
        var doneAt: Date?
        var lastAt: Date

        /// 待機（sleep）を除いた、観測できたツール呼び出し回数
        var observedWork: Int {
            counts.reduce(0) { $1.key.counts ? $0 + $1.value : $0 }
        }
    }

    private(set) var touches: [Touch] = []
    private var index: [String: Int] = [:]          // tool_use_id -> touches の位置
    private var agents: [String: AgentRecord] = [:]
    private var callIssuer: [String: String] = [:]  // 呼び出しID -> 発行したエージェント

    /// ここより前の記録は畳み込みで無視する。実装の区切りで押す「クリア」の実体
    private(set) var clearedAt: Date?

    var selectedSession: String?
    var liveSessions: [LiveSession] = []

    /// 動きがある間だけ真。描画側がこれを見てフレームレートを落とす
    private(set) var isBusy = false
    private var lastActivity = Date.distantPast
    private var pending = 0

    // MARK: 取り込み

    func apply(_ events: [TranscriptEvent]) {
        for event in events {
            switch event {
            case let .touchStarted(id, session, agent, path, kind, at):
                guard index[id] == nil else { break }   // 同じ行を二度読んだ場合の保険
                touches.append(Touch(session: session, agent: agent, path: path, kind: kind, started: at))
                index[id] = touches.count - 1
                pending += 1
                // 触りだけでも台帳に載せる。assistant 行の取りこぼしでチップごと消えないように
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                record.lastAt = max(record.lastAt, at)
                agents[agent] = record

            case let .touchFinished(id, added, removed, at):
                // 知らない tool_use_id（Bash など）は黙って捨てる
                guard let i = index[id], touches[i].finished == nil else { break }
                touches[i].finished = at
                touches[i].added = added
                touches[i].removed = removed
                pending = max(0, pending - 1)

            case let .agentActivity(agent, session, model, at):
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                if let model, record.model != model { record.model = model }
                record.lastAt = max(record.lastAt, at)
                // 一度終わったエージェントに続きを頼むと再開する。灰色のままにしない
                if let done = record.doneAt, at > done { record.doneAt = nil }
                agents[agent] = record

            case let .agentAction(agent, session, kind, detail, at):
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                record.counts[kind, default: 0] += 1
                record.latest = (kind, detail)
                record.lastAt = max(record.lastAt, at)
                if let done = record.doneAt, at > done { record.doneAt = nil }
                agents[agent] = record

            case let .agentEnded(agent, at):
                guard var record = agents[agent] else { break }
                record.doneAt = at
                record.lastAt = max(record.lastAt, at)
                agents[agent] = record

            case let .agentMeta(agent, session, role, depth, call):
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: .distantPast)
                record.role = role
                record.depth = depth
                if !call.isEmpty { record.parentCall = call }
                agents[agent] = record

            case let .agentDone(agent, session, role, model, calls, at):
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                // 完了報告には description が入っていないので、役割名は必ず `general-purpose` に戻る。
                // meta.json から取った具体名（「W2: 承認タブ実装」等）を潰さないよう、穴埋めにだけ使う
                if record.role == nil, !role.isEmpty { record.role = role }
                if !model.isEmpty { record.model = model }
                record.reportedWork = calls
                record.doneAt = at
                record.lastAt = max(record.lastAt, at)
                agents[agent] = record

            case let .agentSpawn(call, by):
                callIssuer[call] = by
            }
        }
        trimIfNeeded()
        lastActivity = Date()
        if !isBusy { isBusy = true }
    }

    private func trimIfNeeded() {
        guard touches.count > maxTouches else { return }
        touches.removeFirst(touches.count - maxTouches + 1000)
        index = [:]                                 // 位置がずれるので張り直す
        pending = touches.count { $0.finished == nil }
        // ponytail: tool_use_id を Touch 側に持たせず作り直しているので、
        // 切り詰め直後に来た touchFinished は取りこぼす。数千件に一度なので放置
    }

    /// 静止したら描画を落とすための定期点検。
    /// 完了していない触りが残っている間は動かし続けたいので、宙ぶらりんの分は静止扱いにしない
    func housekeeping() {
        let silence = Date().timeIntervalSince(lastActivity)
        let quiet = silence > 5 && (pending == 0 || silence > Self.stuckAfter)
        if isBusy == quiet { isBusy = !quiet }
        refreshLiveSessions()
    }

    // MARK: 畳み込み

    /// 実装の区切りで一旦まっさらにする。溜まった終了済みチップとファイルの集計を落とす
    func clear() {
        clearedAt = Date()
    }

    func snapshot(now: Date) -> CockpitSnapshot {
        var cells: [String: FileCell] = [:]
        var live: [String: (target: String, kind: TouchKind)] = [:]
        var touchCount: [String: Int] = [:]
        // (エージェント, ファイル) ごとの読み書き回数。フラグ判定はこの粒度でしか意味を持たない
        var reads: [Pair: Int] = [:]
        var writes: [Pair: Int] = [:]

        // ponytail: 毎フレーム O(n) で畳み直す。n は上限 5000 なので実測で十分速い
        for touch in touches {
            if let filter = selectedSession, touch.session != filter { continue }
            if let cleared = clearedAt, touch.started < cleared { continue }

            let pair = Pair(agent: touch.agent, path: touch.path)
            switch touch.kind {
            case .read:  reads[pair, default: 0] += 1
            case .write: writes[pair, default: 0] += 1
            }

            touchCount[touch.agent, default: 0] += 1

            let glowing: Bool
            if let finished = touch.finished {
                let since = now.timeIntervalSince(finished)
                glowing = since >= 0 && since < Self.afterglow
            } else {
                glowing = now.timeIntervalSince(touch.started) < Self.stuckAfter
            }

            var cell = cells[touch.path] ?? FileCell(id: touch.path,
                                                     name: (touch.path as NSString).lastPathComponent,
                                                     lastAt: touch.started)
            if touch.kind == .read { cell.reads += 1 }
            cell.added += touch.added
            cell.removed += touch.removed
            cell.lastAt = max(cell.lastAt, touch.started)
            if touch.kind == .write {
                let at = touch.finished ?? touch.started
                cell.lastWriteAt = max(cell.lastWriteAt ?? at, at)
            }
            if glowing {
                // 書き込み中は読み取り中より強い
                if touch.kind == .write { cell.state = .writing }
                else if cell.state != .writing { cell.state = .reading }
                live[touch.agent] = (touch.path, touch.kind)
            }
            cells[touch.path] = cell
        }

        // フラグ：同じエージェントが繰り返し読んでいて、一度も書いていないファイル
        var flagCount = 0
        for (pair, count) in reads where count >= flagReadThreshold && (writes[pair] ?? 0) == 0 {
            guard var cell = cells[pair.path] else { continue }
            flagCount += 1
            cell.flaggedBy = agents[pair.agent].flatMap(\.role)
                ?? role(of: pair.agent, session: agents[pair.agent]?.session ?? "")
            if cell.state == .idle { cell.state = .flagged }
            cells[pair.path] = cell
        }

        // 画面に収まる分だけ、最後に触られた順で残す
        var kept = Array(cells.values).sorted { $0.lastAt > $1.lastAt }
        if kept.count > Self.maxFiles { kept = Array(kept.prefix(Self.maxFiles)) }

        return CockpitSnapshot(chips: buildChips(live: live, touchCount: touchCount, now: now),
                               cards: group(kept),
                               flagCount: flagCount)
    }

    /// チップは触った記録ではなく台帳から作る。
    /// Bash しか使わないサブエージェントはファイルを一度も触らないので、
    /// 触りから組み立てると存在ごと消えてしまう
    private func buildChips(live: [String: (target: String, kind: TouchKind)],
                            touchCount: [String: Int],
                            now: Date) -> [AgentChip] {
        var chips: [AgentChip] = []
        for (id, record) in agents {
            if let filter = selectedSession, record.session != filter { continue }
            if let cleared = clearedAt, record.lastAt < cleared { continue }

            let running = live[id]
            // ファイルを触っていなくても、transcript が伸びていれば動いている
            let silence = now.timeIntervalSince(record.lastAt)
            let working = record.doneAt == nil && silence >= 0 && silence < Self.activeWindow
            chips.append(AgentChip(
                id: id,
                role: record.role ?? role(of: id, session: record.session),
                model: record.model ?? "",
                depth: record.depth ?? (isRoot(id, session: record.session) ? 0 : 1),
                parent: record.parentCall.flatMap { callIssuer[$0] },
                // 終了報告が来ていればそれが確定値。来るまでは観測できたぶんで代用する
                work: record.reportedWork ?? max(record.observedWork, touchCount[id] ?? 0),
                doing: Self.doingText(record, working: working || running != nil),
                done: record.doneAt != nil,
                busy: running != nil || working,
                target: running?.target,
                kind: running?.kind,
                lastAt: record.lastAt))
        }

        // 階層ごとに、労働量の多い順に左から。同量なら動いたのが新しい順
        chips.sort { ($0.depth, -$0.work, $1.lastAt) < ($1.depth, -$1.work, $0.lastAt) }
        return chips.count > Self.maxChips ? Array(chips.prefix(Self.maxChips)) : chips
    }

    private struct Pair: Hashable {
        let agent: String
        let path: String
    }

    /// 親ディレクトリごとにカードへまとめる。まとめる鍵は必ず絶対パス
    /// （別プロジェクトの同名ディレクトリを1枚に混ぜないため）で、短くするのは表示だけ。
    private func group(_ cells: [FileCell]) -> [DirCard] {
        var buckets: [String: [FileCell]] = [:]
        for cell in cells {
            buckets[(cell.id as NSString).deletingLastPathComponent, default: []].append(cell)
        }
        let prefix = commonDirectoryPrefix(Array(buckets.keys))

        // 並びは基本アルファベット順で固定して目が迷子にならないようにする。
        // ただしフラグは気づかれないと意味が無いので、持っているカード・ファイルだけ先頭に寄せる
        // （フラグは全体の1.4%しか立たないので、並びが揺れるのは稀）
        return buckets
            .map { dir, files in
                DirCard(id: dir, dir: Self.shortDirName(dir, strippingPrefix: prefix),
                        files: files.sorted {
                            ($0.flaggedBy != nil ? 0 : 1, $0.name) < ($1.flaggedBy != nil ? 0 : 1, $1.name)
                        })
            }
            .sorted {
                let a = $0.files.contains { $0.flaggedBy != nil } ? 0 : 1
                let b = $1.files.contains { $0.flaggedBy != nil } ? 0 : 1
                return (a, $0.dir, $0.id) < (b, $1.dir, $1.id)
            }
    }

    /// 共通の先頭部分を落とし、それでも長ければ末尾2階層だけ残す。
    /// 複数プロジェクトを同時に見ていると共通部分がほぼ無く、フルパスは読めないため。
    static func shortDirName(_ dir: String, strippingPrefix prefix: String) -> String {
        var rest = dir.hasPrefix(prefix) ? String(dir.dropFirst(prefix.count)) : dir
        if rest.hasPrefix("/") { rest.removeFirst() }
        if rest.isEmpty { return (dir as NSString).lastPathComponent }

        let parts = rest.split(separator: "/")
        guard parts.count > 2 else { return rest }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    private func commonDirectoryPrefix(_ dirs: [String]) -> String {
        guard var prefix = dirs.first else { return "" }
        for dir in dirs.dropFirst() {
            var a = prefix.split(separator: "/", omittingEmptySubsequences: false)
            let b = dir.split(separator: "/", omittingEmptySubsequences: false)
            var i = 0
            while i < a.count && i < b.count && a[i] == b[i] { i += 1 }
            a = Array(a[0..<i])
            prefix = a.joined(separator: "/")
            if prefix.isEmpty { return "" }
        }
        return prefix
    }

    /// 動いている間は「今していること」（例: `検索 grep` / `編集 Cockpit.swift`）、
    /// 止まっていれば「してきたこと」の内訳（例: `検索12 閲覧5 編集2`）。
    /// 線が引けない作業はここでしか見えない
    static func doingText(_ record: AgentRecord, working: Bool) -> String {
        if working, let latest = record.latest {
            return latest.detail.isEmpty ? latest.kind.rawValue : "\(latest.kind.rawValue) \(latest.detail)"
        }
        let top = record.counts
            .filter { $0.key.counts && $0.value > 0 }
            .sorted { ($1.value, $1.key.rawValue) < ($0.value, $0.key.rawValue) }
            .prefix(3)
        return top.map { "\($0.key.rawValue)\($0.value)" }.joined(separator: " ")
    }

    // MARK: エージェントの素性

    /// メインセッションはエージェントIDがセッションIDそのもの。それが階層の頂点になる
    private func isRoot(_ agent: String, session: String) -> Bool { agent == session }

    private func role(of agent: String, session: String) -> String {
        if let known = agents[agent]?.role { return known }
        if isRoot(agent, session: session) { return Self.rootRole }
        return agent.count > 8 ? "…" + agent.suffix(6) : agent
    }

    // MARK: 稼働中セッション

    /// `~/.claude/sessions/<pid>.json` は1プロセス1ファイルで、生死と busy/idle を持っている。
    /// transcript を舐めずにセッション一覧が作れる唯一の場所。
    func refreshLiveSessions() {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var found: [LiveSession] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let id = obj["sessionId"] as? String
            else { continue }
            found.append(LiveSession(id: id,
                                     name: obj["name"] as? String ?? String(id.prefix(8)),
                                     cwd: obj["cwd"] as? String ?? "",
                                     busy: (obj["status"] as? String) == "busy"))
        }
        let sorted = found.sorted { $0.name < $1.name }
        if sorted != liveSessions { liveSessions = sorted }
    }
}
