import SwiftUI
import UserNotifications
import AppKit

// MARK: - 画面の根

/// Sumi v11 の画面。**2つの姿**を行き来する。
///
/// ```
/// 管制塔（p=0）: 青が全面。左に白い三角「01 TALK ▸」、右列は門の窓と同じ指示
/// 会話（p=1）  : 白い面が「<」の形に開く（XC=W-394・XT=W-540）。右列はタブごとの2枠
/// ```
/// 境界は XC=(W-394)p・XT=146+(W-540-146)p で補間し、白い面は 0.5s・24fps で横に滑る。
/// 上帯 56（AT22_・05 PLAN のティック・日付・＋）、下帯 44（端末の帯・門・一個前→現在地）。
/// 重なりの順（下から）: 白い面 → 青い面 → 右列 → 切り欠き・鶴・帯 → メニュー → 板 → 決定のドット → DotWipe
struct CockpitView: View {
    let cockpit: Cockpit
    /// `--shot` が焼く時刻。入っている間は TimelineView・ScrollView・TextField を作らない
    var shot: Date? = nil
    /// `--shot --mode` で焼くタブ。nil なら保存されている値
    var shotTab: V11Tab? = nil
    /// `--shot --tower` で管制塔を焼く
    var shotTower = false
    /// `--shot --menu root|project|workspace|jump` でメニューを開いた所を焼く
    var shotMenu: String? = nil
    /// `--shot --sheet new|delete|pick` で板を開いた所を焼く（見本の worktree を使う）
    var shotSheet: String? = nil
    /// `--shot --review <worktree>` で読み込み済みの差分
    var shotReview: ReviewModel? = nil
    var shotFiles: FilesModel? = nil
    var shotTerm = false
    /// `--ripple back:10` / `fwd:4` … 管制塔⇄会話の波紋の途中のコマ（白い面もそのコマの位置に置く）
    var shotRipple: String? = nil

    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    @AppStorage("v11Tab") private var storedTab = V11Tab.talk
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""
    @AppStorage(Cockpit.grokPathKey) private var grokPath = ""
    @AppStorage("showThinking") private var showThinking = false
    @AppStorage("towerFold") private var towerFold = true

    /// 手前に開いているもの。Esc はここから畳む
    @State private var overlay: Overlay?
    @State private var menu: MenuState?
    @State private var wipe: Wipe?
    @State private var flights: [DotFlight] = []
    @State private var ripple: TabRipple?
    /// メニューでタブを替えた直後、波紋が覆い切るまで右列を隠す（v11 の hideR）
    @State private var hideRight = false
    /// 最後に入ったタイル（worktree のパス）
    @State private var enteredWorkspace: String?
    @State private var bursts: [Burst] = []
    /// 部品の矩形（ドットの出発点と行き先、墨を落とす高さ）。**観測しない箱**に入れる——
    /// @State にすると、スクロールのたびに根ごと組み直す
    @State private var book = RectBook()

    // 2つの姿。起動は管制塔から
    @State private var tower = true
    @State private var towerP: Double = 0
    @State private var settled = true
    /// 右列の中身。白い面が滑り始めて 1/3 の所で差し替える（枠は動かさない）
    @State private var colTower = true
    @State private var towerFocus = 0
    @State private var towerHover: String?
    @State private var location = Location(prev: nil, cur: "00 TOWER")
    /// REVIEW と GIT が同じ差分・ステージ・コミットを見る
    @State private var review = ReviewModel()
    /// FILES の木と、手で直すために開いた1本
    @State private var files = FilesModel()
    /// worktree ごとの端末（アプリが閉じるまで生きている）と、引き出しが開いているか
    @State private var terminals = Terminals()
    @State private var termOpen = false
    /// 送出の間は鶴が畳んで送る（upload）、終わると片足で立つ
    @State private var craneFx: String?

    // 壁打ち（会話画面の「□ 壁打ち」）
    /// worktree ごとの壁打ち（採った・決めた印）と、暫定プランの ⑂ から新規の板に渡す最初の指示
    @State private var spar = SparModel()
    @State private var newPrompt = ""
    // 構造
    // 門
    @State private var gate = GateUI()
    /// 答えた門の印。会話の流れに `GATE // W6 → ALLOWED` として混ぜる（画面だけの記録）
    @State private var verdicts: [VerdictLine] = []
    @State private var riskyLevel: Gate.Level?
    /// 会話画面で「新しい会話」の最初の1通を書いている間（右列の履歴からも入る）
    @State private var talkComposing = false
    /// FILES で記憶DB を見ているか（ファイル｜記憶DB）
    @State private var filesMemory = false
    @State private var gateArmedAt = Date.distantPast
    @State private var replySession: String?
    @State private var windowVisible = true


    enum Overlay: Equatable {
        case tasks
        case file(String)
        case agent(String)
        /// 新規ワークスペース（斜線の板）。分岐元の worktree を渡せる
        case newWorkspace(from: String?)
        case delete(String)
        /// 競走の勝者を採る（組の鍵）
        case pick(String)
        /// ⌘P
        case quickOpen
        /// 内蔵ブラウザ（会話の URL の札から）
        case browser(URL)
    }

    struct Location: Equatable {
        var prev: String?
        var cur: String
    }

    private var tab: V11Tab { shotTab ?? storedTab }
    private var mode: CockpitMode { tab.mode }
    private var isTower: Bool { shot != nil ? shotTower : tower }
    private var p: CGFloat { CGFloat(shot != nil ? shotRippleFrame?.p ?? (shotTower ? 0 : 1) : towerP) }

    /// 撮影用: 波紋の始まりと、そのコマの白い面の開き（滑りは 0.5s・会話へは ease-out、管制塔へは ease-in）
    private var shotRippleFrame: (ripple: TabRipple, p: Double)? {
        guard let shot, let spec = shotRipple?.split(separator: ":"), spec.count == 2, let n = Int(spec[1]) else { return nil }
        let kind: TabRipple.Kind = spec[0] == "back" ? .toTower : spec[0] == "side" ? .side : .toChat
        let k = min(1, Double(n) / 12)
        return (TabRipple(kind: kind, started: shot.addingTimeInterval(-Double(n) / 24 - 0.01)),
                kind == .toTower ? 1 - k * k * k : kind == .side ? 1 : 1 - pow(1 - k, 3))
    }

    var body: some View { reactive }

    private var core: some View {
        GeometryReader { geo in
            // 根の時計は motionPaused の外にあるので、窓が隠れたら自分で止める
            Ticker(fps: 1, paused: !windowVisible) { now in
                screen(size: geo.size, now: now)
            }
            .environment(\.frozenTime, shot)
            .coordinateSpace(.named(RectBook.space))
            .onPreferenceChange(SumiRectsKey.self) { [book] value in
                MainActor.assumeIsolated { book.rects = value }
            }
            // 訊かれた時の窓。質問と計画はどの画面でも、道具の承認は会話画面以外で（会話画面は門のカード）
            .overlay {
                if shot == nil, let ask = asking {
                    AskWindow(cockpit: cockpit, approval: ask).id(ask.id)
                }
            }
            .onAppear { book.size = geo.size }
            .onChange(of: geo.size) { book.size = geo.size }
        }
        .background(Palette.blue)
        // `onKeyPress` はフォーカスを持つ View にしか来ない。焦点の輪は意匠に合わないので消す。
        // 入力欄に焦点がある間は文字がそちらへ吸われるので、ここへは落ちてこない
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
        .onChange(of: threshold, initial: true) { cockpit.flagReadThreshold = threshold }
        .onChange(of: launcherEnabled) { findCLIs(force: true) }
        .onChange(of: claudePath) { findCLIs(force: true) }
        .onChange(of: codexPath) { findCLIs(force: true) }
        .onChange(of: grokPath) { findCLIs(force: true) }
        // CLI が見つかったら、モデルの一覧を CLI に訊く（claude は list_models・grok は grok models）
        .task(id: cockpit.found.keys.map(\.rawValue).sorted()) { if shot == nil { await cockpit.refreshCatalog() } }
        // 入っているスキルを読み直す（作業場所が変わった時。リポジトリの .claude/skills も見る）
        .task(id: currentWorkspace) { if shot == nil { await cockpit.refreshSkills(repo: currentWorkspace) } }
        // Dock のバッジ＝人の番で止まっている／見ていない間に何か起きたセッションの数。
        // 画像焼き（--shot）では NSApplication が無いので何もしない
        .onChange(of: cockpit.attentionCount, initial: true) { _, count in
            NSApp?.dockTile.badgeLabel = count == 0 ? nil : "\(count)"
        }
    }

