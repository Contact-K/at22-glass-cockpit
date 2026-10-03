import SwiftUI

// MARK: - 10 SETTINGS

/// 設定はここ1か所（⌘, もこのタブを開く）。承認の段・エージェントと CLI・起こすかどうか・スキル・表示・置き場
struct SettingsScreen: View {
    static let levelKey = "defaultLevel"
    static let agentKey = "defaultAgent"
    /// 新しく起こす claude の既定のエフォート（空なら claude の既定）。会話画面の入力欄の左からも選べる
    static let effortKey = "defaultEffort"

    let cockpit: Cockpit
    let width: CGFloat
    /// 窓の高さ。900 未満では行の上下を詰めて、最後の行まで下帯の上に収める
    var height: CGFloat = 900

    @AppStorage(levelKey) private var level = Gate.defaultLevel.rawValue
    @AppStorage(agentKey) private var agent = "claude|opus"
    @AppStorage("showThinking") private var showThinking = false
    /// 上限は参照の点の数（Cockpit.maxReadTicks）に合わせる。
    /// ここを超えると点が埋まりきったまま増えず、「あと何回でフラグか」が読めなくなる
    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    /// 連携機能は既定オフ。**入れただけで LLM を起こすアプリにはしない**
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    /// CLI の場所を人が指定する口。空ならログインシェルに訊く
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""
    @AppStorage(Cockpit.grokPathKey) private var grokPath = ""
    @AppStorage(Worktree.rootKey) private var worktreeRoot = ""
    /// 各 CLI のログインの状態。開いた時と、ログインを押して戻った時に読み直す
    @State private var logins: [Backend: String] = [:]
    @State private var loginProblem: String?
    @State private var note: String?
    @State private var skill = SkillInstall.state()
    /// Lv.4 / Lv.5 は一度だけ確かめる（もう一度押すと決まる）
    @State private var armed: Gate.Level?
    @State private var levelNote: String?
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionMark(number: "10", title: "SETTINGS", jp: "設定")
                Text("Defaults.").font(.display(44))
            }
            .padding(.bottom, 18)
            // 行が増えて低い窓では下帯に潜るので、行の部分だけ送れるようにする
            LiveScroll {
            VStack(alignment: .leading, spacing: 0) {
            row("01", "Approval", "承認の段 · 新しいワークスペースの既定と、いまの会話") {
                HStack(spacing: 0) {
                    ForEach(Array(Gate.Level.allCases.enumerated()), id: \.offset) { i, l in
                        let on = level == l.rawValue
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(String(l.title.prefix { $0 != " " }).uppercased()).font(.mono(11)).tracking(0.9)
                                if cockpit.selectedSession != nil && cockpit.gateLevel == l {
                                    Text("いま").font(.mono(9)).padding(.horizontal, 4).padding(.vertical, 1)
                                        .overlay(Rectangle().stroke(lineWidth: 1))
                                }
                            }
                            Text(armed == l ? "もう一度押す" : String(l.title.drop { $0 != " " }.dropFirst())).font(.bodyJP(13))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
                        .background(on ? Palette.Light.fg : .clear)
                        .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Palette.Light.fg).frame(width: 1) } }
                        .contentShape(Rectangle())
                        .onTapGesture { pickLevel(l) }
                        .help(NewWorkspaceSheet.levelNote[l] ?? "")
                    }
                }
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                if let levelNote { Text(levelNote).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
            }
            row("02", "Agents", "既定のエージェントと、各 CLI の場所・ログイン") {
                SumiPicker(sections: Backend.allCases.map { backend in
                    .init(title: backend.title.uppercased(), items: cockpit.models(backend).map(\.id).map { m in
                        .init(id: backend.rawValue + "|" + m, text: label(backend, m), on: agent == backend.rawValue + "|" + m)
                    })
                }, onPick: { _, id in agent = id }) {
                    Text("既定  " + agentLabel + " ▾").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.mono(13))
                .padding(.horizontal, 10).frame(height: 38)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                // 見つかった場所を必ず出す。見つからない時しか出さないと「探したのか・見つけたのか」が読めない
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Backend.allCases, id: \.self) { agentLine($0) }
                }
                if let loginProblem { Text(loginProblem).font(.bodyJP(12)).foregroundStyle(Palette.Light.danger) }
                Text("AT22 は API キーも OAuth トークンも預からない。ログイン済みの CLI を起こすだけで、通信はそのプロセスが行う。"
                     + "場所は通常ログインシェルを1回通して見つける。見つからない環境だけ絶対パスを書く。")
                    .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).fixedSize(horizontal: false, vertical: true)
            }
            row("03", "Launch", "AT22 から起こすか") {
                HStack(spacing: 12) {
                    Button(launcherEnabled ? "■ セッションを起こす · 続きを送る" : "□ セッションを起こす · 続きを送る") {
                        launcherEnabled.toggle()
                    }
                    .buttonStyle(SumiButtonStyle(primary: launcherEnabled, size: 11))
                    Text("既定は切。入れただけで LLM を起こすアプリにしないため")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2)
                }
            }
            row("04", "Display", "表示と片付け") {
                HStack(spacing: 8) {
                    Button(showThinking ? "■ 思考を見せる" : "□ 思考を見せる") { showThinking.toggle() }
                        .buttonStyle(SumiButtonStyle(primary: showThinking, size: 11))
                    Button("止まったエージェントを畳む") {
                        cockpit.clearIdleAgents(now: Date())
                        flash("止まったエージェントを畳みました")
                    }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    Button("全部まっさらに") {
                        cockpit.clear()
                        flash("ここから先だけを数えます")
                    }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    if let note { Text(note).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
                }
                HStack(spacing: 8) {
                    Button("−") { threshold = max(2, threshold - 1) }.buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    Text("\(threshold) 回").font(.mono(13)).frame(width: 44)
                    Button("＋") { threshold = min(Cockpit.maxReadTicks, threshold + 1) }
                        .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    // 実 transcript 2478組の分布から既定は3回（当てはまるのは全体の1.4%）
                    Text("同じエージェントがこの回数以上読み、一度も書いていないファイルに ⚑ を立てる")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2)
                }
            }
            row("05", "Worktrees", "置き場 · 新しく作るワークスペースから効く") {
                TextField("空ならリポジトリの中（<リポジトリ>/" + Worktree.directory + "）· 例 ~/worktrees", text: $worktreeRoot)
                    .textFieldStyle(.plain).font(.mono(13))
                    .padding(.horizontal, 10).frame(height: 38)
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                Text(Worktree.location(repo: "<リポジトリ>", name: "名前", root: worktreeRoot)
                     + "  ·  枝は " + Worktree.branch(for: "名前"))
                    .font(.mono(11)).foregroundStyle(Palette.Light.fg2).lineLimit(1).minimumScaleFactor(0.7)
            }
            row("06", "Skills", "門の手順と、入っているスキル") {
                HStack(spacing: 12) {
                    Button(skill == .current ? "入れ直す" : "門の手順をインストール") { installSkill() }
                        .buttonStyle(SumiButtonStyle(primary: skill != .current, size: 11))
                        .disabled(SkillInstall.source == nil)
                    Text(skill.label + " · ~/.claude/skills/\(SkillInstall.name)")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).lineLimit(1).minimumScaleFactor(0.8)
                }
                // 入っているスキル（変換はしない）。claude 側のスキルを codex / grok にも見せる時は共有の置き場にリンクを張る
                VStack(alignment: .leading, spacing: 0) {
                    Text("入っているスキル · \(cockpit.skills.count) 本 · 入力欄の「／」から呼べる")
                        .font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2).padding(.bottom, 4)
                    ForEach(cockpit.skills) { s in
                        let shared = cockpit.skills.contains { $0.source == .agents && $0.name == s.name }
                        HStack(spacing: 10) {
                            Text(s.name).font(.mono(12)).lineLimit(1)
                            Text(s.plugin.isEmpty ? s.source.label : "プラグイン · " + s.plugin)
                                .font(.bodyJP(10)).foregroundStyle(Palette.Light.fg3).lineLimit(1)
                            Spacer(minLength: 0)
                            if s.source == .claude || s.source == .plugin || s.source == .repo {
                                if shared {
                                    Text("共有済み").font(.mono(9)).foregroundStyle(Palette.Light.fg3)
                                } else {
                                    Button("共有") { share(s) }.buttonStyle(.plain).font(.mono(10)).underline()
                                        .help("~/.agents/skills と ~/.grok/skills にリンクを張り、codex / grok からも見えるようにする")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .help(s.description)
                    }
                }
                .task { await cockpit.refreshSkills(repo: nil) }
            }
            }
            .frame(width: width, alignment: .leading)
            }
            .frame(height: max(200, height - 84 - 120 - 60))
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
        .task(id: cockpit.found.keys.sorted { $0.rawValue < $1.rawValue }) { if frozen == nil { await readLogins() } }
    }

    /// 1つのエージェントの行。見つかった場所・ログインの状態・ログインの口・場所の手入力
    private func agentLine(_ backend: Backend) -> some View {
        let path = cockpit.found[backend]?.executable.path
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(backend.title.uppercased()).font(.mono(11)).tracking(0.9).frame(width: 64, alignment: .leading)
                Text(path ?? "見つからない · 下の欄に絶対パスを書く").font(.mono(11))
                    .foregroundStyle(path == nil ? Palette.Light.danger : Palette.Light.fg2)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 8)
                if path != nil {
                    Text(logins[backend] ?? "…").font(.mono(10)).foregroundStyle(Palette.Light.fg3).lineLimit(1)
                    Button("ログイン") {
                        loginProblem = cockpit.login(backend)
                        // Terminal で済ませて戻ってきた頃に読み直す
                        Task {
                            try? await Task.sleep(for: .seconds(20))
                            await readLogins()
                        }
                    }
                    .buttonStyle(.plain).font(.mono(10)).underline()
                    .help("\(backend.command) \((backend.loginArguments).joined(separator: " ")) を Terminal で開く")
                }
            }
            // 欄は見つからない時か、既に手で書いてある時だけ。見つかっている CLI に欄を並べると行が倍に伸びる
            if let binding = pathBinding(backend), path == nil || !binding.wrappedValue.isEmpty {
                TextField("\(backend.command) の場所（空ならログインシェルに訊く）", text: binding)
                    .textFieldStyle(.plain).font(.mono(12))
                    .padding(.horizontal, 10).frame(height: 30)
                    .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
    }

    private func pathBinding(_ backend: Backend) -> Binding<String>? {
        switch backend {
        case .claude: $claudePath
        case .codex: $codexPath
        case .grok: $grokPath
        case .hermes: nil
        }
    }

    private func readLogins() async {
        for backend in Backend.allCases where cockpit.found[backend] != nil {
            logins[backend] = await cockpit.loginStatus(backend)
        }
    }

    private var agentLabel: String {
        let parts = agent.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let b = Backend(rawValue: parts.first ?? "") else { return agent }
        return label(b, parts.count > 1 ? parts[1] : "")
    }

    private func label(_ b: Backend, _ m: String) -> String { b.title + " " + (m.isEmpty ? "既定" : m) }

    private func row<C: View>(_ n: String, _ en: String, _ jp: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(n).font(.mono(11)).tracking(1.1).foregroundStyle(Palette.pink)
                Text(en).font(.display(24))
                Text(jp).font(.brush(13))
            }
            content()
        }
        .padding(.vertical, height < 900 ? 9 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
    }

    /// 段を選ぶ。新しいワークスペースの既定にし、会話を開いていればその会話の段にも書く（次に送った時から）
    private func pickLevel(_ l: Gate.Level) {
        if (l == .auto || l == .unattended), armed != l, l.rawValue != level || cockpit.gateLevel != l {
            armed = l
            levelNote = "人の承認なしに書き換える段です。もう一度押すと決まります"
            return
        }
        armed = nil
        level = l.rawValue
        if cockpit.selectedSession != nil {
            levelNote = cockpit.applyLevel(l, to: cockpit.selectedSession) == .saved
                ? "\(l.title) にしました。いまの会話にも、次に送った時から効きます"
                : "既定にしました（いまの会話には書けませんでした）"
        } else {
            levelNote = "\(l.title) を新しいワークスペースの既定にしました"
        }
    }

    private func share(_ s: Skills.Skill) {
        do {
            let made = try Skills.share(s)
            flash(made.isEmpty ? "\(s.name) は既に共有されています" : "\(s.name) を codex / grok にも見せました")
            Task { await cockpit.refreshSkills(repo: nil) }
        } catch {
            flash("共有できませんでした: \(error.localizedDescription)")
        }
    }

    private func installSkill() {
        do {
            try SkillInstall.install()
            skill = SkillInstall.state()
            flash("門の手順を入れました（新しく起こしたセッションから効きます）")
        } catch {
            flash("入れられませんでした: \(error.localizedDescription)")
        }
    }

    private func flash(_ text: String) {
        note = text
        Task { try? await Task.sleep(for: .seconds(2.4)); if note == text { note = nil } }
    }
}

