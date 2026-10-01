import SwiftUI

// MARK: - メニューの状態

/// 開いているメニュー1つぶん。時刻で動くもの（ドット・線・帯）は始めた時刻だけを持つ
struct MenuState: Equatable {
    struct Band: Equatable {
        let at: Date
        /// 下層へ潜る時は左から右、戻る時は右から左へ白帯が横切る
        let forward: Bool
    }

    let opened: Date
    var closing: Date?
    /// ドットが育ちきったか。立つと面の時計が止まる
    var settled = false
    var path: [Int] = []
    var highlight: Int
    var band: Band?
    var shake = 0
    /// 開いた直後の1回だけ、項目を順に迫り出させる（`sm-in` の遅延）
    var fresh = true

    init(opened: Date, highlight: Int) {
        self.opened = opened
        self.highlight = highlight
    }
}

// MARK: - 項目（実データ）

/// メニューの1項目。葉は `action` を持ち、枝は `kids` を持つ
struct MenuItem {
    enum Action {
        case tab(CockpitMode)
        case structure(StructFilter)
        case note(String)
        case session(String)
        case recent(RecentSession)
        /// セッションの選び口（01 TALK の一覧）へ戻る
        case picker
        case codex(Cockpit.CodexRecord)
        case newSession
        case agent(String)
        case level(Gate.Level)
        case model(String)
        case thinking
        case clearIdle
        case clearAll
        case tasks
        case settings
        case none
    }

    let en: String
    let jp: String
    let desc: String
    var kids: [MenuItem]? = nil
    var action: Action = .none