    /// 根の反応（キー以外）。body の連鎖が長すぎると型検査が終わらないので2つに分けた
    private var reactive: some View {
        core
        .task { cockpit.onAttention = { _, title, body in Notifier.post(title: title, body: body) } }
        // 止まっている門が入れ替わったら、答えかけを捨てて新しい門の本文から始める
        .onChange(of: stop?.id, initial: true) {
            gate = GateUI(revised: stop?.seed ?? "")
            // 次の門が出た直後の Enter / 1 は受けない。続けて押すと、見ていない門を許可してしまう
            gateArmedAt = Date()
        }
        .onChange(of: currentLocation) { old, new in location = Location(prev: old, cur: new) }
        .onChange(of: lastReplyID) { old, id in
            // セッションを切り替えた・履歴を読んだだけの時は飛ばさない（返答が着いた時だけ）
            defer { replySession = cockpit.selectedSession }
            guard old != nil, id != nil, replySession == cockpit.selectedSession,
                  tab == .talk, !isTower, shot == nil else { return }
            // 返答が着いた。鶴から最後の枠へドットを渡す（v10 の `ask` の後半）
            after(0.06) { fly(from: book.rects["crane"], to: book.rects["c0last"]) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .at22OpenSettings)) { _ in openSettings() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
            windowVisible = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
        }
        .alert("この段は人間の承認なしにファイルを書き換える", isPresented: Binding(
            get: { riskyLevel != nil }, set: { if !$0 { riskyLevel = nil } })) {
            Button("やめる", role: .cancel) { riskyLevel = nil }
            Button("承知した", role: .destructive) {
                if let level = riskyLevel {
                    // 会話を開いていればその会話に（次に送った時から）、無ければ新しい会話の既定に
                    if cockpit.selectedSession != nil { cockpit.applyLevel(level, to: cockpit.selectedSession) }
                    else { UserDefaults.standard.set(level.rawValue, forKey: SettingsScreen.levelKey) }
                }
                riskyLevel = nil
            }
        } message: {
            Text("\(riskyLevel?.title ?? "") では、起こしたセッションが確認を求めずに編集します。")
        }
        .task {
            guard shot == nil else { return }
            findCLIs(force: false)
            while !Task.isCancelled {
                cockpit.housekeeping()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task {
            // 2.6 秒ごとに、ACTIONS の行の高さへ墨を落とす（書込＝青、それ以外＝ピンク）
            guard shot == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                if windowVisible, menu == nil, !isTower, settled { dripInk() }
            }
        }
    }

    // MARK: 組み立て

    @ViewBuilder
    private func screen(size: CGSize, now: Date) -> some View {
        let w = size.width, h = size.height
        let snap = cockpit.snapshot(now: now, mode: mode)
        let gates = cockpit.gates
        let actions = Cockpit.actionRows(chips: snap.chips, gates: gates,
                                         cells: snap.cards.flatMap(\.files), now: now)
        // 計画は見ている会話のもの。会話を選んでいない時は、いまの worktree の会話のものだけ（ほかの worktree を混ぜない）
        let tasks: [RoadmapTask] = cockpit.selectedSession.map { cockpit.allTasks(session: $0) }
            ?? currentWorkspace.map { ws in cockpit.allTasks(session: nil).filter { cockpit.workspacePath(of: $0.session) == ws } }
            ?? []
        let busy = cockpit.isWorking(cockpit.selectedSession)
        let trail = currentTrail()
        let crane = craneStatus(busy: busy, trail: trail)
        let contentW = max(380, w - 780)
        let p = self.p
        let towerShown = isTower || !settled
        let colTower = shot != nil ? shotTower : self.colTower
        // 1回の描画で1回だけ組む（GIT は右列と本文の両方で使う）
        let projects = towerShown || colTower || tab == .git ? TowerData.projects(cockpit) : []
        let paused = !windowVisible || menu?.settled == true || shot != nil

        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                // 白い面。管制塔へ戻る時は左へ退く
                ZStack(alignment: .topLeading) {
                    Palette.Light.bg
                    if !isTower || !settled {
                        tabContent(snap: snap, actions: actions, tasks: tasks, trail: trail, projects: projects, w: w, h: h, contentW: contentW)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .offset(x: (p - 1) * max(0, w - 540))

                // 青い面。白い面の形にくり抜く。管制塔はここに載る
                ZStack(alignment: .topLeading) {
                    Palette.blue
                    if towerShown {
                        Suminagashi(tank: Ink.tower, paused: paused || !isTower)
                            .frame(width: w, height: max(1, h - 100))
                            .offset(y: 56)
                        TowerScreen(projects: projects, width: w, height: h,
                                    focus: towerFocusID(projects), hover: $towerHover,
                                    onEnter: { enter($0) }, onAct: { towerAct($0, $1) })
                    } else {
                        Suminagashi(tank: Ink.tank, paused: paused)
                            .frame(width: 540, height: max(1, h - 100))
                            .clipShape(InkClip())
                            .offset(x: w - 540, y: 56)
                    }
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .clipShape(BlueSheet(p: p), style: FillStyle(eoFill: true))
                .contentShape(BlueSheet(p: p), eoFill: true)

                BlueSheet.edge(p: p, size: size).stroke(p < 0.5 ? Palette.white : Palette.blue, lineWidth: 3)
                    .allowsHitTesting(false)

                // 右列。枠は動かさず中身だけ差し替える
                Group {
                    if colTower {
                        TowerSide(stops: Stop.all(cockpit, chips: snap.chips), projects: projects, height: h,
                                  hover: $towerHover,
                                  onAnswer: { stop, verdict in
                                      answer(stop, verdict, revised: "", from: nil,
                                             word: verdict == .deny ? "REJECTED" : "ALLOWED")
                                  },
                                  onEnter: { path, stopID in enter(path: path, stopID: stopID, projects: projects) },
                                  activity: cockpit.activity,
                                  onOpenSession: { session in
                                      if let row = cockpit.workspaceTree().flatMap(\.workspaces).flatMap(\.agents).first(where: { $0.id == session }) {
                                          Task { await cockpit.open(row) }
                                      } else {
                                          cockpit.selectedSession = session
                                      }
                                      storedTab = .talk
                                      setTower(false)
                                  })
                    } else if tab == .review {
                        ReviewPanels(cockpit: cockpit, model: shotReview ?? review, session: cockpit.selectedSession, height: h,
                                     onSent: { fly(from: book.rects["crane"], to: book.rects["crane"]) })
                    } else if tab == .git {
                        let tiles = project(of: currentWorkspace, in: projects.isEmpty ? TowerData.projects(cockpit) : projects)?.tiles ?? []
                        GitPanels(model: shotReview ?? review,
                                  branch: tiles.first { $0.id == currentWorkspace }?.branch,
                                  branches: tiles.compactMap(\.branch), height: h)
                    } else if tab == .settings {
                        KeysPanel(height: h)
                    } else if tab == .files {
                        if filesMemory {
                            MemoryPanels(cockpit: cockpit, workspace: currentWorkspace, height: h, onTalk: { go(.talk) })
                        } else {
                            FilesPanels(cockpit: cockpit, model: shotFiles ?? files, height: h)
                        }
                    } else if tab == .talk, !isTower, cockpit.selectedSession != nil, cockpit.gateLevel == .plan {
                        // 壁打ち中は右列を暫定プラン・決定事項に（05 PLAN に送る・HANDOFF に書く）
                        SparPanels(cockpit: cockpit, model: spar, workspace: currentWorkspace, lead: cockpit.selectedSession,
                                   height: h,
                                   onLaunch: { step in newPrompt = step; overlay = .newWorkspace(from: currentWorkspace) },
                                   fly: { fly(from: $0, to: $1) }, rects: book.rects)
                    } else if tab == .talk {
                        RightColumn(cockpit: cockpit, actions: actions.rows, doneCount: actions.doneCount,
                                    snapshot: snap, tasks: tasks, height: h,
                                    onOpen: { row in
                                        if let path = row.path { openFile(path) }
                                        else if !row.waiting { overlay = .agent(row.id) }
                                        else { go(.talk) }
                                    },
                                    workspace: isTower ? nil : currentWorkspace,
                                    onNew: { cockpit.selectedSession = nil; talkComposing = true })
                    }
                }
                .frame(width: 352)
                .opacity(hideRight ? 0 : 1)
                .offset(x: w - 376, y: 76)

                if settled || shot != nil { notch(w: w, h: h) }

                // メニューを開いている間は、同じ鶴をメニューの前に出す（下のこれは隠す）
                craneButton(crane).opacity(menuShown ? 0 : 1)

                HeaderBand(tasks: tasks, now: now, width: w,
                           onTasks: { overlay = overlay == .tasks ? nil : .tasks },
                           onNew: { overlay = .newWorkspace(from: isTower ? nil : currentWorkspace) })
                    .frame(width: w, height: 56)

                FooterBand(width: w, termLine: "\(wsName) % ", busy: busy, stop: stop,
                           stopCount: cockpit.stoppedCount,
                           location: shot != nil ? Location(prev: nil, cur: currentLocation) : location,
                           onTerm: { termOpen.toggle() }, onGate: { if let id = stop.flatMap(stopWorkspace) { enter(path: id, stopID: stop?.id, projects: projects) } else { setTower(false) } })
                    .frame(width: w, height: 44)
                    .offset(y: h - 44)

                PullDrawer(open: termOpen || shotTerm) {
                    TerminalDrawer(terminals: terminals, path: currentWorkspace ?? NSHomeDirectory(), name: wsName,
                                   onClose: { termOpen = false })
                }
                .frame(width: max(300, min(1016, w - 424)), height: 396)
                .offset(x: 24, y: h - 44 - 396)
            }
            .environment(\.motionPaused, !windowVisible || menu?.settled == true)

            if let menu = self.menu ?? shotMenuState(projects: projects) {
                let rows = menuRows(menu, projects: projects.isEmpty ? TowerData.projects(cockpit) : projects)
                Group {
                    switch menu.kind {
                    case .menu:
                        WedgeMenu(state: menu, rows: rows,
                                  crumbs: menuCrumbs(menu, projects: projects.isEmpty ? TowerData.projects(cockpit) : projects),
                                  size: size,
                                  onPick: { pickMenu($0) }, onHover: { self.menu?.highlight = $0 },
                                  onCrumb: { menuGo($0) }, onUp: { menuUp() }, onClose: { hideMenu() })
                    case .jump:
                        JumpMenu(state: menu, rows: rows, size: size,
                                 onPick: { pickMenu($0) }, onHover: { self.menu?.highlight = $0 },
                                 onClose: { hideMenu() })
                    }
                }
                .zIndex(30)
                craneButton(crane).zIndex(31)
            }

            if let overlay = self.overlay ?? shotOverlay(projects) {
                overlayView(overlay, snap: snap, projects: projects, w: w, h: h).zIndex(40)
            }

            TabRippleLayer(ripple: shotRippleFrame?.ripple ?? ripple, p: Double(p)).frame(width: w, height: h).zIndex(55)
            BurstLayer(bursts: bursts).frame(width: w, height: h).zIndex(59)
            DecideLayer(flights: flights).frame(width: w, height: h).zIndex(60)
            DotWipeLayer(wipe: wipe).frame(width: w, height: h).zIndex(70)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipped()
    }

    private var menuShown: Bool { menu != nil || shotMenu != nil }

    /// 左下の鶴。押すとメニュー。メニューの上では白い面に乗るので青で描く（v11: zIndex menu ? 61 : 25）
    private func craneButton(_ status: CraneStatus) -> some View {
        CraneButton(tower: isTower, onWhite: menuShown, label: (isTower ? "00 TOWER" : tab.no + " " + tab.en) + " · M",
                    status: status, onTap: { menu == nil ? openMenu() : hideMenu() })
            .frame(width: 150, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 40)
            .padding(.bottom, 46)
    }

    /// 手前に開いた板。新規は全面、削除・採るは幕の上の白い板、それ以外は v10 のモーダル
    @ViewBuilder
    private func overlayView(_ overlay: Overlay, snap: CockpitSnapshot, projects: [TowerProject],
                             w: CGFloat, h: CGFloat) -> some View {
        let all = projects.isEmpty ? TowerData.projects(cockpit) : projects
        let tiles = all.flatMap(\.tiles)
        switch overlay {
        case let .browser(url):
            BrowserSheet(start: url, onClose: { self.overlay = nil })
                .frame(width: w, height: h)
        case let .newWorkspace(from):
            NewWorkspaceSheet(cockpit: cockpit, projects: all, from: from, prompt0: newPrompt, launcherReady: launcherReady,
                              onClose: { self.overlay = nil; newPrompt = "" },
                              onCreated: { self.overlay = nil; newPrompt = ""; setTower(true) },
                              onOpenSettings: { openSettings() })
                .frame(width: w, height: h)
        case let .delete(id):
            if let tile = tiles.first(where: { $0.id == id }) {
                DeleteSheet(cockpit: cockpit, tile: tile, onClose: { self.overlay = nil }).frame(width: w, height: h)
            }
        case .quickOpen:
            QuickOpen(files: files.files, onPick: { f in self.overlay = nil; openFile(f) }, onClose: { self.overlay = nil })
                .frame(width: w, height: h)
        case let .pick(race):
            PickSheet(cockpit: cockpit, group: tiles.filter { $0.race == race }, onClose: { self.overlay = nil })
                .frame(width: w, height: h)
        default:
            Modals(cockpit: cockpit, overlay: overlay, snapshot: snap,
                   onClose: { self.overlay = nil },
                   onLaunched: { self.overlay = nil; storedTab = .talk; setTower(false) },
                   onOpenSettings: { openSettings() })
                .frame(width: w, height: h)
        }
    }

    /// 白い面の中身。タブごとに1枚
    @ViewBuilder
    private func tabContent(snap: CockpitSnapshot, actions: (rows: [ActionRow], doneCount: Int),
                            tasks: [RoadmapTask], trail: [(path: String, kind: TouchKind)], projects: [TowerProject],
                            w: CGFloat, h: CGFloat, contentW: CGFloat) -> some View {
        switch tab {
        case .talk:
            TalkScreen(cockpit: cockpit, headline: Cockpit.headline(rows: actions.rows),
                       subtitle: subtitle(tasks), showThinking: showThinking,
                       verdicts: verdicts, gate: $gate, gateFailed: gate.failed != nil && gate.failed == stop?.id,
                       stop: stop,
                       others: Stop.all(cockpit, chips: snap.chips).filter { $0.stop.id != stop?.id
                           && $0.workspace != currentWorkspace },
                       onOther: { other in enter(path: other.workspace, stopID: other.stop.id,
                                                 projects: TowerData.projects(cockpit)) },
                       pendingGates: cockpit.stoppedCount, trail: trail, ctxAlarm: ctxAlarm,
                       height: h - 72, width: contentW, modalOpen: overlay != nil,
                       onChoose: { choose($0) },
                       onRewrite: { issueRewrite() },
                       onNew: { overlay = .newWorkspace(from: isTower ? nil : currentWorkspace) },
                       workspace: isTower ? nil : currentWorkspace,
                       composing: $talkComposing,
                       onRiskyLevel: { riskyLevel = $0 },
                       onBrowse: { overlay = .browser($0) },
                       spar: spar, fly: { fly(from: $0, to: $1) }, rects: book.rects)
                .offset(x: 220, y: 72)
        case .files:
            ZStack(alignment: .topTrailing) {
                if filesMemory {
                    MemoryScreen(cockpit: cockpit, workspace: currentWorkspace, width: contentW, height: h,
                                 onOpen: { overlay = .file($0) })
                } else {
                    FilesScreen(model: shotFiles ?? files, width: contentW, height: h)
                }
                // ファイル｜記憶DB
                HStack(spacing: 0) {
                    Button("ファイル") { filesMemory = false }.buttonStyle(SumiButtonStyle(primary: !filesMemory, size: 11))
                    Button("記憶DB") { filesMemory = true }.buttonStyle(SumiButtonStyle(primary: filesMemory, size: 11))
                }
            }
            .frame(width: contentW, alignment: .topLeading)
            .offset(x: 220, y: 84)
            .task(id: currentWorkspace) { if shot == nil { await files.load(root: currentWorkspace) } }
        case .review:
            ReviewScreen(cockpit: cockpit, model: shotReview ?? review, workspace: currentWorkspace, session: cockpit.selectedSession,
                         width: contentW, height: h,
                         onOpen: { path, line in openFile(path, line: line) },
                         onGit: { go(.git) })
                .offset(x: 220, y: 84)
        case .git:
            GitScreen(cockpit: cockpit, model: shotReview ?? review, workspace: currentWorkspace,
                      branch: currentWorkspace.flatMap { ws in projects.flatMap(\.tiles).first { $0.id == ws }?.branch },
                      width: contentW, height: h,
                      onReview: { go(.review) },
                      onBurst: { burst(at: book.rects[$0]) },
                      onFly: { a, b, ink in fly(from: book.rects[a], to: book.rects[b], ink: ink) },
                      onPushing: { on in
                          craneFx = on ? "push" : "ok"
                          if !on { after(1.8) { if craneFx == "ok" { craneFx = nil } } }
                      })
                .offset(x: 220, y: 84)
        case .settings:
            SettingsScreen(cockpit: cockpit, width: contentW, height: h, onTalk: { go(.talk) })
            .offset(x: 220, y: 84)
        }
    }

    /// 切り欠き。管制塔では左の白い三角（会話へ）、会話では右の青い三角（管制塔へ）
    @ViewBuilder
    private func notch(w: CGFloat, h: CGFloat) -> some View {
        let apex = (56 + h - 44) / 2
        if isTower {
            ZStack(alignment: .topLeading) {
                Color.clear
                VStack(alignment: .leading, spacing: 8) {
                    Text("01").foregroundStyle(Palette.pink)
                    Text("TALK")
                    Text("▸").font(.mono(18))
                    Text("会話").font(.brush(13)).tracking(0)
                    if stop != nil { Blink() }
                }
                .font(.mono(10)).tracking(Palette.caps(10))
                .foregroundStyle(Palette.blue)
                .offset(x: 12, y: apex - 56 - 64)
            }
            .frame(width: 146, height: h - 100)
            .contentShape(NotchShape(left: true))
            .onTapGesture { setTower(false) }
            .help("会話を開く (⌘0)")
            .offset(y: 56)
        } else {
            ZStack(alignment: .topLeading) {
                Color.clear
                HStack(spacing: 6) {
                    Text("◂")
                    Text("00").foregroundStyle(Palette.pink)
                    Text("TOWER")
                }
                .font(.mono(10)).tracking(Palette.caps(10))
                .foregroundStyle(Palette.white)
                .offset(x: 22, y: apex - 56 - 8)
            }
            .frame(width: 146, height: h - 100)
            .contentShape(NotchShape(left: false))
            .onTapGesture { setTower(true) }
            .help("管制塔へ戻す (Esc · ⌘0)")
            .offset(x: w - 540, y: 56)
        }
    }

    // MARK: 状態の読み出し

    private var stop: Stop? {
        // 門の題にだけ chips が要る。承認や何も無い時に snapshot（touches を全部たたむ）を走らせない
        Stop.current(cockpit, chips: cockpit.snapshot(now: Date(), mode: .work).chips)
    }

    private var ctxAlarm: Bool { cockpit.reading.stage == .warning }

    /// いま開いているワークスペースの名前（下帯・端末の帯）
    private var wsName: String {
        guard let session = cockpit.selectedSession, let path = cockpit.workspacePath(of: session) else {
            return cockpit.selectedSession.flatMap { cockpit.title(for: $0) }.map { String($0.prefix(18)) } ?? "—"
        }
        return (path as NSString).lastPathComponent
    }

    /// 下帯右の「一個前 → 現在地」の現在地
    private var currentLocation: String { isTower ? "00 TOWER" : "\(wsName) · \(tab.no) \(tab.en)" }

    /// 止まっている1件が属するワークスペース
    private func stopWorkspace(_ stop: Stop) -> String? {
        switch stop.source {
        case let .approval(a): cockpit.workspacePath(of: a.session)
        case let .gate(g): cockpit.workspacePath(of: g.by)
        }
    }

    private func towerFocusID(_ projects: [TowerProject]) -> String? {
        let order = TowerData.order(projects, fold: towerFold)
        return order.indices.contains(towerFocus) ? order[towerFocus].id : nil
    }

    /// 最後の返答。これが変わった時にだけ鶴からドットを飛ばす
    private var lastReplyID: Int? {
        let session = cockpit.selectedSession
        return cockpit.messages.last { $0.session == session && $0.speaker == .model && !$0.thinking }?.id
    }

    /// TALK の小見出し。進行中のタスクが無ければセッションの題
    private func subtitle(_ tasks: [RoadmapTask]) -> String {
        let tail = " — 司令塔とのやり取りと、止まった指示はここに流れます。"
        if let task = tasks.first(where: { $0.status == .inProgress }) { return "▸\(task.number) \(task.subject)" + tail }
        if let id = cockpit.selectedSession, let title = cockpit.title(for: id) { return "▸ \(title)" + tail }
        return cockpit.selectedSession == nil ? "セッションを選ぶと、司令塔とのやり取りがここに流れます。" : "▸" + tail
    }

    /// いま進んでいるターンの足跡（最後の人の発言より後に司令塔が触ったもの）
    private func currentTrail() -> [(path: String, kind: TouchKind)] {
        guard let session = cockpit.selectedSession else { return [] }
        let since = cockpit.messages.last { $0.session == session && $0.speaker == .human }?.at ?? .distantPast
        return cockpit.touches
            .filter { $0.session == session && $0.agent == session && $0.started >= since }
            .map { ($0.path, $0.kind) }
    }

    /// 鶴の状態。処理中は畳んで InkLoader に、門が止まっている間は片足で待つ
    private func craneStatus(busy: Bool, trail: [(path: String, kind: TouchKind)]) -> CraneStatus {
        if craneFx == "push" { return CraneStatus(busy: "upload", pose: .idle, state: "PUSHING · 送出中", sub: "送っています") }
        if craneFx == "ok" { return CraneStatus(busy: nil, pose: .one, state: "PUSHED · 送りました", sub: "送り終わりました") }
        if busy {
            let step = cockpit.liveInk(cockpit.selectedSession)
            return CraneStatus(busy: step, pose: .idle, state: step.uppercased(), sub: TalkScreen.stepLabel[step] ?? "")
        }
        if cockpit.stoppedCount > 0 {
            return CraneStatus(busy: "wait", pose: .one, state: "ASKING · MENU",
                               sub: cockpit.gates.isEmpty ? "承認を待っています" : "門の応答を待っています")
        }
        if ctxAlarm {
            return CraneStatus(busy: "overload", pose: .idle, state: "MENU", sub: "文脈があふれそうです")
        }
        return CraneStatus(busy: nil, pose: .idle, state: "MENU", sub: "C0 司令塔")
    }

    // MARK: 遷移

    /// タブを移る。DotWipe が覆いきった所（380ms）で差し替え、1.86 秒で戻る。
    /// 壁打ちに未保存があると動かない（書きかけを捨てない）。管制塔からは滑って会話へ入るだけ
    /// 窓で訊く1件。質問・計画はどの会話のものでも（待たせている順）、道具の承認は見ている会話のものを会話画面の外で
    private var asking: Approval? {
        let waiting = cockpit.approvals.sorted { $0.at < $1.at }
        if let ask = waiting.first(where: AskWindow.isWindowed) { return ask }
        guard !isTower, tab != .talk else { return nil }
        return waiting.first { $0.session == cockpit.selectedSession }
    }

    /// 設定は 10 SETTINGS の1か所（⌘, の別窓はやめた）。板が開いていれば閉じてから
    private func openSettings() {
        overlay = nil
        go(.settings)
    }

    private func go(_ to: V11Tab, origin: CGPoint? = nil, fromMenu: Bool = false) {
        guard wipe == nil else {
            if fromMenu { hideMenu() }
            return
        }
        if isTower {
            storedTab = to
            menu = nil
            setTower(false)
            return
        }
        guard to != tab || fromMenu else { return }
        let started = Wipe(from: tab.en, to: to,
                           origin: origin ?? CGPoint(x: book.size.width / 2, y: book.size.height / 2),
                           started: Date())
        wipe = started
        after(Wipe.swapAt) {
            storedTab = to
            menu = nil
            overlay = nil
        }
        after(Wipe.total) { if wipe == started { wipe = nil } }
    }

    /// メニューからタブを選んだ時（v11 の pickMenu）。大見出しの全面ドットは使わない:
    /// 白い面の中身はその場で替え、右の「<」の窓だけをドットの波紋で覆って新しい右列に差し替える。
    /// 管制塔からは滑らずにそのまま会話へ入る
    private func sideTab(_ to: V11Tab) {
        overlay = nil
        if isTower { storedTab = to; setTower(false, slide: false); return }
        guard to != tab else { return }
        storedTab = to
        guard ripple == nil else { return }
        hideRight = true
        let wave = TabRipple(kind: .side, started: Date())
        ripple = wave
        after(8.0 / 24) { hideRight = false }
        after(1.0) { if ripple == wave { ripple = nil } }
    }

    /// 管制塔 ⇄ 会話。白い面が 0.5s・24fps で滑る（会話へは ease-out、管制塔へは ease-in）。
    /// 右列の中身は 8 コマ目（1/3 の所）で差し替える
    /// - Parameter slide: false なら滑らずにその場で替える（メニューから入る時。白い面がもう覆っている）
    private func setTower(_ value: Bool, slide: Bool = true) {
        guard value != tower, shot == nil else { return }
        tower = value
        settled = false
        let wave = TabRipple(kind: value ? .toTower : .toChat, started: Date())
        ripple = wave
        after(1.0) { if ripple == wave { ripple = nil } }
        let from = towerP, to: Double = value ? 0 : 1, started = Date()
        after(8.0 / 24) { if tower == value { colTower = value } }
        guard slide else { towerP = to; settled = true; return }
        Task { @MainActor in
            let frame = 1.0 / 24, duration = 0.5
            while tower == value {
                let k = min(1, floor(Date().timeIntervalSince(started) / frame) * frame / duration)
                let e = value ? k * k * k : 1 - pow(1 - k, 3)
                towerP = from + (to - from) * e
                if k >= 1 { break }
                try? await Task.sleep(for: .seconds(frame))
            }
            if tower == value { settled = true; colTower = value }
        }
    }

    /// タイルを押した。先頭のエージェントの会話を開いて、滑って会話へ
    private func enter(_ tile: WsTile) {
        enteredWorkspace = tile.id
        if let lead = tile.lead { Task { await cockpit.open(lead) } } else { cockpit.selectedSession = nil }
        storedTab = .talk
        setTower(false)
    }

    /// 門の窓・同じ指示の行から入る。承認ならそのセッションを開く
    private func enter(path: String, stopID: String?, projects: [TowerProject]) {
        if let stopID, let approval = cockpit.approvals.first(where: { $0.id == stopID }) {
            cockpit.selectedSession = approval.session
            storedTab = .talk
            setTower(false)
            return
        }
        guard let tile = projects.flatMap(\.tiles).first(where: { $0.id == path }) else { setTower(false); return }
        enter(tile)
    }

    private func towerAct(_ action: TileAction, _ tile: WsTile) {
        switch action {
        case .branch: overlay = .newWorkspace(from: tile.id)
        case .terminal:
            // 中の端末で続きを開く（Terminal.app はメニューの葉に残す）
            if let lead = tile.lead, let command = cockpit.handOff(lead.id) {
                terminals.add(tile.id, name: "resume", command: command)
            }
            enter(tile)
            termOpen = true
        case .forget: cockpit.removeProject(tile.id)
        case .delete: overlay = .delete(tile.id)
        case .pick: if let race = tile.race { overlay = .pick(race) }
        case .retry: cockpit.retryWorkspace(tile.id)
        }
    }

    /// 決定のドットを1回飛ばす。どちらかの矩形がまだ測れていなければ飛ばさない
    private func fly(from a: CGRect?, to b: CGRect?, ink: Color = Palette.blue) {
        guard let a, let b, shot == nil else { return }
        let flight = DotFlight(from: a, to: b, ink: ink)
        flights.append(flight)
        after(flight.duration + 0.3) { flights.removeAll { $0.id == flight.id } }
    }

    private func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            action()
        }
    }

    private func dripInk() {
        let rows = Cockpit.actionRows(chips: cockpit.snapshot(now: Date(), mode: .work).chips,
                                      gates: cockpit.gates).rows
        let w = book.size.width, h = book.size.height
        guard h > 100 else { return }
        let inkLeft = w - 540, panelLeft = w - 376, apexY = (56 + (h - 44)) / 2
        for (i, row) in rows.enumerated() {
            guard let rect = book.rects["act:\(i)"] else { continue }
            let y = rect.midY
            // 五角形の尖りに沿った縁。行の中心と縁の中ほどへ落とす
            let edge = inkLeft + 146 * (y < apexY ? (y - 56) / (apexY - 56) : (h - 44 - y) / (h - 44 - apexY))
            let x = ((edge + panelLeft) / 2 - inkLeft) / 540
            Ink.tank.drip(x: Float(x), y: Float((y - 56) / (h - 100)), accent: row.accent,
                          amount: row.accent ? 0.7 : 0.8, after: 0.42 * Double(i + 1))
        }
    }

    // MARK: 門

    /// i はカードに並んだ順（書き換えられない時は 許可・却下 の2つ）
    private func choose(_ i: Int) {
        guard let stop, stop.options.indices.contains(i) else { return }
        gate.choice = i
        gate.shake += 1
        let option = stop.options[i]
        if option == 1 {
            // 書き換えている間に猶予で通ってしまわないよう止める
            if case let .approval(a) = stop.source { cockpit.holdGrace(a.id) }
            after(0.11) { gate.rewriting = true }
            return
        }
        answer(stop, option == 0 ? .allow : .deny, revised: "", from: book.rects["gateBtn:\(i)"],
               word: option == 0 ? "ALLOWED" : "REJECTED")
    }

    private func issueRewrite() {
        guard let stop, !gate.revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        answer(stop, .revise, revised: gate.revised, from: book.rects["gateBtn:rw"], word: "REWRITTEN")
    }

    private func answer(_ stop: Stop, _ verdict: Gate.Verdict, revised: String, from: CGRect?, word: String) {
        switch stop.source {
        case let .gate(request):
            answer(request, verdict, revised: revised, from: from, word: word)
        case let .approval(approval):
            // 送れたかどうかは必ず見る。相手は答えが届くまで道具の前で止まっている
            guard cockpit.answer(approval, allow: verdict != .deny, input: verdict == .revise ? revised : nil) else {
                gate.failed = approval.id
                return
            }
            gate.failed = nil
            gate.rewriting = false
            verdicts.append(VerdictLine(id: approval.id, session: approval.session, at: Date(),
                                        text: "APPROVAL // \(approval.tool) → \(word)"))
        }
    }

    /// 門に答える。**書けたかどうかは必ず見る**——黙って消すと司令塔が待ち続ける。
    /// 書けた時だけドットを飛ばし（門のボタン → PLAN の行 → ACTIONS の最後の行）、会話に印を残す
    private func answer(_ request: Gate.Request, _ verdict: Gate.Verdict, revised: String,
                        from: CGRect?, word: String) {
        let label = Cockpit.gateLabel(chips: cockpit.snapshot(now: Date(), mode: .work).chips)
        guard cockpit.answer(request, verdict, revised: revised) == .saved else {
            gate.failed = request.id
            return
        }
        gate.failed = nil
        gate.rewriting = false
        verdicts.append(VerdictLine(id: request.id, session: cockpit.selectedSession, at: Date(),
                                    text: "GATE // \(label) → \(word)"))
        let plan = book.rects["plan:current"] ?? book.rects["plan:0"]
        fly(from: from, to: plan, ink: verdict == .deny ? Palette.Light.fg3 : Palette.blue)
        after(1.15) { fly(from: plan, to: book.rects["act:last"]) }
    }

    /// 成功の合図。矩形がまだ測れていなければ出さない
    private func burst(at rect: CGRect?) {
        guard let rect else { return }
        let b = Burst(center: CGPoint(x: rect.midX, y: rect.midY))
        bursts.append(b)
        after(0.8) { bursts.removeAll { $0.id == b.id } }
    }

    /// ファイルをその行で FILES に開く。worktree の外のもの（記憶DB など）は従来の板で読む
    private func openFile(_ path: String, line: Int = 1) {
        guard let root = currentWorkspace, !path.hasPrefix("/") || path.hasPrefix(root + "/") else {
            overlay = .file(path)
            return
        }
        let relative = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
        if files.root != root { files.loadNow(root: root, open: nil) }
        files.show(relative, line: line)
        if tab != .files { go(.files) }
    }

    // MARK: キー

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if menu != nil { return menuKey(press) }
        if press.modifiers == .command, press.characters == "0" {
            setTower(!tower)
            return .handled
        }
        if press.modifiers == .command, press.characters == "p" {
            Task { await files.load(root: currentWorkspace) }
            overlay = .quickOpen
            return .handled
        }
        if press.modifiers == .command, press.characters == "j" {
            openMenu(.jump)
            return .handled
        }
        if press.modifiers == .command, let n = Int(press.characters), (1...6).contains(n) {
            let projects = TowerData.projects(cockpit)
            let rows = jumpRows(projects)
            if rows.indices.contains(n - 1) { jump(to: String(rows[n - 1].key.dropFirst(2)), projects: projects) }
            return .handled
        }
        // 打っている最中は、修飾キー無しの鍵（1文字のタブ・M・N・門の ←→ ENTER 1–3）を横取りしない。
        // 入力欄・エディタ（どちらも NSText）に焦点がある時は Esc だけ、端末の時は Esc も通す
        let responder = NSApp.keyWindow?.firstResponder
        if Terminals.owns(responder) { return .ignored }
        if responder is NSText, press.key != .escape { return .ignored }
        if press.key == .escape {
            // 手前から順に畳む。一度に全部消すと、戻るつもりで土台まで戻ってしまう
            if overlay != nil { overlay = nil; return .handled }
            if termOpen { termOpen = false; return .handled }
            if gate.rewriting { gate.rewriting = false; return .handled }
            if !isTower { setTower(true); return .handled }
            return .ignored
        }
        guard overlay == nil, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        if press.characters == "m" { openMenu(); return .handled }
        if isTower { return towerKey(press) }
        if let to = V11Tab.allCases.first(where: { $0.keys.contains(press.characters) }) {
            go(to)
            return .handled
        }
        // 門のカードが出ている間だけ ←→ ENTER 1–3 が効く
        guard tab == .talk, stop != nil, !gate.rewriting, wipe == nil,
              Date().timeIntervalSince(gateArmedAt) > 0.6 else { return .ignored }
        switch press.key {
        case .rightArrow: gate.choice = (gate.choice + 1) % (stop?.options.count ?? 3); return .handled
        case .leftArrow: gate.choice = (gate.choice + (stop?.options.count ?? 3) - 1) % (stop?.options.count ?? 3); return .handled
        case .return: choose(gate.choice); return .handled
        default: break
        }
        if let n = Int(press.characters), (1...(stop?.options.count ?? 3)).contains(n) { choose(n - 1); return .handled }
        return .ignored
    }