/// SETTINGS の右列。操作の鍵の一覧
struct KeysPanel: View {
    let height: CGFloat

    static let keys = [("M", "メニュー"), ("⌘,", "設定（このタブ）"), ("←  →", "メニューの階層を上る · 入る"), ("⌘0", "管制塔 ⇄ 会話"),
                       ("⌘J", "ワークスペースへ飛ぶ"), ("⌘1–6", "待ちの順に飛ぶ"), ("⌃`", "端末を引き出す · しまう"),
                       ("⌘P", "ファイルを開く"), ("⌘S", "開いたファイルを保存"), ("ESC", "閉じる · 戻る")]

    var body: some View {
        SumiPanel(number: "10", title: "KEYS", jp: "操作", foot: nil) {
            ForEach(Self.keys, id: \.0) { k, d in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(k).font(.mono(12)).frame(width: 84, alignment: .leading)
                    Text(d).font(.bodyJP(13))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            }
        }
        .frame(width: 352, height: height - 136)
    }
}

/// 門の手順（Resources/Skills/at22-gate）を Claude Code のユーザーのスキル置き場へ入れる。
/// **人が押した時だけ書く**。入れた後は claude が自分で読み、サブエージェントを起こす前に gate.sh を呼ぶ
enum SkillInstall {
    static let name = "at22-gate"