    /// 葉は全部実データから組む（v10 の `MENU` はデモの台本なので、形だけを借りる）。
    /// ponytail: 一覧の葉は頭から 12 件で切る。足りなければ 02 / 03 の画面の側で選ぶ
    @MainActor
    static func tree(cockpit: Cockpit, chips: [AgentChip], showThinking: Bool, launcherReady: Bool) -> [MenuItem] {
        let labels = Cockpit.agentLabels(chips)
        let agents = chips.filter { !$0.done }.map { chip in
            MenuItem(en: labels[chip.id] ?? "W?", jp: chip.role,
                     desc: (chip.model.isEmpty ? "—" : chip.model) + " · " + (chip.busy ? "稼働" : "待機"),
                     action: .agent(chip.id))
        }
        let notes = cockpit.memory.filter { !$0.isIndex }
        let handoff = notes.first { $0.file.uppercased().contains("HANDOFF") } ?? notes.first
        let session = cockpit.selectedSession
        let codex = session.map { cockpit.backend(of: $0) == .codex } ?? false
        let canPickModel = session != nil && !cockpit.isWorking(session)

        var sessions: [MenuItem] = [MenuItem(en: "New session", jp: "新しく起こす",
                                             desc: launcherReady ? "claude / codex を起こす" : "設定で連携を入にすると使える",
                                             action: .newSession),
                                    MenuItem(en: "All sessions", jp: "一覧から選ぶ", desc: "実行中・履歴・Codex を全部並べる",
                                             action: .picker)]
        sessions += cockpit.liveSessions.prefix(12).map { live in
            MenuItem(en: String(live.id.prefix(8)).uppercased(), jp: cockpit.title(for: live.id) ?? live.name,
                     desc: (live.busy ? "実行中 · " : "") + (live.cwd as NSString).lastPathComponent,
                     action: .session(live.id))
        }
        let liveIDs = Set(cockpit.liveSessions.map(\.id))
        sessions += cockpit.recentSessions.filter { !liveIDs.contains($0.id) }.prefix(12).map { recent in
            MenuItem(en: String(recent.id.prefix(8)).uppercased(), jp: cockpit.title(for: recent.id) ?? recent.project,
                     desc: recent.project + " · " + recent.modifiedAt.formatted(.dateTime.month().day().hour().minute()),
                     action: .recent(recent))
        }
        sessions += cockpit.codexRecords.filter { !liveIDs.contains($0.id) }.prefix(5).map { record in
            MenuItem(en: String(record.id.prefix(8)).uppercased(), jp: cockpit.title(for: record.id) ?? "Codex",
                     desc: "Codex · " + (record.cwd as NSString).lastPathComponent, action: .codex(record))
        }

        let models = (codex ? ModelChoice.codexModels : ModelChoice.claudeModels).map { choice in
            MenuItem(en: choice.title, jp: choice.id, desc: "次に繋いだ時から効く",
                     action: canPickModel ? .model(choice.id) : .none)
        }
        let keys: [(String, String, String)] = [
            ("M", "メニュー", "開く · ↑↓ 選ぶ · → 開く · ← 戻る"),
            ("A  B  C", "画面", "01 WORK · 02 STRUCTURE · 03 SPARRING"),
            ("⇧⌘T", "タスク", "06 Tasks を開く"),
            ("⇧⌘G", "門を許可", "←→ 選ぶ · ENTER 決定 · 1–3"),
            ("⌘Return", "送る", "生成中は止める"),
            ("Esc", "畳む", "手前から順に"),
        ]

        return [
            MenuItem(en: "Work", jp: "作業", desc: "会話と門 · いま動いているもの", kids: [
                MenuItem(en: "Conversation", jp: "会話", desc: "司令塔とのやり取り", action: .tab(.work)),
                MenuItem(en: "Agents", jp: "エージェント", desc: "C0 と配下 · \(agents.count) 体",
                         kids: agents.isEmpty ? [MenuItem(en: "None", jp: "居ない", desc: "動いているエージェントはいない")] : agents),
                MenuItem(en: "Gates", jp: "門", desc: "止まっている指示 · \(cockpit.gates.count) 件", action: .tab(.work)),
                MenuItem(en: "Tasks", jp: "タスク", desc: "進行表 · ⇧⌘T", action: .tasks),
                MenuItem(en: "Thinking", jp: "思考", desc: "思考も会話に出す · いま " + (showThinking ? "ON" : "OFF"), action: .thinking),
                MenuItem(en: "Clear idle", jp: "非アクティブを消す", desc: "動いていないエージェントだけを消す", action: .clearIdle),
                MenuItem(en: "Clear", jp: "クリア", desc: "溜まった終了済みとファイルの集計を落とす", action: .clearAll),
            ], action: .tab(.work)),
            MenuItem(en: "Structure", jp: "構造", desc: "ファイルの関係 · ホバーで浮かぶ", kids: [
                MenuItem(en: "Files", jp: "ファイル", desc: "種類で分ける", kids: [
                    MenuItem(en: "All", jp: "全部", desc: "絞り込まない", action: .structure(.all)),
                    MenuItem(en: "Sources", jp: "実装", desc: FileCategory.source.title, action: .structure(.category(.source))),
                    MenuItem(en: "Tests", jp: "検査", desc: FileCategory.test.title, action: .structure(.category(.test))),
                    MenuItem(en: "Docs", jp: "ノート", desc: FileCategory.note.title, action: .structure(.category(.note))),
                    MenuItem(en: "Config", jp: "設定", desc: FileCategory.config.title, action: .structure(.category(.config))),
                ]),
                MenuItem(en: "Ties", jp: "依存", desc: "関係のあるものだけ", action: .structure(.ties)),
                MenuItem(en: "Hot spots", jp: "熱い所", desc: "書込量の上位 2%", action: .structure(.hot)),
            ], action: .tab(.structure)),
            MenuItem(en: "Sparring", jp: "壁打ち", desc: "引き継ぎと記憶", kids: [
                MenuItem(en: "Handoff", jp: "引き継ぎ", desc: handoff?.relative ?? "まだ無い",
                         action: handoff.map { .note($0.id) } ?? .tab(.memory)),
                MenuItem(en: "Memory", jp: "記憶", desc: "記憶DB · \(notes.count) 件",
                         kids: notes.isEmpty ? [MenuItem(en: "Empty", jp: "空", desc: "エージェントが memory/ に書くと出る", action: .tab(.memory))]
                                             : notes.prefix(12).map { MenuItem(en: $0.name, jp: $0.kind, desc: $0.summary, action: .note($0.id)) }),
                MenuItem(en: "Sessions", jp: "過去の回", desc: (session.map { String($0.prefix(8)).uppercased() } ?? "—")
                         + " ほか \(max(0, sessions.count - 1)) 回", kids: sessions),
            ], action: .tab(.memory)),
            MenuItem(en: "Settings", jp: "設定", desc: "承認レベル · モデル · 鍵", kids: [
                MenuItem(en: "Approval", jp: "承認レベル", desc: "いま " + cockpit.gateLevel.title,
                         kids: Gate.Level.allCases.map { level in
                             MenuItem(en: String(level.title.prefix { $0 != " " }).uppercased(),
                                      jp: String(level.title.drop { $0 != " " }.dropFirst()),
                                      desc: level.needsConfirmation ? "確認してから切り替える" : level.permissionMode,
                                      action: .level(level))
                         }),
                MenuItem(en: "Models", jp: "モデル",
                         desc: canPickModel ? (session.flatMap { cockpit.model(of: $0) } ?? "既定") : "走っている間は切り替えられない",
                         kids: models),
                MenuItem(en: "Keys", jp: "鍵", desc: "ショートカット一覧",
                         kids: keys.map { MenuItem(en: $0.0, jp: $0.1, desc: $0.2) }),
                MenuItem(en: "Preferences", jp: "環境設定", desc: "⌘, · しきい値と連携", action: .settings),
            ]),
        ]
    }
}