    /// 管制塔: ←→ で1枚ずつ、↑↓ で4枚ずつ、ENTER で入る、N で新規
    private func towerKey(_ press: KeyPress) -> KeyPress.Result {
        let order = TowerData.order(TowerData.projects(cockpit), fold: towerFold)
        let n = order.count
        switch press.key {
        case .rightArrow: towerFocus = min(max(0, n - 1), towerFocus + 1)
        case .leftArrow: towerFocus = max(0, towerFocus - 1)
        case .downArrow: towerFocus = min(max(0, n - 1), towerFocus + 4)
        case .upArrow: towerFocus = max(0, towerFocus - 4)
        case .return: if order.indices.contains(towerFocus) { enter(order[towerFocus]) }
        default:
            guard press.characters == "n" else { return .ignored }
            overlay = .newWorkspace(from: nil)
        }
        return .handled
    }

    private func findCLIs(force: Bool) { cockpit.findCLIs(force: force) }

    // MARK: メニュー

    /// 連携が入っていて、起こせる CLI が1つでも見つかっている
    private var launcherReady: Bool { launcherEnabled && !cockpit.found.isEmpty }

    /// いま開いているワークスペース（worktree のパス）と、それを持つプロジェクト
    /// いま開いている worktree。セッションがあればその置き場、無ければ最後に入ったタイル
    /// （エージェントのいない worktree でも REVIEW・GIT・FILES・端末が使える）
    private var currentWorkspace: String? {
        cockpit.selectedSession.flatMap { cockpit.workspacePath(of: $0) } ?? enteredWorkspace
    }