    enum State {
        case missing, stale, current
        var label: String {
            switch self {
            case .missing: "未インストール"
            case .stale: "入っているが AT22 の版と違う（入れ直すと手元の変更は消える）"
            case .current: "インストール済み"
            }
        }
    }

    /// 配布物は .app の Resources/Skills、`swift run` はリポジトリの Resources/Skills
    static var source: URL? {
        let manager = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Skills/\(name)"),
           manager.fileExists(atPath: bundled.path) { return bundled }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Skills/\(name)")
        return manager.fileExists(atPath: repo.path) ? repo : nil
    }

    static var target: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/skills/\(name)")
    }

    static func state() -> State {
        guard let source else { return .missing }
        let manager = FileManager.default
        guard manager.fileExists(atPath: target.path) else { return .missing }
        let files = (try? manager.contentsOfDirectory(atPath: source.path)) ?? []
        let same = files.allSatisfy { f in
            manager.contentsEqual(atPath: source.appendingPathComponent(f).path, andPath: target.appendingPathComponent(f).path)
        }
        return same ? .current : .stale
    }

    static func install() throws {
        guard let source else { throw CocoaError(.fileNoSuchFile) }
        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
        try manager.copyItem(at: source, to: target)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.appendingPathComponent("gate.sh").path)
    }
}
