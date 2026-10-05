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
    /// Link の左の段で選んでいるプロバイダ
    @State private var picked: Backend = .claude
    /// 2層目（プロバイダを足す）を開いているか。メニューからは行けない——Link の「＋」からだけ
    @State private var adding = false
    /// SSH の接続先（08 Remote）。書き換えたら保存する
    @State private var hosts: [Remote.Host] = Remote.hosts
    @AppStorage(Cockpit.sleepAfterKey) private var sleepAfter = 15
    @AppStorage(Cockpit.autoAfterPlanKey) private var autoAfterPlan = false
    @AppStorage(Hydra.maxHeadsKey) private var hydraHeads = 8
    @AppStorage(Hydra.maxRoundsKey) private var hydraRounds = 3
    @AppStorage(Hydra.maxToolsKey) private var hydraTools = 160
    @AppStorage(Hydra.maxMinutesKey) private var hydraMinutes = 35
    /// Tailscale の相手（08 Remote の「Tailscale から選ぶ」）。nil は未取得
    @State private var tsPeers: [(name: String, online: Bool, os: String)]?
    @State private var tsProblem: String?
    /// 会話を起こした後に会話画面へ（08 Remote の「会話を起こす」）
    var onTalk: () -> Void = {}
    @State private var note: String?
    @State private var skill = SkillInstall.state()
    /// Lv.3 / Lv.4 は一度だけ確かめる（もう一度押すと決まる）
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
                    ForEach(Array(Gate.Level.ladder.enumerated()), id: \.offset) { i, l in
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
                settingLine("計画の後", "壁打ちで計画を確定したら（計画の窓で「この計画で進める」・05 PLAN に積まれた）、その会話の段を Lv.3 任せてるにする") {
                    Button(autoAfterPlan ? "■ 任せてるへ" : "□ 任せてるへ") { autoAfterPlan.toggle() }
                        .buttonStyle(SumiButtonStyle(primary: autoAfterPlan, size: 11))
                }
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
            row("03", "Launch", "AT22 からエージェントを動かすか") {
                HStack(spacing: 12) {
                    Button(launcherEnabled ? "■ 動かす" : "□ 動かす") { launcherEnabled.toggle() }
                        .buttonStyle(SumiButtonStyle(primary: launcherEnabled, size: 11))
                    Text(launcherEnabled
                         ? "入: 会話から新しく起こす・続きを送る・承認に答える、ができる"
                         : "切: 見るだけ。端末で動いている claude の様子を眺めるだけで、AT22 からは何も起こさない")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).fixedSize(horizontal: false, vertical: true)
                }
                Text("既定は切。入れただけで LLM を起こし、料金がかかるアプリにしないため")
                    .font(.bodyJP(11)).foregroundStyle(Palette.Light.fg3)
            }
            row("04", "Display", "画面に出すもの・片付け") {
                settingLine("思考", "会話に、エージェントが考えた途中（thinking）も出すか") {
                    Button(showThinking ? "■ 見せる" : "□ 見せる") { showThinking.toggle() }
                        .buttonStyle(SumiButtonStyle(primary: showThinking, size: 11))
                }
                settingLine("片付け", "管制塔と ACTIONS から、終わったサブエージェントの行を消す（記録は残る）") {
                    Button("止まったものを畳む") {
                        cockpit.clearIdleAgents(now: Date())
                        flash("止まったエージェントを畳みました")
                    }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                }
                settingLine("数え直し", "触った回数・⚑・作業の量をゼロにして、ここから先だけを数える（会話は消えない）") {
                    Button("まっさらに") {
                        cockpit.clear()
                        flash("ここから先だけを数えます")
                    }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                }
                if let note { Text(note).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
                // 実 transcript 2478組の分布から既定は3回（当てはまるのは全体の1.4%）
                settingLine("⚑ 読みすぎ", "同じエージェントがこの回数以上読み、一度も書いていないファイルに ⚑（迷っている印）を立てる") {
                    HStack(spacing: 6) {
                        Button("−") { threshold = max(2, threshold - 1) }.buttonStyle(SumiButtonStyle(primary: false, size: 11))
                        Text("\(threshold) 回").font(.mono(13)).frame(width: 44)
                        Button("＋") { threshold = min(Cockpit.maxReadTicks, threshold + 1) }
                            .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    }
                }
            }
            row("05", "Worktrees", "新しいワークスペース（worktree）を作る場所 · 次に作るものから効く") {
                TextField("空ならリポジトリの中（<リポジトリ>/" + Worktree.directory + "）· 例 ~/worktrees", text: $worktreeRoot)
                    .textFieldStyle(.plain).font(.mono(13))
                    .padding(.horizontal, 10).frame(height: 38)
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                Text(Worktree.location(repo: "<リポジトリ>", name: "名前", root: worktreeRoot)
                     + "  ·  枝は " + Worktree.branch(for: "名前"))
                    .font(.mono(11)).foregroundStyle(Palette.Light.fg2).lineLimit(1).minimumScaleFactor(0.7)
                Text("// セットアップ · worktree を作った直後に、その中で走らせる（終わってからエージェントを起こす）")
                    .font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2).padding(.top, 6)
                ForEach(cockpit.projects, id: \.self) { repo in
                    HStack(spacing: 10) {
                        Text((repo as NSString).lastPathComponent).font(.mono(12)).frame(width: 150, alignment: .leading).lineLimit(1)
                        TextField("例 npm install && cp ../.env .env", text: Binding(
                            get: { UserDefaults.standard.dictionary(forKey: Cockpit.setupScriptsKey)?[repo] as? String ?? "" },
                            set: { value in
                                var all = UserDefaults.standard.dictionary(forKey: Cockpit.setupScriptsKey) ?? [:]
                                all[repo] = value
                                UserDefaults.standard.set(all, forKey: Cockpit.setupScriptsKey)
                            }))
                            .textFieldStyle(.plain).font(.mono(12))
                            .padding(.horizontal, 10).frame(height: 30)
                            .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
                    }
                }
                if cockpit.projects.isEmpty {
                    Text("登録したリポジトリはまだない（管制塔で足すとここに並ぶ）").font(.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
                }
            }
            row("06", "Skills", "同梱のスキル（門・記憶DB の書き方・Hydra）と、入っているスキル") {
                HStack(spacing: 12) {
                    Button(skill == .current ? "入れ直す" : "同梱のスキルをインストール") { installSkill() }
                        .buttonStyle(SumiButtonStyle(primary: skill != .current, size: 11))
                        .disabled(SkillInstall.sourceRoot == nil)
                    Text(skill.label + " · ~/.claude/skills/ に " + SkillInstall.names.joined(separator: "・"))
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
            row("07", "Sessions", "会話の動かし方 · 裏で動いているものの扱い") {
                settingLine("眠らせる", "この分数動かなかった claude のプロセスを畳む。送る時に続きから起こし直す（0 で畳まない）") {
                    stepper(value: $sleepAfter, range: 0...240, step: 5, unit: "分")
                }
                settingLine("Hydra 同時", "一系統（head が呼んだ分も含む）で同時に動かせる数") {
                    stepper(value: $hydraHeads, range: 1...16, step: 1, unit: "体")
                }
                settingLine("Hydra 回数", "一系統で任せられる回数（ラウンド）。越えたら任せずに司令塔へ知らせる") {
                    stepper(value: $hydraRounds, range: 1...10, step: 1, unit: "回")
                }
                settingLine("Hydra 道具", "head 1体が使える道具の回数。越えたら止めて司令塔へ知らせる") {
                    stepper(value: $hydraTools, range: 20...1000, step: 20, unit: "回")
                }
                settingLine("Hydra 時間", "head 1体が動ける時間。越えたら止めて司令塔へ知らせる") {
                    stepper(value: $hydraMinutes, range: 5...240, step: 5, unit: "分")
                }
            }
            row("08", "Remote", "ほかのマシンで動かす · SSH か Tailscale で。VPN（WireGuard など）は繋がっていれば SSH で届く") {
                ForEach($hosts) { $host in
                    let via = host.via ?? .ssh
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            hostField("名前", text: $host.name).frame(width: 110)
                            hostField(via == .tailscale ? "Tailscale のマシン名" : "user@host または Host 名", text: $host.target)
                            hostField("相手の作業フォルダ（絶対パス）", text: $host.path)
                            Button("会話を起こす ▸") { startRemote(host) }
                                .buttonStyle(SumiButtonStyle(primary: true, size: 11))
                                .disabled(host.target.isEmpty || host.path.isEmpty)
                            Button("×") { hosts.removeAll { $0.id == host.id } }.buttonStyle(.plain).font(.mono(12))
                        }
                        HStack(spacing: 8) {
                            Text("経由").font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).frame(width: 110, alignment: .leading)
                            HStack(spacing: 0) {
                                ForEach(Remote.Via.allCases, id: \.self) { v in
                                    Button(v.title) { host.via = v }.buttonStyle(SumiButtonStyle(primary: via == v, size: 11))
                                }
                            }
                            if via == .ssh {
                                hostField("ssh の追加オプション（例 -J bastion -p 2222 -i ~/.ssh/work）",
                                          text: Binding(get: { host.options ?? "" }, set: { host.options = $0 }))
                            } else {
                                tailscalePicker { host.target = $0 }
                                Text("相手で tailscale up --ssh を済ませておく。鍵は要らない")
                                    .font(.bodyJP(11)).foregroundStyle(Palette.Light.fg3)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                }
                Button("＋ 接続先を足す") { hosts.append(.init(name: "", target: "", path: "")) }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                Text("相手のマシンにも、使うエージェント（claude など）を入れてログインしておく。相手の transcript と記憶DB は読めないので、会話は流れてきた分だけを出す")
                    .font(.bodyJP(11)).foregroundStyle(Palette.Light.fg3).fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: hosts) { Remote.hosts = hosts }
            row("09", "Schedule", "定期実行 · 決めた worktree に、決めた間隔か毎日の時刻で指示を送る（AT22 が開いていて、03 が入の間だけ）") {
                let spaces = cockpit.workspaceTree().flatMap(\.workspaces)
                ForEach(cockpit.schedules.indices, id: \.self) { i in
                    let s = cockpit.schedules[i]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button(s.enabled ? "■" : "□") { cockpit.schedules[i].enabled.toggle() }.buttonStyle(.plain).font(.mono(13))
                            SumiPicker(sections: [.init(title: "WORKTREE", items: spaces.map {
                                .init(id: $0.id, text: $0.name, on: $0.id == s.workspace)
                            })], onPick: { _, id in cockpit.schedules[i].workspace = id }) {
                                Text((s.workspace.isEmpty ? "worktree を選ぶ" : (s.workspace as NSString).lastPathComponent) + " ▾")
                                    .font(.mono(12)).padding(.horizontal, 8).frame(height: 30)
                                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                            }
                            if s.dailyAt.isEmpty {
                                stepper(value: Binding(get: { cockpit.schedules[i].everyMinutes },
                                                       set: { cockpit.schedules[i].everyMinutes = $0 }),
                                        range: 5...1440, step: 5, unit: "分ごと")
                            }
                            hostField("毎日 HH:mm（空なら間隔）", text: Binding(get: { cockpit.schedules[i].dailyAt },
                                                                            set: { cockpit.schedules[i].dailyAt = $0 }))
                                .frame(width: 150)
                            Spacer(minLength: 0)
                            Button("今すぐ") { cockpit.runSchedule(s.id) }.buttonStyle(SumiButtonStyle(primary: false, size: 11))
                                .disabled(s.workspace.isEmpty || s.prompt.isEmpty)
                            Button("×") { cockpit.schedules.remove(at: i) }.buttonStyle(.plain).font(.mono(12))
                        }
                        hostField("送る指示（例: 依存を更新して、テストが通るか確かめて報告して）",
                                  text: Binding(get: { cockpit.schedules[i].prompt }, set: { cockpit.schedules[i].prompt = $0 }))
                        Text(s.lastRun.map { "前回 " + $0.formatted(.dateTime.month().day().hour().minute()) } ?? "まだ動いていない")
                            .font(.mono(10)).foregroundStyle(Palette.Light.fg3)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                }
                Button("＋ 予定を足す") {
                    cockpit.schedules.append(.init(workspace: spaces.first?.id ?? "", prompt: ""))
                }
                .buttonStyle(SumiButtonStyle(primary: false, size: 11))
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

    /// 選ぶ口に出すもの（入っていて、使わないにしていない）
    private var enabled: [Backend] { Backend.usable(found: Set(cockpit.found.keys), disabled: disabledAgents) }

    /// Link に並べるもの: 入っているもの全部（使わないにしたものも、戻せるように残す）。
    /// 入っているかは検出だけで決める——入れ直したら ↻ 探し直す で並び直る
    private var shown: [Backend] { Backend.allCases.filter { cockpit.found[$0] != nil } }

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
        let off = !enabled.contains(backend)
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
                Button(on ? "■ 使う" : "□ 使う") { toggle(backend) }
                    .buttonStyle(SumiButtonStyle(primary: on, size: 11))
                    .help(on ? "外すと、エージェントを選ぶ口に出なくなる" : "選ぶ口に戻す")
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
            // Orca の Args / Env。手元でも SSH の先でも、起こす時に効く
            Text("// 起こし方の上書き").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2).padding(.top, 4)
            field("引数（前に足す・空白区切り）", key: LaunchOverrides.argsKey(backend.command))
            field("環境変数（K=V を ; で区切る・例 OLLAMA_HOST=http://localhost:11434）", key: LaunchOverrides.envKey(backend.command))
        }
        .opacity(on ? 1 : 0.55)
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
                Text("入っているかは AT22 が探して決めます。入っていないものは Install ↗ で入れ方を開き、入れたら ↻ 探し直す で Link に並びます。"
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
        .onAppear { if frozen == nil { cockpit.findCLIs(force: true) } }
    }

    private func addRow(_ backend: Backend) -> some View {
        let installed = cockpit.found[backend] != nil
        let start = [backend.command] + (backend.isACP ? Cockpit.acpArguments(backend, model: "", level: .normal) : [])
        return HStack(spacing: 12) {
            Rectangle().fill(installed ? Palette.pink : Palette.Light.line).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(backend.title).font(.display(20))
                Text(start.joined(separator: " ") + "  ·  " + (backend.isACP ? "ACP" : backend == .claude ? "stream-json" : "exec"))
                    .font(.mono(10)).foregroundStyle(Palette.Light.fg2)
            }
            Spacer(minLength: 8)
            Text(installed ? "インストール済み" : "未導入").font(.mono(10))
                .foregroundStyle(installed ? Palette.Light.fg : Palette.Light.fg3).frame(width: 110, alignment: .trailing)
            Button(installed ? "Docs ↗" : "Install ↗") { NSWorkspace.shared.open(backend.homepage) }
                .buttonStyle(SumiButtonStyle(primary: !installed, size: 11)).frame(width: 110)
                .help(backend.homepage.absoluteString)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
    }

    /// Tailscale の相手を選ぶ（`tailscale status --json`）。開いた時に1回だけ訊く
    private func tailscalePicker(onPick: @escaping (String) -> Void) -> some View {
        Group {
            if let tsPeers, !tsPeers.isEmpty {
                SumiPicker(sections: [.init(title: "TAILSCALE", items: tsPeers.map {
                    .init(id: $0.name, text: ($0.online ? "● " : "○ ") + $0.name + ($0.os.isEmpty ? "" : "  ·  " + $0.os), on: false)
                })], onPick: { _, name in onPick(name) }) {
                    Text("Tailscale から選ぶ ▾").font(.mono(11)).padding(.horizontal, 8).frame(height: 30)
                        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                }
            } else if let tsProblem {
                Text("Tailscale を読めない: " + tsProblem).font(.bodyJP(11)).foregroundStyle(Palette.Light.danger).lineLimit(1)
            } else if tsPeers?.isEmpty == true {
                Text("Tailscale の相手がいない").font(.bodyJP(11)).foregroundStyle(Palette.Light.fg3)
            }
        }
        .task {
            guard frozen == nil, tsPeers == nil, tsProblem == nil else { return }
            switch await Task.detached(operation: { Remote.tailscalePeers() }).value {
            case let .success(list): tsPeers = list
            case let .failure(error): tsProblem = "\(error)".split(separator: "\n").first.map(String.init) ?? "tailscale が無い"
            }
        }
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack(spacing: 6) {
            Button("−") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) }
                .buttonStyle(SumiButtonStyle(primary: false, size: 11))
            Text("\(value.wrappedValue) \(unit)").font(.mono(13)).frame(width: 56)
            Button("＋") { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) }
                .buttonStyle(SumiButtonStyle(primary: false, size: 11))
        }
    }

    private func hostField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).font(.mono(12))
            .padding(.horizontal, 8).frame(height: 30)
            .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
    }

    /// SSH の先で、既定のエージェントの会話を起こす（最初の1通は会話画面で）
    private func startRemote(_ host: Remote.Host) {
        let parts = agent.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let backend = Backend(rawValue: parts.first ?? "") ?? .claude
        if cockpit.launch(prompt: "", cwd: host.workspace, backend: backend, model: parts.count > 1 ? parts[1] : "") != nil {
            onTalk()
        } else {
            flash(cockpit.launchError ?? "起こせませんでした")
        }
    }

    /// UserDefaults の文字列1つに直に繋ぐ欄（鍵がプロバイダごとに変わるので @AppStorage が使えない）
    private func field(_ placeholder: String, key: String) -> some View {
        TextField(placeholder, text: Binding(get: { UserDefaults.standard.string(forKey: key) ?? "" },
                                             set: { UserDefaults.standard.set($0, forKey: key) }))
            .textFieldStyle(.plain).font(.mono(12))
            .padding(.horizontal, 10).frame(height: 30)
            .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
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
        case .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi, .openclaw: nil
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

    /// 行の中の1項目: 左に名前、真ん中に何のためか、右に操作
    private func settingLine<C: View>(_ name: String, _ purpose: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(name).font(.bodyJP(13)).frame(width: 86, alignment: .leading)
            Text(purpose).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 4)
    }

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