    private func project(of workspace: String?, in projects: [TowerProject]) -> TowerProject? {
        guard let workspace else { return nil }
        return projects.first { $0.tiles.contains { $0.id == workspace } }
    }

    private func shotOverlay(_ projects: [TowerProject]) -> Overlay? {
        guard shot != nil, let shotSheet else { return nil }
        let tiles = (projects.isEmpty ? TowerData.projects(cockpit) : projects).flatMap(\.tiles)
        switch shotSheet {
        case "new": return .newWorkspace(from: tiles.first { !$0.isMain }?.id)
        case "delete": return tiles.first { !$0.isMain && $0.failed == nil }.map { .delete($0.id) }
        case "pick": return tiles.compactMap(\.race).first.map { .pick($0) }
        default: return nil
        }
    }

    /// `--shot --menu` の時だけ。開ききった所を1枚焼く
    private func shotMenuState(projects: [TowerProject]) -> MenuState? {
        guard shot != nil, let shotMenu else { return nil }
        var state = MenuState(kind: shotMenu == "jump" ? .jump : .menu, opened: .distantPast, highlight: 1)
        state.settled = true
        let all = projects.isEmpty ? TowerData.projects(cockpit) : projects
        state.project = all.first?.id
        state.workspace = all.first?.tiles.first { !$0.isMain }?.id
        state.level = shotMenu == "root" ? .root : shotMenu == "project" ? .project : .workspace
        return state
    }

