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
        case .memory: "記憶DB"
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

/// ACTIONS の行の動作の和名（「書込中」の並び）。InkLoader の状態名から引く
enum TaskInk {
    static let jp: [String: String] = [
        "write": "書込中", "search": "読取中", "build": "ビルド中", "upload": "送出中",
        "download": "取得中", "transfer": "受け渡し中", "handoff": "引継中",
    ]
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
    /// いまの動作を InkLoader の状態名で（`Cockpit.inkStatus`）。動いている時だけ意味がある
    var ink: String = "think"
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
    static let launcherOffMessage = "連携が「切」なので起こさない。10 SETTINGS の 03 Launch で「動かす」にする"
    private var launcherOn: Bool { UserDefaults.standard.bool(forKey: Self.launcherEnabledKey) }
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

    var selectedSession: String? {
        // 見たものは既読。未読は「選んでいない間に何か起きた」印なので、選んだ瞬間に消す
        didSet { if let selectedSession { unread.remove(selectedSession) } }
    }
    /// 選んでいない間にターンが終わった・失敗した・承認を求めてきたセッション（サイドバーの太字）
    private(set) var unread: Set<String> = []
    /// 人の注意を引く出来事。画面の外（通知）へ渡す口。Cockpit は AppKit を知らない
    var onAttention: ((_ session: String, _ title: String, _ body: String) -> Void)?
    var liveSessions: [LiveSession] = []
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
    /// 人が選んだ考える深さ（claude の --effort / codex の model_reasoning_effort）。モデルと同じく繋ぎ直しで効く
    private var sessionEffort: [String: String] = [:]
    /// stdout から拾っている部分テキスト。確定は transcript の担当——ここは「いま書いている途中」だけ。
    /// ターン終了で消える。**セッションごとに持つ**——1本にまとめていた頃は、どれか1つが
    /// 書いている間、`isWorking` が全セッションを稼働中と答えていた
    /// **観測しない**——チャンクごとに根から全部描き直していた。画面は毎秒の時計で読み直すので足りる
    @ObservationIgnored private(set) var streaming: [String: String] = [:]
    /// いま書きかけが流れているセッション（観測する方。入る・抜ける時だけ描き直す）
    private(set) var writing: Set<String> = []

    private func clearStreaming(_ session: String) {
        streaming[session] = nil
        if writing.contains(session) { writing.remove(session) }
    }
    /// セッションごとの、受領確認を待っている割り込みの request_id。
    /// ここを持つことで、投げっぱなし（応答の見落とし）と、誤報（止まり損ない）を防ぐ
    private var interruptRequests: [String: String] = [:]
    /// 人が止めたターン。claude は止めたターンを `error_during_execution` で終えるので、
    /// ここに無いと「自分で止めたのに失敗」と出てしまう（実機で確認）
    private var stopping: Set<String> = []

    /// モデルが書いた言葉。tool_use しか見ていなかったので、これまで画面に出ていなかった分
    private(set) var messages: [Message] = []
    /// 送った時に会話へ出した、transcript からまだ届いていない人の発言（セッション → 文）
    private var echoes: [String: [String]] = [:]
    /// 実測1セッションで text 256件 / thinking 297件。数セッションぶん抱えても軽いが、
    /// 上限は置く（1件が数千字になることがある）
    static let maxMessages = 4000
    /// 発言の id。`messages.count` で振ると上限に届いた後は全部同じ id になり、会話の LazyVStack が固まった
    private var nextMessageID = 0