// MARK: - メニューの画面

/// P5 風のメニュー。白い斜線（18°）が引かれる → 線から離れる順にドットが育って青い面になる →
/// 項目が線に沿って並ぶ。選んだ項目だけ白い板（右端が尖る）＋刃。下層は面の色が深くなり、白帯が横切る
struct SumiMenu: View {
    let state: MenuState
    let items: [MenuItem]
    let crumbs: [String]
    let size: CGSize
    let onPick: (Int) -> Void
    let onHover: (Int) -> Void
    let onBack: () -> Void
    let onRoot: () -> Void
    let onCrumb: (Int) -> Void
    let onClose: () -> Void

    private static let tan18 = CGFloat(tan(18 * Double.pi / 180))
    /// 項目の色の段（選んだ所から離れるほど沈む）
    private static let tones = [Palette.blue, Palette.Blue.fg2, Palette.Blue.fg3, Palette.Blue.dim]

    var body: some View {
        ZStack(alignment: .topLeading) {
            MenuDots(opened: state.opened, closing: state.closing, settled: state.settled)
            Rectangle().fill(Palette.depth[min(2, state.path.count)]).opacity(state.path.isEmpty ? 0 : 1)
            BandSweep(band: state.band, size: size)
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onClose)
            content.modifier(ExitFade(closing: state.closing != nil))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            // 鶴の影。ponytail: v10 は鶴の形に切り抜いた墨流し。ここは無地の鶴の影で済ませている
            Mascot(pitch: 64, lookRight: false, pose: .idle, color: Palette.navy, accent: Palette.navy)
                .offset(x: size.width - 512 + 40, y: size.height - 512 + 60)
                .allowsHitTesting(false)
                .modifier(Late(delay: 0.42))
            Slash(height: size.height, closing: state.closing != nil)
                .allowsHitTesting(false)
            crumbBar
                .offset(x: 310, y: 24)
                .modifier(Late(delay: 0.3))
            ZStack(alignment: .topLeading) {
                ForEach(Array(placed.enumerated()), id: \.offset) { i, slot in
                    item(i, slot: slot)
                }
            }
            .modifier(Shake(trigger: state.shake))
            VStack(alignment: .leading, spacing: 14) {
                Text("[×] CLOSE · ESC").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.white)
                Mascot(pitch: 9, lookRight: true, pose: .one, color: Palette.white)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 40)
            .padding(.bottom, 64)
            .modifier(Late(delay: 0.3))
        }
    }

    // MARK: 並べ方

    private struct Slot {
        let top: CGFloat
        let font: CGFloat
        let distance: Int
    }

    /// 選んだ項目を大きく、離れるほど小さく。全体を縦の中央に置き、線に沿って右へずらす
    private var placed: [Slot] {
        // 一覧が縮んだ時に、選んでいた番号が外へはみ出さないように詰める（v10 の `Math.min(mh, len-1)`）
        let highlight = min(state.highlight, max(0, items.count - 1))
        let sizes: [(CGFloat, CGFloat, Int)] = items.indices.map { i in
            let d = abs(i - highlight)
            let f: CGFloat = d == 0 ? (state.path.isEmpty ? 112 : 96) : d == 1 ? 44 : 34
            return (f, d == 0 ? f * 1.12 + 40 : f * 1.32, d)
        }
        let total = sizes.reduce(0) { $0 + $1.1 } + 12
        var y = size.height / 2 - total / 2
        return sizes.map { f, hh, d in
            defer { y += hh + 6 }
            return Slot(top: y, font: f, distance: d)
        }
    }

    private func item(_ i: Int, slot: Slot) -> some View {
        let it = items[i]
        let on = slot.distance == 0
        let tone = Self.tones[min(slot.distance, 3)]
        let number = state.path.map { String($0 + 1) }.joined(separator: "-")
            + (state.path.isEmpty ? "" : "-") + String(format: "%02d", i + 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(number).font(.mono(11)).tracking(Palette.caps(11))
                    .foregroundStyle(on ? Palette.Light.fg2 : tone)
                Text(it.en).font(.display(slot.font))
                    .foregroundStyle(on ? Palette.blue : tone)
                Text(it.jp).font(.brush(14))
                    .foregroundStyle(on ? Palette.blue : Self.tones[min(slot.distance + 1, 3)])
            }
            .lineLimit(1)
            .padding(on ? EdgeInsets(top: 4, leading: 20, bottom: 2, trailing: 44)
                        : EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            if on {
                HStack(spacing: 14) {
                    Text(it.desc + (it.kids.map { "  ▸ \($0.count)" } ?? ""))
                        .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                    Text("→ 開く · ← 戻る · M 閉じる").font(.mono(9)).tracking(Palette.caps(9))
                        .foregroundStyle(Palette.Light.fg3)
                }
                .padding(EdgeInsets(top: 2, leading: 20, bottom: 10, trailing: 44))
            }
        }
        .fixedSize()
        .background {
            if on { Chevron(head: 22, skew: 18, origin: 1).fill(Palette.white) }
        }
        .overlay(alignment: .trailing) {
            if on {
                Blade(trigger: "\(i)-\(state.path)")
                    .frame(width: 150, height: 4)
                    .offset(x: 156)
            }
        }
        .contentShape(Rectangle())
        .onHover { if $0 { onHover(i) } }
        .onTapGesture { onPick(i) }
        .modifier(StepIn(delay: state.fresh ? 0.38 + Double(i) * 0.045 : 0, trigger: state.path.count))
        .offset(x: 310 + slot.top * Self.tan18, y: slot.top)
    }

    private var crumbBar: some View {
        HStack(spacing: 0) {
            Button(action: onRoot) {
                Text("00 MENU").padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(Palette.blue).background(Palette.white)
            }
            .buttonStyle(PressStyle())
            ForEach(Array(crumbs.enumerated()), id: \.offset) { k, crumb in
                Rectangle().fill(Palette.white).frame(width: 28, height: 1)
                Button { onCrumb(k) } label: {
                    Text(crumb).padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(Rectangle().stroke(Palette.white, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
            if !state.path.isEmpty {
                Button(action: onBack) { Text("◂ BACK · ←").padding(.horizontal, 8).padding(.vertical, 6) }
                    .buttonStyle(PressStyle())
                    .padding(.leading, 20)
            }
        }
        .font(.mono(10)).tracking(Palette.caps(10))
        .foregroundStyle(Palette.white)
    }
}

// MARK: - 部品の動き（時計を回さずに、`task` の中で数コマだけ進める）

/// 白い斜線。開く時は 120ms・4コマで引かれ、閉じる時は 300ms 待ってから 130ms で消える
private struct Slash: View {
    let height: CGFloat
    let closing: Bool
    @State private var drawn: CGFloat = 0
    @State private var erased: CGFloat = 0
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: MenuDots.lineX, y: 0))
            p.addLine(to: CGPoint(x: MenuDots.lineX + height * MenuDots.tan18, y: height))
        }
        .trim(from: erased, to: drawn)
        .stroke(Palette.white, lineWidth: 3)
        .task(id: closing) {
            if frozen != nil { drawn = 1; return }
            if !closing {
                for k in 1...4 { drawn = CGFloat(k) / 4; try? await Task.sleep(for: .milliseconds(30)) }
            } else {
                try? await Task.sleep(for: .milliseconds(300))
                for k in 1...4 { erased = CGFloat(k) / 4; try? await Task.sleep(for: .milliseconds(32)) }
            }
        }
    }
}