    /// M は白い面（ワークスペースのタブから始める）、⌘J は斜線の世界
    private func openMenu(_ kind: MenuState.Kind = .menu) {
        guard wipe == nil else { return }
        let opened = Date()
        var state = MenuState(kind: kind, opened: opened, highlight: 0)
        if kind == .menu {
            let projects = TowerData.projects(cockpit)
            state.workspace = currentWorkspace
            state.project = project(of: currentWorkspace, in: projects)?.id
            if state.workspace == nil { state.level = state.project == nil ? .root : .project }
            state.highlight = state.level == .workspace ? (V11Tab.allCases.firstIndex(of: tab) ?? 0) : 0
        }
        menu = state
        after(WedgeMenu.openTime + 0.08) { if menu?.opened == opened { menu?.settled = true } }
    }

    /// 閉じる。ドットが縮み終わってから外す
    private func hideMenu() {
        guard let state = menu, state.closing == nil else { return }
        menu?.closing = Date()
        menu?.settled = false
        after(WedgeMenu.closeTime + 0.06) { if menu?.opened == state.opened { menu = nil } }
    }

    private func menuRows(_ state: MenuState, projects: [TowerProject]) -> [MenuRow] {
        switch state.kind {
        case .jump: return jumpRows(projects)
        case .menu: break
        }
        switch state.level {
        case .root:
            return projects.map { p in
                MenuRow(key: "p:" + p.id, num: String(format: "%02d", p.tiles.count), en: p.name, jp: "プロジェクト",
                        desc: "\(p.tiles.count) worktrees · → で入る")
            }
        case .project:
            let tiles = projects.first { $0.id == state.project }?.tiles ?? []
            let ordered = tiles.filter(\.isMain) + tiles.filter { !$0.isMain }.sorted { $0.rank < $1.rank }
            return ordered.map { t in
                MenuRow(key: "w:" + t.id, num: t.isMain ? "◆" : "·", en: t.name, jp: t.state.jp,
                        desc: (t.branch ?? "切り離し") + " · → で入る")
            }
        case .workspace:
            let name = state.workspace.map { ($0 as NSString).lastPathComponent } ?? wsName
            return V11Tab.allCases.map { t in
                MenuRow(key: "t:" + t.rawValue, num: t.no, en: t.en.capitalized, jp: t.jp,
                        desc: "\(name) の \(t.jp) · \(t.keys[0].uppercased())")
            }
        }
    }