    /// 発言を足すのはここだけ（id を振る・上限で落とす）
    private func appendMessage(session: String, agent: String, text: String, thinking: Bool, speaker: Speaker, at: Date) {
        messages.append(Message(id: nextMessageID, session: session, agent: agent,
                                text: text, thinking: thinking, speaker: speaker, at: at))
        nextMessageID += 1
        // ponytail: 余裕を持たせてまとめて落とす。1件ごとだと開き直しの流し込みで 件数×4000 ずらしていた
        if messages.count > Self.maxMessages + 500 { messages.removeFirst(messages.count - Self.maxMessages) }
    }

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
        appendMessage(session: record.id, agent: record.id,
                      text: "以前のやり取りはこの画面には出ません（今回の分から表示）",
                      thinking: false, speaker: .model, at: Date())

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
                if hydraStarted[session] != nil { hydraTools[session, default: 0] += 1 }
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
                if speaker == .model, !thinking, agent == session {
                    adoptPlan(text, session: session, at: at)
                    adoptHydra(text, session: session, at: at)
                }
                if speaker == .human, let i = echoes[session]?.firstIndex(of: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    echoes[session]?.remove(at: i)
                    break
                }
                appendMessage(session: session, agent: agent, text: text, thinking: thinking, speaker: speaker, at: at)
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
        refreshMemoryInBackground()
        refreshGates()
        refreshWorktreesIfNeeded()
        autoHideIdleAgents(now: Date())
        watchHandoffs()
        sleepIdleSessions()
        runSchedules(now: Date())
        releaseGraceApprovals(now: Date())
        checkHydraLimits(now: Date())
        // Hydra の報告の送り待ち。司令塔の「次のターンの終わり」だけを待っていると、報告が届いた時に
        // 司令塔がもうターンを終えていた場合、二度と送られなかった（2026-10-04 に本物の claude で通して見つけた）
        for lead in hydraOutbox.keys where !isWorking(lead) && canSend(to: lead) { flushHydra(lead) }
    }

    // MARK: 定期実行

    /// 決めた worktree に、決めた間隔か毎日の時刻で指示を送る（新しい会話を起こす）。AT22 が開いている間だけ
    struct Schedule: Codable, Identifiable, Equatable {
        var id = UUID()
        var workspace: String
        var prompt: String
        /// 間隔（分）。`dailyAt` が書いてあればそちらが優先
        var everyMinutes = 60
        /// 毎日の時刻 "HH:mm"（空なら間隔で）
        var dailyAt = ""
        var enabled = true
        var lastRun: Date? = Date()
    }

    static let schedulesKey = "schedules"

    var schedules: [Schedule] = {
        guard let data = UserDefaults.standard.data(forKey: Cockpit.schedulesKey),
              let list = try? JSONDecoder().decode([Schedule].self, from: data) else { return [] }
        return list
    }() {
        didSet { if let data = try? JSONEncoder().encode(schedules) { UserDefaults.standard.set(data, forKey: Self.schedulesKey) } }
    }

    /// その予定が今やる時か（純関数。p0 で固定）
    nonisolated static func isDue(_ schedule: Schedule, now: Date, calendar: Calendar = .current) -> Bool {
        guard schedule.enabled, !schedule.workspace.isEmpty, !schedule.prompt.isEmpty else { return false }
        let parts = schedule.dailyAt.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2, let today = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) {
            return now >= today && (schedule.lastRun ?? .distantPast) < today
        }
        return now.timeIntervalSince(schedule.lastRun ?? .distantPast) >= Double(max(1, schedule.everyMinutes)) * 60
    }

    /// 今すぐ1回（設定の「今すぐ」）。起こせたら true
    @discardableResult
    func runSchedule(_ id: UUID, now: Date = Date()) -> Bool {
        guard let i = schedules.firstIndex(where: { $0.id == id }) else { return false }
        let s = schedules[i]
        schedules[i].lastRun = now
        // 既定のエージェント（SettingsScreen.agentKey と同じ鍵。Cockpit は SwiftUI を見ない）
        let parts = (UserDefaults.standard.string(forKey: "defaultAgent") ?? "claude|").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let backend = Backend(rawValue: parts.first ?? "") ?? .claude
        let keep = selectedSession
        let id = launch(prompt: s.prompt, cwd: s.workspace, backend: backend, model: parts.count > 1 ? parts[1] : "",
                        level: level(ofWorkspace: s.workspace))
        selectedSession = keep
        guard let session = id?.uuidString.lowercased() else {
            appendLaunchError("定期実行（\((s.workspace as NSString).lastPathComponent)）を起こせなかった")
            return false
        }
        titles[session] = "定期 · " + (Self.titleRule(s.prompt) ?? "")
        noteAttention(session, "定期実行で起こした")
        return true
    }

    private func runSchedules(now: Date) {
        // 連携が切ってあれば動かさない（入れただけで LLM を起こすアプリにしない）
        guard UserDefaults.standard.bool(forKey: Self.launcherEnabledKey) else { return }
        for s in schedules where Self.isDue(s, now: now) { runSchedule(s.id, now: now) }
    }

    /// worktree の段（その worktree の `memory/gate/LEVEL`）
    func level(ofWorkspace cwd: String) -> Gate.Level {
        Gate.level(memoryRoot: projectsRoot.appendingPathComponent(Self.projectSlug(cwd)).appendingPathComponent("memory"))
    }

    // MARK: Issues から

    /// リポジトリの開いている Issue（`gh issue list`）。gh が無い・ログインしていない時は理由を返す
    nonisolated static func issues(repo: String) -> Result<[(number: Int, title: String, body: String)], Error> {
        Result {
            let out = try Worktree.run("/bin/zsh", ["-lc", "gh issue list --state open --limit 30 --json number,title,body"],
                                       in: repo, withErrors: true)
            guard let rows = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [[String: Any]] else {
                throw Worktree.Failure(message: out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return rows.compactMap { r in
                guard let n = r["number"] as? Int, let t = r["title"] as? String else { return nil }
                return (n, t, r["body"] as? String ?? "")
            }
        }
    }

    // MARK: 眠らせて再開

    /// 何分動かなかったら、claude のプロセスを畳むか（0 で畳まない）。送る時に `--resume` で起こし直す
    static let sleepAfterKey = "sleepAfterMinutes"
    /// 畳んだ会話（画面に「眠っている」を出す）
    private(set) var sleeping: Set<String> = []

    private func sleepIdleSessions() {
        let minutes = UserDefaults.standard.object(forKey: Self.sleepAfterKey) as? Int ?? 15
        guard minutes > 0 else { return }
        let now = Date()
        for (session, run) in runs where backend(of: session) == .claude && !isWorking(session)
            && run.connection.acceptsInput && !approvals.contains(where: { $0.session == session })
            && handoffs[session] == nil {
            let last = agents[session]?.lastAt ?? .distantPast
            guard now.timeIntervalSince(last) > Double(minutes) * 60 else { continue }
            run.connection.close()
            forget(session)
            sleeping.insert(session)
        }
    }

    // MARK: 文脈が溢れる前の引き継ぎ

    /// 引き継ぎを書かせている会話（書かせた時刻）。書き終えたら新しい会話を起こす
    private(set) var handoffs: [String: Date] = [:]
    /// もう引き継いだ会話（二度は書かせない）
    private var handedOff: Set<String> = []
    /// 引き継ぎがうまくいかなかった時の一言（会話画面に出す）
    private(set) var handoffProblem: [String: String] = [:]

    /// その会話の文脈の段（50 / 70 / 85%）
    func contextStage(_ session: String?) -> Snowman.Stage { readings[session ?? ""]?.stage ?? .fresh }

    /// その会話の worktree の段（`memory/gate/LEVEL`）
    func level(of session: String) -> Gate.Level {
        guard let cwd = cwd(of: session) else { return gateLevel }
        return Gate.level(memoryRoot: projectsRoot.appendingPathComponent(Self.projectSlug(cwd)).appendingPathComponent("memory"))
    }

    /// 引き継ぎに入れるか。壁打ち（読むだけ）は書けないので入らない
    func canHandOff(_ session: String?) -> Bool {
        guard let session else { return false }
        return !handedOff.contains(session) && handoffs[session] == nil && level(of: session) != .plan
    }

    /// 引き継ぎを書かせる。書き終えたら `watchHandoffs` が新しい会話を起こす
    @discardableResult
    func requestHandoff(_ session: String) -> Bool {
        guard canHandOff(session), !isWorking(session), let cwd = cwd(of: session) else { return false }
        guard send(Memory.handoffPrompt(dir: memoryDirectory(cwd: cwd), session: session), to: session) else {
            handoffProblem[session] = launchError ?? "引き継ぎを送れませんでした"
            return false
        }
        handoffProblem[session] = nil
        handoffs[session] = Date()
        return true
    }

    /// 毎秒。Lv.3/4 は 85% で自動で書かせる（Lv.1/2 は会話画面の札から）。
    /// 書かせた会話のターンが終わったら、同じ worktree・エージェント・モデルで新しい会話を起こす。古い会話は閉じない
    private func watchHandoffs() {
        for session in runs.keys where contextStage(session) == .warning && canHandOff(session) && !isWorking(session) {
            if level(of: session).needsConfirmation { requestHandoff(session) }
        }
        for (session, at) in handoffs where Date().timeIntervalSince(at) > 3 && !isWorking(session) {
            handoffs[session] = nil
            handedOff.insert(session)
            guard let cwd = cwd(of: session) else { continue }
            let note = Memory.eachNotePath(dir: memoryDirectory(cwd: cwd), session: session)
            let keep = selectedSession
            guard let id = launch(prompt: Memory.resumePrompt(note: note), cwd: cwd, backend: backend(of: session),
                                  model: model(of: session) ?? "", level: level(of: session),
                                  effort: effort(of: session) ?? "")?.uuidString.lowercased() else {
                handoffProblem[session] = launchError ?? "新しい会話を起こせませんでした"
                continue
            }
            if let title = title(for: session) { titles[id] = "続き · " + title }
            // 見ていた会話を引き継いだ時だけ、新しい方へ移る
            if keep != session { selectedSession = keep }
        }
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

    /// worktree の記憶DB。**リポジトリ本体で1つ**——Claude Code の自動記憶も worktree をまたいで
    /// 本体の置き場を使うので、そこに揃える（worktree ごとに分けると本人の記憶と別の DB になる）。
    /// リポジトリでないフォルダはそのフォルダの置き場
    func memoryDirectory(cwd: String) -> String {
        // リモートの相手は手元の記憶DB を書けない
        guard !Remote.isRemote(cwd) else { return "" }
        // 裏の走査が埋めた本体を先に見る（"" はリポジトリでない）。1秒ごとの見回りからメインで git を叩かない
        let base = repoOf[cwd].map { $0.isEmpty ? cwd : $0 } ?? (try? Worktree.root(of: cwd)) ?? cwd
        return projectsRoot.appendingPathComponent(Self.projectSlug(base)).appendingPathComponent("memory").path
    }

    /// 清書。記憶DBを読んで PROJECT.md を企画書に書き直す claude を1本起こす。
    /// 普通のセッションとして会話の一覧に出る——清書のための別の仕組みは作らない。
    /// 門の段（LEVEL）も選択中の会話も動かさない（壁打ちと同じ）
    @discardableResult
    func compose(workspace: String) -> String? {
        let dir = memoryDirectory(cwd: workspace)
        let keep = selectedSession
        let id = launchClaude(prompt: Memory.composePrompt(dir: dir), cwd: workspace, model: "",
                              allowedTools: Memory.composeTools(dir: dir), level: .normal, writesLevel: false)
        selectedSession = keep
        guard let id = id?.uuidString.lowercased() else { return nil }
        titles[id] = "清書 · PROJECT.md"
        composing[workspace] = id
        return id
    }

    /// 清書中のセッション（worktree → セッションID）。終わったかは `isWorking` で見る
    private(set) var composing: [String: String] = [:]

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
        // 采配の門は、任せてる・留守番なら AT22 が許可する（Hydra と同じ。マージ・push・PR は人）。
        // 段は門と同じ置き場の LEVEL で見る——gate.sh は頼んだ会話（by:）を書かないので、by: で引くと Lv.4 でも門が残った
        let level = Gate.level(memoryRoot: dir)
        for request in found where request.dispatch != nil && [.auto, .unattended].contains(level)
            && !FileManager.default.fileExists(atPath: Gate.verdictPath(for: request)) {
            // answer は中で読み直すので、同じ門に二度答えて二重に起こさないよう答えの有無を毎回見る
            answer(request, .allow)
        }
        if level != gateLevel { gateLevel = level }
    }

    /// 門に答える。**書けなかったら必ず呼び出し元に返す**——
    /// 黙って画面から消すと、司令塔は答えが来ないまま待ち続ける
    /// 采配（`dispatch:` のある門）は、許可・書換の答えを書いた**後で** AT22 がワークスペースを作って
    /// ワーカーを起こし、最初のターンが終わったら `<id>.result` を書く。答えを先に書くのは、
    /// 作成を待つ間に門が板に残って二度押されないため
    @discardableResult
    func answer(_ request: Gate.Request, _ verdict: Gate.Verdict,
                revised: String = "", at: Date = Date()) -> NoteSaveResult {
        // 門が置かれたプロジェクトへ書く（Hydra の門は選択中とは別の会話のプロジェクトにあることがある）
        let result = saveNote(path: Gate.verdictPath(for: request),
                              text: Gate.verdictText(verdict, at: at, revised: revised),
                              creating: true, project: Gate.projectDirectory(of: request.id).map { URL(fileURLWithPath: $0) })
        guard result == .saved else { return result }
        refreshGates()
        if let backend = request.dispatch, verdict != .deny {
            dispatch(request, backend: backend, instruction: verdict == .revise ? revised : request.instruction)
        }
        return result
    }

    /// 采配したワーカー → 答えた門のパス。最初のターンが終わったら結果を書いて外す
    private var dispatched: [String: String] = [:]

    private func dispatch(_ request: Gate.Request, backend: Backend, instruction: String) {
        let gate = request.id
        // 頼んだ司令塔の作業場所から（Hydra は門に by: で会話が書いてある）。分からなければ選択中の会話
        let cwd = cwd(of: request.by) ?? selectedSession.flatMap(cwd(of:)) ?? ""
        // 頼んだ司令塔の段で起こす（選択中の会話の段ではない）
        let level = request.by.isEmpty || self.cwd(of: request.by) == nil ? gateLevel : self.level(of: request.by)
        Task {
            let repo = await Task.detached { try? Worktree.root(of: cwd) }.value
            guard let repo else {
                return writeResult(gate, status: "failed", fields: [("error", "司令塔の作業ディレクトリがリポジトリの外")])
            }
            createWorkspace(repo: repo, name: request.name, base: request.base, backend: backend, model: request.model,
                            prompt: instruction, level: level) { [weak self] path, session, error in
                guard let self else { return }
                if let session, error == nil {
                    self.dispatched[session] = gate
                    // Hydra の head は系統と上限の数えに入れる
                    if request.call.hasPrefix("hydra-"), !request.by.isEmpty {
                        self.hydraLead[session] = request.by
                        self.hydraStarted[session] = Date()
                    }
                } else {
                    self.writeResult(gate, status: "failed", fields: [("workspace", path), ("error", error ?? "起こせなかった")])
                }
            }
        }
    }

    /// 采配の結果を門の隣に書く。**門が置かれたプロジェクト**へ（その間に選択が別へ移っていても）
    private func writeResult(_ gate: String, status: String, fields: [(String, String)], summary: String = "") {
        guard let project = Gate.projectDirectory(of: gate) else { return }
        let result = saveNote(path: Gate.resultPath(for: gate),
                              text: Gate.resultText(status: status, fields: fields, summary: summary, at: Date()),
                              creating: true, project: URL(fileURLWithPath: project))
        if result != .saved { appendLaunchError("采配の結果を書けない: \(Gate.resultPath(for: gate))") }
    }

    /// 采配したワーカーの最初のターンが終わった。本文はそのターンの返事（書きかけが無い相手は最後の発言）
    private func reportDispatched(_ session: String, status: String, reply: String?) {
        guard let gate = dispatched.removeValue(forKey: session) else { return }
        let path = cwd(of: session) ?? ""
        let text = reply ?? messages.last { $0.session == session && $0.speaker == .model && !$0.thinking }?.text ?? ""
        let branch = Worktree.branch(for: (path as NSString).lastPathComponent)
        writeResult(gate, status: status,
                    fields: [("workspace", path), ("branch", branch),
                             ("agent", backend(of: session).rawValue), ("session", session)],
                    summary: String(text.suffix(4000)))
        // Hydra の head なら、頼んだ司令塔へ次のメッセージとして返す
        let front = Memory.frontMatter((try? String(contentsOfFile: gate, encoding: .utf8)) ?? "")
        if let call = front["call"], call.hasPrefix("hydra-"), let lead = front["by"], !lead.isEmpty {
            deliverHydra(Hydra.report(name: front["name"] ?? call, agent: backend(of: session).rawValue, status: status,
                                      workspace: path, branch: branch, reply: text), to: lead)
        }
    }

    // MARK: 使い方の流れ（チュートリアルと「いまの一手」）

    /// AT22 の流れ。連携 → プロジェクト → ワークスペース → 会話 → REVIEW → GIT
    enum FlowStep: Int, CaseIterable, Sendable {
        case link, project, workspace, talk, review, git
        var no: String { String(format: "%02d", rawValue + 1) }
        var en: String { ["Link", "Project", "Workspace", "Talk", "Review", "Git"][rawValue] }
        var jp: String { ["連携", "プロジェクト", "ワークスペース", "会話", "見る", "送る"][rawValue] }
        /// 「いまの一手」の1行（鶴の札・管制塔の空の状態）
        var hint: String {
            ["10 SETTINGS で CLI を入れて連携を「動かす」に", "＋ で新しいプロジェクトを立ち上げる",
             "＋ でワークスペース（worktree）を作る", "会話を開いて最初の1通を送る",
             "変更あり · 07 REVIEW で見てステージする", "08 GIT で記帳して送る"][rawValue]
        }
    }

    /// 状態から、いまやる一手。全部済んでいて変更も無ければ nil（出さない）
    nonisolated static func flowStep(cli: Bool, launcher: Bool, projects: Bool, worktrees: Bool,
                                     sessions: Bool, changes: Bool) -> FlowStep? {
        if !cli || !launcher { return .link }
        if !projects { return .project }
        if !worktrees { return .workspace }
        if !sessions { return .talk }
        return changes ? .review : nil
    }

    /// いまの状態で `flowStep` を引く（画面から）
    func currentFlowStep(workspace: String?) -> FlowStep? {
        Self.flowStep(cli: !found.isEmpty, launcher: launcherOn, projects: !projects.isEmpty,
                      worktrees: worktrees.values.contains { $0.contains { !$0.isMain } },
                      sessions: !liveSessions.isEmpty || !recentSessions.isEmpty,
                      changes: workspace.flatMap { diffStats[$0] }.map { $0.files > 0 } ?? false)
    }

    // MARK: Hydra

    /// 起こした head の重複を防ぐ（会話 → 名前）。transcript を読み直しても二度起こさない
    private var hydraSeen: Set<String> = []
    /// 司令塔が作業中で渡せなかった報告。手が空いたら送る
    private var hydraOutbox: [String: [String]] = [:]
    /// 根の司令塔ごとの Hydra のラウンド数（上限は設定）
    private var hydraRounds: [String: Int] = [:]
    /// head → 頼んだ司令塔。一系統（孫まで）を根で数えるために辿る
    @ObservationIgnored private var hydraLead: [String: String] = [:]
    /// head を起こした時刻と、使った道具の回数（1体の上限）
    @ObservationIgnored private var hydraStarted: [String: Date] = [:]
    @ObservationIgnored private var hydraTools: [String: Int] = [:]

    /// 一系統の根（head でない司令塔）
    func hydraRoot(of session: String) -> String {
        var s = session
        for _ in 0..<16 { guard let up = hydraLead[s] else { break }; s = up }
        return s
    }

    /// その系統で動いている head の数
    private func activeHeads(under root: String) -> Int {
        hydraLead.keys.filter { runs[$0] != nil && hydraRoot(of: $0) == root }.count
    }

    /// 1体の上限（道具の回数・時間）を見る。超えた head は止めて、頼んだ司令塔に知らせる（毎秒の見回りから）
    private func checkHydraLimits(now: Date) {
        for (head, started) in hydraStarted where runs[head] != nil {
            if hydraTools[head, default: 0] >= Hydra.maxTools { stopHead(head, reason: "道具 \(Hydra.maxTools) 回") }
            else if now.timeIntervalSince(started) > Double(Hydra.maxMinutes) * 60 { stopHead(head, reason: "\(Hydra.maxMinutes) 分") }
        }
    }

    private func stopHead(_ head: String, reason: String) {
        hydraStarted[head] = nil
        let lead = hydraLead[head]
        if dispatched[head] != nil {
            reportDispatched(head, status: "limit", reply: "上限（\(reason)）に達したので AT22 が止めた。")
        } else if let lead {
            deliverHydra("[Hydra] head（\(String(head.prefix(8)))）を上限（\(reason)）で止めました。変更は worktree に残っています。", to: lead)
        }
        noteAttention(head, "Hydra の上限（\(reason)）で止めた")
        runs[head]?.connection.close()
        forget(head)
    }

    /// 司令塔の返事の ```hydra を head ごとの采配の門にする。**直近2分の返事だけ**（履歴の読み直しで起こさない）。
    /// Lv.3 / Lv.4 のプロジェクトなら人に訊かずに許可する
    private func adoptHydra(_ text: String, session: String, at: Date) {
        guard text.contains("```hydra"), !sparSessions.contains(session),
              Date().timeIntervalSince(at) < 120, let cwd = cwd(of: session) else { return }
        let project = projectsRoot.appendingPathComponent(Self.projectSlug(cwd))
        let memory = project.appendingPathComponent("memory")
        let level = Gate.level(memoryRoot: memory)
        var heads = Hydra.heads(in: text).filter { !hydraSeen.contains(session + "#" + $0.name) }
        guard !heads.isEmpty else { return }
        // 上限は一系統で数える（head が呼んだ Hydra も根の司令塔の分）。黙って捨てず、頼んだ側に伝える
        let root = hydraRoot(of: session)
        guard hydraRounds[root, default: 0] < Hydra.maxRounds else {
            noteAttention(session, "Hydra の上限（\(Hydra.maxRounds) ラウンド）に達したので、これ以上は任せない")
            deliverHydra("[AT22] Hydra の上限（一系統で \(Hydra.maxRounds) ラウンド）に達したので、この ```hydra は起こしていません。自分で進めるか、人に相談してください。", to: session)
            return
        }
        let room = Hydra.maxHeads - activeHeads(under: root)
        guard room > 0 else {
            deliverHydra("[AT22] Hydra の同時の上限（\(Hydra.maxHeads) 体）に達しているので、この ```hydra は起こしていません。報告を待ってから頼み直してください。", to: session)
            return
        }
        if heads.count > room {
            deliverHydra("[AT22] 同時の上限（\(Hydra.maxHeads) 体）を越える分は起こしていません: \(heads.dropFirst(room).map(\.name).joined(separator: ", "))", to: session)
            heads = Array(heads.prefix(room))
        }
        hydraRounds[root, default: 0] += 1
        for head in heads where hydraSeen.insert(session + "#" + head.name).inserted {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            let path = memory.appendingPathComponent("\(Gate.directory)/\(stamp)-hydra-\(head.name).md").path
            let text = Hydra.gateText(head, by: session, at: Date())
            guard saveNote(path: path, text: text, creating: true, project: project) == .saved else {
                appendLaunchError("Hydra の門を書けない: \(head.name)")
                continue
            }
            if level == .auto || level == .unattended, let request = Gate.parse(path: path, text: text) {
                answer(request, .allow)
            }
        }
        refreshGates()
    }

    private func deliverHydra(_ report: String, to lead: String) {
        if !isWorking(lead), canSend(to: lead), send(report, to: lead) { return }
        hydraOutbox[lead, default: []].append(report)
    }

    /// 司令塔のターンが終わった時、溜まっていた報告を1通にまとめて送る
    private func flushHydra(_ session: String) {
        guard let pending = hydraOutbox.removeValue(forKey: session), !pending.isEmpty else { return }
        if !send(pending.joined(separator: "\n\n---\n\n"), to: session) { hydraOutbox[session] = pending }
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

    /// 段をいまの会話にも効かせる。そのプロジェクトの `memory/gate/LEVEL` に書き、ターンの合間なら接続を畳む
    /// （次に送った時に新しい `--permission-mode` で繋ぎ直す）。設定の段は以前は新規の既定にしか効かず、
    /// 留守番にしても今の会話は元の段のまま毎回訊いていた
    /// 壁打ちを入れる前の段（worktree ごと）。切った時にそこへ戻す
    private var levelBeforePlan: [String: Gate.Level] = [:]

    /// 壁打ち（plan＝読むだけ）を入れる・切る。段とは別のトグル。段は worktree ごとなので、その worktree の会話すべてに効く
    @discardableResult
    func setPlanMode(_ on: Bool, session: String?) -> NoteSaveResult {
        guard let session, let cwd = cwd(of: session) else { return .failed }
        if on {
            if gateLevel != .plan { levelBeforePlan[cwd] = gateLevel }
            return applyLevel(.plan, to: session)
        }
        return applyLevel(levelBeforePlan[cwd] ?? Gate.defaultLevel, to: session)
    }

    @discardableResult
    func applyLevel(_ level: Gate.Level, to session: String?) -> NoteSaveResult {
        guard let session, let cwd = cwd(of: session) else { return .failed }
        let result = setGateLevel(level, cwd: cwd)
        if result == .saved, let run = runs[session], run.connection.acceptsInput {
            run.connection.close()
            forget(session)
        }
        return result
    }

    /// 壁打ちで決めたことを、その作業場所の記憶DB の HANDOFF に足す。ノートが無ければ `sessions/HANDOFF.md` を作る
    /// （以前は既にある時しか書けず、worktree の会話ではたいてい「ありません」で終わっていた）
    func appendHandoff(_ section: String, cwd: String) -> (NoteSaveResult, String) {
        // 記憶DBはリポジトリ本体で1つ（`memoryDirectory(cwd:)`）。worktree の置き場に書くと 04 MEMORY に出ない
        let memory = URL(fileURLWithPath: memoryDirectory(cwd: cwd))
        let project = memory.deletingLastPathComponent()
        let manager = FileManager.default
        let candidates = [memory.appendingPathComponent("sessions/HANDOFF.md"), memory.appendingPathComponent("HANDOFF.md")]
            + ((try? manager.contentsOfDirectory(atPath: memory.path)) ?? [])
                .filter { $0.uppercased().contains("HANDOFF") && $0.hasSuffix(".md") }
                .map { memory.appendingPathComponent($0) }
        if let found = candidates.first(where: { manager.fileExists(atPath: $0.path) }),
           let old = try? String(contentsOf: found, encoding: .utf8) {
            return (saveNote(path: found.path, text: old + section, expectedText: old, project: project), found.lastPathComponent)
        }
        let fresh = memory.appendingPathComponent("sessions/HANDOFF.md")
        let text = "---\nname: HANDOFF\ndescription: 引き継ぎ（AT22 の壁打ちで決めたことなど）\nmetadata:\n  type: progress\n---\n\n# HANDOFF\n" + section
        return (saveNote(path: fresh.path, text: text, creating: true, project: project), "sessions/HANDOFF.md（新規）")
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
                allowedTools: [String] = [], level: Gate.Level? = nil, effort: String = "") -> UUID? {
        // 連携が「切」の間は何も起こさない（設定 03 Launch の約束）。起こす経路は全部ここを通る
        guard launcherOn else { launchError = Self.launcherOffMessage; return nil }
        let level = level ?? gateLevel
        let id: UUID?
        switch backend {
        case .claude:
            id = launchClaude(prompt: prompt, cwd: cwd, model: model, allowedTools: allowedTools,
                              level: level, effort: effort)
            if let id, !effort.isEmpty { sessionEffort[id.uuidString.lowercased()] = effort }
        case .codex:
            id = launchCodex(prompt: prompt, cwd: cwd, model: model, level: level)
        case .grok, .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi, .openclaw:
            id = launchACP(backend, prompt: prompt, cwd: cwd, model: model, level: level)
        }
        if let id { markAT22(id.uuidString.lowercased()) }
        return id
    }

    // MARK: 会話の出どころ（AT22 で起こした／外部）

    /// AT22 が起こした会話（端末や別のアプリで始めたものは入らない）。UserDefaults に残す
    private(set) var at22Sessions: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "at22Sessions") ?? [])

    private func markAT22(_ session: String) {
        guard !at22Sessions.contains(session) else { return }
        at22Sessions.insert(session)
        // ponytail: 並びを持たない集合なので、500 を越えたら丸ごと捨てずに残す（数百本で困ったら日付つきにする）
        UserDefaults.standard.set(Array(at22Sessions), forKey: "at22Sessions")
    }

    /// AT22 で起こした会話か。codex・ACP の台帳にあるものも AT22 が起こしたもの
    func isAT22(_ session: String) -> Bool {
        at22Sessions.contains(session) || runRecords.contains { $0.id == session }
    }

    /// 会話の一覧の切り替え（全部｜AT22｜外部）
    enum SessionOrigin: String, CaseIterable, Sendable {
        case all, at22, external
        static let key = "sessionOrigin"
        var label: String { ["全部", "AT22", "外部"][Self.allCases.firstIndex(of: self)!] }
        func shows(at22: Bool) -> Bool { self == .all || (self == .at22) == at22 }
    }

    /// 会話の中で動いているサブエージェント（Task で起こしたもの）。管制塔で会話の札の右に生やす
    func subagents(of session: String, now: Date = Date()) -> [(id: String, role: String, act: String)] {
        agents.filter { $0.key != session && $0.value.session == session && $0.value.doneAt == nil
            && Self.isWorking($0.value, now: now) }
            .sorted { $0.value.lastAt > $1.value.lastAt }
            .map { (id: $0.key, role: $0.value.role ?? "agent", act: Self.inkStatus($0.value, touching: nil)) }
    }

    /// 壁打ち用の読むだけのセッション（claude の plan モード）を worktree に起こす。
    /// 選択中のセッションも、そのプロジェクトの門の段（`memory/gate/LEVEL`）も動かさない
    /// 壁打ちのセッション。繋ぎ直す時も plan モード（読むだけ）で繋ぐ
    private(set) var sparSessions: Set<String> = []

    /// アプリを開き直した後、覚えておいた壁打ちのセッションを transcript から読み直す。選択中のセッションは動かさない
    func adoptSparring(_ id: String, cwd: String) async {
        sparSessions.insert(id)
        guard !loadedSessions.contains(id) else { return }
        let project = projectsRoot.appendingPathComponent(Self.projectSlug(cwd))
        let url = project.appendingPathComponent(id + ".jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let keep = selectedSession
        await loadSession(RecentSession(id: id, project: project.lastPathComponent, projectURL: project,
                                        transcriptURL: url, modifiedAt: Date()))
        selectedSession = keep
    }

    func launchSparring(prompt: String, cwd: String, model: String = "", effort: String = "") -> String? {
        let keep = selectedSession
        let id = launchClaude(prompt: prompt, cwd: cwd, model: model, allowedTools: [], level: .plan,
                              writesLevel: false, effort: effort)
        selectedSession = keep
        guard let id = id?.uuidString.lowercased() else { return nil }
        sparSessions.insert(id)
        if !model.isEmpty { sessionModel[id] = model }
        if !effort.isEmpty { sessionEffort[id] = effort }
        return id
    }

    private func launchClaude(prompt: String, cwd: String, model: String,
                              allowedTools: [String], level: Gate.Level, writesLevel: Bool = true,
                              effort: String = "") -> UUID? {
        guard let claude else {
            launchError = "claude が見つからない"
            return nil
        }
        // 司令塔は起きてすぐ `memory/gate/LEVEL` を読むので、起こす前に**起こす先のプロジェクトへ**書く。
        // 選択中のセッションの記憶DBに書いていた頃は、別プロジェクトの司令塔の段が変わっていた
        if writesLevel { setGateLevel(level, cwd: cwd) }
        let config = Launcher.Config(cwd: cwd, level: level,
                                     prompt: prompt, allowedTools: allowedTools, model: model, effort: effort,
                                     memoryDir: memoryDirectory(cwd: cwd))
        let sessionID = UUID()
        // transcript のファイル名は小文字。合わせておかないと起こした本人を見失う
        let id = sessionID.uuidString.lowercased()
        let token = UUID()
        // 題は起こした時点で最初の指示から付ける（transcript が一覧に載るのを待たない）
        if let title = Self.titleRule(prompt) { titles[id] = title }

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
        guard launcherOn else { launchError = Self.launcherOffMessage; return false }
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
        // 壁打ちのセッションは繋ぎ直しても読むだけ
        let config = Launcher.Config(cwd: cwd, level: sparSessions.contains(session) ? .plan : gateLevel, prompt: "",
                                     model: sessionModel[session] ?? "", effort: sessionEffort[session] ?? "",
                                     memoryDir: memoryDirectory(cwd: cwd))
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
        // claude は繋いだまま `/model` を送る（Orca と同じ）。繋ぎ直すと数秒待たされ、走っている途中なら切れる
        if backend(of: session) == .claude, !model.isEmpty, run.connection.send("/model " + model) { return }
        run.connection.close()
        forget(session)
    }

    /// 考える深さを選ぶ。claude は `/effort` を送る。ほかはターンの合間なら今の接続を畳み、次に送った時に新しい深さで繋がる
    func setEffort(_ effort: String, for session: String) {
        sessionEffort[session] = effort
        guard let run = runs[session], run.connection.acceptsInput else { return }
        if backend(of: session) == .claude, !effort.isEmpty, run.connection.send("/effort " + effort) { return }
        run.connection.close()
        forget(session)
    }

    func effort(of session: String) -> String? { sessionEffort[session] }

    // MARK: スキル

    /// 入っているスキル（Skills.discover）。入力欄の「／ SKILL」と設定の 06 Skill が使う
    private(set) var skills: [Skills.Skill] = []

    /// 撮影用（task を待たない）
    func loadSkillsForProbe(_ list: [Skills.Skill]) { skills = list }

    func refreshSkills(repo: String?) async {
        let found = await Task.detached { Skills.discover(repo: repo) }.value
        if found != skills { skills = found }
    }

    // MARK: モデルの一覧

    /// CLI から取れたモデルの一覧（取れるまでは AgentCatalog.seed）
    private(set) var catalog: [Backend: [AgentCatalog.Model]] = [:]

    func models(_ backend: Backend) -> [AgentCatalog.Model] { catalog[backend] ?? AgentCatalog.seed(backend) }

    /// 見つかっている CLI に一覧を訊く。claude は list_models（API のターンは起きない）、grok は `grok models`
    func refreshCatalog() async {
        let claude = found[.claude], grok = found[.grok]
        if let claude, catalog[.claude] == nil {
            let list = await Task.detached { Self.probeClaudeModels(claude) }.value
            if !list.isEmpty { catalog[.claude] = list }
        }
        if let grok, catalog[.grok] == nil {
            let text = await Task.detached {
                (try? Worktree.run(grok.executable.path, ["models"], in: NSHomeDirectory(), path: grok.path)) ?? ""
            }.value
            let list = AgentCatalog.parseGrok(text)
            if !list.isEmpty { catalog[.grok] = list }
        }
        if let codex = codexFound, catalog[.codex] == nil {
            let list = await Task.detached { Self.probeCodexModels(codex) }.value
            if !list.isEmpty { catalog[.codex] = list }
        }
    }

    /// `codex app-server` に initialize → model/list を流して一覧を取る（15 秒で諦める）
    nonisolated static func probeCodexModels(_ cli: Launcher.Found) -> [AgentCatalog.Model] {
        let task = Process()
        task.executableURL = cli.executable
        task.arguments = ["app-server"]
        task.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if let path = cli.path {
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = path
            task.environment = env
        }
        let input = Pipe(), output = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        for object: [String: Any] in [
            ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "at22", "title": "AT22", "version": "0.2"]]],
            ["method": "initialized"],
            ["id": 2, "method": "model/list", "params": ["limit": 100]],
        ] {
            if let line = CodexServerConnection.line(object) { input.fileHandleForWriting.write(line) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { if task.isRunning { task.terminate() } }
        var buffer = Data()
        var found: [AgentCatalog.Model] = []
        while task.isRunning, found.isEmpty {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if case let .response(id, result, _)? = RPC.classify(line), id == 2 { found = AgentCatalog.parseCodex(result) }
            }
        }
        task.terminate()
        return found
    }

    /// `claude -p --input-format stream-json` に list_models を流し、control_response を待つ（20 秒で諦める）
    nonisolated static func probeClaudeModels(_ cli: Launcher.Found) -> [AgentCatalog.Model] {
        let task = Process()
        task.executableURL = cli.executable
        task.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        task.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if let path = cli.path {
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = path
            task.environment = env
        }
        let input = Pipe(), output = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let request = #"{"type":"control_request","request_id":"at22-models","request":{"subtype":"list_models"}}"# + "\n"
        input.fileHandleForWriting.write(Data(request.utf8))
        // 応答が来ないまま読み取りが止まらないよう、20 秒で相手を止める（止まれば読み取りは空で返る）
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if task.isRunning { task.terminate() } }
        let deadline = Date().addingTimeInterval(20)
        var buffer = Data()
        var found: [AgentCatalog.Model] = []
        while Date() < deadline, task.isRunning, found.isEmpty {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                if line.range(of: Data("control_response".utf8)) != nil {
                    found = AgentCatalog.parseClaude(Data(line))
                    break
                }
            }
        }
        task.terminate()
        try? input.fileHandleForWriting.close()
        return found
    }

    /// そのセッションが実際に使っているモデル。transcript から観測した値
    func model(of session: String) -> String? {
        sessionModel[session] ?? agents[session]?.model
    }

    /// 接続を手放す。書きかけ・割り込み待ち・答え待ちの承認も一緒に消す
    private func forget(_ session: String) {
        runs[session] = nil
        clearStreaming(session)
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
            if !text.isEmpty, !writing.contains(session) { writing.insert(session) }

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
            decideApproval(approval, session: session)

        case let .turnEnded(tokens):
            // codex・ACP は止めても turnEnded（stopReason: cancelled）で終わる。止めたのを「終わった」と報告しない
            reportDispatched(session, status: stopping.contains(session) ? "stopped" : "done", reply: streaming[session])
            defer { flushHydra(session) }
            // 確定メッセージは transcript（または `.message`）から来るので、書きかけは残さない
            clearStreaming(session)
            stopping.remove(session)
            openTurns.remove(session)
            noteAttention(session, "ターンが終わった")
            if let tokens {
                Snowman.observe(&readings[session, default: Snowman.Reading()], tokens: tokens)
            }

        case let .turnFailed(reason):
            // 理由を launchError に載せる。握り潰すと司令塔が「成功した」と誤認する。
            // 書きかけは消す——失敗しても途中まで書けたと見えてはいけない
            clearStreaming(session)
            openTurns.remove(session)
            // 人が止めたターンの終わり方は失敗ではない。それ以外の理由なら止めた後でも出す
            // ponytail: 何も走っていない時に止めると印が次のターンまで残り、その次の
            // error_during_execution を1回だけ見逃す。止めるボタンは走っている間しか出ない
            if stopping.remove(session) != nil, reason == "error_during_execution" {
                reportDispatched(session, status: "stopped", reply: nil)
                break
            }
            reportDispatched(session, status: "failed", reply: reason)
            failedTurns.insert(session)
            noteAttention(session, "失敗した — \(reason)")
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
        // 要判断（留守番で断って積んだもの）。相手はもう待っていないので、許可なら「やり直してよい」と伝える
        if let i = deferred.firstIndex(where: { $0.id == approval.id }) {
            deferred.remove(at: i)
            if allow {
                preapproved.insert(Self.approvalKey(approval))
                deliverHydra("[AT22] 要判断に積んだ「\(approval.detail)」は人が許可した。必要なら今やり直してよい。", to: approval.session)
            }
            return true
        }
        guard runs[approval.session]?.connection.answer(approval, allow: allow, input: input) == true else {
            return false
        }
        approvals.removeAll { $0.id == approval.id }
        return true
    }

    /// 留守番で断って積んだ高リスクの道具（要判断）。相手は先へ進んでいる。人が見て許可か捨てるを選ぶ
    private(set) var deferred: [Approval] = []
    /// 要判断から人が許可した呼び出し。同じ呼び出しが来たら1回だけ通す
    @ObservationIgnored private var preapproved: Set<String> = []

    nonisolated static func approvalKey(_ a: Approval) -> String { a.session + "\u{0}" + a.tool + "\u{0}" + a.input }

    /// 道具の承認を段で決める（3つの相手が合流する1か所）。
    /// 隣で見てる→訊く／気にかけてる→低は猶予の後に通す／任せてる→低はすぐ通す／留守番→低はすぐ・高は積んで断る
    private func decideApproval(_ approval: Approval, session: String) {
        var approval = approval
        var decision = Gate.humanOnly.contains(approval.tool) ? .ask
            : level(of: session).decide(Gate.risk(tool: approval.tool, input: approval.input, cwd: cwd(of: session) ?? ""))
        if preapproved.remove(Self.approvalKey(approval)) != nil { decision = .allow }
        switch decision {
        case .allow:
            if runs[session]?.connection.answer(approval, allow: true, input: nil) == true {
                log(session, "自動で通した — \(approval.tool) \(approval.detail)")
            } else {
                approvals.append(approval)
                noteAttention(session, "承認を待っている — \(approval.detail)")
            }
        case .queue:
            approval.denyNote = Gate.queuedMessage
            _ = runs[session]?.connection.answer(approval, allow: false, input: nil)
            if !deferred.contains(where: { Self.approvalKey($0) == Self.approvalKey(approval) }) { deferred.append(approval) }
            noteAttention(session, "要判断に積んだ — \(approval.detail)")
        case let .graceAllow(seconds):
            approval.autoAt = Date().addingTimeInterval(seconds)
            approvals.append(approval)
            log(session, "\(Int(seconds))秒後に通す — \(approval.tool) \(approval.detail)")
        case .ask:
            approvals.append(approval)
            noteAttention(session, "承認を待っている — \(approval.detail)")
        }
    }

    /// 猶予が切れた承認を通す（毎秒の見回りから）
    private func releaseGraceApprovals(now: Date) {
        for approval in approvals where approval.autoAt.map({ $0 <= now }) == true {
            if answer(approval, allow: true) { log(approval.session, "猶予の後に通した — \(approval.tool) \(approval.detail)") }
        }
    }

    /// 猶予を止めて人の答えを待つ（書き換えを始めた時）
    func holdGrace(_ id: String) {
        guard let i = approvals.firstIndex(where: { $0.id == id }), approvals[i].autoAt != nil else { return }
        approvals[i].autoAt = nil
    }

    /// 人の番で止まっているものの数（門＋道具の承認＋要判断）。タブとステータスバーの件数
    var stoppedCount: Int { gates.count + approvals.count + deferred.count }

    /// 検査・画像焼きから承認の依頼を直接流し込む口
    func loadApprovalsForProbe(_ requests: [Approval]) { approvals = requests }

    /// 人の注意を引く出来事。見ていないセッションなら未読にし、画面の外（通知）にも渡す
    /// 活動フィード（管制塔）。全 worktree の出来事を新しい順に。ponytail: 200件で古いものから落とす
    struct Activity: Identifiable, Equatable {
        let id = UUID()
        let at: Date
        let session: String
        let title: String
        let text: String
    }
    private(set) var activity: [Activity] = []

    private func noteAttention(_ session: String, _ what: String) {
        log(session, what)
        guard session != selectedSession else { return }
        unread.insert(session)
        onAttention?(session, title(for: session) ?? String(session.prefix(8)), what)
    }

    /// 活動フィードにだけ残す（未読にも通知にもしない。自動で通した道具など）
    private func log(_ session: String, _ what: String) {
        activity.insert(Activity(at: Date(), session: session, title: title(for: session) ?? String(session.prefix(8)), text: what), at: 0)
        if activity.count > 200 { activity.removeLast(activity.count - 200) }
    }

    /// 人の番で止まっている・見ていない間に何か起きたセッションの数（Dock のバッジ）
    var attentionCount: Int {
        Set(approvals.map(\.session))
            .union(liveSessions.filter { $0.waiting != nil }.map(\.id))
            .union(unread).count
    }

    /// 木や ⌘J の行を開く。過去のセッションは読み込み、Codex / Grok の台帳は続きに繋ぐ
    func open(_ row: AgentRow) async {
        selectedSession = row.id
        if let recent = row.recent { await loadSession(recent) }
        else if let record = row.record { resumeRunRecord(record) }
    }

    /// Terminal で続きを開くコマンド。**パスはシェル用に引用する**（空白や ' を含むフォルダでも壊れない）
    func terminalCommand(for session: String) -> String? {
        guard let cwd = cwd(of: session) else { return nil }
        let backend = backend(of: session)
        let exe = Self.shellQuote(found[backend]?.executable.path ?? backend.command)
        let remote = runRecords.first { $0.id == session }?.threadID
        let resume: String
        switch backend {
        case .claude: resume = "\(exe) --resume \(Self.shellQuote(session))"
        case .codex:
            guard let remote else { return nil }
            resume = "\(exe) resume \(Self.shellQuote(remote))"
        case .grok:
            guard let remote else { return nil }
            resume = "\(exe) -r \(Self.shellQuote(remote))"
        case .hermes:
            guard let remote else { return nil }
            resume = "\(exe) --resume \(Self.shellQuote(remote))"
        // ponytail: 続きの開き方は CLI ごとに違い、まだ確かめていない
        case .gemini, .qwen, .goose, .opencode, .copilot, .kimi, .openclaw:
            return nil
        }
        return "cd \(Self.shellQuote(cwd)) && \(resume)"
    }

    nonisolated static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Terminal.app で続きを開く（生の TUI が要る時の逃げ道）。**先に AT22 の接続を閉じる**——
    /// 同じセッションに2つのプロセスが書くと、transcript が混ざる。初回は macOS が操作の許可を訊く
    func openInTerminal(_ session: String) -> String? {
        guard let command = handOff(session) else { return "このセッションの続きを開く手掛かりが無い" }
        return runInTerminal(command)
    }

    /// 続きを端末に渡す。AT22 の接続を閉じて、端末で打つ1行（`cd … && claude --resume …`）を返す
    func handOff(_ session: String) -> String? {
        guard let command = terminalCommand(for: session) else { return nil }
        if let run = runs[session] {
            run.connection.close()
            forget(session)
        }
        return command
    }

    /// 各 CLI 自身のログインを Terminal で起こす。**トークンはその CLI が持つ**——AT22 は何も預からない
    func login(_ backend: Backend) -> String? {
        guard let cli = found[backend] else { return "\(backend.command) が見つからない" }
        return runInTerminal(([cli.executable.path] + backend.loginArguments).map(Self.shellQuote).joined(separator: " "))
    }

    /// 裏で走らせているログイン（Orca と同じく Terminal を開かない）。URL は CLI の出力から拾って画面に出す
    struct LoginRun: Equatable {
        var url: URL?
        var running = true
        var note = ""
    }
    private(set) var loginRuns: [Backend: LoginRun] = [:]
    private var loginProcesses: [Backend: Process] = [:]

    /// CLI の公式のログインを裏で起こす。トークンは CLI が持ち、AT22 は預からない。
    /// 対話式のもの（hermes setup）だけは Terminal で開く
    func startLogin(_ backend: Backend) {
        guard let cli = found[backend] else { loginRuns[backend] = LoginRun(running: false, note: "見つからない"); return }
        if backend.loginIsInteractive {
            loginRuns[backend] = LoginRun(running: false, note: login(backend) ?? "Terminal で開きました")
            return
        }
        loginProcesses[backend]?.terminate()
        let task = Process()
        task.executableURL = cli.executable
        task.arguments = backend.loginArguments
        var env = ProcessInfo.processInfo.environment
        if let path = cli.path { env["PATH"] = path }
        task.environment = env
        task.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        loginRuns[backend] = LoginRun()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let url = Self.firstURL(in: String(decoding: handle.availableData, as: UTF8.self)) else { return }
            Task { @MainActor in if self?.loginRuns[backend]?.url == nil { self?.loginRuns[backend]?.url = url } }
        }
        task.terminationHandler = { [weak self] done in
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = done.terminationStatus == 0
            Task { @MainActor in
                guard let self, self.loginProcesses[backend] === done else { return }
                self.loginProcesses[backend] = nil
                self.loginRuns[backend]?.running = false
                self.loginRuns[backend]?.note = ok ? "ログインが終わりました" : "止まりました。Terminal で続けられます"
            }
        }
        do {
            try task.run()
            loginProcesses[backend] = task
        } catch {
            loginRuns[backend] = LoginRun(running: false, note: "起こせませんでした: \(error.localizedDescription)")
        }
    }

    func cancelLogin(_ backend: Backend) {
        loginProcesses[backend]?.terminate()
        loginProcesses[backend] = nil
        loginRuns[backend] = nil
    }

    /// 出力の中の最初の https の URL（ログインの案内）
    nonisolated static func firstURL(in text: String) -> URL? {
        guard let r = text.range(of: #"https://[^\s"'<>]+"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)")))
    }

    /// CLI を探す（起動時と、設定の「探し直す」）。場所の上書きは設定の値
    /// 選ぶ口に出すプロバイダ（入っていて、設定で無効にしていない）
    func usableBackends() -> [Backend] {
        Backend.usable(found: Set(found.keys), disabled: UserDefaults.standard.string(forKey: Backend.disabledKey) ?? "")
    }

    func findCLIs(force: Bool) {
        let d = UserDefaults.standard
        let paths: [Backend: String] = [.claude: d.string(forKey: Self.claudePathKey) ?? "",
                                        .codex: d.string(forKey: Self.codexPathKey) ?? "",
                                        .grok: d.string(forKey: Self.grokPathKey) ?? ""]
        for backend in Backend.allCases {
            let path = paths[backend] ?? ""
            findIfNeeded(backend, override: path.isEmpty ? nil : path, force: force)
        }
    }

    /// ログインの状態を1行で。調べ方は CLI ごとに違う（どれも読むだけ）
    func loginStatus(_ backend: Backend) async -> String {
        guard let cli = found[backend] else { return "見つからない" }
        return await Task.detached {
            switch backend {
            case .claude:
                let json = (try? Worktree.run(cli.executable.path, ["auth", "status"], in: NSHomeDirectory(), path: cli.path)) ?? ""
                return Self.claudeLogin(json)
            case .codex:
                let text = (try? Worktree.run(cli.executable.path, ["login", "status"], in: NSHomeDirectory(),
                                              path: cli.path, withErrors: true)) ?? ""
                return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未ログイン"
            case .grok:
                return Self.grokLogin(FileManager.default.contents(atPath: NSHomeDirectory() + "/.grok/auth.json"))
            case .hermes:
                return "Hermes の設定に従う（hermes setup）"
            case .gemini, .qwen, .goose, .opencode, .copilot, .kimi, .openclaw:
                return "\(backend.command) の中でログインする"
            }
        }.value
    }

    /// `claude auth status`（JSON）を1行に
    nonisolated static func claudeLogin(_ json: String) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              object["loggedIn"] as? Bool == true else { return "未ログイン" }
        let method = object["authMethod"] as? String ?? ""
        let plan = object["subscriptionType"] as? String ?? ""
        return "ログイン済み（" + [method, plan].filter { !$0.isEmpty }.joined(separator: " · ") + "）"
    }

    /// `~/.grok/auth.json` にアカウントがあればログイン済み。**expires_at は見ない**——
    /// 短命のトークンの期限で、grok が自分で更新する（期限切れの記録のまま動くのを実測）
    nonisolated static func grokLogin(_ data: Data?) -> String {
        guard let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              !object.isEmpty else { return "未ログイン" }
        return "ログイン済み（xAI）"
    }

    /// Terminal.app で1行のコマンドを走らせる。初回は macOS が Terminal の操作の許可を訊く
    private func runInTerminal(_ command: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"Terminal\"", "-e", "activate",
                          "-e", "do script \(Self.appleScriptString(command))", "-e", "end tell"]
        do { try task.run() } catch { return "Terminal を開けない: \(error)" }
        return nil
    }

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
    /// 送った発言をすぐ会話に出す。claude は同じ発言を transcript にも書くので、それが届いた時に
    /// 二重に並ばないよう覚えておく（`apply` の `.said` が1回だけ読み飛ばす）
    func appendHuman(_ text: String, session: String) {
        if backend(of: session) == .claude, !Remote.isRemote(cwd(of: session) ?? "") { echoes[session, default: []].append(text) }
        appendMessage(session: session, agent: session, text: text, thinking: false, speaker: .human, at: Date())
    }

    private func launchCodex(prompt: String, cwd: String, model: String, level: Gate.Level) -> UUID? {
        guard let codex = codexFound else {
            launchError = "codex が見つからない"
            return nil
        }

        _ = codex
        let sessionID = UUID().uuidString.lowercased()
        // app-server に繋ぐ（止める・承認に答える、ができる）。言葉はスレッドが開くまで接続が溜めておく
        guard let run = startCodex(session: sessionID, cwd: cwd, model: model, effort: sessionEffort[sessionID] ?? "",
                                   level: level, resume: nil),
              run.connection.send(promised(prompt, session: sessionID, cwd: cwd, level: level)) else {
            if launchError == nil { launchError = "codex を起動できなかった" }
            return nil
        }

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
        sleeping.remove(session)
        let wire = promisePending.remove(session) != nil
            ? promised(body, session: session, cwd: cwd(of: session) ?? "", level: level(of: session)) : body
        guard run.connection.send(wire) else {
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
            _ = codex
            return startCodex(session: session, cwd: record.cwd, model: sessionModel[session] ?? record.model,
                              effort: sessionEffort[session] ?? "", level: gateLevel, resume: thread)
        case .grok, .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi, .openclaw:
            let backend = backend(of: session)
            guard let record = runRecords.first(where: { $0.id == session }), let remote = record.threadID else {
                launchError = "\(backend.title) のセッションが見つからない"
                return nil
            }
            return startACP(backend, session: session, cwd: record.cwd, model: sessionModel[session] ?? record.model,
                            level: gateLevel, resume: remote)
        }
    }

    /// ACP の相手ごとの起動引数。
    /// grok agent には権限モードの指定が無い。どの段も訊かせて、AT22 が段で決める（--always-approve は使わない）。
    /// それ以外は本人の既定（~/.claude/settings.json の defaultMode）に従う——auto なら grok 自身が判定する。
    /// Hermes はモデルも承認も自身の設定（hermes model / hermes setup）に従う
    nonisolated static func acpArguments(_ backend: Backend, model: String, level: Gate.Level,
                                         effort: String = "") -> [String] {
        switch backend {
        case .grok:
            var arguments = ["agent"]
            if !model.isEmpty { arguments += ["-m", model] }
            if !effort.isEmpty { arguments += ["--reasoning-effort", effort] }
            return arguments + ["stdio"]
        case .hermes, .goose, .opencode, .kimi, .openclaw:
            return ["acp"]
        case .gemini, .qwen, .copilot:
            return ["--acp"]
        case .claude, .codex:
            return []
        }
    }

    /// codex の app-server を起こす。`resume` を渡すと thread/resume で続きへ繋ぐ
    private func startCodex(session: String, cwd: String, model: String, effort: String, level: Gate.Level,
                            resume: String?) -> Run? {
        guard let codex = codexFound else {
            launchError = "codex が見つからない"
            return nil
        }
        let token = UUID()
        do {
            let connection = try CodexServerConnection.start(
                codex.executable, path: codex.path, cwd: cwd, session: session, model: model, effort: effort,
                level: level, resume: resume, onEvent: agentStream(session: session),
                onExit: exitHandler(label: "codex", session: session, token: token))
            let run = Run(connection: connection, token: token)
            runs[session] = run
            backends[session] = .codex
            launchError = nil
            return run
        } catch {
            launchError = "codex を起こせなかった: \(error)"
            return nil
        }
    }

    /// ACP の相手を起こす。`resume` を渡すと session/load で続きへ繋ぐ（履歴は相手が送り直す）
    private func startACP(_ backend: Backend, session: String, cwd: String, model: String, level: Gate.Level,
                          resume: String?) -> Run? {
        guard let cli = found[backend] else {
            launchError = "\(backend.command) が見つからない"
            return nil
        }
        let token = UUID()
        do {
            let connection = try ACPConnection.start(
                cli.executable, arguments: Self.acpArguments(backend, model: model, level: level,
                                                             effort: sessionEffort[session] ?? ""), cwd: cwd,
                path: cli.path, session: session, resume: resume,
                onEvent: agentStream(session: session),
                onExit: exitHandler(label: backend.command, session: session, token: token))
            let run = Run(connection: connection, token: token)
            runs[session] = run
            backends[session] = backend
            return run
        } catch {
            launchError = "\(error)"
            return nil
        }
    }

    /// codex / ACP には system prompt の口が無いので、最初の1通の頭に約束（PLAN・Hydra・記憶）を付ける。
    /// 最初の1通が空で起こした時は、次に送る1通に付ける（`promisePending`）
    private func promised(_ prompt: String, session: String, cwd: String, level: Gate.Level) -> String {
        guard !prompt.isEmpty else { promisePending.insert(session); return prompt }
        var promises = [Sparring.planProtocol, Hydra.protocolText]
        let dir = memoryDirectory(cwd: cwd)
        if !dir.isEmpty && level != .plan { promises.append(Memory.protocolText(dir: dir, session: session)) }
        return "[AT22 からの約束。返事に書き写さなくてよい]\n" + promises.joined(separator: "\n\n") + "\n\n---\n\n" + prompt
    }

    /// 約束をまだ渡していない会話（最初の1通が空だった）
    private var promisePending: Set<String> = []

    private func launchACP(_ backend: Backend, prompt: String, cwd: String, model: String, level: Gate.Level) -> UUID? {
        let sessionID = UUID().uuidString.lowercased()
        guard let run = startACP(backend, session: sessionID, cwd: cwd, model: model, level: level, resume: nil),
              run.connection.send(promised(prompt, session: sessionID, cwd: cwd, level: level)) else { return nil }
        let tab = LiveSession(id: sessionID, name: String(sessionID.prefix(8)), cwd: cwd, busy: false)
        loadedSessionTabs[sessionID] = tab
        liveSessions.append(tab)
        liveSessions.sort { $0.name < $1.name }
        beginTurn(sessionID)
        appendHuman(prompt, session: sessionID)
        // 相手側のIDは挨拶が済んだ時（.ready）に台帳へ入る
        runRecords.append(RunRecord(id: sessionID, threadID: nil, title: Self.titleRule(prompt) ?? "", cwd: cwd,
                                    model: model, lastUsed: Date(), backend: backend))
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
        if writing.contains(wanted) { return true }
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
        adoptMemory(root: projectRoot(of: selectedSession), loaded: nil)
    }

    @ObservationIgnored private var memoryLoading = false
    @ObservationIgnored private var memoryLoadedAt = Date.distantPast
    @ObservationIgnored private var memoryLoadedFor: String?

    /// 毎秒の見回りから。projects の列挙と記憶の .md を全部読むのを裏へ出す（メインで毎秒読んでいた）。
    /// ponytail: 同じ会話なら3秒に1回。会話を切り替えた時はすぐ読む
    private func refreshMemoryInBackground() {
        let session = selectedSession ?? liveSessions.first?.id
        guard !memoryLoading, session != memoryLoadedFor || Date().timeIntervalSince(memoryLoadedAt) > 3 else { return }
        memoryLoading = true
        memoryLoadedAt = Date()
        memoryLoadedFor = session
        let cwd = liveSessions.first { $0.id == session }?.cwd
        let projects = projectsRoot
        Task.detached(priority: .utility) {
            let root = Self.projectRoot(of: session, cwd: cwd, projectsRoot: projects)
            let loaded = root.map { Memory.load(projectRoot: $0) } ?? []
            await MainActor.run { [weak self] in
                self?.memoryLoading = false
                self?.adoptMemory(root: root, loaded: loaded)
            }
        }
    }

    /// `loaded` が nil なら、ここで読む（自己チェックの同期の経路）
    private func adoptMemory(root: URL?, loaded: [Memory.Node]?) {
        guard let root else {
            if !memory.isEmpty { memory = [] }
            memoryRoot = nil
            return
        }
        memoryRoot = root
        let loaded = loaded ?? Memory.load(projectRoot: root)
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
        let wanted = session ?? liveSessions.first?.id
        return Self.projectRoot(of: wanted, cwd: liveSessions.first { $0.id == wanted }?.cwd, projectsRoot: projectsRoot)
    }

    nonisolated private static func projectRoot(of wanted: String?, cwd: String?, projectsRoot: URL) -> URL? {
        guard let wanted else { return nil }
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: projectsRoot.path)) ?? [] {
            let dir = projectsRoot.appendingPathComponent(entry)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(wanted).jsonl").path) {
                return dir
            }
        }
        guard let cwd, !cwd.isEmpty else { return nil }
        let dir = projectsRoot.appendingPathComponent(projectSlug(cwd))
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

    @ObservationIgnored private var memoryRootsCache: (at: Date, roots: [String]) = (.distantPast, [])

    func refreshStructureIfNeeded() {
        // ponytail: projects の列挙は10秒に1回で足りる（新しいプロジェクトの記憶DB は数秒遅れて拾う）
        if Date().timeIntervalSince(memoryRootsCache.at) > 10 { memoryRootsCache = (Date(), Self.memoryRoots()) }
        let roots = Set(liveSessions.map(\.cwd).filter { !$0.isEmpty })
            .union(memoryRootsCache.roots)
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
        var unread = false
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
        /// 失敗した時に同じ中身で作り直すための材料（「再試行」）
        var retry: Retry?

        struct Retry: Equatable {
            let base: String
            let racer: Racer
            let prompt: String
            let level: Gate.Level
            let thinking: String
        }
    }

    /// 登録したリポジトリ。UserDefaults（AT22 自身の記録はここだけに置く）
    private(set) var projects: [String] = UserDefaults.standard.stringArray(forKey: "projects") ?? []
    private(set) var workspaceMeta: [String: WorkspaceMeta] = {
        guard let data = UserDefaults.standard.data(forKey: "workspaceMeta") else { return [:] }
        return (try? JSONDecoder().decode([String: WorkspaceMeta].self, from: data)) ?? [:]
    }()
    /// 各リポジトリの worktree 一覧。git に訊き直すのは数秒おき（裏で）
    private(set) var worktrees: [String: [Worktree.Entry]] = [:]
    /// 各ワークスペースの基点からの差分の量。管制塔のタイルの `+42 −7` に出す（worktree の読み直しと一緒に取る）
    private(set) var diffStats: [String: Worktree.Stat] = [:]
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

    /// プロジェクトの立ち上げ方
    enum NewProject: Equatable {
        /// リモートのリポジトリを置き場の下にクローンする（名前が空なら URL の末尾）
        case clone(url: String, parent: String, name: String)
        /// 置き場の下に新しいフォルダを作り、git init と最初のコミットまで。`github` なら gh repo create で GitHub にも作る
        case local(parent: String, name: String, github: Bool)
        /// 手元の既存のフォルダを登録する（git でなければ git init する）
        case existing(path: String)
    }

    /// クローン先のフォルダ名（URL の末尾から .git を落とす）
    nonisolated static func cloneName(_ url: String) -> String {
        let last = url.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    /// 立ち上げる。git と gh は手元のログインシェルで走らせる（認証も名前の設定も本人のもの）。
    /// 終わったら登録し、本体のパスを返す
    func createProject(_ how: NewProject) async -> Result<String, Error> {
        let result: Result<String, Error> = await Task.detached {
            Result {
                let q = Remote.quote
                func sh(_ command: String, in dir: String) throws { _ = try Worktree.run("/bin/zsh", ["-lc", command], in: dir, withErrors: true) }
                switch how {
                case let .clone(url, parent, name):
                    let folder = name.isEmpty ? Self.cloneName(url) : name
                    guard !url.isEmpty, !folder.isEmpty else { throw Worktree.Failure(message: "URL を書いてください") }
                    let dest = (parent as NSString).appendingPathComponent(folder)
                    guard !FileManager.default.fileExists(atPath: dest) else { throw Worktree.Failure(message: "同じ名前のフォルダが既にある: \(dest)") }
                    try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                    try sh("git clone -- \(q(url)) \(q(dest))", in: parent)
                    return dest
                case let .local(parent, name, github):
                    guard !name.isEmpty else { throw Worktree.Failure(message: "名前を書いてください") }
                    let dest = (parent as NSString).appendingPathComponent(name)
                    guard !FileManager.default.fileExists(atPath: dest) else { throw Worktree.Failure(message: "同じ名前のフォルダが既にある: \(dest)") }
                    try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
                    try "# \(name)\n".write(toFile: dest + "/README.md", atomically: true, encoding: .utf8)
                    // worktree を作るには最初のコミットが要る
                    try sh("git init -q -b main && git add -A && git commit -qm 'はじめ'", in: dest)
                    if github { try sh("gh repo create \(q(name)) --private --source . --push", in: dest) }
                    return dest
                case let .existing(path):
                    if (try? Worktree.root(of: path)) == nil {
                        try sh("git init -q -b main && git add -A && git commit -qm 'はじめ' --allow-empty", in: path)
                    }
                    return try Worktree.root(of: path)
                }
            }
        }.value
        if case let .success(repo) = result { addProject(repo) }
        return result
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
        let bases = workspaceMeta.mapValues(\.baseSHA)
        Task.detached(priority: .utility) {
            var roots: [String: String] = [:]
            for cwd in unknown { roots[cwd] = (try? Worktree.root(of: cwd)) ?? "" }
            var lists: [String: [Worktree.Entry]] = [:]
            for repo in known.union(roots.values.filter { !$0.isEmpty }) {
                lists[repo] = (try? Worktree.list(repo: repo)) ?? []
            }
            // ponytail: 5秒おきに worktree の数だけ `git diff --shortstat`。数十本を超えたら変わった所だけ読む
            var stats: [String: Worktree.Stat] = [:]
            for entry in lists.values.flatMap({ $0 }) {
                stats[entry.path] = Worktree.shortStat(entry.path, base: bases[entry.path] ?? "HEAD")
            }
            let (found, listed, counted) = (roots, lists, stats)
            await MainActor.run { [weak self] in
                guard let self else { return }
                // 空でも merge は観測を鳴らす（5秒ごとに根から描き直していた）
                if !found.isEmpty { self.repoOf.merge(found) { _, new in new } }
                if listed != self.worktrees { self.worktrees = listed }
                if counted != self.diffStats { self.diffStats = counted }
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
                record: runs[session] == nil && !liveSessions.contains { $0.id == session } ? record : nil,
                unread: unread.contains(session)))
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

    /// 1本のワークスペースで走らせるエージェント
    struct Racer: Equatable {
        let name: String
        let backend: Backend
        var model = ""
    }

    /// 1本版。`then` は（置き場, 起こしたセッション, 失敗の理由）
    func createWorkspace(repo: String, name: String, base: String, backend: Backend, model: String,
                         prompt: String, level: Gate.Level,
                         then: ((String, String?, String?) -> Void)? = nil) {
        createWorkspaces(repo: repo, base: base, racers: [Racer(name: name, backend: backend, model: model)],
                         prompt: prompt, level: level, then: then)
    }

    /// ワークスペースを作り、できたらそこでエージェントを起こす。作成は裏で進め、
    /// 待つ間はカードに「作成中」、失敗したら理由を出す（ダイアログは待たせない）。
    /// 2つ以上渡すと**競走**：最初の1本で基点を SHA に固定し、残りも同じ SHA から作って同じ指示を送る。
    /// 作るのは1本ずつ順に——同じリポジトリで `git worktree add` を同時に走らせない（ref や exclude の取り合い）
    func createWorkspaces(repo: String, base: String, racers: [Racer], prompt: String, level: Gate.Level,
                          effort thinking: String = "", then: ((String, String?, String?) -> Void)? = nil) {
        let parent = racers.count > 1 ? "競走 " + base + " " + UUID().uuidString.prefix(8) : nil
        for racer in racers {
            pendingWorkspaces[Worktree.location(repo: repo, name: racer.name)] = PendingWorkspace(repo: repo, name: racer.name, error: nil)
        }
        addProject(repo)
        Task {
            var pinned: String?
            for racer in racers {
                let from = pinned ?? base
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try Worktree.add(repo: repo, name: racer.name, base: from) }
                }.value
                if case let .success(made) = result { pinned = pinned ?? made.baseSHA }
                finishWorkspace(repo: repo, racer: racer, base: base, parent: parent, result: result,
                                prompt: prompt, level: level, thinking: thinking, then: then)
            }
        }
    }

    private func finishWorkspace(repo: String, racer: Racer, base: String, parent: String?,
                                 result: Result<(path: String, branch: String, baseSHA: String), Error>,
                                 prompt: String, level: Gate.Level, thinking: String = "",
                                 then: ((String, String?, String?) -> Void)?) {
        let path = Worktree.location(repo: repo, name: racer.name)
        switch result {
        case let .success(made):
            workspaceMeta[made.path] = WorkspaceMeta(baseRef: base, baseSHA: made.baseSHA, parent: parent, createdAt: Date())
            saveWorkspaceMeta()
            refreshWorktreesIfNeeded(force: true)
            // セットアップスクリプト（リポジトリごと）。終わってからエージェントを起こす
            let script = (UserDefaults.standard.dictionary(forKey: Self.setupScriptsKey)?[repo] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !script.isEmpty, setupDone.insert(made.path).inserted {
                pendingWorkspaces[path]?.error = nil
                setupRunning.insert(made.path)
                Task {
                    let result = await Task.detached(priority: .userInitiated) {
                        Result { try Worktree.run("/bin/zsh", ["-lc", script], in: made.path, withErrors: true) }
                    }.value
                    setupRunning.remove(made.path)
                    if case let .failure(error) = result {
                        noteAttention(made.path, "セットアップスクリプトが失敗した — \(error)")
                        appendLaunchError("セットアップ（\((made.path as NSString).lastPathComponent)）: \(error)")
                    }
                    finishWorkspace(repo: repo, racer: racer, base: base, parent: parent, result: .success(made),
                                    prompt: prompt, level: level, thinking: thinking, then: then)
                }
                return
            }
            pendingWorkspaces[path] = nil
            let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { then?(made.path, nil, nil); return }
            let session = launch(prompt: prompt, cwd: made.path, backend: racer.backend, model: racer.model, level: level,
                                 effort: racer.backend == .claude ? thinking : "")
            then?(made.path, session?.uuidString.lowercased(), session == nil ? (launchError ?? "起こせなかった") : nil)
        case let .failure(error):
            pendingWorkspaces[path]?.error = "\(error)"
            pendingWorkspaces[path]?.retry = .init(base: base, racer: racer, prompt: prompt, level: level, thinking: thinking)
            then?(path, nil, "\(error)")
        }
    }

    /// リポジトリごとのセットアップスクリプト（`[リポジトリのパス: スクリプト]`）
    static let setupScriptsKey = "setupScripts"
    /// セットアップを走らせた／走らせている worktree（二度は走らせない）
    private var setupDone: Set<String> = []
    private(set) var setupRunning: Set<String> = []

    /// 作れなかったワークスペースを同じ中身で作り直す。
    /// ponytail: 競走の1本として作り直しても競走の束には戻さない（勝ちを決める時に並ばない）
    func retryWorkspace(_ path: String) {
        guard let pending = pendingWorkspaces[path], pending.error != nil, let r = pending.retry else { return }
        pendingWorkspaces[path]?.error = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Worktree.add(repo: pending.repo, name: r.racer.name, base: r.base) }
            }.value
            finishWorkspace(repo: pending.repo, racer: r.racer, base: r.base, parent: nil, result: result,
                            prompt: r.prompt, level: r.level, thinking: r.thinking, then: nil)
        }
    }

    /// 同じ競走で走った他のワークスペース（まだ残っているものだけ）
    func rivals(of path: String) -> [String] {
        guard let parent = workspaceMeta[path]?.parent,
              let list = worktrees.values.first(where: { $0.contains { $0.path == path } }) else { return [] }
        return list.map(\.path).filter { $0 != path && workspaceMeta[$0]?.parent == parent }
    }

    /// 競走の勝ちを決める。**人が負けの一覧（未コミットの変更の数つき）を見て押した後だけ**呼ぶ。
    /// 負けは変更ごと消し、枝は `-d`（コミットを積んだ負けの枝は残る）。勝ちは普通のワークスペースに戻る。
    /// 戻り値は人に伝える一言（残した枝など）
    func adopt(_ winner: String) async -> [String] {
        var notes: [String] = []
        for loser in rivals(of: winner) {
            if let note = await deleteWorkspace(loser, force: true, deleteBranch: true) { notes.append(note) }
        }
        workspaceMeta[winner]?.parent = nil
        saveWorkspaceMeta()
        return notes
    }

    /// 検査・画像焼きからワークスペースの木を直接流し込む口。実機の git と ~/.claude に依存させない
    func loadWorkspacesForProbe(projects: [String], worktrees: [String: [Worktree.Entry]],
                                pending: [String: PendingWorkspace] = [:], failed: Set<String> = [],
                                backends: [String: Backend] = [:], meta: [String: WorkspaceMeta] = [:]) {
        self.projects = projects
        self.workspaceMeta = meta
        self.worktrees = worktrees
        self.pendingWorkspaces = pending
        self.failedTurns = failed
        self.backends.merge(backends) { _, new in new }
        lastWorktreeScan = .distantFuture      // 毎秒の読み直しで消されないように
    }

    // MARK: レビューと出荷

    /// 差分に付けるコメント1件。`line` は新しい側の行番号（削除行だけは旧い側）
    struct ReviewComment: Identifiable, Equatable {
        let id = UUID()
        let file: String
        let line: Int?
        let code: String
        var text: String
    }

    /// セッションが居るワークスペース（最も長い前方一致）。一覧をまだ読んでいなければ nil
    func workspacePath(of session: String) -> String? {
        guard let cwd = cwd(of: session) else { return nil }
        return Self.owner(of: cwd, among: worktrees.values.flatMap { $0.map(\.path) })
    }

    /// 差分の基準。AT22 が作ったワークスペースは作った時の SHA（そこからの全部）、
    /// それ以外は HEAD（まだコミットしていない分だけ）
    func reviewBase(of path: String) -> String { workspaceMeta[path]?.baseSHA ?? "HEAD" }

    func review(_ path: String) async -> Result<[Worktree.DiffFile], Worktree.Failure> {
        let base = reviewBase(of: path)
        return await Task.detached {
            Result { try Worktree.review(path, base: base) }.mapError { ($0 as? Worktree.Failure) ?? .init(message: "\($0)") }
        }.value
    }

    /// 行コメントをまとめて1通にする。どのファイルの何行目の、どのコードについてかを必ず添える
    nonisolated static func reviewMessage(_ comments: [ReviewComment]) -> String {
        let items = comments.enumerated().map { index, comment in
            let place = comment.line.map { "\(comment.file):\($0)" } ?? comment.file
            let code = comment.code.isEmpty ? "" : "\n   > \(comment.code.trimmingCharacters(in: .whitespaces))"
            return "\(index + 1). \(place)\(code)\n   \(comment.text)"
        }
        return "レビューのコメントが \(comments.count) 件あります。直してください。\n\n" + items.joined(separator: "\n\n")
    }

    /// 出荷の3つ（コミット・push・PR）。**どれも人が押した時だけ**。結果は人に見せる一言で返す
    func commit(_ path: String, message: String) async -> String {
        await Task.detached {
            do { return try Worktree.commitAll(path, message: message) } catch { return "コミットできない: \(error)" }
        }.value
    }

    func push(_ path: String) async -> String {
        guard let branch = worktrees.values.flatMap({ $0 }).first(where: { $0.path == path })?.branch else {
            return "枝が無い（切り離し）ので push できない"
        }
        return await Task.detached {
            do { return try Worktree.push(path, branch: branch).nilIfEmpty ?? "push した: \(branch)" }
            catch { return "push できない: \(error)" }
        }.value
    }

    /// PR を作る。gh は自分の認証（gh auth）を使う——AT22 は何も預からない
    func createPullRequest(_ path: String) async -> String {
        let entry = worktrees.values.flatMap { $0 }.first { $0.path == path }
        guard let branch = entry?.branch else { return "枝が無い（切り離し）ので PR を作れない" }
        let baseRef = workspaceMeta[path]?.baseRef
        return await Task.detached {
            guard let gh = Launcher.locate(override: nil, command: "gh") else { return "gh が見つからない" }
            // 基点が枝の名前ならそこへ。HEAD や SHA で作ったものは gh の既定（リポジトリの既定の枝）に任せる
            var arguments = ["pr", "create", "--head", branch, "--fill"]
            if let baseRef, baseRef != "HEAD", !baseRef.allSatisfy(\.isHexDigit) { arguments += ["--base", baseRef] }
            do { return try Worktree.run(gh.executable.path, arguments, in: path, path: gh.path) }
            catch { return "PR を作れない: \(error)" }
        }.value
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
    /// 壁打ちの計画を `PLAN:` 行で受け取った司令塔の分。TaskCreate の無い相手のために AT22 が積む
    /// （セッション → 積んだ順のキー）。`NOW: n` / `DONE: n` で n 番目の状態を進める
    private var adoptedPlans: [String: [String]] = [:]

    private func adoptPlan(_ text: String, session: String, at: Date) {
        guard text.contains("PLAN") || text.contains("NOW") || text.contains("DONE") else { return }
        let steps = Sparring.planLines(text)
        if !steps.isEmpty {
            // 番号はいちばん新しい PLAN: の並びで振り直す。続けて数えると、2回目の計画の後の NOW: 1 が
            // 1回目の手順を指していた（済んだ手順が進行中に戻った・2026-10-03 壁打ちで再現）
            var next = (tasks.values.filter { $0.session == session }.map(\.number).max() ?? 0) + 1
            var keys: [String] = []
            for step in steps {
                if let known = tasks.first(where: { $0.value.session == session && $0.value.subject == step })?.key {
                    keys.append(known)
                    continue
                }
                let key = "\(session)#plan\(next)"
                tasks[key] = RoadmapTask(id: key, session: session, number: next, subject: step, activeForm: step,
                                         detail: "計画（PLAN: 行で受け取り）", status: .pending, at: at)
                keys.append(key)
                next += 1
            }
            adoptedPlans[session] = keys
        }
        for (n, done) in Sparring.progressLines(text) {
            guard let keys = adoptedPlans[session], keys.indices.contains(n - 1),
                  let task = tasks[keys[n - 1]] else { continue }
            // 済んだ手順は NOW: で戻さない
            if !done && task.status == .completed { continue }
            tasks[keys[n - 1]]?.status = done ? .completed : .inProgress
            tasks[keys[n - 1]]?.at = at
        }
    }

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
                waiting: waiting,
                ink: Self.inkStatus(record, touching: running?.kind)))
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
    /// いまの動作を InkLoader の状態名で。ファイルを触っていれば書込／読取、そうでなければ
    /// 最後の道具（考えた方が新しければ think）。**Bash の swift build の最中に think を出さない**
    nonisolated static func inkStatus(_ record: AgentRecord, touching: TouchKind?) -> String {
        if let touching { return touching == .write ? "write" : "search" }
        guard let latest = record.latest, let acted = record.actedAt,
              acted >= (record.thoughtAt ?? .distantPast) else { return "think" }
        return ink(for: latest.kind, detail: latest.detail)
    }

    /// 道具の種類 → InkLoader の状態名
    nonisolated static func ink(for kind: WorkKind, detail: String) -> String {
        let d = detail.lowercased()
        switch kind {
        case .edit: return "write"
        case .read, .search: return "search"
        case .build: return "build"
        case .git:
            if d.contains("push") || d.contains("pr create") { return "upload" }
            if d.contains("pull") || d.contains("fetch") || d.contains("clone") { return "download" }
            return "transfer"
        case .spawn: return "handoff"
        case .wait: return "think"
        case .other:
            if ["curl", "wget", "install", "brew", "webfetch", "download"].contains(where: d.contains) { return "download" }
            return "transfer"
        }
    }

    /// あるセッションの司令塔がいま何をしているか（管制塔・鶴・会話の処理中の箱が使う）
    func liveInk(_ session: String?) -> String {
        guard let session, let record = agents[session] else { return "think" }
        let touching = touches.last { $0.session == session && $0.agent == session && $0.finished == nil }?.kind
        return Self.inkStatus(record, touching: touching)
    }

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

        // codex / grok / hermes のセッション（AT22 の台帳に最初の指示が残っている）
        if backend(of: sessionID) != .claude {
            if let record = runRecords.first(where: { $0.id == sessionID }) {
                let result = Self.titleRule(record.title)
                titles.updateValue(result, forKey: sessionID)
                return result
            }
            titles.updateValue(nil, forKey: sessionID)
            return nil
        }

        // claude セッション: transcript から最初のユーザー発言を取得。
        // まだ一覧に無い時は覚えない——起こした直後に nil を覚えると、題が付かないまま残る
        guard let recent = recentSessions.first(where: { $0.id == sessionID }) else { return nil }
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
        var trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        // `[壁打ち · 案を出す]` のような AT22 が付けた頭は題にしない
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            trimmed = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        }
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

    /// 末尾の `maximum` バイト。`end` を渡すとそこまで（そこから先は読まない）
    nonisolated private static func tail(of url: URL, maximum: UInt64, end: UInt64? = nil) -> (data: Data, partial: Bool)? {
        guard maximum > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let stop = min(size, end ?? size)
        guard stop > 0 else { return nil }
        let start = stop > maximum ? stop - maximum : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.read(upToCount: Int(stop - start)) else { return nil }
        return (data, start > 0)
    }

    /// transcript を追いかけている側が、ファイルごとにどこから読み始めたか（App が繋ぐ）
    var watchedFrom: (() -> [String: UInt64])?

    /// `limits` はファイルごとの「ここから先はもう流し込んである」位置。その手前だけを読む
    nonisolated private static func replay(_ session: RecentSession, limits: [String: UInt64] = [:]) -> SessionReplay {
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
            guard let chunk = tail(of: source, maximum: maximum, end: limits[source.path]) else { continue }
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
        // 全部もう流し込んであって読まなかった時も、作業場所（cwd）だけは頭から拾う
        if replay.cwd.isEmpty, let handle = try? FileHandle(forReadingFrom: session.transcriptURL) {
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 65_536)) ?? Data()
            for line in head.split(separator: 0x0A) {
                if let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                   let cwd = obj["cwd"] as? String { replay.cwd = cwd; break }
            }
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
        let limits = watchedFrom?() ?? [:]
        let replay = await Task.detached(priority: .utility) { Self.replay(session, limits: limits) }.value
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
        // 端末で動いているセッションの区切り。AT22 の接続が無いので、状態の変わり目で拾う
        for session in found where runs[session.id] == nil {
            let before = liveSessions.first { $0.id == session.id }
            if session.waiting != nil, before?.waiting == nil { noteAttention(session.id, "承認を待っている") }
            else if before?.busy == true, !session.busy { noteAttention(session.id, "ターンが終わった") }
        }
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

