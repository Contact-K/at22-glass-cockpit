import Foundation
import Observation

// MARK: - 描画用スナップショット

/// 作業は人と動き、構造はコードと依存を軸にし、同じ情報を一画面で競合させない
enum CockpitMode: String, CaseIterable {
    case work
    case structure
    case memory

    /// 保存値は表示文言から切り離し、文言変更で選択が初期化されないようにする
    var title: String {
        switch self {
        case .work: "作業"
        case .structure: "構造"
        // ケース名（＝保存値）は変えない。変えると保存済みの選択が黙って初期化される
        case .memory: "壁打ち"
        }
    }
}

/// ファイルの見え方。書き込み中 > 読み取り中 > フラグ付き > アイドル の優先順
enum FileState {
    case writing
    case reading
    case flagged
    case idle
}

/// 記憶ノートの保存結果。競合は書き込み失敗と分け、人間に選択を返す
enum NoteSaveResult: Equatable {
    case saved
    case conflict
    case failed
}

struct FileCell: Identifiable {
    let id: String            // 絶対パス
    let name: String
    var touched = false
    var reads = 0             // 全エージェント合計の参照回数
    var added = 0
    var removed = 0
    var state: FileState = .idle
    /// 記憶モードだけ入る。2行目＝1行要約、3行目＝行数・書いたセッション・状態
    var note = ""
    var trace = ""
    /// 字下げの深さ（壁打ちモードの記憶DB）。Obsidian のアウトラインと同じ見え方にする
    var indent = 0
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
    /// 吹き出しでは省略前の指示を読めるよう、表示用の role / doing と分けて持つ
    var instruction: String
    var counts: [(kind: WorkKind, count: Int)]
    /// 累積トークン消費（重み付き）。`buildChips` で計算
    let spent: Double
    /// 同じセッションの合計に対する割合（0…1）。合計が0なら0
    let share: Double
    /// 人間の返事待ち（`LiveSession.waiting`）。セッション単位の値なので司令塔にだけ載る
    var waiting: String? = nil
}

struct CockpitSnapshot {
    var mode: CockpitMode = .work
    var chips: [AgentChip] = []
    var cards: [DirCard] = []
    var flagCount = 0
    /// 参照回数の点がいくつで埋まりきるか。フラグのしきい値と同じ値を運ぶ
    var readThreshold = 3
    /// 上限の外に畳んだエージェント数
    var hiddenChips = 0
    /// 答え待ちで止まっている指示。線の上に紙として停める
    var gates: [Gate.Request] = []
}

struct LiveSession: Identifiable, Hashable {
    let id: String
    let name: String
    let cwd: String
    let busy: Bool
    /// 人間の返事を待って止まっている時だけ入る（「承認待ち」「入力待ち」）。
    /// Claude Code 自身が `sessions/<pid>.json` に書く値なので、フックも設定も要らない
    var waiting: String? = nil
}

/// 終了済みも含む transcript の入口。ファイル名のUUIDを選択キーにそのまま使う
struct RecentSession: Identifiable, Hashable, Sendable {
    let id: String
    let project: String
    let projectURL: URL
    let transcriptURL: URL
    let modifiedAt: Date
}

/// 進行表の1件。計画段階で積まれ、順に進んで、終わったものからグレーアウトする
struct RoadmapTask: Identifiable {
    let id: String            // "<session>#<taskId>"。taskId はセッション内でしか一意でない
    let session: String
    let number: Int           // 並び順。taskId の数値
    let subject: String
    let activeForm: String    // 進行中に出す「〜中」の形
    let detail: String        // description。クリックした先で出す
    var status: TaskStatus
    var at: Date
}

/// 誰かが書いた言葉1件。**ツール呼び出しではない部分**——
/// 人間か司令塔かの発言が出るようにしたので、これまで一切出ていなかった会話が成立する
struct Message: Identifiable, Sendable {
    let id: Int
    let session: String
    let agent: String
    let text: String
    /// thinking ブロックか。実測で text 256件に対し thinking 297件あるので、既定では畳む
    let thinking: Bool
    /// 誰の言葉か。人間の発言が表示されることで、司令塔との窓口として会話になる
    let speaker: Speaker
    let at: Date
}

/// セルをクリックした先に出す、1回ぶんの書き込み
struct WriteEntry: Identifiable {
    let id: Int
    let role: String
    let at: Date
    let added: Int
    let removed: Int
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
    /// ponytail: 環境や使い方で最適値は動くので、決め打ちにせず外から変えられる形にしてある。
    /// 保存は View 側の @AppStorage が持つ（ここが UserDefaults を読むと自己チェックが
    /// 実機の設定に左右されて再現しなくなる）
    var flagReadThreshold = 3
    static let thresholdKey = "flagReadThreshold"
    /// 起動機能の有効化フラグ。View や Settings から @AppStorage で参照される。
    /// キーの文字列を1箇所で管理し、片方だけを直したときに黙ってずれるバグを防ぐ
    static let launcherEnabledKey = "launcherEnabled"
    /// Claude Code のパス指定。View や Settings から @AppStorage で参照される。
    /// キーの文字列を1箇所で管理し、片方だけを直したときに黙ってずれるバグを防ぐ
    static let claudePathKey = "claudePath"
    static let codexPathKey = "codexPath"
    static let grokPathKey = "grokPath"

    /// 画面に並べるファイル数の上限（最終接触が新しい順）
    static let maxFiles = 48
    /// 構造は全体像を優先するが、数千セルを毎フレーム組む負荷は避ける。
    /// Release・幅1100・400セルを2000回組んだ実測で平均0.44ms
    static let maxStructureFiles = 400
    /// チップの上限。終了したエージェントは「クリア」まで残す設計なので、
    /// 溜まりすぎた分は件数チップに畳み、消えたこと自体は隠さない
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
        /// 最後に考えた時刻。ツールを呼ばずに考えている間、`latest` は前の作業のまま止まるので、
        /// これと比べないと「1つ前にやったこと」を今やっているかのように出してしまう
        var thoughtAt: Date?
        /// 最後にツールを呼んだ時刻。`thoughtAt` との新しさ比べに使う
        var actedAt: Date?
        /// 累積トークン消費（重み付き）。**`Snowman.Reading.tokens` とは別物**——
        /// あちらはメインセッションの文脈の大きさであり、こちらはこのエージェント自身が消費した量
        var spent: Double = 0