    /// ⌘J の並び。全ワークスペースのエージェントを あなた待ち → 作業中 → 完了 → 待機 の順に
    private func jumpRows(_ projects: [TowerProject]) -> [MenuRow] {
        let stops = Stop.all(cockpit, chips: [])
        let rows = projects.flatMap(\.tiles).flatMap { tile in tile.rows.map { (tile, $0) } }
            .sorted { $0.1.status < $1.1.status || ($0.1.status == $1.1.status && $0.1.unread && !$1.1.unread) }
        return rows.enumerated().map { i, pair in
            let (tile, row) = pair
            let stop = stops.first { $0.workspace == tile.id }
            let state: TileState = [.wait, .work, .fail, .done, .idle][row.status.rawValue]
            return MenuRow(key: "a:" + row.id, num: i < 6 ? "⌘\(i + 1)" : "", en: tile.name, jp: row.backend.title,
                           desc: [row.backend.title, cockpit.model(of: row.id) ?? "", "·", row.title]
                               .filter { !$0.isEmpty }.joined(separator: " "),
                           tag: row.status == .waiting ? (stop?.stop.title ?? state.jp) : state.jp,
                           wait: row.status == .waiting)
        }
    }

    private func menuCrumbs(_ state: MenuState, projects: [TowerProject]) -> [MenuCrumb] {
        var crumbs = [MenuCrumb(title: "~/" + "code", level: .root)]
        if state.level != .root, let p = projects.first(where: { $0.id == state.project }) {
            crumbs.append(MenuCrumb(title: p.name, level: .project))
        }
        if state.level == .workspace, let ws = state.workspace {
            crumbs.append(MenuCrumb(title: ".worktrees/" + (ws as NSString).lastPathComponent, level: .workspace))
        }
        return crumbs
    }

    private func menuKey(_ press: KeyPress) -> KeyPress.Result {
        guard let state = menu else { return .ignored }
        if press.modifiers == .command, press.characters == "j" { hideMenu(); return .handled }
        let n = max(1, menuRows(state, projects: TowerData.projects(cockpit)).count)
        switch press.key {
        case .downArrow: menu?.highlight = (state.highlight + 1) % n
        case .upArrow: menu?.highlight = (state.highlight + n - 1) % n
        case .return, .rightArrow: pickMenu(state.highlight)
        case .leftArrow, .delete: if state.kind == .menu { menuUp() }
        case .escape: hideMenu()
        default:
            guard press.characters == "m" else { return .ignored }
            hideMenu()
        }
        return .handled
    }

    private func menuUp() {
        guard let state = menu else { return }
        switch state.level {
        case .workspace: menuGo(.project)
        case .project: menuGo(.root)
        case .root: hideMenu()
        }
    }

    private func menuGo(_ level: MenuState.Level) {
        guard menu != nil else { return }
        menu?.level = level
        if level == .root { menu?.project = nil }
        if level != .workspace { menu?.workspace = nil }
        menu?.highlight = 0
        menu?.turn += 1
    }

    private func pickMenu(_ i: Int) {
        guard let state = menu else { return }
        let projects = TowerData.projects(cockpit)
        let rows = menuRows(state, projects: projects)
        guard rows.indices.contains(i) else { return }
        let key = rows[i].key
        menu?.highlight = i
        let value = String(key.dropFirst(2))
        switch key.prefix(2) {
        case "p:":
            menu?.project = value
            menuGo(.project)
        case "w:":
            menu?.workspace = value
            menuGo(.workspace)
        case "t:":
            guard let to = V11Tab(rawValue: value) else { return }
            hideMenu()
            if let ws = state.workspace, ws != currentWorkspace,
               let tile = projects.flatMap(\.tiles).first(where: { $0.id == ws }) {
                enter(tile)
                storedTab = to
            } else {
                sideTab(to)
            }
        case "a:":
            hideMenu()
            jump(to: value, projects: projects)
        default: break
        }
    }