/// 選んだ板の右へ伸びる刃。170ms・4コマ
private struct Blade: View {
    let trigger: String
    @State private var scale: CGFloat = 0

    var body: some View {
        Rectangle().fill(Palette.white)
            .scaleEffect(x: scale, anchor: .leading)
            .task(id: trigger) {
                scale = 0
                for k in 1...4 { try? await Task.sleep(for: .milliseconds(42)); scale = CGFloat(k) / 4 }
            }
    }
}

/// 階層を移る時に横切る白帯（220 幅・−18° の斜め）。260ms・8コマ
private struct BandSweep: View {
    let band: MenuState.Band?
    let size: CGSize
    @State private var step: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let step, let band {
                let from: CGFloat = band.forward ? -300 : size.width + 260
                let to: CGFloat = band.forward ? size.width + 260 : -400
                Rectangle().fill(Palette.white)
                    .frame(width: 220, height: size.height + 80)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: -MenuDots.tan18, d: 1,
                                                       tx: MenuDots.tan18 * (size.height + 80) / 2, ty: 0))
                    .offset(x: from + (to - from) * CGFloat(step) / 8, y: -40)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .task(id: band?.at) {
            guard band != nil else { return }
            for k in 0...8 { step = k; try? await Task.sleep(for: .milliseconds(32)) }
            step = nil
        }
    }
}