        /// 待機（sleep）を除いた、観測できたツール呼び出し回数
        var observedWork: Int {
            counts.reduce(0) { $1.key.counts ? $0 + $1.value : $0 }
        }
    }

    /// MCP の内部作業は transcript に出ないため、ここで数えるのは依頼した回数だけ
    private struct MCPRecord {
        var session: String
        var server: String
        var parent: String
        var prompt: String
        var calls: Int
        var done: Bool
        var lastAt: Date
    }

    private(set) var touches: [Touch] = []
    private var index: [String: Int] = [:]          // tool_use_id -> touches の位置
    private var seenActions: Set<String> = []       // "<session>#<agent>#<tool_use_id>"
    private var agents: [String: AgentRecord] = [:]
    private var mcpWorkers: [String: MCPRecord] = [:]
    private var mcpCallKey: [String: String] = [:]   // tool_use_id -> 呼び出し中または thread の鍵
    /// 台帳を消すと履歴の役割名が hex に戻るため、表示だけを止める。
    /// 集合ではなく「いつ隠したか」を持つ。集合＋即時 remove だと、過去の行を1件読み直しただけで
    /// 活動とみなして復活してしまい、隠した分がまとめて戻る
    private var hiddenAt: [String: Date] = [:]
    /// 終わったエージェントを自動で隠すまでの無音。手で押さなくても溜まらないようにする。
    /// 完了直後に消すと「何が終わったか」を見る間が無いので、stuckAfter と同じ長さを取る
    static let autoHideAfter: TimeInterval = 120
    /// 返ってこない MCP 呼び出しを「進行中」とみなす上限。
    /// 実測で codex の1往復は15〜40分かかるので、エージェントの stuckAfter では短すぎる。
    /// ponytail: 1時間で頭打ち。これを超える外部作業を扱うなら、サーバーごとに変える
    static let mcpStuckAfter: TimeInterval = 3600
    private var callIssuer: [String: String] = [:]  // 呼び出しID -> 発行したエージェント

    /// 進行表。キーは "<session>#<taskId>"
    private var tasks: [String: RoadmapTask] = [:]
    private var taskCall: [String: String] = [:]    // TaskCreate の tool_use_id -> 上のキー
    /// 番号が付く前の TaskCreate。結果の行が来るまでここで待つ
    private var pendingTasks: [String: RoadmapTask] = [:]
    /// 進行表に残す完了済みの数。グレーアウトしていく様子は見せたいが、
    /// 実測で1セッション最大200件なので全部並べると画面が埋まる
    /// 進行表の帯（`progressStrip`）も同じ値で畳むので、隔離の外に出しておく
    nonisolated static let keptCompleted = 3

    /// ここより前の記録は畳み込みで無視する。実装の区切りで押す「クリア」の実体
    private(set) var clearedAt: Date?

    var selectedSession: String?
    var liveSessions: [LiveSession] = []
    private(set) var activeSessions: Set<String> = []
    private(set) var recentSessions: [RecentSession] = []
    private let projectsRoot: URL
    private var loadedSessions: Set<String> = []
    private var loadingSessions: Set<String> = []
    private var loadedSessionTabs: [String: LiveSession] = [:]
    private var lastRecentScan = Date.distantPast
    private var scanningRecent = false
    /// メニューは毎秒開かれうるが、transcript の更新時刻を秒単位で追う必要はない
    static let recentScanInterval: TimeInterval = 10
    nonisolated static let maxRecentSessions = 30

    /// 記憶DB。エージェントが主に書き、AT22 は表示と人間による既存ノートの編集を担う。
    /// 置き場は `~/.claude/projects/<プロジェクト>/memory/`——AT22 は配布物なので、
    /// 入れた人の誰にでもある場所でないと成立しない（Vault は作った人の環境にしか無い）
    private(set) var memory: [Memory.Node] = []
    private var memoryRoot: URL?
    /// 置換失敗と読み返し不一致を実ファイルで再現する自己チェック用の差し替え口
    var replaceNoteForProbe: ((URL, URL) throws -> URL?)?

    /// 答え待ちで止まっている指示。**司令塔は Bash の待ちループの中で本当に止まっている**ので、
    /// ここが空になるまで向こうは進めない。読むだけで、止めているのは AT22 ではない
    private(set) var gates: [Gate.Request] = []
    /// 承認の強さ。正は `memory/gate/LEVEL` の中身——司令塔も同じファイルを読むので、
    /// UserDefaults に置くと向こうから見えない
    private(set) var gateLevel = Gate.defaultLevel
    /// AT22 が起こした／繋いだ接続。キーはセッションID。終了まで手元に置いて、落ちた理由を拾う。
    /// `token` は繋ぐたびに新しくする——同じセッションへ繋ぎ直した後に古いプロセスが終わった時、
    /// 新しい方まで片付けないため
    private struct Run {
        let connection: any AgentConnection
        let token: UUID
    }
    private var runs: [String: Run] = [:]
    /// 人の返事を待っている承認の依頼。答えると消える
    private(set) var approvals: [Approval] = []
    /// ターンを回している AT22 の接続。送った時に開き、ターンの終わり・失敗・接続の終了で閉じる。
    /// **ここを持つまで、起こしたセッションのタブは busy のまま固定で**、Codex は終わっても
    /// 「処理中」に見え続けていた（`-p` の claude は `~/.claude/sessions` に載らないので同じ）
    private var openTurns: Set<String> = []
    /// 最後のターンが失敗したセッション。サイドバーの赤い印。次に送ると消える
    private(set) var failedTurns: Set<String> = []
    private(set) var launchError: String?
    /// 人がセッションごとに選んだモデル。**選ばれていない間は渡さない**——
    /// `--resume` にモデルを渡さなければ、claude は元のセッションの設定をそのまま引き継ぐ
    private var sessionModel: [String: String] = [:]
    /// stdout から拾っている部分テキスト。確定は transcript の担当——ここは「いま書いている途中」だけ。
    /// ターン終了で消える。**セッションごとに持つ**——1本にまとめていた頃は、どれか1つが
    /// 書いている間、`isWorking` が全セッションを稼働中と答えていた
    private(set) var streaming: [String: String] = [:]
    /// セッションごとの、受領確認を待っている割り込みの request_id。
    /// ここを持つことで、投げっぱなし（応答の見落とし）と、誤報（止まり損ない）を防ぐ
    private var interruptRequests: [String: String] = [:]
    /// 人が止めたターン。claude は止めたターンを `error_during_execution` で終えるので、
    /// ここに無いと「自分で止めたのに失敗」と出てしまう（実機で確認）
    private var stopping: Set<String> = []

    /// モデルが書いた言葉。tool_use しか見ていなかったので、これまで画面に出ていなかった分
    private(set) var messages: [Message] = []
    /// 実測1セッションで text 256件 / thinking 297件。数セッションぶん抱えても軽いが、
    /// 上限は置く（1件が数千字になることがある）
    static let maxMessages = 4000

    /// 司令塔がサブエージェントを呼んだ記録。**会話の流れに1行として混ぜるためだけ**に持つ。
    /// 作業そのものは盤面のエージェント帯が語るので、ここは「呼んだ」ことしか語らない
    struct AgentCall: Identifiable, Sendable {
        let id: String          // Agent ツールの tool_use id
        let session: String
        let by: String          // 呼んだ側のエージェントID
        let type: String        // subagent_type（Explore / general-purpose …）
        let title: String       // description（作業内容の1行）
        let at: Date
    }
    private(set) var agentCalls: [AgentCall] = []
    /// 実測で1セッション数十件。上限は messages と同じ考え方で置くだけ
    nonisolated static let maxAgentCalls = 500

    /// 会話に出す呼び出し。**その実体が終わっているか**は台帳から引く
    func agentCalls(session: String?) -> [AgentCall] {
        agentCalls.filter { session == nil || $0.session == session }
    }

    /// この呼び出しで起きたエージェントが終わっているか。`nil` はまだ結びついていない
    func callFinished(_ call: String) -> Bool? {
        guard let record = agents.values.first(where: { $0.parentCall == call }) else { return nil }
        return record.doneAt != nil
    }

    /// 文脈の膨らみ。セッションごと
    private(set) var readings: [String: Snowman.Reading] = [:]

    /// 見ているセッションの雪だるま。選んでいなければ稼働中の先頭
    var reading: Snowman.Reading {
        readings[selectedSession ?? liveSessions.first?.id ?? ""] ?? Snowman.Reading()
    }

    /// codex セッション台帳（内部セッションID → threadID・題名等）
    /// UserDefaults（キー "codexSessions"）で読み書き
    private(set) var runRecords: [RunRecord] = []

    /// セッションのバックエンド種別（claude または codex）
    private var backends: [String: Backend] = [:]

    /// AT22 が起こした、transcript を AT22 が読まない相手（Codex / ACP）のセッション台帳。
    /// UserDefaults で永続化し、アプリを閉じても続きに繋げるようにする
    struct RunRecord: Codable, Identifiable {
        var id: String              // 内部セッションID（UUID lowercased）
        /// 相手側のID（codex の thread / ACP の sessionId）。続きに繋ぐ時に使う
        var threadID: String?
        var title: String
        var cwd: String
        var model: String
        var lastUsed: Date
        /// どのエージェントか。項目の無い古い記録は codex（台帳を持っていたのは codex だけだった）
        var backend: Backend

        enum CodingKeys: String, CodingKey {
            case id, threadID, title, cwd, model, lastUsed, backend
        }

        init(id: String, threadID: String?, title: String, cwd: String, model: String,
             lastUsed: Date, backend: Backend) {
            (self.id, self.threadID, self.title, self.cwd, self.model, self.lastUsed, self.backend)
                = (id, threadID, title, cwd, model, lastUsed, backend)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            threadID = try c.decodeIfPresent(String.self, forKey: .threadID)
            title = try c.decode(String.self, forKey: .title)
            cwd = try c.decode(String.self, forKey: .cwd)
            model = try c.decode(String.self, forKey: .model)
            lastUsed = try c.decode(Date.self, forKey: .lastUsed)
            backend = try c.decodeIfPresent(Backend.self, forKey: .backend) ?? .codex
        }
    }

    /// コード構造。ファイル同士の依存。走査は重いので裏で回して結果だけ受け取る
    private(set) var structure = Structure.Graph()
    private var scanRoots: Set<String> = []
    private var lastScan = Date.distantPast
    private var scanning = false
    private var wroteSinceScan = false
    /// 書き込みがあってからこれだけ空けて張り直す。1回147ms（実測99ファイル）なので
    /// 毎回でも回せるが、裏に投げっぱなしにすると常時走り続ける
    static let rescanInterval: TimeInterval = 10

    /// 動きがある間だけ真。描画側がこれを見てフレームレートを落とす
    private(set) var isBusy = false
    private var lastActivity = Date.distantPast
    private var pending = 0

    init(projectsRoot: URL? = nil) {
        self.projectsRoot = projectsRoot
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        // codex 台帳を UserDefaults から読み込み
        loadRunRecords()
    }

    /// codex 台帳を UserDefaults から読み込む
    private func loadRunRecords() {
        guard let data = UserDefaults.standard.data(forKey: "codexSessions") else { return }
        if let decoded = try? JSONDecoder().decode([RunRecord].self, from: data) {
            runRecords = decoded
        }
    }

    /// codex 台帳を UserDefaults に保存
    private func saveRunRecords() {
        if let encoded = try? JSONEncoder().encode(runRecords) {
            UserDefaults.standard.set(encoded, forKey: "codexSessions")
        }
    }

    /// codex 台帳から既存セッションをライブセッション化（プロセスはまだ起動しない）
    func resumeRunRecord(_ record: RunRecord) {
        // ライブセッションに追加（プロセスはまだ無し）
        let tab = LiveSession(id: record.id, name: String(record.id.prefix(8)),
                             cwd: record.cwd, busy: false)
        loadedSessionTabs[record.id] = tab
        if !liveSessions.contains(where: { $0.id == record.id }) {
            liveSessions.append(tab)
            liveSessions.sort { $0.name < $1.name }
        }

        backends[record.id] = record.backend

        // 案内メッセージを追加
        messages.append(Message(
            id: messages.count,
            session: record.id,
            agent: record.id,
            text: "以前のやり取りはこの画面には出ません（今回の分から表示）",
            thinking: false,
            speaker: .model,
            at: Date()))

        selectedSession = record.id
        refreshLiveSessions()
    }

    // MARK: 取り込み

    func apply(_ events: [TranscriptEvent]) {
        for event in events {
            switch event {
            case let .touchStarted(id, session, agent, path, kind, at):
                guard index[id] == nil else { break }   // 同じ行を二度読んだ場合の保険
                touches.append(Touch(session: session, agent: agent, path: path, kind: kind, started: at))
                index[id] = touches.count - 1
                pending += 1
                if kind == .write { wroteSinceScan = true }   // 構造が変わったかもしれない
                // 触りだけでも台帳に載せる。assistant 行の取りこぼしでチップごと消えないように
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                record.lastAt = max(record.lastAt, at)
                agents[agent] = record

            case let .touchFinished(id, added, removed, at):
                finishMCP(call: id, at: at)
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

            case let .agentAction(id, agent, session, kind, detail, at):
                guard seenActions.insert("\(session)#\(agent)#\(id)").inserted else { break }
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                record.counts[kind, default: 0] += 1
                record.latest = (kind, detail)
                record.lastAt = max(record.lastAt, at)
                record.actedAt = max(record.actedAt ?? at, at)
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

            case let .agentSpawn(call, by, session, type, title, at):
                callIssuer[call] = by
                // 会話の流れに「呼んだ」ことを混ぜるための記録。同じ呼び出しは1回だけ
                if !agentCalls.contains(where: { $0.id == call }) {
                    agentCalls.append(AgentCall(id: call, session: session, by: by,
                                                type: type, title: title, at: at))
                    if agentCalls.count > Self.maxAgentCalls {
                        agentCalls.removeFirst(agentCalls.count - Self.maxAgentCalls)
                    }
                }

            case let .taskDeclared(call, session, subject, activeForm, detail, at):
                pendingTasks[call] = RoadmapTask(id: "", session: session, number: 0,
                                                 subject: subject, activeForm: activeForm,
                                                 detail: detail, status: .pending, at: at)

            case let .taskNumbered(call, number):
                guard let waiting = pendingTasks.removeValue(forKey: call) else { break }
                let key = "\(waiting.session)#\(number)"
                taskCall[call] = key
                // 番号が決まってから積む。順番から推測すると、セッション再開でずれる
                tasks[key] = RoadmapTask(id: key, session: waiting.session,
                                         number: Int(number) ?? tasks.count,
                                         subject: waiting.subject, activeForm: waiting.activeForm,
                                         detail: waiting.detail, status: .pending, at: waiting.at)

            case let .taskStatus(session, number, status, at):
                let key = "\(session)#\(number)"
                guard var task = tasks[key] else { break }   // 起動前に作られた分は知らない
                task.status = status
                task.at = at
                tasks[key] = task

            case let .mcpCalled(call, session, by, server, tool, prompt, at):
                guard mcpCallKey[call] == nil else { break }
                // prompt の無い呼び出しは仕事を任せたのではなく、道具を使っただけ（ブラウザ操作・検索など）。
                // 1回ごとに1体にすると、実測でブラウザ操作85回が85行になって帯を埋めた。
                // 呼んだエージェント × サーバで1体に束ね、回数を労働量として積む
                let key = prompt.isEmpty ? "mcp-tool:\(session)#\(by)#\(server)" : "mcp-call:\(call)"
                mcpCallKey[call] = key
                if prompt.isEmpty, var worker = mcpWorkers[key] {
                    worker.calls += 1
                    worker.prompt = tool
                    worker.done = false
                    worker.lastAt = max(worker.lastAt, at)
                    mcpWorkers[key] = worker
                } else {
                    mcpWorkers[key] = MCPRecord(session: session, server: server, parent: by,
                                                prompt: prompt.isEmpty ? tool : prompt,
                                                calls: 1, done: false, lastAt: at)
                }

            case let .mcpThread(call, thread):
                mergeMCP(call: call, thread: thread)

            case let .said(agent, session, text, speaker, thinking, at):
                messages.append(Message(id: messages.count, session: session, agent: agent,
                                        text: text, thinking: thinking, speaker: speaker, at: at))
                if messages.count > Self.maxMessages { messages.removeFirst(messages.count - Self.maxMessages) }
                // 考えた印。モデルが考えた時だけ thoughtAt を進める。人間の発言で思考中になってはいけない
                // ツールを呼ばずに考えている間、`latest` は前の作業のまま止まる
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                record.lastAt = max(record.lastAt, at)
                if speaker == .model && thinking { record.thoughtAt = max(record.thoughtAt ?? at, at) }
                agents[agent] = record

            case let .context(session, agent, tokens, spend, at):
                // サブエージェントの文脈量が親セッションの雪だるまに混入するバグを防ぐ。
                // メインセッション行（`agent == session`）だけが雪だるまを動かす。
                // サブエージェント行（`agent != session`）は台帳に費用を足すだけで、
                // 親の `readings[session]` には触らない。こうしないと、直近サブエージェントと
                // メインセッションの間で雪だるまが行き来する
                if agent == session {
                    Snowman.observe(&readings[session, default: Snowman.Reading()], tokens: tokens)
                }
                // 台帳に消費量を積む。まだ無いエージェントでも作る（`.said` の受けと同じ作法）。
                // loadSession が二度目の replay を弾くので同じ行を二度読まない前提で、
                // seenContexts による排除はしない（既存の `.agentAction` と同じ）。
                // 仮に重複しても、share は同一セッション内の比なので分子分母が同じだけ増えて割合は変わらず、
                // 絶対値の spent は work と同じ性質の誤差を持つ
                var record = agents[agent] ?? AgentRecord(session: session, lastAt: at)
                record.spent += spend
                record.lastAt = max(record.lastAt, at)
                agents[agent] = record

            case let .compacted(session, before, after, _):
                Snowman.compact(&readings[session, default: Snowman.Reading()],
                                before: before, after: after)
            }
        }
        trimIfNeeded()
        lastActivity = Date()
        if !isBusy { isBusy = true }
    }

    /// 結果が届いた時刻まで `lastAt` を進める。ここを止めると、飛行中に畳まれたワーカーが
    /// 完了しても二度と戻らない（`buildChips` の復帰条件が `lastAt > hidden` のため）。
    /// エージェント側で `agentActivity` が `lastAt` を進めているのと同じ作法
    private func finishMCP(call: String, at: Date) {
        guard let key = mcpCallKey[call], var worker = mcpWorkers[key] else { return }
        worker.done = true
        worker.lastAt = max(worker.lastAt, at)
        mcpWorkers[key] = worker
    }

    /// threadId が返るまでは呼び出しIDで置き、判明した時点で過去の同一スレッドへ合流する
    private func mergeMCP(call: String, thread: String) {
        // 束ねた道具の1体（mcp-tool:）はスレッドを持たない。ここで動かすと束ごと消える
        guard let oldKey = mcpCallKey[call], oldKey.hasPrefix("mcp-call:"),
              let current = mcpWorkers.removeValue(forKey: oldKey) else { return }
        let key = "mcp-thread:\(current.server)#\(thread)"
        var merged = mcpWorkers[key] ?? current
        if mcpWorkers[key] != nil {
            merged.calls += current.calls
            if current.lastAt >= merged.lastAt {
                merged.prompt = current.prompt
                merged.parent = current.parent
                merged.server = current.server
                merged.session = current.session
                merged.lastAt = current.lastAt
            }
            merged.done = current.done
        }
        mcpWorkers[key] = merged
        mcpCallKey[call] = key
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
        refreshRecentSessionsIfNeeded()
        refreshStructureIfNeeded()
        refreshMemory()
        refreshGates()
        refreshWorktreesIfNeeded()
        autoHideIdleAgents(now: Date())
    }

    /// 記憶DBに書く。**AT22 が書くのはここだけ**——コードにも transcript にも触らない。
    /// 一時ファイルに書き、編集中の基準版が変わっていないことを置換直前に確かめる。
    /// 置換後は返されたURLを読み、内容が一致した時だけ成功にする
    /// （構想ノートの「アトミック書き込み → 読み返して検証」の踏襲）。
    /// 人間とエージェントが同じファイルを書くので、壊れた状態を残さないことが要る
    /// - Parameter creating: まだ無いファイルを作ってよいか。門の答え（`gate/<id>.verdict`）と
    ///   承認モード（`gate/LEVEL`）だけがこれを使う。置き場のガードは通常の経路と同じものを通す
    @discardableResult
    /// - Parameter project: 書き込む先のプロジェクト（`~/.claude/projects/<slug>`）。省略すると
    ///   選択中のセッションのもの。**どちらでも置き場のガードは同じ**——`projects/` の直下で、
    ///   その `memory/` の内側だけ
    func saveNote(path: String, text: String, expectedText: String? = nil,
                  overwrite: Bool = false, creating: Bool = false, project explicit: URL? = nil) -> NoteSaveResult {
        let manager = FileManager.default
        let projects = projectsRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let root = explicit ?? memoryRoot else { return .failed }
        let project = root.standardizedFileURL.resolvingSymlinksInPath()
        let memory = root.appendingPathComponent("memory").standardizedFileURL.resolvingSymlinksInPath()
        guard project.path.hasPrefix(projects.path + "/"),
              memory.lastPathComponent == "memory",
              memory.deletingLastPathComponent().path == project.path else { return .failed }

        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(memory.path + "/") else { return .failed }

        // 新規作成だけは置換ではなく素の書き込みで済ませる。`replaceItemAt` は元が要るし、
        // `String.write(atomically:)` が一時ファイル＋rename を自前でやる
        if creating, !manager.fileExists(atPath: url.path) {
            do {
                try manager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                // 掘った後にもう一度確かめる。`gate/` 自体が外へのシンボリックリンクだと、
                // 掘った先が置き場の外になりうる
                let settled = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                guard settled.path.hasPrefix(memory.path + "/") else { return .failed }
                try text.write(to: settled, atomically: true, encoding: .utf8)
                let matches = (try? String(contentsOf: settled, encoding: .utf8)) == text
                refreshMemory()
                return matches ? .saved : .failed
            } catch {
                return .failed
            }
        }

        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return .failed }

        // 同時起動と、同名のディレクトリを一時ファイルとして消す事故を避ける
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        var removeTemporary = true
        defer { if removeTemporary { try? manager.removeItem(at: tmp) } }
        do {
            try text.write(to: tmp, atomically: false, encoding: .utf8)
            if !overwrite, let expectedText,
               (try? String(contentsOf: url, encoding: .utf8)) != expectedText {
                refreshMemory()
                return .conflict
            }
            let saved: URL?
            if let replaceNoteForProbe {
                saved = try replaceNoteForProbe(url, tmp)
            } else {
                saved = try manager.replaceItemAt(url, withItemAt: tmp)
            }
            guard let saved else {
                refreshMemory()
                return .failed
            }
            // ファイルプロバイダが一時URLを結果として返した場合、その実体まで掃除しない
            removeTemporary = saved.standardizedFileURL != tmp.standardizedFileURL
            let matches = (try? String(contentsOf: saved, encoding: .utf8)) == text
            refreshMemory()
            return matches ? .saved : .failed
        } catch {
            return .failed
        }
    }

    /// 記憶DBの置き場。無ければ作る先を返すだけで、ここでは作らない
    func memoryDirectory() -> URL? { memoryRoot?.appendingPathComponent("memory") }

    /// パスから記憶DBの1本を引く。押した先で中身を出すのに使う
    func memoryNode(at path: String) -> Memory.Node? { memory.first { $0.id == path } }

    /// 検査から記憶DBを直接流し込む口。実機の `memory/` に依存させないため
    func loadMemoryForProbe(_ nodes: [Memory.Node]) { memory = nodes }

    // MARK: 門（人間の介入）

    /// 止まっている門と承認の強さを読み直す。`refreshMemory` と同じ毎秒の周回に乗せる。
    /// ponytail: ディレクトリを1つ読むだけ。門は同時に数件しか開かない
    func refreshGates() {
        // 検査・画像焼きから流し込んだ門は実ファイルの裏付けを持たないので、
        // 毎秒の読み直しで消される。流し込んだ間はこの周回を止める
        guard !gatesArePinned else { return }
        guard let dir = memoryDirectory() else {
            if !gates.isEmpty { gates = [] }
            return
        }
        let found = Gate.pending(memoryRoot: dir)
        if found.map(\.id) != gates.map(\.id) { gates = found }
        let level = Gate.level(memoryRoot: dir)
        if level != gateLevel { gateLevel = level }
    }

    /// 門に答える。**書けなかったら必ず呼び出し元に返す**——
    /// 黙って画面から消すと、司令塔は答えが来ないまま待ち続ける
    @discardableResult
    func answer(_ request: Gate.Request, _ verdict: Gate.Verdict,
                revised: String = "", at: Date = Date()) -> NoteSaveResult {
        let result = saveNote(path: Gate.verdictPath(for: request),
                              text: Gate.verdictText(verdict, at: at, revised: revised),
                              creating: true)
        if result == .saved { refreshGates() }
        return result
    }

    /// 承認の強さを変える。ファイルが正なので、選んだその場で書く
    /// - Parameter cwd: これから起こすセッションの作業ディレクトリ。渡すと**そのプロジェクト**の
    ///   `LEVEL` に書く（まだ transcript が無くても書ける）。省略すると選択中のセッションのもの
    @discardableResult
    func setGateLevel(_ level: Gate.Level, cwd: String? = nil) -> NoteSaveResult {
        let project = cwd.map { projectsRoot.appendingPathComponent(Self.projectSlug($0)) } ?? memoryRoot
        guard let project else { return .failed }
        let result = saveNote(path: Gate.levelPath(memoryRoot: project.appendingPathComponent("memory")),
                              text: level.rawValue + "\n", creating: true, project: project)
        // 表示している段は選択中のセッションのもの。別プロジェクトに書いた時は変えない
        if result == .saved, project.standardizedFileURL == memoryRoot?.standardizedFileURL { gateLevel = level }
        return result
    }

    /// 検査から門を直接流し込む口
    func loadGatesForProbe(_ requests: [Gate.Request]) {
        gates = requests
        gatesArePinned = true
    }
    /// 流し込んだ門を毎秒の読み直しから守る。**検査と画像焼きだけが立てる**
    private var gatesArePinned = false

    // MARK: 起動

    /// CLI の在り処。見つかるまでそのエージェントの起動UIは出さない（配布先で「押しても無反応」にしない）
    private(set) var found: [Backend: Launcher.Found] = [:]
    private var lookedFor: Set<Backend> = []
    /// デバウンス用。設定画面でパスを打つたびにログインシェルを立てないよう、前の探索を取り消して待つ
    private var lookups: [Backend: Task<Void, Never>] = [:]
    var claude: Launcher.Found? { found[.claude] }
    var codexFound: Launcher.Found? { found[.codex] }
    var grokFound: Launcher.Found? { found[.grok] }

    /// ログインシェルを起こして CLI を探す。既定は1回だけだが、設定でパスを変えた時は再探索
    func findIfNeeded(_ backend: Backend, override: String? = nil, force: Bool = false) {
        guard force || !lookedFor.contains(backend) else { return }
        lookedFor.insert(backend)
        if force { lookups[backend]?.cancel() }
        lookups[backend] = Task.detached(priority: .utility) {
            // force のときだけ待つ。起動時（force: false）は遅延なく実行
            if force {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            let result = Launcher.locate(override: override, command: backend.command)
            await MainActor.run { [weak self] in self?.found[backend] = result }
        }
    }

    /// Claude Code または Codex を起こす。**採番した UUID をそのまま選択セッションにする**ので、
    /// transcript（claude の場合）が書かれ始めた瞬間から起こした先が画面に出る
    /// - Parameters:
    ///   - prompt: 最初の指示
    ///   - cwd: 作業ディレクトリ
    ///   - backend: .claude または .codex（デフォルト: .claude）
    ///   - model: モデルID（例: "opus", "gpt-5.3-codex"）。空なら既定値を使用
    ///   - allowedTools: 白名簿（claude のみ）
    ///   - level: 承認の段。省略すると選択中のセッションの段を使う
    @discardableResult
    func launch(prompt: String, cwd: String, backend: Backend = .claude, model: String = "",
                allowedTools: [String] = [], level: Gate.Level? = nil) -> UUID? {
        let level = level ?? gateLevel
        switch backend {
        case .claude:
            return launchClaude(prompt: prompt, cwd: cwd, model: model, allowedTools: allowedTools,
                                level: level)
        case .codex:
            return launchCodex(prompt: prompt, cwd: cwd, model: model, level: level)
        case .grok:
            return launchGrok(prompt: prompt, cwd: cwd, model: model, level: level)
        }
    }

    private func launchClaude(prompt: String, cwd: String, model: String,
                              allowedTools: [String], level: Gate.Level) -> UUID? {
        guard let claude else {
            launchError = "claude が見つからない"
            return nil
        }
        // 司令塔は起きてすぐ `memory/gate/LEVEL` を読むので、起こす前に**起こす先のプロジェクトへ**書く。
        // 選択中のセッションの記憶DBに書いていた頃は、別プロジェクトの司令塔の段が変わっていた
        setGateLevel(level, cwd: cwd)
        let config = Launcher.Config(cwd: cwd, level: level,
                                     prompt: prompt, allowedTools: allowedTools, model: model)
        let sessionID = UUID()
        // transcript のファイル名は小文字。合わせておかないと起こした本人を見失う
        let id = sessionID.uuidString.lowercased()
        let token = UUID()

        do {
            let connection = try ClaudeConnection.start(
                config, using: claude, session: id, sessionID: sessionID,
                onEvent: agentStream(session: id),
                onExit: exitHandler(label: "claude", session: id, token: token))
            runs[id] = Run(connection: connection, token: token)
            backends[id] = .claude
            launchError = nil

            // `.jsonl` はまだ無い。タブを先に立てておかないと、起こした直後の数秒が行方不明になる
            loadedSessionTabs[id] = LiveSession(id: id, name: String(id.prefix(8)),
                                                cwd: cwd, busy: false)
            beginTurn(id)
            selectedSession = id
            refreshLiveSessions()
            return sessionID
        } catch {
            launchError = "\(error)"
            return nil
        }
    }

    /// **AT22 が起こしていないセッションの続きに繋ぐ。**
    ///
    /// 履歴から開いたものや端末で始まったものには stdin が無く、そのままでは人間が言葉を送れない。
    /// 送ろうとした瞬間に `claude --resume` を起こし、以後はふつうの送信と同じ経路になる。
    /// 同じ `<セッションID>.jsonl` の続きが書かれるので、会話も盤面も既存の読み取り経路のまま繋がる。
    ///
    /// ponytail: 繋ぐのは送信の直前だけ。開いて眺めているだけのセッションでプロセスは起こさない
    @discardableResult
    func attach(to session: String) -> Bool {
        if runs[session] != nil { return true }
        guard backend(of: session) == .claude else { return false }
        guard let claude else {
            launchError = "claude が見つからない。設定で場所を指定する"
            return false
        }
        guard let cwd = liveSessions.first(where: { $0.id == session })?.cwd, !cwd.isEmpty else {
            launchError = "このセッションの作業ディレクトリが分からない"
            return false
        }

        // 言葉は空で繋ぐだけ。最初の1件も呼び出し側の `send` が流す（送る口を1本に保つ）。
        // モデルは人が明示した時だけ渡す——渡さなければ claude は元のセッションの設定を引き継ぐ
        let config = Launcher.Config(cwd: cwd, level: gateLevel, prompt: "",
                                     model: sessionModel[session] ?? "")
        let token = UUID()
        do {
            let connection = try ClaudeConnection.start(
                config, using: claude, session: session, resuming: session,
                onEvent: agentStream(session: session),
                onExit: exitHandler(label: "claude", session: session, token: token))
            runs[session] = Run(connection: connection, token: token)
            backends[session] = .claude
            launchError = nil
            return true
        } catch {
            launchError = "\(error)"
            return false
        }
    }

    /// 人が選んだモデル。**繋ぎ直すまで効かない**ので、ターンの合間なら今の接続を畳んでおく。
    /// 次に送った時に新しいモデルで繋がる（`claude -p` も codex も、走っている最中には切り替えられない）
    func setModel(_ model: String, for session: String) {
        sessionModel[session] = model
        // codex は台帳のモデルで繋ぐ。以前はここを書き換えず、選び直しても効いていなかった
        if let index = runRecords.firstIndex(where: { $0.id == session }) {
            runRecords[index].model = model
            saveRunRecords()
        }
        guard let run = runs[session], run.connection.acceptsInput else { return }
        run.connection.close()
        forget(session)
    }

    /// そのセッションが実際に使っているモデル。transcript から観測した値
    func model(of session: String) -> String? {
        sessionModel[session] ?? agents[session]?.model
    }

    /// 接続を手放す。書きかけ・割り込み待ち・答え待ちの承認も一緒に消す
    private func forget(_ session: String) {
        runs[session] = nil
        streaming[session] = nil
        interruptRequests[session] = nil
        stopping.remove(session)
        openTurns.remove(session)
        approvals.removeAll { $0.session == session }
    }

    /// 終わった時の後始末。起こす／繋ぐで同じものを使う。
    /// 片付けるのは `token` が合う時だけ——モデルの切り替えで閉じた古いプロセスが、
    /// 繋ぎ直した後に終わることがあり、そこで消すと新しい接続まで捨ててしまう
    private func exitHandler(label: String, session: String, token: UUID) -> @Sendable (Int32, String) -> Void {
        { status, errors in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.runs[session]?.token == token { self.forget(session) }
                guard status != 0 else { return }
                self.launchError = errors.isEmpty
                    ? "\(label) が終了コード \(status) で終わった" : errors
            }
        }
    }

    /// 接続の出来事を状態に反映するハンドラ。**起こす時と繋ぐ時で同じもの**を使う——
    /// 2本に割ると、片方だけ直して挙動が食い違う。
    /// `readabilityHandler` は別スレッドで走るので、MainActor に載せ替える
    private func agentStream(session: String) -> @Sendable (AgentEvent) -> Void {
        { event in
            Task { @MainActor [weak self] in self?.handle(event, session: session) }
        }
    }

    /// 接続から来た出来事を1件、そのセッションの状態に反映する。自己チェックが直接叩く
    func handle(_ event: AgentEvent, session: String) {
        switch event {
        case let .ready(remoteID):
            // 続きに繋ぐための相手側の ID。アプリを閉じても続けられるよう台帳に残す
            if let index = runRecords.firstIndex(where: { $0.id == session }) {
                runRecords[index].threadID = remoteID
                saveRunRecords()
            }

        case let .partial(text):
            // 部分テキスト。ターン終了で消える
            streaming[session, default: ""] += text

        case let .message(text, thinking):
            // transcript を AT22 が読まない相手の確定した発言。transcript 由来と同じ入口に通すので、
            // 会話にも盤面のチップにも同じ規則で出る
            apply([.said(agent: session, session: session, text: text, speaker: .model,
                         thinking: thinking, at: Date())])

        case let .said(text):
            apply([.said(agent: session, session: session, text: text, speaker: .human,
                         thinking: false, at: Date())])

        case let .tool(id, kind, title, path, write, done):
            // 道具の呼び出し。transcript の tool_use と同じ出来事に直して、労働量・「今していること」・
            // ファイルの触りを盤面に出す。開始と完了が別々に来る相手（ACP）は、2回目は閉じるだけ
            let now = Date()
            var events: [TranscriptEvent] = [
                .agentActivity(agent: session, session: session, model: model(of: session), at: now),
                .agentAction(id: id, agent: session, session: session, kind: kind, detail: title, at: now),
            ]
            if let path {
                if index[id] == nil {
                    events.append(.touchStarted(id: id, session: session, agent: session, path: path,
                                                kind: write ? .write : .read, at: now))
                }
                if done { events.append(.touchFinished(id: id, added: 0, removed: 0, at: now)) }
            }
            apply(events)

        case let .approval(approval):
            approvals.append(approval)

        case let .turnEnded(tokens):
            // 確定メッセージは transcript（または `.message`）から来るので、書きかけは残さない
            streaming[session] = nil
            stopping.remove(session)
            openTurns.remove(session)
            if let tokens {
                Snowman.observe(&readings[session, default: Snowman.Reading()], tokens: tokens)
            }

        case let .turnFailed(reason):
            // 理由を launchError に載せる。握り潰すと司令塔が「成功した」と誤認する。
            // 書きかけは消す——失敗しても途中まで書けたと見えてはいけない
            streaming[session] = nil
            openTurns.remove(session)
            // 人が止めたターンの終わり方は失敗ではない。それ以外の理由なら止めた後でも出す
            // ponytail: 何も走っていない時に止めると印が次のターンまで残り、その次の
            // error_during_execution を1回だけ見逃す。止めるボタンは走っている間しか出ない
            if stopping.remove(session) != nil, reason == "error_during_execution" { break }
            failedTurns.insert(session)
            appendLaunchError("失敗: \(reason)")

        case let .interruptAcknowledged(requestID, stillQueued, cancelled):
            // 割り込みの受領確認。**そのセッションに**送った ID と照合する。
            // 握り潰すと、止め損ないが画面に現れず、司令塔が気づけない
            guard requestID == interruptRequests[session] else { break }
            // **`cancelled` は成功の印**（取り消せた件数）。ここで警告を出すと、
            // 完璧に止まったときに「止まっていない」と誤報することになる。
            // 止まり損ないを示すのは `stillQueued` だけ
            if stillQueued > 0 {
                appendLaunchError("割り込みが全部は通らず、\(stillQueued) 件残っている（取消 \(cancelled) 件）")
            }
            interruptRequests[session] = nil

        case let .error(message):
            appendLaunchError(message)
        }
    }

    /// 承認に答える。**呼ぶのは人のクリックだけ**。`input` を渡すと書き換えた入力で許可する。
    /// 送れなかった時（書き換えた入力が JSON として読めない等）は依頼を残して false——
    /// 黙って消すと、相手は答えを待ったまま止まり続ける
    @discardableResult
    func answer(_ approval: Approval, allow: Bool, input: String? = nil) -> Bool {
        guard runs[approval.session]?.connection.answer(approval, allow: allow, input: input) == true else {
            return false
        }
        approvals.removeAll { $0.id == approval.id }
        return true
    }

    /// 人の番で止まっているものの数（門＋道具の承認）。タブとステータスバーの件数
    var stoppedCount: Int { gates.count + approvals.count }

    /// 検査・画像焼きから承認の依頼を直接流し込む口
    func loadApprovalsForProbe(_ requests: [Approval]) { approvals = requests }

    /// ターンを開く。前のターンの「失敗」の印はここで消す
    private func beginTurn(_ session: String) {
        openTurns.insert(session)
        failedTurns.remove(session)
    }

    /// 割り込みを送ったことを覚える。受領確認の照合と、止めたターンの終わり方の見分けに使う
    func expectInterrupt(_ requestID: String, for session: String) {
        interruptRequests[session] = requestID
        stopping.insert(session)
    }

    private func appendLaunchError(_ message: String) {
        if let existing = launchError, !existing.isEmpty {
            launchError = existing + "\n" + message
        } else {
            launchError = message
        }
    }

    /// 人の発言は transcript から返ってくるまで画面に出ない。
    /// 押してから数秒何も起きないと「効いていない」に見えるので、送った側で先に置く
    private func appendHuman(_ text: String, session: String) {
        messages.append(Message(id: messages.count, session: session, agent: session,
                                text: text, thinking: false, speaker: .human, at: Date()))
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }

    private func launchCodex(prompt: String, cwd: String, model: String, level: Gate.Level) -> UUID? {
        guard let codex = codexFound else {
            launchError = "codex が見つからない"
            return nil
        }

        let sessionID = UUID().uuidString.lowercased()
        let connection = CodexConnection(
            found: codex, config: CodexLauncher.Config(cwd: cwd, level: level, prompt: "", model: model),
            threadID: nil, onEvent: agentStream(session: sessionID))
        guard connection.send(prompt) else {
            launchError = "codex を起動できなかった"
            return nil
        }
        runs[sessionID] = Run(connection: connection, token: UUID())
        backends[sessionID] = .codex

        // codex セッションをライブセッション・台帳に登録
        let tab = LiveSession(id: sessionID, name: String(sessionID.prefix(8)), cwd: cwd, busy: false)
        beginTurn(sessionID)
        loadedSessionTabs[sessionID] = tab
        liveSessions.append(tab)
        liveSessions.sort { $0.name < $1.name }
        appendHuman(prompt, session: sessionID)

        // 台帳に記録（最初は threadID は nil、thread が始まった時に入る）
        let title = Self.titleRule(prompt) ?? ""
        let record = RunRecord(id: sessionID, threadID: nil, title: title, cwd: cwd, model: model,
                               lastUsed: Date(), backend: .codex)
        runRecords.append(record)
        saveRunRecords()

        selectedSession = sessionID
        launchError = nil
        refreshLiveSessions()

        return UUID(uuidString: sessionID) ?? UUID()
    }

    /// 走っているセッションに割り込んで1件送る。
    ///
    /// **セッションが選ばれていれば送れる。**
    ///
    /// 以前は「AT22 が起こしたセッションだけ」だった。人が端末で開いている transcript を
    /// 2つのプロセスが書く事故を避けるためだったが、その結果**履歴から開いた会話には
    /// 一言も送れず、画面が行き止まりになっていた**。いまは送る直前に `connect` が
    /// 繋ぐので、口は常に1本のまま繋がる
    func canSend(to session: String?) -> Bool {
        guard let session else { return false }
        // codex は1ターン1プロセス。走っている間は次を受けられない（ボタンは停止に変わる）
        return runs[session]?.connection.acceptsInput ?? true
    }

    @discardableResult
    func send(_ text: String, to session: String?) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let session else { return false }

        // 繋がっていなければここで繋ぐ。**送ろうとした時が繋ぎ時**——
        // 開いて眺めているだけのセッションでプロセスを起こさない
        guard let run = runs[session] ?? connect(session) else {
            return false        // 理由は connect が launchError に載せている
        }
        guard run.connection.acceptsInput else {
            launchError = "まだ前のターンを処理している"
            return false
        }
        guard run.connection.send(body) else {
            forget(session)
            launchError = "送れなかった。セッションが終わっている"
            return false
        }
        beginTurn(session)
        appendHuman(body, session: session)
        return true
    }

    /// まだ繋がっていないセッションに繋ぐ。claude は `--resume`、codex は台帳の thread ID で続きへ
    private func connect(_ session: String) -> Run? {
        switch backend(of: session) {
        case .claude:
            return attach(to: session) ? runs[session] : nil
        case .codex:
            guard let codex = codexFound else {
                launchError = "codex が見つかりません"
                return nil
            }
            guard let record = runRecords.first(where: { $0.id == session }) else {
                launchError = "codex セッションが見つかりません"
                return nil
            }
            guard let thread = record.threadID else {
                launchError = "codex のスレッドID が不明です"
                return nil
            }
            let config = CodexLauncher.Config(cwd: record.cwd, level: gateLevel, prompt: "",
                                              model: sessionModel[session] ?? record.model)
            let run = Run(connection: CodexConnection(found: codex, config: config, threadID: thread,
                                                      onEvent: agentStream(session: session)),
                          token: UUID())
            runs[session] = run
            return run
        case .grok:
            guard let record = runRecords.first(where: { $0.id == session }), let remote = record.threadID else {
                launchError = "Grok のセッションが見つからない"
                return nil
            }
            return startGrok(session: session, cwd: record.cwd, model: sessionModel[session] ?? record.model,
                             level: gateLevel, resume: remote)
        }
    }

    /// Grok を ACP で起こす。`resume` を渡すと session/load で続きへ繋ぐ（履歴は相手が送り直す）
    private func startGrok(session: String, cwd: String, model: String, level: Gate.Level,
                           resume: String?) -> Run? {
        guard let grok = grokFound else {
            launchError = "grok が見つからない"
            return nil
        }
        // grok agent には権限モードの指定が無い。Lv.4/5 だけ全部通す（--always-approve）。
        // それ以外は本人の既定（~/.claude/settings.json の defaultMode）に従う——auto なら grok 自身が判定する
        var arguments = ["agent"]
        if !model.isEmpty { arguments += ["-m", model] }
        if level.needsConfirmation { arguments.append("--always-approve") }
        arguments.append("stdio")
        let token = UUID()
        do {
            let connection = try ACPConnection.start(
                grok.executable, arguments: arguments, cwd: cwd, path: grok.path,
                session: session, resume: resume,
                onEvent: agentStream(session: session),
                onExit: exitHandler(label: "grok", session: session, token: token))
            let run = Run(connection: connection, token: token)
            runs[session] = run
            backends[session] = .grok
            return run
        } catch {
            launchError = "\(error)"
            return nil
        }
    }

    private func launchGrok(prompt: String, cwd: String, model: String, level: Gate.Level) -> UUID? {
        let sessionID = UUID().uuidString.lowercased()
        guard let run = startGrok(session: sessionID, cwd: cwd, model: model, level: level, resume: nil),
              run.connection.send(prompt) else { return nil }
        let tab = LiveSession(id: sessionID, name: String(sessionID.prefix(8)), cwd: cwd, busy: false)
        loadedSessionTabs[sessionID] = tab
        liveSessions.append(tab)
        liveSessions.sort { $0.name < $1.name }
        beginTurn(sessionID)
        appendHuman(prompt, session: sessionID)
        // 相手側のIDは挨拶が済んだ時（.ready）に台帳へ入る
        runRecords.append(RunRecord(id: sessionID, threadID: nil, title: Self.titleRule(prompt) ?? "", cwd: cwd,
                                    model: model, lastUsed: Date(), backend: .grok))
        saveRunRecords()
        selectedSession = sessionID
        launchError = nil
        refreshLiveSessions()
        return UUID(uuidString: sessionID) ?? UUID()
    }

    /// 走っているセッションの進行中のターンだけを止める。
    ///
    /// **AT22 が繋いでいるセッションにだけ通る。** セッション自体は開いたまま。
    /// 返された request_id で `interruptAcknowledged` を照合し、止まりきったか確認する
    @discardableResult
    func interrupt(_ session: String?) -> Bool {
        guard let session else { return false }
        // 繋がっていないセッションは AT22 から止められない。**別の端末が回している**ので、
        // 「終わっている」と言うと嘘になる。止められない理由をそのまま出す
        guard let run = runs[session] else {
            launchError = "このセッションは AT22 から繋がっていないので止められない"
            return false
        }
        guard let requestID = run.connection.interrupt() else {
            // claude は stdin に書けなかった＝もう終わっている。codex は走っているターンが無い
            if backend(of: session) == .claude { forget(session) }
            launchError = "止められなかった。セッションが終わっている"
            return false
        }
        // 受領確認を返さない相手（codex はプロセスを落とすだけ）は照合しない
        if requestID.isEmpty { stopping.insert(session) } else { expectInterrupt(requestID, for: session) }
        return true
    }

    /// そのセッションが今動いているか。メッセージ窓の「思考中」表示に使う。
    ///
    /// `liveSessions` の busy フラグ、接続からの部分テキスト、エージェント台帳の最終活動時刻から判定する。
    /// `streaming` が空でなければ「今この瞬間」書いている状態なので優先。
    /// 既存の `activeWindow` 定数と `isBusy` 判定を組み合わせるだけで、新しい閾値は作らない
    func isWorking(_ session: String?) -> Bool {
        guard let wanted = session else {
            // セッションが指定されていない場合は、稼働中のセッションが1つでもあれば true
            return liveSessions.contains { $0.busy }
        }
        // そのセッションの接続から部分テキストが流れてきている。「今書いている途中」の状態
        if streaming[wanted]?.isEmpty == false { return true }
        // AT22 の接続がターンを回している間は稼働中（書きかけがまだ来ていない考え中も含む）
        if openTurns.contains(wanted) { return true }
        // 指定されたセッションが liveSessions に在るか、busy フラグで確認
        if let session = liveSessions.first(where: { $0.id == wanted }), session.busy {
            return true
        }
        // liveSessions に無い場合は、台帳から最終活動を見る（起動直後など）。
        // 判定そのものはチップのランプと同じ `Self.isWorking` に通す——
        // ここで条件を書き直すと、片方だけ直したときに窓とチップで食い違う
        let now = Date()
        return agents.contains { $0.value.session == wanted && Self.isWorking($0.value, now: now) }
    }

    /// 見ているセッションのプロジェクトの記憶DBを読み直す。
    /// AT22 は `~/.claude/projects/` を既に歩いているので、セッションのディレクトリから直に辿れる。
    /// transcript がまだ無いセッションだけ、cwd からスラッグを組み立てて補う。
    /// ponytail: 毎秒読む。実測5本・36行なので測るまでもなく軽い。数百本になったら間隔を空ける
    func refreshMemory() {
        guard let root = projectRoot(of: selectedSession) else {
            if !memory.isEmpty { memory = [] }
            memoryRoot = nil
            return
        }
        memoryRoot = root
        let loaded = Memory.load(projectRoot: root)
        if loaded.map(\.id) != memory.map(\.id) || loaded.map(\.modified) != memory.map(\.modified) {
            memory = loaded
        }
    }

    /// セッションUUID から、その記憶DBが置かれているプロジェクトのディレクトリへ。
    ///
    /// 二段構え。まず transcript の在り処で引く（確実）。**始まったばかりのセッションは
    /// まだ .jsonl を書いていない**ので、その時だけ cwd からディレクトリ名を組む。
    /// 選んでいなければ稼働中の先頭を使う
    private func projectRoot(of session: String?) -> URL? {
        guard let wanted = session ?? liveSessions.first?.id else { return nil }

        for entry in (try? FileManager.default.contentsOfDirectory(atPath: projectsRoot.path)) ?? [] {
            let dir = projectsRoot.appendingPathComponent(entry)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(wanted).jsonl").path) {
                return dir
            }
        }
        guard let cwd = liveSessions.first(where: { $0.id == wanted })?.cwd, !cwd.isEmpty else { return nil }
        let dir = projectsRoot.appendingPathComponent(Self.projectSlug(cwd))
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// `/Users/x/Swift_PRJS/AT22_Glass_Cockpit` → `-Users-x-Swift-PRJS-AT22-Glass-Cockpit`。
    /// 英数字以外を `-` に置換するだけ。手元の8プロジェクト全部で実際の名前と一致した
    nonisolated static func projectSlug(_ cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// 自動で畳む部分だけを切り出した入口。`housekeeping` は実機の `~/.claude/sessions` を読み、
    /// 続けて実プロジェクトを走査するので、自己チェックから呼ぶと結果が動かす機械に左右される。
    /// 畳む判定だけを見たい検査はこちらを使う
    func foldIdleAgents(now: Date) { autoHideIdleAgents(now: now) }

    /// 終わったエージェントは放っておくと溜まり続ける。無音が続いたものを自動で畳む。
    /// 手で押す「非アクティブを消す」と同じ判定を使い、動いて見えるものは絶対に消さない
    private func autoHideIdleAgents(now: Date) {
        let liveAgents = Set(touches.lazy.filter { Self.isGlowing($0, now: now) }.map(\.agent))
        for (id, record) in agents where hiddenAt[id] == nil {
            guard !Self.isBusy(record, live: liveAgents.contains(id), now: now),
                  now.timeIntervalSince(record.lastAt) > Self.autoHideAfter else { continue }
            hiddenAt[id] = now
        }
        for (id, worker) in mcpWorkers where hiddenAt[id] == nil {
            guard !Self.isBusy(worker, now: now),
                  now.timeIntervalSince(worker.lastAt) > Self.autoHideAfter else { continue }
            hiddenAt[id] = now
        }
    }

    /// プロジェクトの根は稼働中セッションの `cwd` から取る（`~/.claude/sessions/<pid>.json` に入っている）。
    /// 走査は数百ファイルを読むのでメインアクタから外す。実測99ファイルで147ms
    /// 書き残されたものの置き場。プロジェクトの外にあるので、走査の根に足さないと拾えない
    nonisolated static func memoryRoots() -> [String] {
        let home = NSHomeDirectory()
        var roots = ["\(home)/.claude/plans"]
        let projects = "\(home)/.claude/projects"
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: projects)) ?? [] {
            let memory = "\(projects)/\(entry)/memory"
            if FileManager.default.fileExists(atPath: memory) { roots.append(memory) }
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func refreshStructureIfNeeded() {
        let roots = Set(liveSessions.map(\.cwd).filter { !$0.isEmpty })
            .union(Self.memoryRoots())
        let changed = roots != scanRoots
        let stale = wroteSinceScan && Date().timeIntervalSince(lastScan) > Self.rescanInterval
        guard !scanning, !roots.isEmpty, changed || stale else { return }

        scanning = true
        scanRoots = roots
        let urls = roots.map { URL(fileURLWithPath: $0) }
        Task.detached(priority: .utility) {
            let graph = Structure.scan(roots: urls)
            await MainActor.run { [weak self] in self?.adopt(graph) }
        }
    }

    /// 合成データの自己チェックも実走査と同じ更新経路を通し、構造の畳み込み差を作らない
    func adopt(_ graph: Structure.Graph) {
        structure = graph
        lastScan = Date()
        wroteSinceScan = false
        scanning = false
    }

    // MARK: ワークスペース（プロジェクト → worktree → エージェント）

    /// エージェントの状態。サイドバーの印の色になる
    enum AgentStatus: Int, Comparable, Sendable {
        case waiting, working, failed, done, idle     // 並べる順（人の番が先）
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    struct AgentRow: Identifiable {
        let id: String
        let title: String
        let backend: Backend
        let status: AgentStatus
        /// まだ読み込んでいない過去のセッション。押したら読み込む
        let recent: RecentSession?
        /// AT22 の台帳にある Codex / Grok のセッション。押したら続きに繋ぐ
        let record: RunRecord?
    }

    struct WorkspaceNode: Identifiable {
        /// worktree のパス
        let id: String
        let name: String
        let branch: String?
        let isMain: Bool
        var agents: [AgentRow]
        /// 作っている最中なら "作成中"、失敗したらその理由
        var pending: String?
    }

    struct ProjectNode: Identifiable {
        /// リポジトリ本体のパス
        let id: String
        let name: String
        let registered: Bool
        var workspaces: [WorkspaceNode]
    }

    /// AT22 が作ったワークスペースの基点。差分の基準（レビュー）と親子（競走）に使う
    struct WorkspaceMeta: Codable, Equatable {
        var baseRef: String
        var baseSHA: String
        var parent: String?
        var createdAt: Date
    }

    struct PendingWorkspace: Equatable {
        let repo: String
        let name: String
        var error: String?
    }

    /// 登録したリポジトリ。UserDefaults（AT22 自身の記録はここだけに置く）
    private(set) var projects: [String] = UserDefaults.standard.stringArray(forKey: "projects") ?? []
    private(set) var workspaceMeta: [String: WorkspaceMeta] = {
        guard let data = UserDefaults.standard.data(forKey: "workspaceMeta") else { return [:] }
        return (try? JSONDecoder().decode([String: WorkspaceMeta].self, from: data)) ?? [:]
    }()
    /// 各リポジトリの worktree 一覧。git に訊き直すのは数秒おき（裏で）
    private(set) var worktrees: [String: [Worktree.Entry]] = [:]
    /// 作業ディレクトリ → リポジトリ本体（"" はリポジトリの外）。一度訊いたら覚えておく
    private var repoOf: [String: String] = [:]
    private(set) var pendingWorkspaces: [String: PendingWorkspace] = [:]
    private var lastWorktreeScan = Date.distantPast
    private var scanningWorktrees = false

    func addProject(_ repo: String) {
        guard !projects.contains(repo) else { return }
        projects.append(repo)
        UserDefaults.standard.set(projects, forKey: "projects")
        refreshWorktreesIfNeeded(force: true)
    }

    func removeProject(_ repo: String) {
        projects.removeAll { $0 == repo }
        UserDefaults.standard.set(projects, forKey: "projects")
    }

    /// 選んだフォルダをリポジトリとして登録する。worktree の中を選んでも本体を登録する
    func addProject(containing folder: String) async -> String? {
        let result = await Task.detached { Result { try Worktree.root(of: folder) } }.value
        switch result {
        case let .success(repo): addProject(repo); return nil
        case let .failure(error): return "\(error)"
        }
    }

    private func saveWorkspaceMeta() {
        if let data = try? JSONEncoder().encode(workspaceMeta) {
            UserDefaults.standard.set(data, forKey: "workspaceMeta")
        }
    }

    /// worktree の一覧を読み直す。動いているセッションの在り処からもリポジトリを見つける——
    /// 登録しなくても、端末や `claude -w` で始めた作業がその場で木に並ぶ。
    /// ponytail: 5秒おきに git を数回叩くだけ。リポジトリが数十を超えたら FSEvents で .git を見る
    func refreshWorktreesIfNeeded(force: Bool = false) {
        guard !scanningWorktrees, force || Date().timeIntervalSince(lastWorktreeScan) > 5 else { return }
        scanningWorktrees = true
        lastWorktreeScan = Date()
        let unknown = Set(liveSessions.map(\.cwd) + runRecords.map(\.cwd)).filter { !$0.isEmpty && repoOf[$0] == nil }
        let known = Set(projects + repoOf.values.filter { !$0.isEmpty })
        Task.detached(priority: .utility) {
            var roots: [String: String] = [:]
            for cwd in unknown { roots[cwd] = (try? Worktree.root(of: cwd)) ?? "" }
            var lists: [String: [Worktree.Entry]] = [:]
            for repo in known.union(roots.values.filter { !$0.isEmpty }) {
                lists[repo] = (try? Worktree.list(repo: repo)) ?? []
            }
            let (found, listed) = (roots, lists)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.repoOf.merge(found) { _, new in new }
                if listed != self.worktrees { self.worktrees = listed }
                self.scanningWorktrees = false
            }
        }
    }

    /// セッションの作業ディレクトリ。起こしたタブ・稼働中・台帳の順に見る
    func cwd(of session: String) -> String? {
        (loadedSessionTabs[session]?.cwd).flatMap { $0.isEmpty ? nil : $0 }
            ?? liveSessions.first { $0.id == session }?.cwd
            ?? runRecords.first { $0.id == session }?.cwd
    }

    func status(of session: String) -> AgentStatus {
        if approvals.contains(where: { $0.session == session })
            || liveSessions.first(where: { $0.id == session })?.waiting != nil { return .waiting }
        if isWorking(session) { return .working }
        if failedTurns.contains(session) { return .failed }
        if runs[session] != nil { return .done }
        return .idle
    }

    /// 作業ディレクトリが属するワークスペース。**最も長い前方一致**——本体のパスは
    /// `.claude/worktrees/*` 全部の前方にもなるので、短い方に吸われないようにする
    nonisolated static func owner(of cwd: String, among paths: [String]) -> String? {
        paths.filter { cwd == $0 || cwd.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }

    /// サイドバーの木。登録したリポジトリを先に、見つけたリポジトリを名前順に。
    /// ponytail: リポジトリの外で動いているセッションは載せない（会話欄の履歴から開ける）
    func workspaceTree() -> [ProjectNode] {
        let discovered = Set(repoOf.values.filter { !$0.isEmpty }).subtracting(projects)
            .sorted { ($0 as NSString).lastPathComponent < ($1 as NSString).lastPathComponent }
        let repos = projects + discovered
        var paths = repos.flatMap { repo in worktrees[repo]?.map(\.path) ?? [repo] }
        paths += pendingWorkspaces.keys.filter { !paths.contains($0) }

        var rows: [String: [AgentRow]] = [:]
        var placed = Set<String>()
        let sessions = Set(liveSessions.map(\.id) + runRecords.map(\.id) + runs.keys)
        for session in sessions {
            guard let cwd = cwd(of: session), let workspace = Self.owner(of: cwd, among: paths) else { continue }
            let record = runRecords.first { $0.id == session }
            rows[workspace, default: []].append(AgentRow(
                id: session, title: title(for: session) ?? String(session.prefix(8)),
                backend: backend(of: session), status: status(of: session), recent: nil,
                record: runs[session] == nil && !liveSessions.contains { $0.id == session } ? record : nil))
            placed.insert(session)
        }
        // 過去のセッションは cwd を持たないので、プロジェクトのフォルダ名（slug）で突き合わせる。
        // 1つのワークスペースに並べるのは新しい方から5本まで（それより前は会話欄の履歴で）
        for workspace in paths {
            let slug = Self.projectSlug(workspace)
            let past = recentSessions.filter { $0.project == slug && !placed.contains($0.id) }.prefix(5)
            rows[workspace, default: []] += past.map {
                AgentRow(id: $0.id, title: title(for: $0.id) ?? String($0.id.prefix(8)), backend: .claude,
                         status: .idle, recent: $0, record: nil)
            }
        }

        return repos.map { repo in
            let entries = worktrees[repo] ?? []
            var workspaces = entries.map { entry in
                WorkspaceNode(id: entry.path, name: entry.isMain ? "本体" : (entry.path as NSString).lastPathComponent,
                              branch: entry.branch, isMain: entry.isMain,
                              agents: (rows[entry.path] ?? []).sorted { $0.status < $1.status },
                              pending: nil)
            }
            for (path, pending) in pendingWorkspaces where pending.repo == repo && !entries.contains(where: { $0.path == path }) {
                workspaces.append(WorkspaceNode(id: path, name: Worktree.slug(pending.name), branch: nil, isMain: false,
                                                agents: [], pending: pending.error ?? "作成中"))
            }
            return ProjectNode(id: repo, name: (repo as NSString).lastPathComponent,
                               registered: projects.contains(repo), workspaces: workspaces)
        }
    }

    /// ワークスペースを作り、できたらそこでエージェントを起こす。作成は裏で進め、
    /// 待つ間はカードに「作成中」、失敗したら理由を出す（ダイアログは待たせない）
    func createWorkspace(repo: String, name: String, base: String, backend: Backend, model: String,
                         prompt: String, level: Gate.Level) {
        let path = Worktree.location(repo: repo, name: name)
        pendingWorkspaces[path] = PendingWorkspace(repo: repo, name: name, error: nil)
        addProject(repo)
        Task.detached(priority: .userInitiated) {
            let result = Result { try Worktree.add(repo: repo, name: name, base: base) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case let .success(made):
                    self.pendingWorkspaces[path] = nil
                    self.workspaceMeta[made.path] = WorkspaceMeta(baseRef: base, baseSHA: made.baseSHA,
                                                                  parent: nil, createdAt: Date())
                    self.saveWorkspaceMeta()
                    self.refreshWorktreesIfNeeded(force: true)
                    let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !prompt.isEmpty {
                        self.launch(prompt: prompt, cwd: made.path, backend: backend, model: model, level: level)
                    }
                case let .failure(error):
                    self.pendingWorkspaces[path]?.error = "\(error)"
                }
            }
        }
    }

    /// 検査・画像焼きからワークスペースの木を直接流し込む口。実機の git と ~/.claude に依存させない
    func loadWorkspacesForProbe(projects: [String], worktrees: [String: [Worktree.Entry]],
                                pending: [String: PendingWorkspace] = [:], failed: Set<String> = [],
                                backends: [String: Backend] = [:]) {
        self.projects = projects
        self.worktrees = worktrees
        self.pendingWorkspaces = pending
        self.failedTurns = failed
        self.backends.merge(backends) { _, new in new }
        lastWorktreeScan = .distantFuture      // 毎秒の読み直しで消されないように
    }

    /// 失敗したまま残っている「作成中」を畳む
    func dismissPending(_ path: String) { pendingWorkspaces[path] = nil }

    /// 消す前に人へ見せる、未コミットの変更
    func dirtyFiles(of path: String) async -> [String] {
        await Task.detached { (try? Worktree.dirtyFiles(path)) ?? [] }.value
    }

    /// ワークスペースを消す。**そこで動いている接続を先に閉じる**（書いている最中の場所を消さない）。
    /// `force` は未コミットの変更を人に見せて確認を取った後だけ立てる。
    /// 戻り値は人に伝える一言（失敗の理由、または枝を残した旨）。何も無ければ nil
    func deleteWorkspace(_ path: String, force: Bool, deleteBranch: Bool) async -> String? {
        guard let (repo, entry) = worktrees.lazy.compactMap({ repo, list in
            list.first { $0.path == path }.map { (repo, $0) } }).first else {
            return "この作業場所は一覧に無い"
        }
        for session in runs.keys where cwd(of: session).map({ Self.owner(of: $0, among: [path]) != nil }) == true {
            runs[session]?.connection.close()
            forget(session)
        }
        let branch = entry.branch
        let outcome: String? = await Task.detached {
            do { try Worktree.remove(repo: repo, path: path, force: force) } catch { return "\(error)" }
            if deleteBranch, let branch, !Worktree.deleteBranch(branch, repo: repo) {
                return "枝 \(branch) はマージされていないので残した（中身を見てから消せる）"
            }
            return nil
        }.value
        workspaceMeta[path] = nil
        saveWorkspaceMeta()
        refreshWorktreesIfNeeded(force: true)
        return outcome
    }

    // MARK: 畳み込み

    /// 実装の区切りで一旦まっさらにする。溜まった終了済みチップとファイルの集計を落とす
    func clear() {
        clearedAt = Date()
    }

    /// 見えているセッションだけを対象にし、履歴の役割名を保ったまま非稼働チップを隠す
    func clearIdleAgents(now: Date) {
        let cleared = clearedAt
        let filter = selectedSession
        let liveAgents = Set(touches.lazy.filter { touch in
            (filter == nil || touch.session == filter)
                && (cleared.map { touch.started >= $0 } ?? true)
                && Self.isGlowing(touch, now: now)
        }.map(\.agent))

        for (id, record) in agents {
            if let filter = selectedSession, record.session != filter { continue }
            if Self.isBusy(record, live: liveAgents.contains(id), now: now) { continue }
            hiddenAt[id] = now
        }
        for (id, worker) in mcpWorkers {
            if let filter = selectedSession, worker.session != filter { continue }
            if Self.isBusy(worker, now: now) { continue }
            hiddenAt[id] = now
        }
    }

    func snapshot(now: Date, mode: CockpitMode) -> CockpitSnapshot {
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

            let glowing = Self.isGlowing(touch, now: now)

            var cell = cells[touch.path] ?? FileCell(id: touch.path,
                                                     name: (touch.path as NSString).lastPathComponent,
                                                     touched: true,
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

        if mode == .memory {
            // 記憶DBだけを出す。材料（企画ノート等）は落とした——
            // 素は人間が別の場所から持ち込むもので、この画面はDBを組み上げる場所
            let outline = Memory.outline(memory)
            let files = outline.rows.map { row -> FileCell in
                var cell = FileCell(id: row.node?.id ?? "group:\(row.depth):\(row.label)",
                                    name: row.label,
                                    touched: !row.isFolder,
                                    lastAt: row.node?.modified ?? .distantPast)
                cell.indent = row.depth
                cell.note = row.node?.summary ?? ""
                cell.trace = row.node.map(Self.memoryTrace) ?? ""
                return cell
            }
            let title = outline.done > 0 ? "記憶DB（完了 \(outline.done) 件）" : "記憶DB"
            return CockpitSnapshot(mode: mode,
                                   cards: [DirCard(id: "db:outline", dir: title, files: files)],
                                   readThreshold: flagReadThreshold)
        }

        if mode == .structure {
            // 走査の根は稼働中セッション全部の cwd なので、絞らないと別プロジェクトの
            // ソースやノートが混ざる（Obsidian の Vault を開いていると数十件流れ込む）。
            // タブで1つ選んでいる間は、そのセッションのプロジェクト配下だけにする
            let root = selectedSession.flatMap { id in
                liveSessions.first { $0.id == id }?.cwd
            }.flatMap { $0.isEmpty ? nil : $0 }
            let scanned = root.map { r in structure.files.filter { $0.hasPrefix(r + "/") } }
                ?? structure.files
            for path in scanned where cells[path] == nil {
                cells[path] = FileCell(id: path,
                                       name: (path as NSString).lastPathComponent,
                                       lastAt: .distantPast)
            }
        }

        var kept = Array(cells.values)
        // 作業は直近の動き、構造は全域の位置を安定させるためパスを基準にする。
        // 同着にもパスを使い、フレームごとの並び替わりを防ぐ
        if mode == .work {
            kept.sort { $0.lastAt > $1.lastAt }
            if kept.count > Self.maxFiles { kept = Array(kept.prefix(Self.maxFiles)) }
        } else if mode == .structure {
            kept.sort {
                if $0.touched != $1.touched { return $0.touched }
                if $0.touched, $0.lastAt != $1.lastAt { return $0.lastAt > $1.lastAt }
                return $0.id < $1.id
            }
            if kept.count > Self.maxStructureFiles {
                kept = Array(kept.prefix(Self.maxStructureFiles))
            }
        }

        let (chips, hiddenChips) = mode == .work
            ? buildChips(live: live, touchCount: touchCount, now: now) : ([], 0)
        return CockpitSnapshot(mode: mode,
                               chips: chips,
                               cards: group(kept, mode: mode),
                               flagCount: flagCount,
                               readThreshold: flagReadThreshold,
                               hiddenChips: hiddenChips,
                               // 門は指揮系統の上に立つので作業モードだけ。
                               // 構造・壁打ちに出すと、線も出していない場所に紙だけが浮く
                               gates: mode == .work ? gates : [])
    }

    nonisolated static func isNote(_ path: String) -> Bool {
        Structure.noteExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// 記憶DBの3行目。行数、書いたセッション、状態の段階だけを出す
    nonisolated static func memoryTrace(_ node: Memory.Node) -> String {
        var parts = ["\(node.lines)行"]
        if let session = node.session { parts.append("\(session.prefix(8)) が書いた") }
        if let stage = node.state.first(where: { $0.key.lowercased() == "stage" })?.value {
            parts.append("状態 \(stage)")
        }
        return parts.joined(separator: "  ")
    }

    /// ノートの3行目。「どこから来て、どこへ繋がるか」を1行に畳む
    nonisolated static func noteTrace(mentions: Int, sessions: Int, writes: Int, lines: Int) -> String {
        var parts: [String] = ["\(lines)行"]
        if writes > 0 { parts.append("\(sessions)セッションで書かれた") }
        else if sessions > 0 { parts.append("\(sessions)セッションが読んだ") }
        if mentions > 0 { parts.append("→ ソース\(mentions)件に言及") }
        return parts.joined(separator: "  ")
    }

    /// 進行表。未完了は全部出し、完了は直近ぶんだけ残して残りは件数に畳む。
    /// 絞り込みはセッションだけで、`clearedAt` は掛けない。「クリア」は溜まった終了済みエージェントと
    /// 一覧に出すタスク。全件畳まずに出す。TaskPanel で見返せる必要があるため。
    /// `session` が `nil` なら全セッション、指定があればそのセッションだけ。
    /// 並びは `number` 昇順。同じ番号が複数セッションで衝突するので、同番号のときは
    /// `session` 文字列で決定的に並べる。
    func allTasks(session: String?) -> [RoadmapTask] {
        tasks.values
            .filter { session == nil || $0.session == session }
            .sorted { $0.number == $1.number ? $0.session < $1.session : $0.number < $1.number }
    }

    // MARK: 進行表の帯

    /// 最上段の帯に出す並び。**1行に収める**ために、済んだものほど強く畳む。
    ///
    /// 5a の索引装飾（`guidelines/hud.html` の run-together counter）に載せてある:
    /// 古い完了は番号だけを詰めて連結し（`0102030405…`）、直近 `keptCompleted` 件は名前付きで
    /// 残し、進行中を1件立て、残りを控えめに並べる。
    ///
    /// **純関数**。SwiftUI を通さずに検査できるようにしてある（p0）。
    struct ProgressStrip: Equatable {
        /// 古い完了の番号を詰めて連結したもの。空なら出さない
        var foldedNumbers = ""
        /// 直近の完了。名前付きで出す
        var recent: [RoadmapTask] = []
        /// いま動いているもの。**赤が付くのはここだけ**
        var current: RoadmapTask?
        /// これから。番号と名前だけ
        var upcoming: [RoadmapTask] = []

        static func == (a: Self, b: Self) -> Bool {
            a.foldedNumbers == b.foldedNumbers
                && a.recent.map(\.id) == b.recent.map(\.id)
                && a.current?.id == b.current?.id
                && a.upcoming.map(\.id) == b.upcoming.map(\.id)
        }
    }

    /// 帯に出す残りの上限。ここを超えると番号だけの連結に落とす。
    /// ponytail: 1440pt 幅で名前付きが4件入る実測。窓を狭めても折り返さない側に倒してある
    nonisolated static let stripUpcoming = 3

    /// タイトルバーの「消費」。選んだセッション（`nil` なら全部）の重み付き累計。
    /// **畳んだ分・消した分も含める**——ここは「このセッションが今日どれだけ食ったか」の計器で、
    /// 画面に何が出ているかとは関係が無い（`AgentChip.share` の分母と同じ考え方）
    func spendTotal(session: String?) -> Double {
        agents.values
            .filter { session == nil || $0.session == session }
            .reduce(0) { $0 + $1.spent }
    }

    nonisolated static func progressStrip(_ tasks: [RoadmapTask]) -> ProgressStrip {
        var strip = ProgressStrip()
        let done = tasks.filter { $0.status == .completed }
        // 完了は「古いぶんを番号だけに畳む」。keptCompleted は進行表と一覧で同じ値を使う
        let foldCount = max(0, done.count - keptCompleted)
        strip.foldedNumbers = done.prefix(foldCount).map { String($0.number) }.joined()
        strip.recent = Array(done.suffix(min(keptCompleted, done.count)))
        strip.current = tasks.first { $0.status == .inProgress }
        strip.upcoming = Array(tasks.filter { $0.status == .pending }.prefix(stripUpcoming))
        return strip
    }

    /// チップは触った記録ではなく台帳から作る。
    /// Bash しか使わないサブエージェントはファイルを一度も触らないので、
    /// 触りから組み立てると存在ごと消えてしまう
    private func buildChips(live: [String: (target: String, kind: TouchKind)],
                            touchCount: [String: Int],
                            now: Date) -> ([AgentChip], Int) {
        var chips: [AgentChip] = []
        // Claude Code 自身が busy と言っているセッション。考えている時間もここには出る
        let busySessions = Set(liveSessions.lazy.filter(\.busy).map(\.id)).union(openTurns)
        // 返事待ちのセッション。キーはセッションIDなので、引けるのは司令塔（ID＝セッションID）だけ。
        // ponytail: どのサブエージェントのどの道具が待っているかまでは sessions/*.json に無い。
        // 要るなら PermissionRequest フック（agent_id・tool_use_id が来る）だが、設定に触ることになる
        var waitingSessions = Dictionary(liveSessions.compactMap { s in s.waiting.map { (s.id, $0) } },
                                         uniquingKeysWith: { first, _ in first })
        // AT22 が繋いでいるセッションの承認待ち。答えるまで相手は道具の前で止まっている
        for approval in approvals { waitingSessions[approval.session] = "承認待ち" }

        // セッションごとの消費量合計。`share` の分母になる。
        //
        // **分母は「表示中のチップ」ではなく「そのセッションの全履歴」**（畳んだ分・消した分も含む）。
        // 意図的にそうしている。「非アクティブを消す」で古いエージェントを落としたあと、
        // 残ったチップが 5% / 3% と出るのは正しい——「今見えている分はセッション全体の1割しか
        // 食っていない＝多く食ったのは畳んだ側」と読める。ここで表示中だけに揃えると
        // その 5% が 50% に化けて、犯人でないものを犯人に見せてしまう。
        // 代わりに、畳んだあとは表示中の share の合計が 1.0 未満になる
        var sessionSpendTotal: [String: Double] = [:]
        for (_, record) in agents {
            sessionSpendTotal[record.session, default: 0] += record.spent
        }

        for (id, record) in agents {
            // 隠した後に新しく動いたものだけ戻す。時刻で見るので、古い行の読み直しでは戻らない
            if let hidden = hiddenAt[id], record.lastAt <= hidden { continue }
            if let filter = selectedSession, record.session != filter { continue }
            if let cleared = clearedAt, record.lastAt < cleared { continue }

            let running = live[id]
            // **司令塔は考えている間もツールを呼ばない。** transcript の沈黙だけで見ると
            // activeWindow(15秒) で切れて、実際には走っているのにアイドルとして出ていた。
            // `~/.claude/sessions/<pid>.json` の busy が真値なので、そちらを優先する。
            // メインセッションはエージェントIDがセッションIDそのものなので、ここで引ける
            let busy = Self.isBusy(record, live: running != nil || busySessions.contains(id), now: now)
            let totalInSession = sessionSpendTotal[record.session] ?? 0
            let share = totalInSession > 0 ? record.spent / totalInSession : 0
            let waiting = waitingSessions[id]
            // 待っている間は、止まる直前にしていたこと（＝承認を求めている道具）を添える
            let doing = waiting.map { "\($0) · " + Self.doingText(record, working: true, now: now) }
                ?? Self.doingText(record, working: busy, now: now)
            chips.append(AgentChip(
                id: id,
                role: record.role ?? role(of: id, session: record.session),
                model: record.model ?? "",
                depth: record.depth ?? (isRoot(id, session: record.session) ? 0 : 1),
                parent: record.parentCall.flatMap { callIssuer[$0] },
                // 終了報告が来ていればそれが確定値。来るまでは観測できたぶんで代用する
                work: record.reportedWork ?? max(record.observedWork, touchCount[id] ?? 0),
                doing: doing,
                done: record.doneAt != nil,
                // 返事待ちは止まっている。直前15秒に動きがあっても稼働中にしない
                // （赤いランプと琥珀の枠が同時に点くと、動いているのか待っているのか読めない）
                busy: busy && waiting == nil,
                target: running?.target,
                kind: running?.kind,
                lastAt: record.lastAt,
                instruction: record.role ?? role(of: id, session: record.session),
                counts: WorkKind.allCases.compactMap { kind in
                    record.counts[kind].map { (kind, $0) }
                },
                spent: record.spent,
                share: share,
                waiting: waiting))
        }

        for (id, worker) in mcpWorkers {
            if let hidden = hiddenAt[id], worker.lastAt <= hidden { continue }
            if let filter = selectedSession, worker.session != filter { continue }
            if let cleared = clearedAt, worker.lastAt < cleared { continue }
            let busy = Self.isBusy(worker, now: now)
            let parentDepth = agents[worker.parent]?.depth
                ?? (isRoot(worker.parent, session: worker.session) ? 0 : 1)
            chips.append(AgentChip(id: id, role: worker.server, model: "MCP",
                                   depth: parentDepth + 1, parent: worker.parent,
                                   work: worker.calls, doing: worker.prompt,
                                   done: worker.done, busy: busy,
                                   target: nil, kind: nil, lastAt: worker.lastAt,
                                   instruction: worker.prompt, counts: [],
                                   spent: 0, share: 0))
        }

        // 階層ごとに、労働量の多い順に左から。同量なら動いたのが新しい順
        chips.sort { ($0.depth, -$0.work, $1.lastAt) < ($1.depth, -$1.work, $0.lastAt) }
        let hidden = max(0, chips.count - Self.maxChips)
        return (hidden > 0 ? Array(chips.prefix(Self.maxChips)) : chips, hidden)
    }

    private static func isWorking(_ record: AgentRecord, now: Date) -> Bool {
        let silence = now.timeIntervalSince(record.lastAt)
        return record.doneAt == nil && silence >= 0 && silence < Self.activeWindow
    }

    /// ランプと削除判定を同じ入口に通し、画面で稼働中のチップを消さない
    private static func isBusy(_ record: AgentRecord, live: Bool, now: Date) -> Bool {
        live || isWorking(record, now: now)
    }

    /// MCP ワーカーはエージェントと違い、**結果が返るまで1行も出さない**。
    /// 沈黙は「止まった」ではなく「まだ返ってきていない」なので、エージェント側の
    /// stuckAfter(120秒) をそのまま当てると外部呼び出しが軒並み飛行中に消える。
    /// このセッションで実測した codex の1往復は15〜40分だった
    private static func isBusy(_ worker: MCPRecord, now: Date) -> Bool {
        let silence = now.timeIntervalSince(worker.lastAt)
        return !worker.done && silence >= 0 && silence < Self.mcpStuckAfter
    }

    private static func isGlowing(_ touch: Touch, now: Date) -> Bool {
        if let finished = touch.finished {
            let since = now.timeIntervalSince(finished)
            return since >= 0 && since < Self.afterglow
        }
        return now.timeIntervalSince(touch.started) < Self.stuckAfter
    }

    /// 1つのファイルの書き込み履歴。新しい順。
    /// セル右肩から行数を外したので、内訳はここでしか出ない。
    /// 絞り込みは畳み込み（snapshot）と揃える。画面に出ていない記録が混ざると数が合わなくなる
    func writeHistory(of path: String) -> [WriteEntry] {
        var out: [WriteEntry] = []
        for (i, touch) in touches.enumerated() where touch.path == path && touch.kind == .write {
            if let filter = selectedSession, touch.session != filter { continue }
            if let cleared = clearedAt, touch.started < cleared { continue }
            out.append(WriteEntry(id: i,
                                  role: agents[touch.agent]?.role
                                      ?? role(of: touch.agent, session: touch.session),
                                  at: touch.finished ?? touch.started,
                                  added: touch.added,
                                  removed: touch.removed))
        }
        return out.reversed()
    }

    /// 誰が何回読んだか。多い順。右端の点は総数を出さずしきい値までしか埋まらないので、
    /// 正確な回数はここでしか読めない。フラグは (エージェント, ファイル) 単位で立つため、
    /// 総数だけ出しても「なぜ橙なのか」が説明できない
    func readCounts(of path: String) -> [(role: String, count: Int)] {
        var byAgent: [String: Int] = [:]
        for touch in touches where touch.path == path && touch.kind == .read {
            if let filter = selectedSession, touch.session != filter { continue }
            if let cleared = clearedAt, touch.started < cleared { continue }
            byAgent[touch.agent, default: 0] += 1
        }
        return byAgent
            .map { (agents[$0.key]?.role ?? role(of: $0.key, session: agents[$0.key]?.session ?? ""), $0.value) }
            .sorted { ($1.1, $0.0) < ($0.1, $1.0) }
    }

    /// チップの詳細も画面の集計と同じ窓を見る。別の窓だと表示中の労働量とファイル数が食い違う
    func touchedFiles(by agent: String) -> [(path: String, reads: Int, writes: Int)] {
        var files: [String: (reads: Int, writes: Int)] = [:]
        for touch in touches where touch.agent == agent {
            if let filter = selectedSession, touch.session != filter { continue }
            if let cleared = clearedAt, touch.started < cleared { continue }
            var count = files[touch.path] ?? (0, 0)
            if touch.kind == .read { count.reads += 1 } else { count.writes += 1 }
            files[touch.path] = count
        }
        return files.map { ($0.key, $0.value.reads, $0.value.writes) }
            .sorted {
                let a = $0.reads + $0.writes, b = $1.reads + $1.writes
                return a == b ? $0.path < $1.path : a > b
            }
    }

    private struct Pair: Hashable {
        let agent: String
        let path: String
    }

    /// 親ディレクトリごとにカードへまとめる。まとめる鍵は必ず絶対パス
    /// （別プロジェクトの同名ディレクトリを1枚に混ぜないため）で、短くするのは表示だけ。
    private func group(_ cells: [FileCell], mode: CockpitMode) -> [DirCard] {
        var buckets: [String: [FileCell]] = [:]
        for cell in cells {
            buckets[(cell.id as NSString).deletingLastPathComponent, default: []].append(cell)
        }
        let prefix = Self.commonDirectoryPrefix(Array(buckets.keys))
        let positions = Dictionary(uniqueKeysWithValues: cells.enumerated().map { ($1.id, $0) })

        // 構造ではスナップショット全域の順位をカード化後も保ち、
        // 触った順と未接触のパス順がディレクトリ境界で揺れないようにする
        if mode == .structure {
            // カードの中は全域の順位のまま（触った順→パス順が境界で揺れない）。
            // カードの並びだけは作業モードと同じ規則にする。モードで並べ方が違うと、
            // 切り替えたときに同じプロジェクトが違う顔で出る
            return buckets
                .map { dir, files in
                    DirCard(id: dir, dir: Self.shortDirName(dir, strippingPrefix: prefix),
                            files: files.sorted { positions[$0.id]! < positions[$1.id]! })
                }
                .sorted {
                    let a = Self.cardRank($0), b = Self.cardRank($1)
                    return (a, positions[$0.files[0].id]!) < (b, positions[$1.files[0].id]!)
                }
        }

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
                // 並びに規則を持たせる。メイン（浅いディレクトリ）→ サブ（深いほう）→ メモ（.md 等）。
                // フラグだけは気づかれないと意味が無いので、その前に出す
                let a = Self.cardRank($0), b = Self.cardRank($1)
                return (a, $0.dir, $0.id) < (b, $1.dir, $1.id)
            }
    }

    /// カードの並び順。小さいほど先。
    /// 実装の中心（浅い階層のソース）を上に、参考資料（メモ）を下に固定する
    nonisolated static func cardRank(_ card: DirCard) -> Int {
        if card.files.contains(where: { $0.flaggedBy != nil }) { return 0 }
        let notes = card.files.allSatisfy {
            Structure.noteExtensions.contains(($0.id as NSString).pathExtension.lowercased())
        }
        if notes { return 30 }                                   // メモ
        let depth = card.id.split(separator: "/").count
        return min(20, 10 + depth)                               // メイン → サブ（浅い順）
    }

    /// 共通の先頭部分を落とし、それでも長ければ末尾2階層だけ残す。
    /// 複数プロジェクトを同時に見ていると共通部分がほぼ無く、フルパスは読めないため。
    nonisolated static func shortDirName(_ dir: String, strippingPrefix prefix: String) -> String {
        var rest = dir.hasPrefix(prefix) ? String(dir.dropFirst(prefix.count)) : dir
        if rest.hasPrefix("/") { rest.removeFirst() }
        if rest.isEmpty { return (dir as NSString).lastPathComponent }

        let parts = rest.split(separator: "/")
        guard parts.count > 2 else { return rest }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    nonisolated static func commonDirectoryPrefix(_ dirs: [String]) -> String {
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

    /// 動いている間は「今していること」（例: `検索 grep AT22` / `編集 Cockpit.swift`）、
    /// 止まっていれば「してきたこと」の内訳（例: `検索12 閲覧5 編集2`）。
    /// 線が引けない作業はここでしか見えない
    static func doingText(_ record: AgentRecord, working: Bool, now: Date = Date()) -> String {
        // 最後の行動が「考えること」だったなら、今も考えている。
        // ここを見ないと、1つ前に呼んだツールを今やっているかのように出し続ける
        if working, let thought = record.thoughtAt, thought >= (record.actedAt ?? .distantPast) {
            let silence = Int(max(0, now.timeIntervalSince(thought)))
            return silence >= 5 ? "思考中 \(silence)秒" : "思考中"
        }
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

    /// セッションのバックエンド種別を取得（無ければ claude 扱い）
    func backend(of sessionID: String) -> Backend {
        backends[sessionID] ?? .claude
    }

    // MARK: 自動題名

    /// セッションIDから題名を取得（キャッシュを優先。nilも記録される）
    @ObservationIgnored private var titles: [String: String?] = [:]

    func title(for sessionID: String) -> String? {
        // キャッシュが存在するかチェック（nilもキャッシュされている）
        if titles.keys.contains(sessionID) { return titles[sessionID] ?? nil }

        // codex セッション
        if backend(of: sessionID) == .codex {
            if let record = runRecords.first(where: { $0.id == sessionID }) {
                let result = Self.titleRule(record.title)
                titles.updateValue(result, forKey: sessionID)
                return result
            }
            titles.updateValue(nil, forKey: sessionID)
            return nil
        }

        // claude セッション: transcript から最初のユーザー発言を取得
        guard let recent = recentSessions.first(where: { $0.id == sessionID }) else {
            titles.updateValue(nil, forKey: sessionID)
            return nil
        }
        let firstUserText = Self.firstUserMessage(from: recent.transcriptURL)
        let result = Self.titleRule(firstUserText ?? "")
        titles.updateValue(result, forKey: sessionID)
        return result
    }

    /// transcript ファイルから最初のユーザー発言を抽出
    /// JSONL の先頭からユーザー発言を探す。先頭 64KB だけ読む
    nonisolated private static func firstUserMessage(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // 先頭 64KB だけ読む（効率化。読み切れない行は捨てる）
        guard let chunk = try? handle.read(upToCount: 65536) else { return nil }
        let lines = chunk.split(separator: 0x0A, omittingEmptySubsequences: true)

        for lineData in lines {
            guard let dict = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any] else { continue }
            if let type = dict["type"] as? String, type == "user",
               let message = dict["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let text = item["text"] as? String {
                        return text
                    }
                }
            }
        }
        return nil
    }

    /// 題名整形ルール: 最初の行→前後空白除去→30文字超は27文字＋"…"
    nonisolated private static func titleRule(_ text: String) -> String? {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6 else { return nil }
        return trimmed.count > 30
            ? String(trimmed.prefix(27)) + "…"
            : trimmed
    }

    // MARK: 過去のセッション

    nonisolated static func listRecentSessions(root: URL) -> [RecentSession] {
        let fm = FileManager.default
        let projects = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var found: [RecentSession] = []
        for project in projects {
            guard (try? project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = (try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true, let modified = values.contentModificationDate else { continue }
                found.append(RecentSession(id: file.deletingPathExtension().lastPathComponent,
                                           project: project.lastPathComponent,
                                           projectURL: project, transcriptURL: file,
                                           modifiedAt: modified))
            }
        }
        return Array(found.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(maxRecentSessions))
    }

    private struct SessionReplay: Sendable {
        var events: [TranscriptEvent] = []
        var cwd = ""
    }

    nonisolated private static func tail(of url: URL, maximum: UInt64) -> (data: Data, partial: Bool)? {
        guard maximum > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > maximum ? size - maximum : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return (data, start > 0)
    }

    nonisolated private static func replay(_ session: RecentSession) -> SessionReplay {
        let fm = FileManager.default
        let subagents = session.transcriptURL.deletingPathExtension().appendingPathComponent("subagents")
        let files = (try? fm.contentsOfDirectory(at: subagents, includingPropertiesForKeys: nil)) ?? []
        var replay = SessionReplay()

        for meta in files where meta.lastPathComponent.hasSuffix(".meta.json") {
            let name = meta.deletingPathExtension().deletingPathExtension().lastPathComponent
            guard name.hasPrefix("agent-"), let data = try? Data(contentsOf: meta),
                  let event = TranscriptParser.parseMeta(
                    data, agent: String(name.dropFirst("agent-".count)), session: session.id)
            else { continue }
            replay.events.append(event)
        }

        let sources = [session.transcriptURL]
            + files.filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
        var budget = TranscriptWatcher.defaultTotalBudget
        for source in sources {
            let maximum = min(TranscriptWatcher.defaultTailBytes, budget)
            guard let chunk = tail(of: source, maximum: maximum) else { continue }
            budget -= min(budget, UInt64(chunk.data.count))
            var lines = chunk.data.split(separator: 0x0A, omittingEmptySubsequences: true)
            if chunk.partial, !lines.isEmpty { lines.removeFirst() }
            for line in lines {
                let line = Data(line)
                if replay.cwd.isEmpty,
                   let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                   let cwd = obj["cwd"] as? String { replay.cwd = cwd }
                replay.events += TranscriptParser.parse(line, fallbackSession: session.id)
            }
            if budget == 0 { break }
        }
        return replay
    }

    /// 読み込み中の操作を完了通知で巻き戻さないため、開始時と現在が同じ場合だけ選択を進める
    nonisolated static func selectionAfterLoading(_ requested: String,
                                                  from initial: String?,
                                                  current: String?) -> String? {
        current == initial ? requested : current
    }

    func loadSession(_ session: RecentSession) async {
        if loadedSessions.contains(session.id) {
            selectedSession = session.id
            if let tab = loadedSessionTabs[session.id],
               !liveSessions.contains(where: { $0.id == session.id }) {
                liveSessions.append(tab)
                liveSessions.sort { $0.name < $1.name }
            }
            return
        }
        if loadingSessions.contains(session.id) {
            selectedSession = session.id
            return
        }
        let selectionBeforeLoad = selectedSession
        loadingSessions.insert(session.id)
        let replay = await Task.detached(priority: .utility) { Self.replay(session) }.value
        loadingSessions.remove(session.id)
        loadedSessions.insert(session.id)
        apply(replay.events)
        let cwd = replay.cwd.isEmpty ? session.projectURL.path : replay.cwd
        let tab = LiveSession(id: session.id, name: String(session.id.prefix(8)),
                              cwd: cwd, busy: false)
        loadedSessionTabs[session.id] = tab
        liveSessions.removeAll { $0.id == session.id }
        liveSessions.append(tab)
        liveSessions.sort { $0.name < $1.name }
        selectedSession = Self.selectionAfterLoading(session.id,
                                                     from: selectionBeforeLoad,
                                                     current: selectedSession)
    }

    private func refreshRecentSessionsIfNeeded() {
        guard !scanningRecent,
              Date().timeIntervalSince(lastRecentScan) >= Self.recentScanInterval else { return }
        scanningRecent = true
        let root = projectsRoot
        Task.detached(priority: .utility) {
            let sessions = Self.listRecentSessions(root: root)
            await MainActor.run { [weak self] in
                self?.recentSessions = sessions
                self?.lastRecentScan = Date()
                self?.scanningRecent = false
            }
        }
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
                                     busy: (obj["status"] as? String) == "busy",
                                     waiting: Self.waitingLabel(status: obj["status"] as? String,
                                                                waitingFor: obj["waitingFor"] as? String)))
        }
        activeSessions = Set(found.map(\.id))
        let sorted = Self.tabs(live: found, selected: selectedSession, previous: liveSessions,
                               loaded: Array(loadedSessionTabs.values))
        if sorted != liveSessions { liveSessions = sorted }
    }

    /// `status` が `waiting` の時の表示名。実測（v2.1.282）で承認ダイアログ中は
    /// `waitingFor: "permission prompt"`、質問への回答待ちは `"input needed"` が来る。
    /// 知らない値も「人を待っている」ことに変わりはないので入力待ちに寄せる
    nonisolated static func waitingLabel(status: String?, waitingFor: String?) -> String? {
        guard status == "waiting" else { return nil }
        return waitingFor == "permission prompt" ? "承認待ち" : "入力待ち"
    }

    /// 見ていたセッションが終わってもタブは残す。消すと選択だけが残って
    /// 畳み込みが全件落ち、画面が真っ白になる（記録自体は touches に残っている）。
    /// 選択を「すべて」に戻す手もあるが、それだと他セッションが混ざってタブの意味が消える
    static func tabs(live: [LiveSession], selected: String?, previous: [LiveSession],
                     loaded: [LiveSession] = []) -> [LiveSession] {
        var byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        for session in live { byID[session.id] = session }
        var out = Array(byID.values)
        if let id = selected, !out.contains(where: { $0.id == id }),
           let last = previous.first(where: { $0.id == id }) {
            out.append(LiveSession(id: last.id, name: last.name, cwd: last.cwd, busy: false))
        }
        return out.sorted { $0.name < $1.name }
    }
}