    /// ⌘J / ⌘1–6 で選んだエージェントへ飛ぶ
    private func jump(to session: String, projects: [TowerProject]) {
        guard let row = projects.flatMap(\.tiles).flatMap(\.rows).first(where: { $0.id == session }) else { return }
        Task { await cockpit.open(row) }
        storedTab = .talk
        setTower(false)
    }
}

// MARK: - 根が持つ小さな値

/// 部品の矩形。`RectBook.space` の座標で持つ。**観測しない**（書き換えても画面は組み直さない）
@MainActor
final class RectBook {
    static let space = "sumi"
    var rects: [String: CGRect] = [:]
    var size = CGSize(width: 1440, height: 900)
}

struct SumiRectsKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// この部品の矩形を根へ知らせる（決定のドットの出発点・行き先、墨を落とす高さ）
    func reportRect(_ key: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: SumiRectsKey.self, value: [key: geo.frame(in: .named(RectBook.space))])
            }
        }
    }
}

/// 墨流しの水槽は1つだけ。窓を組み直しても溜まった墨を捨てない
@MainActor
enum Ink {
    /// 会話の右の面（540×800）
    static let tank = InkTank()
    /// 管制塔の全面（1440×800）。格子は横に 4/3 倍
    static let tower = InkTank(width: 1440, height: 800, res: InkTank.defaultRes * 4 / 3)
}

/// いま人の答えを待っている1件。**門**（司令塔が自分で止まって待つ）と
/// **道具の承認**（AT22 が繋いだエージェントが道具の前で止まる）を、同じカードで出す。
/// 道具の承認を先に出す——相手はプロセスごと止まっていて、門より先に詰まる
struct Stop {
    enum Source { case gate(Gate.Request), approval(Approval) }
    let source: Source
    let id: String
    let bar: String
    let barJP: String
    let target: String
    let title: String
    let body: String
    let meta: String
    let since: Date
    let canRevise: Bool
    /// 書換欄に最初から入れておく文
    let seed: String
    /// 動いている worktree の名前（Bash の cwd に出す）
    var place = "."
    /// 猶予の期限（気にかけてる）。過ぎると AT22 が許可する
    var autoAt: Date? = nil
    /// 道具の入力を1回だけ解いたもの。読むたびに解くと、カード1枚の描画で20回以上解いていた
    var json: [String: Any] = [:]

    @MainActor
    static func current(_ cockpit: Cockpit, chips: @autoclosure () -> [AgentChip]) -> Stop? {
        if let a = cockpit.approvals.filter({ $0.session == cockpit.selectedSession && !AskWindow.isWindowed($0) }).min(by: { $0.at < $1.at }) {
            return make(a, cockpit: cockpit)
        }
        guard let g = cockpit.gates.min(by: { $0.issued < $1.issued }) else { return nil }
        return make(g, chips: chips())
    }

    /// 管制塔の右列に出す全部（どのセッションの承認も、どの門も）。待たせている順
    @MainActor
    static func all(_ cockpit: Cockpit, chips: @autoclosure () -> [AgentChip]) -> [TowerStop] {
        let gateChips = cockpit.gates.isEmpty ? [] : chips()
        let stops = cockpit.approvals.map { make($0, cockpit: cockpit) } + cockpit.gates.map { make($0, chips: gateChips) }
            + cockpit.deferred.map { make($0, cockpit: cockpit, deferred: true) }
        return stops.sorted { $0.since < $1.since }.map { stop in
            let session: String
            switch stop.source {
            case let .approval(a): session = a.session
            case let .gate(g): session = g.by
            }
            let path = cockpit.workspacePath(of: session) ?? session
            return TowerStop(stop: stop, workspace: path, name: (path as NSString).lastPathComponent)
        }
    }

    enum Kind { case bash, diff, acp, gate, other }

    /// カードの出し方。ACP（Grok など）は書き換えの口が無いので別扱い
    var kind: Kind {
        guard case let .approval(a) = source else { return .gate }
        if !a.canRevise { return .acp }
        if json["command"] != nil { return .bash }
        if json["old_string"] != nil || json["content"] != nil || json["new_string"] != nil { return .diff }
        return .other
    }

    /// 並べる答え（0 許可 / 1 書き換え / 2 却下）。書き換えられない時は2つ
    var options: [Int] { canRevise ? [0, 1, 2] : [0, 2] }

    /// 頼んできた相手（Claude / Grok …、門は司令塔）
    var who: String {
        switch source {
        case .gate: return "C0"
        case .approval: return meta.components(separatedBy: " · ").first ?? "Agent"
        }
    }

    var prettyInput: String {
        guard case let .approval(a) = source else { return seed }
        guard let object = try? JSONSerialization.jsonObject(with: Data(a.input.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return a.input }
        return text
    }

    var command: String { json["command"] as? String ?? "" }
    var timeout: Int? { (json["timeout"] as? Double).map { Int($0 / 1000) } ?? (json["timeout"] as? Int).map { $0 / 1000 } }
    var inputDescription: String { json["description"] as? String ?? "" }
    var diffPath: String { (json["file_path"] ?? json["path"] ?? json["notebook_path"]) as? String ?? target }
    var isNewFile: Bool { json["content"] != nil && json["old_string"] == nil }

    /// 差分の行。Edit は old_string → new_string、Write は中身を全部追加として
    var diffLines: [(kind: Character, old: Int?, new: Int?, text: String)] {
        if let old = json["old_string"] as? String {
            let new = json["new_string"] as? String ?? ""
            let o = old.split(separator: "\n", omittingEmptySubsequences: false)
            let n = new.split(separator: "\n", omittingEmptySubsequences: false)
            return o.enumerated().map { ("-", $0.offset + 1, nil, String($0.element)) }
                + n.enumerated().map { ("+", nil, $0.offset + 1, String($0.element)) }
        }
        if let content = json["content"] as? String {
            return content.split(separator: "\n", omittingEmptySubsequences: false).prefix(200).enumerated()
                .map { ("+", nil, $0.offset + 1, String($0.element)) }
        }
        return []
    }

    /// 道具の入力の1行。Bash ならコマンド、ファイルを触る道具ならパス、門なら行き先
    var inputLine: String {
        switch source {
        case .gate: return "→ " + target
        case let .approval(a):
            if let command = json["command"] as? String { return "$ " + command }
            if let path = (json["file_path"] ?? json["path"] ?? json["notebook_path"]) as? String { return path }
            return a.detail
        }
    }

    @MainActor
    private static func make(_ a: Approval, cockpit: Cockpit, deferred: Bool = false) -> Stop {
        // 要判断（留守番で断って積んだもの）は 許可して伝える／捨てる の2つ。相手はもう待っていない
        Stop(source: .approval(a), id: a.id, bar: deferred ? "C0 // 要判断" : "C0 // APPROVAL", barJP: deferred ? "要判断" : "承認",
             target: a.tool,
             title: deferred ? "要判断 · \(a.tool)" : "Run \(a.tool)?", body: a.detail,
             meta: cockpit.backend(of: a.session).title + " · " + String(a.session.prefix(8)),
             since: a.at, canRevise: deferred ? false : a.canRevise, seed: a.input,
             place: cockpit.workspacePath(of: a.session).map { ".worktrees/" + ($0 as NSString).lastPathComponent } ?? ".",
             autoAt: a.autoAt,
             json: (try? JSONSerialization.jsonObject(with: Data(a.input.utf8))) as? [String: Any] ?? [:])
    }

    private static func make(_ g: Gate.Request, chips: [AgentChip]) -> Stop {
        let to = g.to.isEmpty ? g.call : g.to
        var meta = [g.risk.isEmpty ? nil : g.risk, g.by.isEmpty ? nil : String(g.by.prefix(8)), "→ " + to]
            .compactMap { $0 }.joined(separator: " · ")
        // 采配の門は、通すと AT22 が worktree を作ってワーカーを起こす
        if let backend = g.dispatch {
            meta += " · 采配 → \(backend) で \(g.name)（\(g.base.isEmpty ? "HEAD" : g.base) から）"
        }
        return Stop(source: .gate(g), id: g.id, bar: "C0 // GATE", barJP: "門", target: to,
                    title: "Wake \(Cockpit.gateLabel(chips: chips))?", body: Cockpit.plainLine(g.instruction),
                    meta: meta, since: g.issued, canRevise: true, seed: Cockpit.plainLine(g.instruction))
    }
}

/// 見ていない間にターンが終わった・承認を求めてきた時の通知。**アプリが前に出ている間は出さない**
/// （Dock のバッジで足りる）
enum Notifier {
    /// 通知は bundle ID のある .app（package.sh で組んだもの）の時だけ。
    /// `swift run` の素の実行ファイルで通知の口を叩くと落ちる
    @MainActor
    static func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// 門のカードの手元の状態（←→ で選んでいる番号・書換欄）
struct GateUI: Equatable {
    var choice = 0
    var rewriting = false
    var revised = ""
    var shake = 0
    /// 答えを書けなかった門。**黙って消さない**（司令塔は待ったまま）
    var failed: String?
}

/// 会話の流れに挟む門の印
struct VerdictLine: Identifiable, Equatable {
    let id: String
    let session: String?
    let at: Date
    let text: String
}

/// 鶴が出すもの
struct CraneStatus: Equatable {
    var busy: String?
    var pose: Mascot.Pose
    var state: String
    var sub: String
}

// MARK: - タブ

/// v11 のタブ（STRUCTURE は FILES と統合）。`keys` は1文字で飛ぶ鍵
enum V11Tab: String, CaseIterable {
    // 壁打ちは会話画面のトグルに、記憶DB は FILES の中（ファイル｜記憶DB）に移した
    case talk, files, review, git, settings