// MARK: - Sumi v10 の画面が読む純関数

/// ACTIONS 欄の1行。「誰が・何を・どこに」を1行に畳んだもの。
/// **SwiftUI を通さずに作る**ので、p0 から並べ方と枝の記号を検査できる
struct ActionRow: Identifiable, Equatable {
    let id: String            // エージェントID。門の行は門のID
    let label: String         // C0 / W1 / W2 …
    var branch: String        // │（司令塔自身）/ ├ / └（配下の最後）
    let verb: String          // WRITE / READ / THINK / WAIT / IDLE / DONE
    let jp: String            // 書込中 / 読取中 / 考え中 / 門で待機 …
    let loader: String        // InkLoader の状態名（write / search / think / wait / idle / done）
    let file: String          // いま触っているファイル名。触っていなければ「していること」
    let path: String?         // FILE の吹き出しを開く先。触っていなければ nil
    let note: String          // +42 −7 / 41 calls / 12s
    let waiting: Bool         // 門で止まっている行。ピンクの四角が点滅する
    /// 書込以外か。墨流しに落とす墨の色がこれで決まる（書込＝青、それ以外＝ピンク）
    var accent: Bool { verb != "WRITE" }
}

/// 05 PLAN の窓。**いま動いている所が必ず入る**ように切り取った5行
struct PlanWindow: Equatable {
    var rows: [RoadmapTask] = []
    /// 進行中の番号。無ければ nil
    var current: Int?
    var total = 0
    var done = 0

