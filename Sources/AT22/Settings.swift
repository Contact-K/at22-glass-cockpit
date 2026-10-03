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
    @AppStorage(Backend.disabledKey) private var disabledAgents = ""
    @AppStorage(Backend.addedKey) private var addedAgents = ""
    /// Link の左の段で選んでいるプロバイダ
    @State private var picked: Backend = .claude
    /// 2層目（プロバイダを足す）を開いているか。メニューからは行けない——Link の「＋」からだけ
    @State private var adding = false
    @State private var note: String?
    @State private var skill = SkillInstall.state()
    /// Lv.4 / Lv.5 は一度だけ確かめる（もう一度押すと決まる）
    @State private var armed: Gate.Level?
    @State private var levelNote: String?
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        if adding { addLayer } else { mainLayer }
    }

    /// 1層目（メニューの 10 SETTINGS が着く所）
    private var mainLayer: some View {
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
            row("02", "Link", "連携 · プロバイダを選び、足し、ログインする") {
                SumiPicker(sections: enabled.map { backend in
                    .init(title: backend.title.uppercased(), items: cockpit.models(backend).map(\.id).map { m in
                        .init(id: backend.rawValue + "|" + m, text: label(backend, m), on: agent == backend.rawValue + "|" + m)
                    })
                }, onPick: { _, id in agent = id }) {
                    Text("既定  " + agentLabel + " ▾").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.mono(13))
                .padding(.horizontal, 10).frame(height: 38)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                // 2段: 左でプロバイダを選び、右にその中身（新規の板の「プロバイダ → モデル」と同じ階層）
                HStack(alignment: .top, spacing: 0) {
                    providerList.frame(width: 230)
                    Rectangle().fill(Palette.Light.fg).frame(width: 1)
                    Group {
                        if let show = shown.contains(picked) ? picked : shown.first {
                            providerDetail(show)
                        } else {
                            Text("左の「＋ プロバイダを足す」から、入れたいエージェントを選ぶ").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                        }
                    }
                    .padding(.leading, 18).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                Text("AT22 は API キーも OAuth トークンも預からない。ログインは各 CLI の公式のログインを起こすだけで、トークンは CLI が持つ。")
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
        // 裏のログインが終わったら状態を読み直す
        .onChange(of: cockpit.loginRuns) { if frozen == nil { Task { await readLogins() } } }
    }

    /// 選ぶ口に出すもの（初めからある4つ＋足したもの − 無効）
    private var enabled: [Backend] { Backend.enabled(disabled: disabledAgents, added: addedAgents) }

    /// 使うもの（初めからある4つ＋足したもの）。無効にしたものもここに残して、戻せるようにする
    private var inUse: [Backend] {
        let added = Set(addedAgents.split(separator: ",").map(String.init))
        return Backend.allCases.filter { Backend.builtIn.contains($0) || added.contains($0.rawValue) }
    }

    /// Link に並べるもの: 使うもの（初めからある4つ＋足したもの）のうち、入っているものだけ
    private var shown: [Backend] { inUse.filter { cockpit.found[$0] != nil } }

    /// 左の段。入っているものだけ。一番下の「＋」から2層目（全プロバイダ）へ
    private var providerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("// 入っている  \(shown.count)").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2)
                Spacer()
                Button("↻ 探し直す") { cockpit.findCLIs(force: true) }.buttonStyle(.plain).font(.mono(10)).underline()
                    .help("ログインシェルを1回通して、もう一度探す").padding(.trailing, 10)
            }
            .padding(.bottom, 4)
            ForEach(shown, id: \.self) { providerRow($0) }
            if shown.isEmpty {
                Text("入っているエージェントはまだない").font(.bodyJP(12)).foregroundStyle(Palette.Light.fg3).padding(10)
            }
            Button { adding = true } label: {
                Text("＋ プロバイダを足す").font(.mono(11)).tracking(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).frame(height: 34)
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .padding(.top, 10).padding(.trailing, 10)
        }
    }

    private func providerRow(_ backend: Backend) -> some View {
        let on = picked == backend
        let installed = cockpit.found[backend] != nil
        let off = !enabled.contains(backend) && inUse.contains(backend)
        return HStack(spacing: 8) {
            Rectangle().fill(installed ? Palette.pink : Palette.Light.line).frame(width: 6, height: 6)
            Text(backend.title).font(.bodyJP(14)).lineLimit(1)
            if agent.hasPrefix(backend.rawValue + "|") { Text("既定").font(.mono(9)) }
            if off { Text("無効").font(.mono(9)).opacity(0.6) }
            Spacer(minLength: 4)
            Text(installed ? "入っている" : "未導入").font(.mono(9)).opacity(0.6)
            Text("▸").font(.mono(11)).opacity(on ? 1 : 0.3)
        }
        .padding(.horizontal, 10).frame(height: 34)
        .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
        .background(on ? Palette.Light.fg : .clear)
        .contentShape(Rectangle())
        .onTapGesture { picked = backend }
    }

    /// 右の段。起こし方・使うか・既定・Docs・ログイン・モデル・場所の上書き
    private func providerDetail(_ backend: Backend) -> some View {
        let path = cockpit.found[backend]?.executable.path
        let using = inUse.contains(backend)
        let on = enabled.contains(backend)
        let run = cockpit.loginRuns[backend]
        let start = [backend.command] + (backend.isACP ? Cockpit.acpArguments(backend, model: "", level: .normal) : [])
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(backend.title).font(.display(26))
                Text(backend.isACP ? "ACP" : backend == .claude ? "stream-json" : "exec").font(.mono(9))
                    .padding(.horizontal, 4).padding(.vertical, 1).overlay(Rectangle().stroke(lineWidth: 1))
            }
            Text(path ?? "見つからない · \(backend.command) を入れるか、下に場所を書く").font(.mono(11))
                .foregroundStyle(path == nil ? Palette.Light.danger : Palette.Light.fg2)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Text("起こし方  " + start.joined(separator: " ")).font(.mono(11)).foregroundStyle(Palette.Light.fg2)
            HStack(spacing: 8) {
                if Backend.builtIn.contains(backend) {
                    Button(on ? "■ 使う" : "□ 使う") { toggle(backend) }
                        .buttonStyle(SumiButtonStyle(primary: on, size: 11))
                } else {
                    Button(using ? "外す" : "＋ 選べるようにする") { toggleAdded(backend) }
                        .buttonStyle(SumiButtonStyle(primary: !using, size: 11))
                }
                if path != nil && on && !agent.hasPrefix(backend.rawValue + "|") {
                    Button("既定にする") { agent = backend.rawValue + "|" + (cockpit.models(backend).first?.id ?? "") }
                        .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                }
                Button(path == nil ? "Install ↗" : "Docs ↗") { NSWorkspace.shared.open(backend.homepage) }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11)).help(backend.homepage.absoluteString)
            }
            if path != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("// ログイン").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2)
                    HStack(spacing: 10) {
                        Text(logins[backend] ?? "…").font(.mono(11)).lineLimit(1)
                        Spacer(minLength: 8)
                        if let run, run.running {
                            InkLoader(status: "upload", pitch: 1.2)
                            if let url = run.url {
                                Button("ブラウザで続ける ↗") { NSWorkspace.shared.open(url) }.buttonStyle(.plain).font(.mono(10)).underline()
                            } else {
                                Text("ログインを起こしています").font(.bodyJP(11))
                            }
                            Button("やめる") { cockpit.cancelLogin(backend) }.buttonStyle(.plain).font(.mono(10)).underline()
                        } else {
                            if let note = run?.note, !note.isEmpty {
                                Text(note).font(.bodyJP(11)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                                if note.hasPrefix("止まりました") {
                                    Button("Terminal で") { _ = cockpit.login(backend) }.buttonStyle(.plain).font(.mono(10)).underline()
                                }
                            }
                            Button(backend.loginIsInteractive ? "Terminal で開く ↗" : "ログイン") { cockpit.startLogin(backend) }
                                .buttonStyle(.plain).font(.mono(10)).underline()
                                .help(([backend.command] + backend.loginArguments).joined(separator: " ")
                                      + (backend.loginIsInteractive ? " を Terminal で開く（中で答えながら進む）" : " を裏で起こす"))
                        }
                    }
                }
            }
            let models = cockpit.models(backend)
            if !models.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("// モデル  \(models.count)").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2)
                        .padding(.bottom, 4)
                    ForEach(models.map(\.id), id: \.self) { m in
                        let isDefault = agent == backend.rawValue + "|" + m
                        HStack(spacing: 10) {
                            Text(isDefault ? "■" : "□").font(.mono(11))
                            Text(label(backend, m)).font(.mono(12)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .onTapGesture { if on { agent = backend.rawValue + "|" + m } }
                        .help(on ? "新しく起こす時の既定にする" : "使うようにしてから選べる")
                    }
                }
            }
            if let binding = pathBinding(backend) {
                TextField("\(backend.command) の場所（空なら PATH とログインシェルで探す）", text: binding)
                    .textFieldStyle(.plain).font(.mono(12))
                    .padding(.horizontal, 10).frame(height: 30)
                    .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
            }
        }
        .opacity(using || !Backend.builtIn.contains(backend) ? 1 : 0.55)
    }

    // MARK: 2層目 · プロバイダを足す

    /// 全プロバイダ。入っているものは「＋ 足す」で Link に並び、入っていないものは入れ方を開く
    private var addLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionMark(number: "10", title: "SETTINGS › LINK", jp: "プロバイダを足す")
                    Spacer()
                    Button("← 設定に戻る") { adding = false }.buttonStyle(SumiButtonStyle(primary: false, size: 11))
                }
                Text("Add a provider.").font(.display(44))
                Text("入っているものは「＋ 足す」で Link に並びます。入っていないものは Install ↗ で入れ方を開き、入れてから ↻ 探し直す。"
                     + "どれも ACP か各 CLI の公式の口で繋ぎ、AT22 は鍵を預かりません。")
                    .font(.bodyJP(14)).foregroundStyle(Palette.Light.fg2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)
            HStack {
                Text("// プロバイダ  \(Backend.allCases.count)").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2)
                Spacer()
                Button("↻ 探し直す") { cockpit.findCLIs(force: true) }.buttonStyle(.plain).font(.mono(10)).underline()
            }
            .padding(.bottom, 4)
            LiveScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Backend.allCases, id: \.self) { addRow($0) }
                }
                .frame(width: width, alignment: .leading)
            }
            .frame(height: max(200, height - 84 - 120 - 100))
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
    }

    private func addRow(_ backend: Backend) -> some View {
        let installed = cockpit.found[backend] != nil
        let using = inUse.contains(backend)
        let start = [backend.command] + (backend.isACP ? Cockpit.acpArguments(backend, model: "", level: .normal) : [])
        return HStack(spacing: 12) {
            Rectangle().fill(installed ? Palette.pink : Palette.Light.line).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(backend.title).font(.display(20))
                Text(start.joined(separator: " ") + "  ·  " + (backend.isACP ? "ACP" : backend == .claude ? "stream-json" : "exec"))
                    .font(.mono(10)).foregroundStyle(Palette.Light.fg2)
            }
            Spacer(minLength: 8)
            Text(installed ? "入っている" : "未導入").font(.mono(10)).foregroundStyle(Palette.Light.fg3)
            Button(installed ? "Docs ↗" : "Install ↗") { NSWorkspace.shared.open(backend.homepage) }
                .buttonStyle(SumiButtonStyle(primary: false, size: 11)).help(backend.homepage.absoluteString)
            if Backend.builtIn.contains(backend) {
                Text("初めから").font(.mono(10)).foregroundStyle(Palette.Light.fg3).frame(width: 96)
            } else {
                Button(using ? "✓ 足した" : "＋ 足す") { toggleAdded(backend) }
                    .buttonStyle(SumiButtonStyle(primary: !using, size: 11)).frame(width: 96)
                    .help(using ? "押すと外す" : installed ? "Link に並べる" : "入れたら Link に並ぶ")
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
    }

    private func toggleAdded(_ backend: Backend) {
        var added = Set(addedAgents.split(separator: ",").map(String.init))
        if added.contains(backend.rawValue) { added.remove(backend.rawValue) } else { added.insert(backend.rawValue) }
        addedAgents = added.sorted().joined(separator: ",")
    }

    private func toggle(_ backend: Backend) {
        var off = Set(disabledAgents.split(separator: ",").map(String.init))
        if off.contains(backend.rawValue) { off.remove(backend.rawValue) } else { off.insert(backend.rawValue) }
        disabledAgents = off.sorted().joined(separator: ",")
    }

    private func pathBinding(_ backend: Backend) -> Binding<String>? {
        switch backend {
        case .claude: $claudePath
        case .codex: $codexPath
        case .grok: $grokPath
        case .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi: nil
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