    var no: String { ["01", "02", "07", "08", "10"][index] }
    var en: String { ["TALK", "FILES", "REVIEW", "GIT", "SETTINGS"][index] }
    var jp: String { ["会話", "構造・ファイル・記憶", "差分", "記帳と送出", "設定"][index] }
    var desc: String { ["会話と門", "木・関係・エディタ・記憶DB", "差分と指摘", "記帳・送出・依頼", "既定と操作"][index] }
    var keys: [String] { [["a"], ["b", "e"], ["d"], ["g"], [","]][index] }
    /// 畳み込みの見方（構造は FILES）
    var mode: CockpitMode { self == .files ? .structure : .work }

    init(_ mode: CockpitMode) {
        self = mode == .structure || mode == .memory ? .files : .talk
    }

    private var index: Int { Self.allCases.firstIndex(of: self)! }
}

// MARK: - 面の形

/// 青い面＝全体から白い面をくり抜いた残り。白い面は p で管制塔の「>」（左の三角）から会話の「<」まで変わる。
/// `polygon(0 56, XC 56, XT apex, XC h-44, 0 h-44)`、XC=(W-394)p・XT=146+(W-540-146)p
struct BlueSheet: Shape {
    var p: CGFloat

    nonisolated func path(in r: CGRect) -> Path {
        var path = Path(r)
        path.addPath(Self.white(p: p, size: r.size))
        return path
    }

    nonisolated static func corners(p: CGFloat, size: CGSize) -> (xc: CGFloat, xt: CGFloat, apex: CGFloat) {
        let xc = (size.width - 394) * p
        let xt = 146 + (size.width - 540 - 146) * p
        return (xc, xt, (56 + size.height - 44) / 2)
    }

    nonisolated static func white(p: CGFloat, size: CGSize) -> Path {
        let c = corners(p: p, size: size)
        var hole = Path()
        hole.move(to: CGPoint(x: 0, y: 56))
        hole.addLine(to: CGPoint(x: c.xc, y: 56))
        hole.addLine(to: CGPoint(x: c.xt, y: c.apex))
        hole.addLine(to: CGPoint(x: c.xc, y: size.height - 44))
        hole.addLine(to: CGPoint(x: 0, y: size.height - 44))
        hole.closeSubpath()
        return hole
    }

    /// 境界の折れ線。管制塔では白、会話では青で 3px
    static func edge(p: CGFloat, size: CGSize) -> Path {
        let c = corners(p: p, size: size)
        var path = Path()
        path.move(to: CGPoint(x: c.xc, y: 56))
        path.addLine(to: CGPoint(x: c.xt, y: c.apex))
        path.addLine(to: CGPoint(x: c.xc, y: size.height - 44))
        return path
    }
}

/// 切り欠きの当たり。管制塔は左の白い三角、会話は右の青い三角（どちらも 146 幅）
private struct NotchShape: Shape {
    let left: Bool

    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        if left {
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: r.width, y: r.midY))
            p.addLine(to: CGPoint(x: 0, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: 0, y: r.midY))
            p.addLine(to: CGPoint(x: r.width, y: 0))
            p.addLine(to: CGPoint(x: r.width, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// 墨流しの切り抜き。尖りの左の三角だけを落とす（`polygon(146 0,540 0,540 h,146 h,0 h/2)`）
private struct InkClip: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 146, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 146, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 上帯

/// 青帯 56。`AT22_ GLASS COCKPIT ✳ │ 05 // PLAN ▮▮▮…（ティック）│ 日付 ＋`
private struct HeaderBand: View {
    let tasks: [RoadmapTask]
    let now: Date
    let width: CGFloat
    let onTasks: () -> Void
    let onNew: () -> Void

    /// 信号機の幅＋余白。ここより左に何か置くと窓のボタンに重なる（OS が同じ位置に描く）
    static let trafficLightInset: CGFloat = 78

    var body: some View {
        let ticks = max(120, min(840, width - Self.trafficLightInset - 24 - 300 - 118 - 120))
        HStack(spacing: 12) {
            Text("AT22_").font(.mono(20))
            Text("GLASS COCKPIT").font(.mono(11)).tracking(11 * 0.24)
            RegMark(kind: .star, size: 12)
            PlanTicks(tasks: tasks, width: ticks, onTasks: onTasks)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(now.formatted(.iso8601.year().month().day()))
                Text(now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) + " "
                     + (TimeZone.current.abbreviation() ?? "")).foregroundStyle(Palette.Blue.fg3)
            }
            .font(.mono(9)).tracking(Palette.caps(9))
            Button(action: onNew) {
                RegMark(kind: .cross, size: 14)
                    .frame(width: 32, height: 32)
                    .overlay(Rectangle().strokeBorder(Palette.white, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("新規ワークスペース")
        }
        .foregroundStyle(Palette.white)
        .padding(.leading, Self.trafficLightInset)
        .padding(.trailing, 24)
    }
}

// MARK: - 下帯

/// 青帯 44。左＝端末の帯（最終行・押すと引き出す ⌃`）、右＝門待ち（鶴が手を挙げる）＋「一個前 → 現在地」
private struct FooterBand: View {
    let width: CGFloat
    let termLine: String
    let busy: Bool
    let stop: Stop?
    let stopCount: Int
    let location: CockpitView.Location
    let onTerm: () -> Void
    let onGate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTerm) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) { Text("09").foregroundStyle(Palette.pink); Text(" // TERM") }
                        .font(.mono(10)).tracking(Palette.caps(10))
                    Text(termLine).font(.mono(12)).lineLimit(1).truncationMode(.tail).opacity(0.85)
                    Spacer(minLength: 0)
                    WaveLines(width: 60, height: 16, lines: 3, amp: 3, freq: 2, animate: busy)
                    Text("▴ 引き出す · ⌃`").font(.mono(9)).tracking(Palette.caps(9))
                }
                .padding(.horizontal, 12)
                .frame(width: max(300, min(1016, width - 424)), height: 32)
                .overlay(Rectangle().strokeBorder(Palette.white, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut("`", modifiers: .control)
            .help("端末を引き出す (⌃`)")
            Spacer(minLength: 0)
            if let stop {
                Button(action: onGate) {
                    HStack(spacing: 8) {
                        Mascot(pitch: 5, lookRight: false, busy: "wait", color: Palette.white)
                            .offset(y: -6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("GATE · \(stopCount)").foregroundStyle(Palette.pink)
                            Text(stop.target).foregroundStyle(Palette.Blue.fg3).lineLimit(1)
                        }
                        .font(.mono(9)).tracking(1.2)
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("門が待っています · " + stop.title)
            }
            HStack(spacing: 10) {
                if let prev = location.prev {
                    Text(prev).foregroundStyle(Palette.Blue.fg3)
                    Text("→").foregroundStyle(Palette.Blue.fg3)
                }
                Text(location.cur)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Rectangle().strokeBorder(Palette.white, lineWidth: 1))
            }
            .font(.mono(10)).tracking(0.8)
            .lineLimit(1)
            .fixedSize()
        }
        .foregroundStyle(Palette.white)
        .padding(.horizontal, 24)
    }
}

/// 押すと 1px ずれるだけのボタン（面と色は中身が持つ）
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

// MARK: - 鶴

/// 左下の1羽。鶴 = メニューボタン = 読み込み表示。押すとメニュー（M）。管制塔では白く、言葉は畳む
private struct CraneButton: View {
    let tower: Bool
    /// メニューの白い面の上（青で描く）
    var onWhite = false
    let label: String
    let status: CraneStatus
    let onTap: () -> Void

    var body: some View {
        let ink = tower && !onWhite ? Palette.white : Palette.Light.fg
        VStack(alignment: .leading, spacing: 10) {
            if !tower {
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.sub).font(.bodyJP(13)).lineSpacing(3).lineLimit(2)
                    Text(status.state).font(.mono(10)).tracking(Palette.caps(10))
                        .foregroundStyle(status.busy == "wait" ? Palette.pink : Palette.Light.fg2)
                }
            }
            Mascot(pitch: 9, lookRight: true, pose: status.pose, busy: status.busy, color: ink)
                .reportRect("crane")
            Text(label).font(.mono(10)).tracking(1)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(Rectangle().stroke(ink, lineWidth: 1))
                .fixedSize()
        }
        .foregroundStyle(ink)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help("メニュー (M)")
    }
}