    static func == (a: Self, b: Self) -> Bool {
        a.rows.map(\.id) == b.rows.map(\.id) && a.current == b.current
            && a.total == b.total && a.done == b.done
    }
}

extension Cockpit {

    /// 参照回数の点の上限。設定画面の Stepper の上限もこれ（盤面を消したので置き場をここへ移した）
    nonisolated static let maxReadTicks = 6

    /// 1行に押し込む用に Markdown の記号と改行を潰す。
    /// codex に渡すプロンプトは md なので、生のままだと `##` や `**` が門の本文に混ざって読めない。
    /// （`CockpitLayout` を消したのでここへ移した。中身は同じ）
    nonisolated static func plainLine(_ raw: String) -> String {
        var out = ""
        var atLineStart = true
        for ch in raw {
            if ch == "\n" || ch == "\r" || ch == "\t" {
                if !out.isEmpty, out.last != " " { out.append(" ") }
                atLineStart = true
                continue
            }
            // 行頭の見出し・箇条書き・引用の印だけ落とす（文中の記号は残す）
            if atLineStart, ch == "#" || ch == ">" || ch == "-" || ch == "*" || ch == " " { continue }
            atLineStart = false
            if ch == "`" || ch == "*" || ch == "_" { continue }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 書込量の重み 0–5。02 STRUCTURE の流し組みで**字の大きさ**になる（16 + w×4 pt）。
    ///
    /// 旧 `CockpitLayout.writeTier` の切れ目（1 / 10 / 100）をそのまま下3段に使い、
    /// 字で量を語れるように上を2段足した。
    /// ponytail: 切れ目は経験則。300 と 1000 は「1セッションでよく書かれた」の実感値
    nonisolated static func writeWeight(added: Int, removed: Int) -> Int {
        let lines = max(0, added) + max(0, removed)
        switch lines {
        case ..<1:       return 0
        case 1..<10:     return 1
        case 10..<100:   return 2
        case 100..<300:  return 3
        case 300..<1000: return 4
        default:         return 5
        }
    }

    /// エージェントの呼び名。司令塔は C0、配下は W1, W2 …。
    ///
    /// **番号は ID の並びで振る。** チップの並び（労働量順）で振ると、
    /// 働くたびに W2 と W3 が入れ替わって名前が定まらない。
    /// ponytail: 起きた順ではない。起きた順に揃えるなら台帳の parentCall の発行時刻で並べ直す
    nonisolated static func agentLabels(_ chips: [AgentChip]) -> [String: String] {
        var out: [String: String] = [:]
        let workers = chips.filter { $0.depth > 0 }.map(\.id).sorted()
        for chip in chips where chip.depth == 0 { out[chip.id] = "C0" }
        for (i, id) in workers.enumerated() { out[id] = "W\(i + 1)" }
        return out
    }

    /// 門が起こそうとしている相手の呼び名。**まだ起きていない**ので台帳には居ない——
    /// 次に振られる番号を先回りして当てる（v10 の「Wake W6?」）
    nonisolated static func gateLabel(chips: [AgentChip], index: Int = 0) -> String {
        "W\(chips.filter { $0.depth > 0 }.count + 1 + index)"
    }

    /// 04 ACTIONS に出す行。**最大4行**。
    ///
    /// 選ぶ順: 門で待っているもの → 動いているもの → 止まっているがまだ終わっていないもの。
    /// 終わったものは出さず、件数だけ `doneCount` で返す（欄の下端の `+2 DONE`）。
    /// 並べる順は指揮系統: 司令塔自身の行（│）を先に、配下を後に、門の行を最後に置き、
    /// 配下の最後の1行だけ └ にする
    nonisolated static func actionRows(chips: [AgentChip], gates: [Gate.Request],
                                       cells: [FileCell] = [], now: Date = Date(),
                                       limit: Int = 4) -> (rows: [ActionRow], doneCount: Int) {
        let labels = agentLabels(chips)
        let byPath = Dictionary(cells.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        func row(_ chip: AgentChip) -> ActionRow {
            let name = chip.target.map { ($0 as NSString).lastPathComponent }
            let cell = chip.target.flatMap { byPath[$0] }
            let lines = cell.map { "+\($0.added) −\($0.removed)" }
            let (verb, jp, loader): (String, String, String) = {
                if chip.done { return ("DONE", "終了", "done") }
                // 承認待ち・入力待ち。相手は人の答えが来るまで止まっている
                if let waiting = chip.waiting { return ("WAIT", waiting, "wait") }
                guard chip.busy else { return ("IDLE", "待機", "idle") }
                switch chip.kind {
                case .write?: return ("WRITE", "書込中", "write")
                case .read?:  return ("READ", "読取中", "search")
                case nil:
                    // ファイルを触っていない道具（ビルド・git・起動…）も、その動作の印で出す
                    let ink = chip.ink
                    return (ink == "think" ? "THINK" : ink.uppercased(),
                            ink == "think" ? "考え中" : TaskInk.jp[ink] ?? "作業中", ink)
                }
            }()
            return ActionRow(id: chip.id, label: labels[chip.id] ?? "W?",
                             branch: chip.depth == 0 ? "│" : "├",
                             verb: verb, jp: jp, loader: loader,
                             file: name ?? plainLine(chip.doing),
                             path: chip.target,
                             note: verb == "WRITE" ? (lines ?? "±0") : "\(chip.work) calls",
                             waiting: verb == "WAIT")
        }

        let waiting = gates.enumerated().map { i, gate in
            ActionRow(id: gate.id, label: gateLabel(chips: chips, index: i), branch: "├",
                      verb: "WAIT", jp: "門で待機", loader: "wait",
                      file: gate.to.isEmpty ? gate.call : gate.to, path: nil,
                      note: "\(Int(gate.waited(now: now)))s", waiting: true)
        }
        let asking = chips.filter { $0.waiting != nil && !$0.done }.map(row)
        let busy = chips.filter { $0.busy && $0.waiting == nil && !$0.done }.map(row)
        let resting = chips.filter { !$0.busy && $0.waiting == nil && !$0.done }.map(row)
        // 空きがあれば、終わった配下も新しい順に DONE の行で並べる（何体動いたかが件数だけでは見えない）
        let finished = chips.filter { $0.done && $0.depth > 0 }.sorted { $0.lastAt > $1.lastAt }.map(row)
        let picked = Array((waiting + asking + busy + resting + finished).prefix(limit))

        // 並べ直し: 司令塔 → 配下 → 門。待っている司令塔は司令塔の位置のまま
        let root = picked.filter { $0.branch == "│" }
        let workers = picked.filter { $0.branch != "│" && !$0.waiting }
        var ordered = root + workers + picked.filter { $0.waiting && $0.branch != "│" }
        if let last = ordered.lastIndex(where: { $0.branch != "│" }) { ordered[last].branch = "└" }
        // 件数は行に出しきれなかった分だけ
        return (ordered, chips.filter(\.done).count - picked.filter { $0.verb == "DONE" }.count)
    }

    /// 05 PLAN の5行（下帯のティックは同じ関数を `size: 21` で呼ぶ）。
    ///
    /// 窓は**最初の未完了から**始める。残りが窓に満たない時は、手前の完了で埋めて
    /// いつも同じ行数を保つ——行数が揺れると欄の高さが揺れる
    nonisolated static func planWindow(tasks: [RoadmapTask], size: Int = 5) -> PlanWindow {
        var window = PlanWindow()
        window.total = tasks.count
        window.done = tasks.filter { $0.status == .completed }.count
        window.current = tasks.first { $0.status == .inProgress }?.number
        guard !tasks.isEmpty, size > 0 else { return window }
        let first = tasks.firstIndex { $0.status != .completed } ?? tasks.count
        let start = max(0, min(first, tasks.count - size))
        window.rows = Array(tasks[start..<min(tasks.count, start + size)])
        return window
    }

    /// 01 TALK の大見出し。「W5 writes. W6 waits for you.」型の定型文。
    ///
    /// 英語が主・日本語が従（SUMI_ の規律）。**動いている者と待っている者だけ**を主語にする——
    /// 止まっている者まで並べると、見出しが一覧になって目に入らない
    nonisolated static func headline(rows: [ActionRow]) -> String {
        let waiting = rows.filter(\.waiting).map(\.label)
        let moving = rows.filter { !$0.waiting && $0.verb != "IDLE" && $0.verb != "DONE" }
        let verbs: [String: String] = ["WRITE": "writes", "READ": "reads", "THINK": "thinks"]

        var parts: [String] = []
        if moving.count == 1, let one = moving.first {
            parts.append("\(one.label) \(verbs[one.verb] ?? "works").")
        } else if moving.count == 2 {
            parts.append("\(moving[0].label) and \(moving[1].label) are both at work.")
        } else if moving.count > 2 {
            parts.append("\(moving.count) agents are at work.")
        }
        if waiting.count == 1 { parts.append("\(waiting[0]) waits for you.") }
        else if waiting.count > 1 { parts.append("\(waiting.count) wait for you.") }
        return parts.isEmpty ? "All quiet. Ask C0." : parts.joined(separator: " ")
    }

    /// 司令塔の1ターンの足跡。`C0 // READ → WRITE → REPLY` と、参照したファイル名。
    ///
    /// 渡すのは**そのターンの間に司令塔が触った記録**（時刻順）。同じ動作が続いたら1つに畳み、
    /// 長すぎる時は直近の3つだけを残す。参照は書いたものを先に、最大3件
    nonisolated static func turnTrail(_ touches: [(path: String, kind: TouchKind)],
                                      replied: Bool = true) -> (label: String, refs: [String]) {
        var steps: [String] = []
        for touch in touches {
            let step = touch.kind == .write ? "WRITE" : "READ"
            if steps.last != step { steps.append(step) }
        }
        if steps.count > 3 { steps = Array(steps.suffix(3)) }
        if replied { steps.append("REPLY") }
        if steps.isEmpty { steps = ["THINK"] }

        var refs: [String] = []
        let ordered = touches.filter { $0.kind == .write } + touches.filter { $0.kind == .read }
        for touch in ordered {
            let name = (touch.path as NSString).lastPathComponent
            if !refs.contains(name) { refs.append(name) }
            if refs.count == 3 { break }
        }
        return ("C0 // " + steps.joined(separator: " → "), refs)
    }
}

// MARK: - v11 管制塔の木

/// 管制塔に並べる1本。`parent` は分岐元のワークスペース、`race` は同じ指示で走る組の鍵
struct TowerItem: Equatable, Sendable {
    let id: String
    var parent: String? = nil
    var race: String? = nil
    var isMain = false
    /// 並べる順（あなた待ち 0 → 失敗 → 作業中 → 完了 → 既読の完了 → 待機）
    var rank = 5
    /// 待機・既読の完了。畳む時は下の「静か」の列へ送る
    var quiet = false
}

/// 1つのプロジェクトの木の置き方。本体はプロジェクトの見出し行に出すので、木には置かない
struct TowerLane: Equatable, Sendable {
    struct Placed: Equatable, Sendable {
        let id: String
        let depth: Int
        let row: Int
    }
    struct Race: Equatable, Sendable {
        let key: String
        let depth: Int
        let firstRow: Int
        let lastRow: Int
        let members: [String]
    }
    struct Edge: Equatable, Sendable {
        let from: String
        let to: [String]
        /// 競走の組へ向かう枝（点線）
        let toRace: Bool
    }
    var main: String?
    var placed: [Placed] = []
    var races: [Race] = []
    var edges: [Edge] = []
    var rows = 0
    /// 競走の組が始まる行。組の見出しのぶん高くする
    var raceRows: Set<Int> = []
    var quiet: [String] = []
}

extension Cockpit {
    /// v11 `v11Lane` の写し。親子は分岐元、兄弟は rank 順、同じ `race` は1組に束ねる。
    /// `fold` の時は、静かで生きた子孫も持たない枝を「静か」の列へ送る（競走の組は1本でも生きていれば残す）
    nonisolated static func towerLane(_ items: [TowerItem], fold: Bool) -> TowerLane {
        let main = items.first(where: \.isMain)
        let ids = Set(items.map(\.id))
        func parent(_ w: TowerItem) -> String? {
            if w.isMain { return nil }
            if let p = w.parent, ids.contains(p), p != w.id { return p }
            return main?.id
        }
        func kids(_ id: String) -> [TowerItem] {
            items.filter { parent($0) == id }.sorted { $0.rank < $1.rank }
        }
        func live(_ w: TowerItem) -> Bool { !w.quiet || kids(w.id).contains(where: live) }

        var lane = TowerLane(main: main?.id)
        var sunk = Set<String>()
        func sink(_ w: TowerItem) {
            lane.quiet.append(w.id)
            sunk.insert(w.id)
            kids(w.id).forEach(sink)
        }

        indirect enum Unit { case node(TowerItem, [Unit]), race(String, [(TowerItem, [Unit])]) }
        func units(_ id: String) -> [Unit] {
            var ks = kids(id)
            if fold {
                for k in ks where !live(k) && !(k.race.map { key in ks.contains { $0.race == key && live($0) } } ?? false) {
                    sink(k)
                }
                ks = ks.filter { !sunk.contains($0.id) }
            }
            var out: [Unit] = []
            var seen = Set<String>()
            for k in ks where !seen.contains(k.id) {
                if let key = k.race {
                    let group = ks.filter { $0.race == key }
                    group.forEach { seen.insert($0.id) }
                    out.append(.race(key, group.map { ($0, units($0.id)) }))
                } else {
                    seen.insert(k.id)
                    out.append(.node(k, units(k.id)))
                }
            }
            return out
        }

        var row = 0
        func placeNode(_ w: TowerItem, _ ks: [Unit], depth: Int, from: String?) {
            lane.placed.append(.init(id: w.id, depth: depth, row: row))
            if let from { lane.edges.append(.init(from: from, to: [w.id], toRace: false)) }
            for (i, k) in ks.enumerated() {
                if i > 0 { row += 1 }
                placeUnit(k, depth: depth + 1, from: w.id)
            }
        }
        func placeUnit(_ u: Unit, depth: Int, from: String?) {
            switch u {
            case let .node(w, ks): placeNode(w, ks, depth: depth, from: from)
            case let .race(key, members):
                lane.raceRows.insert(row)
                let first = row
                for (i, m) in members.enumerated() {
                    if i > 0 { row += 1 }
                    placeNode(m.0, m.1, depth: depth, from: nil)
                }
                lane.races.append(.init(key: key, depth: depth, firstRow: first, lastRow: row, members: members.map(\.0.id)))
                if let from { lane.edges.append(.init(from: from, to: members.map(\.0.id), toRace: true)) }
            }
        }

        let roots: [Unit] = main.map { units($0.id) }
            ?? items.filter { parent($0) == nil }.map { .node($0, units($0.id)) }
        for (i, u) in roots.enumerated() {
            if i > 0 { row += 1 }
            placeUnit(u, depth: 0, from: nil)
        }
        lane.rows = roots.isEmpty ? 0 : row + 1
        return lane
    }

    /// 分岐元のワークスペース。AT22 が作った時の基点が別の worktree の枝なら、それが親。
    /// 分からなければ nil（本体の子として並ぶ）
    func towerParent(of path: String) -> String? {
        guard let base = workspaceMeta[path]?.baseRef,
              let list = worktrees.values.first(where: { $0.contains { $0.path == path } }) else { return nil }
        return list.first { $0.path != path && $0.branch == base }?.path
    }

    /// 同じ競走の組の鍵（作った時に付けたもの）
    func raceKey(of path: String) -> String? { workspaceMeta[path]?.parent }
}

extension Cockpit {
    /// 画像焼き・検査から題名を直接入れる口（transcript が無いセッションの題名）
    func setTitleForProbe(_ session: String, _ title: String) { titles[session] = title }
}