/// 遅れて現れる（`sm-late`: 指定の時間だけ隠れてから、1コマで出る）
struct Late: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.frozenTime) private var frozen

    func body(content: Content) -> some View {
        content
            .opacity(shown || frozen != nil ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                shown = true
            }
    }
}

/// 迫り出し（`sm-in`: 左上 12,4 から 150ms・3コマで定位置へ）
private struct StepIn: ViewModifier {
    let delay: Double
    let trigger: Int
    @State private var k = 0
    @Environment(\.frozenTime) private var frozen

    func body(content: Content) -> some View {
        let p = CGFloat(frozen != nil ? 3 : k) / 3
        return content
            .opacity(Double(p))
            .offset(x: -12 * (1 - p), y: -4 * (1 - p))
            .task(id: trigger) {
                guard frozen == nil else { return }
                k = 0
                try? await Task.sleep(for: .seconds(delay))
                for step in 1...3 { k = step; try? await Task.sleep(for: .milliseconds(50)) }
            }
    }
}

/// 閉じる時の引き（`sm-out`: 140ms・3コマで右下へ消える）
private struct ExitFade: ViewModifier {
    let closing: Bool
    @State private var k = 0

    func body(content: Content) -> some View {
        let p = CGFloat(k) / 3
        return content
            .opacity(Double(1 - p))
            .offset(x: -14 * p, y: 4 * p)
            .task(id: closing) {
                guard closing else { k = 0; return }
                for step in 1...3 { try? await Task.sleep(for: .milliseconds(46)); k = step }
            }
    }
}