/// 同梱のスキル（Resources/Skills の at22-gate・at22-handoff・at22-hydra）を Claude Code のユーザーのスキル置き場へ入れる。
/// **人が押した時だけ書く**。入れた後は claude が自分で読む（門・記憶DB の書き方・Hydra の頼み方）
enum SkillInstall {
    /// 同梱の全部（Resources/Skills の下のフォルダ）
    static var names: [String] {
        guard let root = sourceRoot else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

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
    static var sourceRoot: URL? {
        let manager = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Skills"),
           manager.fileExists(atPath: bundled.path) { return bundled }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Skills")
        return manager.fileExists(atPath: repo.path) ? repo : nil
    }

    static func target(_ name: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/skills/\(name)")
    }

    /// 全部入っていて同じなら current、1つでも無ければ missing、違えば stale
    static func state() -> State {
        guard let root = sourceRoot, !names.isEmpty else { return .missing }
        let manager = FileManager.default
        var stale = false
        for name in names {
            let source = root.appendingPathComponent(name), target = target(name)
            guard manager.fileExists(atPath: target.path) else { return .missing }
            let files = (try? manager.contentsOfDirectory(atPath: source.path)) ?? []
            if !files.allSatisfy({ manager.contentsEqual(atPath: source.appendingPathComponent($0).path,
                                                         andPath: target.appendingPathComponent($0).path) }) { stale = true }
        }
        return stale ? .stale : .current
    }

    static func install() throws {
        guard let root = sourceRoot else { throw CocoaError(.fileNoSuchFile) }
        let manager = FileManager.default
        for name in names {
            let target = target(name)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            try manager.copyItem(at: root.appendingPathComponent(name), to: target)
            for script in (try? manager.contentsOfDirectory(atPath: target.path)) ?? [] where script.hasSuffix(".sh") {
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.appendingPathComponent(script).path)
            }
        }
    }
}
