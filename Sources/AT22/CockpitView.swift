import SwiftUI
import AppKit

// MARK: - 画面の根

/// Sumi v10 の画面。青帯2本・白い五角形・右の青い面（墨流し）・左下の鶴。
///
/// ```
/// ┌ 青帯 56 ───────────────────────────────────────────────────────┐
/// │ 白い五角形（右端が W-394 で尖る）     │ 青＋墨流し               │
/// │  鶴   01 TALK / 02 STRUCTURE / 03 SPARRING │ 04 ACTIONS / 05 PLAN │
/// └ 青帯 44: 05 // PLAN のティック ───────────────────────────────┘
/// ```
/// 重なりの順（下から）: 画面 → メニュー → タスク・FILE などのモーダル → 決定のドット → DotWipe
struct CockpitView: View {
    let cockpit: Cockpit
    /// `--shot` が焼く時刻。入っている間は TimelineView・ScrollView・TextField を作らない
    var shot: Date? = nil
    /// `--shot --mode` で焼くタブ。nil なら保存されている値
    var shotMode: CockpitMode? = nil

    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    @AppStorage("cockpitMode") private var storedMode = CockpitMode.work
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""
    @AppStorage("showThinking") private var showThinking = false

    /// 手前に開いているもの。Esc はここから畳む
    @State private var overlay: Overlay?
    @State private var menu: MenuState?
    @State private var wipe: Wipe?
    @State private var flights: [DotFlight] = []
    /// 部品の矩形（ドットの出発点と行き先、墨を落とす高さ）。**観測しない箱**に入れる——
    /// @State にすると、スクロールのたびに根ごと組み直す
    @State private var book = RectBook()

    // 壁打ち
    @State private var editing: String?
    @State private var memoryDirty = false
    // 構造
    @State private var structFilter = StructFilter.all
    // 門
    @State private var gate = GateUI()
    /// 答えた門の印。会話の流れに `GATE // W6 → ALLOWED` として混ぜる（画面だけの記録）
    @State private var verdicts: [VerdictLine] = []
    @State private var riskyLevel: Gate.Level?
    @State private var gateArmedAt = Date.distantPast
    @State private var replySession: String?
    @State private var windowVisible = true

    @Environment(\.openSettings) private var openSettings

    enum Overlay: Equatable {
        case tasks
        case file(String)
        case agent(String)
        case newSession
    }

    private var mode: CockpitMode { shotMode ?? storedMode }

    var body: some View {
        GeometryReader { geo in
            Ticker(fps: 1) { now in
                screen(size: geo.size, now: now)
            }
            .environment(\.frozenTime, shot)
            .coordinateSpace(.named(RectBook.space))
            .onPreferenceChange(SumiRectsKey.self) { [book] value in
                MainActor.assumeIsolated { book.rects = value }
            }
            .onAppear { book.size = geo.size }
            .onChange(of: geo.size) { book.size = geo.size }
        }
        .background(Palette.Light.bg)
        // `onKeyPress` はフォーカスを持つ View にしか来ない。焦点の輪は意匠に合わないので消す。
        // 入力欄に焦点がある間は文字がそちらへ吸われるので、ここへは落ちてこない
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
        .onChange(of: threshold, initial: true) { cockpit.flagReadThreshold = threshold }
        .onChange(of: launcherEnabled) { findCLIs(force: true) }
        .onChange(of: claudePath) { findCLIs(force: true) }
        .onChange(of: codexPath) { findCLIs(force: true) }
        // 止まっている門が入れ替わったら、答えかけを捨てて新しい門の本文から始める
        .onChange(of: oldestGate?.id, initial: true) {
            gate = GateUI(revised: oldestGate.map { Cockpit.plainLine($0.instruction) } ?? "")
            // 次の門が出た直後の Enter / 1 は受けない。続けて押すと、見ていない門を許可してしまう
            gateArmedAt = Date()
        }
        .onChange(of: lastReplyID) { old, id in
            // セッションを切り替えた・履歴を読んだだけの時は飛ばさない（返答が着いた時だけ）
            defer { replySession = cockpit.selectedSession }
            guard old != nil, id != nil, replySession == cockpit.selectedSession,
                  mode == .work, shot == nil else { return }
            // 返答が着いた。鶴から最後の枠へドットを渡す（v10 の `ask` の後半）
            after(0.06) { fly(from: book.rects["crane"], to: book.rects["c0last"]) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
            windowVisible = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
        }
        .alert("この段は人間の承認なしにファイルを書き換える", isPresented: Binding(
            get: { riskyLevel != nil }, set: { if !$0 { riskyLevel = nil } })) {
            Button("やめる", role: .cancel) { riskyLevel = nil }
            Button("承知した", role: .destructive) {
                if let level = riskyLevel { cockpit.setGateLevel(level) }
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
                if windowVisible, menu == nil { dripInk() }
            }
        }
    }

    // MARK: 組み立て

    @ViewBuilder
    private func screen(size: CGSize, now: Date) -> some View {
        let w = size.width, h = size.height
        let snap = cockpit.snapshot(now: now, mode: .work)
        let gates = cockpit.gates
        let actions = Cockpit.actionRows(chips: snap.chips, gates: gates,
                                         cells: snap.cards.flatMap(\.files), now: now)
        let tasks = cockpit.allTasks(session: cockpit.selectedSession)
        let busy = cockpit.isWorking(cockpit.selectedSession)
        let trail = currentTrail()
        let crane = craneStatus(busy: busy, trail: trail)
        let contentW = max(380, w - 780)

        ZStack(alignment: .topLeading) {
            // 画面の層。メニューが面を覆いきった間・窓が隠れている間は、ここの時計を全部止める
            ZStack(alignment: .topLeading) {
                Palette.Light.bg
                Chassis().fill(Palette.blue, style: FillStyle(eoFill: true))
                // 右の面。尖りの右側だけを墨流しにする
                Suminagashi(tank: Ink.tank, paused: !windowVisible || menu?.settled == true || shot != nil)
                    .frame(width: 540, height: max(1, h - 100))
                    .clipShape(InkClip())
                    .offset(x: w - 540, y: 56)
                Chassis.edge(w: w, h: h).stroke(Palette.white, lineWidth: 3)
                Chassis.apex(w: w, h: h).stroke(Palette.blue, lineWidth: 3)

                TopBand(cockpit: cockpit, mode: mode, now: now, onGate: { go(.work) },
                        onNew: { overlay = .newSession })
                    .frame(width: w, height: 56)

                Group {
                    switch mode {
                    case .work:
                        TalkScreen(cockpit: cockpit, headline: Cockpit.headline(rows: actions.rows),
                                   subtitle: subtitle(tasks), showThinking: showThinking,
                                   verdicts: verdicts, gate: $gate, gateFailed: gateFailedFor(oldestGate),
                                   request: oldestGate, gateLabel: Cockpit.gateLabel(chips: snap.chips),
                                   pendingGates: gates.count, trail: trail, ctxAlarm: ctxAlarm,
                                   height: h - 72, width: contentW, modalOpen: overlay != nil,
                                   onChoose: { choose($0) },
                                   onRewrite: { issueRewrite() },
                                   onNew: { overlay = .newSession })
                            .offset(x: 220, y: 72)
                    case .structure:
                        StructureScreen(cockpit: cockpit, filter: structFilter, width: contentW, height: h - 84 - 60,
                                        onOpen: { overlay = .file($0) })
                            .offset(x: 220, y: 84)
                    case .memory:
                        SparringScreen(cockpit: cockpit, editing: $editing, dirty: $memoryDirty,
                                       width: contentW, height: h - 84 - 60)
                            .offset(x: 220, y: 84)
                    }
                }

                CraneButton(mode: mode, status: crane, onTap: { openMenu() })
                    .frame(width: 150, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 40)
                    .padding(.bottom, 64)

                RightColumn(cockpit: cockpit, actions: actions.rows, doneCount: actions.doneCount,
                            snapshot: snap, tasks: tasks, height: h,
                            onOpen: { row in
                                if let path = row.path { overlay = .file(path) }
                                else if !row.waiting { overlay = .agent(row.id) }
                                else { go(.work) }
                            })
                    .frame(width: 352)
                    .offset(x: w - 376, y: 76)

                BottomBand(tasks: tasks, actions: actions.rows, busy: busy, width: w,
                           onTasks: { overlay = overlay == .tasks ? nil : .tasks })
                    .frame(width: w, height: 44)
                    .offset(y: h - 44)

            }
            .environment(\.motionPaused, !windowVisible || menu?.settled == true)

            if let menu {
                SumiMenu(state: menu, items: menuLevel(menu.path, snap: snap), crumbs: crumbs(menu.path, snap: snap),
                         size: size,
                         onPick: { pickMenu($0, snap: snap) },
                         onHover: { i in self.menu?.highlight = i },
                         onBack: { menuUp() }, onRoot: { menuShift([], 0) },
                         onCrumb: { k in menuShift(Array(menu.path.prefix(k + 1)), 0) },
                         onClose: { hideMenu() })
                    .zIndex(30)
            }

            if let overlay {
                Modals(cockpit: cockpit, overlay: overlay, snapshot: snap,
                       onClose: { self.overlay = nil },
                       onLaunched: { self.overlay = nil; storedMode = .work },
                       onOpenSettings: { openSettings() })
                    .frame(width: w, height: h)
                    .zIndex(40)
            }

            DecideLayer(flights: flights).frame(width: w, height: h).zIndex(60)
            DotWipeLayer(wipe: wipe).frame(width: w, height: h).zIndex(70)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .clipped()
    }

    // MARK: 状態の読み出し

    private var oldestGate: Gate.Request? { cockpit.gates.min { $0.issued < $1.issued } }

    private func gateFailedFor(_ request: Gate.Request?) -> Bool {
        request.map { gate.failed == $0.id } ?? false
    }

    private var ctxAlarm: Bool { cockpit.reading.stage == .warning }

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
        if busy {
            let step = trail.last.map { $0.kind == .write ? "write" : "search" } ?? "think"
            return CraneStatus(busy: step, pose: .idle, state: step.uppercased(), sub: TalkScreen.stepLabel[step] ?? "")
        }
        if !cockpit.gates.isEmpty {
            return CraneStatus(busy: "wait", pose: .one, state: "ASKING · MENU", sub: "門の応答を待っています")
        }
        if ctxAlarm {
            return CraneStatus(busy: "overload", pose: .idle, state: "MENU", sub: "文脈があふれそうです")
        }
        return CraneStatus(busy: nil, pose: .idle, state: "MENU", sub: "C0 司令塔")
    }

    // MARK: 遷移

    /// タブを移る。DotWipe が覆いきった所（380ms）で差し替え、1.86 秒で戻る。
    /// 壁打ちに未保存があると動かない（書きかけを捨てない）
    private func go(_ to: CockpitMode, origin: CGPoint? = nil, fromMenu: Bool = false) {
        guard wipe == nil, !(memoryDirty && to != mode) else {
            if fromMenu { hideMenu() }
            return
        }
        guard to != mode || fromMenu else { return }
        let started = Wipe(from: mode, to: to,
                           origin: origin ?? CGPoint(x: book.size.width / 2, y: book.size.height / 2),
                           started: Date())
        wipe = started
        after(Wipe.swapAt) {
            storedMode = to
            menu = nil
            overlay = nil
        }
        after(Wipe.total) { if wipe == started { wipe = nil } }
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

    private func choose(_ i: Int) {
        guard let request = oldestGate else { return }
        gate.choice = i
        gate.shake += 1
        if i == 1 {
            after(0.11) { gate.rewriting = true }
            return
        }
        answer(request, i == 0 ? .allow : .deny, revised: "", from: book.rects["gateBtn:\(i)"],
               word: i == 0 ? "ALLOWED" : "REJECTED")
    }

    private func issueRewrite() {
        guard let request = oldestGate,
              !gate.revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        answer(request, .revise, revised: gate.revised, from: book.rects["gateBtn:rw"], word: "REWRITTEN")
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

    // MARK: キー

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if menu != nil { return menuKey(press) }
        if press.key == .escape {
            // 手前から順に畳む。一度に全部消すと、戻るつもりで土台まで戻ってしまう
            if overlay != nil { overlay = nil; return .handled }
            if gate.rewriting { gate.rewriting = false; return .handled }
            return .ignored
        }
        guard overlay == nil, press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        switch press.characters {
        case "m": openMenu(); return .handled
        case "a": go(.work); return .handled
        case "b": go(.structure); return .handled
        case "c": go(.memory); return .handled
        default: break
        }
        // 門のカードが出ている間だけ ←→ ENTER 1–3 が効く
        guard mode == .work, oldestGate != nil, !gate.rewriting, wipe == nil,
              Date().timeIntervalSince(gateArmedAt) > 0.6 else { return .ignored }
        switch press.key {
        case .rightArrow: gate.choice = (gate.choice + 1) % 3; return .handled
        case .leftArrow: gate.choice = (gate.choice + 2) % 3; return .handled
        case .return: choose(gate.choice); return .handled
        default: break
        }
        if let n = Int(press.characters), (1...3).contains(n) { choose(n - 1); return .handled }
        return .ignored
    }

    private func findCLIs(force: Bool) {
        cockpit.findClaudeIfNeeded(override: claudePath.isEmpty ? nil : claudePath, force: force)
        cockpit.findCodexIfNeeded(override: codexPath.isEmpty ? nil : codexPath, force: force)
    }

    // MARK: メニュー

    private func openMenu() {
        guard wipe == nil else { return }
        let opened = Date()
        menu = MenuState(opened: opened, highlight: [CockpitMode.work, .structure, .memory].firstIndex(of: mode) ?? 0)
        // 開ききったら面の時計を止める（以後はただの青い面）
        after(MenuDots.settleTime + 0.4) { if menu?.opened == opened { menu?.settled = true } }
    }

    /// 閉じる。ドットが縮み終わる 560ms 後に外す
    private func hideMenu() {
        guard let state = menu, state.closing == nil else { return }
        menu?.closing = Date()
        menu?.settled = false
        after(0.56) { if menu?.opened == state.opened { menu = nil } }
    }

    private func menuKey(_ press: KeyPress) -> KeyPress.Result {
        guard let state = menu else { return .ignored }
        let n = max(1, menuLevel(state.path, snap: cockpit.snapshot(now: Date(), mode: .work)).count)
        switch press.key {
        case .downArrow: menu?.highlight = (state.highlight + 1) % n
        case .upArrow: menu?.highlight = (state.highlight + n - 1) % n
        case .return, .rightArrow: pickMenu(state.highlight, snap: cockpit.snapshot(now: Date(), mode: .work))
        case .leftArrow, .delete, .escape: menuUp()
        default:
            guard press.characters == "m" else { return .ignored }
            hideMenu()
        }
        return .handled
    }

    private func menuUp() {
        guard let path = menu?.path else { return }
        if path.isEmpty { hideMenu(); return }
        menuShift(Array(path.dropLast()), path.last ?? 0)
    }

    /// 階層を移る。白い帯が横切る間（130ms）に中身を差し替える
    private func menuShift(_ path: [Int], _ highlight: Int) {
        guard let state = menu else { return }
        menu?.band = MenuState.Band(at: Date(), forward: path.count > state.path.count)
        menu?.fresh = false
        after(0.13) {
            menu?.path = path
            menu?.highlight = highlight
            menu?.shake += 1
        }
    }

    private func menuLevel(_ path: [Int], snap: CockpitSnapshot) -> [MenuItem] {
        var level = MenuItem.tree(cockpit: cockpit, chips: snap.chips, showThinking: showThinking,
                                  launcherReady: launcherReady)
        for i in path {
            guard level.indices.contains(i), let kids = level[i].kids else { return [] }
            level = kids
        }
        return level
    }

    private func crumbs(_ path: [Int], snap: CockpitSnapshot) -> [String] {
        path.indices.map { k in
            let level = menuLevel(Array(path.prefix(k)), snap: snap)
            let i = path[k]
            return String(format: "%02d ", i + 1) + (level.indices.contains(i) ? level[i].en.uppercased() : "")
        }
    }

    private func pickMenu(_ i: Int, snap: CockpitSnapshot) {
        guard let state = menu else { return }
        let level = menuLevel(state.path, snap: snap)
        let i = min(i, level.count - 1)
        guard level.indices.contains(i) else { return }
        let item = level[i]
        menu?.highlight = i
        if item.kids != nil {
            menuShift(state.path + [i], 0)
            return
        }
        menu?.shake += 1
        after(0.11) { perform(item.action) }
    }

    private var launcherReady: Bool {
        launcherEnabled && (cockpit.claude != nil || cockpit.codexFound != nil)
    }

    /// 葉を押した。タブへ移るものは DotWipe で、それ以外はその場で済ませて閉じる
    private func perform(_ action: MenuItem.Action) {
        let origin = CGPoint(x: 500, y: 450)
        switch action {
        case let .tab(to):
            go(to, origin: origin, fromMenu: true)
        case let .structure(filter):
            structFilter = filter
            go(.structure, origin: origin, fromMenu: true)
        case let .note(path):
            if !memoryDirty { editing = path }
            go(.memory, origin: origin, fromMenu: true)
        case .session, .recent, .codex, .picker where memoryDirty:
            // 書きかけの記憶ノートはセッションのプロジェクトに属する。切り替えると捨てることになる
            hideMenu()
        case .picker:
            cockpit.selectedSession = nil
            go(.work, origin: origin, fromMenu: true)
        case let .session(id):
            cockpit.selectedSession = id
            go(.work, origin: origin, fromMenu: true)
        case let .recent(session):
            cockpit.selectedSession = session.id
            Task { await cockpit.loadSession(session) }
            go(.work, origin: origin, fromMenu: true)
        case let .codex(record):
            cockpit.selectedSession = record.id
            cockpit.resumeCodexRecord(record)
            go(.work, origin: origin, fromMenu: true)
        case .newSession:
            hideMenu()
            if launcherReady { overlay = .newSession } else { openSettings() }
        case let .agent(id):
            hideMenu()
            overlay = .agent(id)
        case let .level(level):
            hideMenu()
            if level.needsConfirmation { riskyLevel = level } else { cockpit.setGateLevel(level) }
        case let .model(id):
            hideMenu()
            if let session = cockpit.selectedSession { cockpit.setModel(id, for: session) }
        case .thinking:
            showThinking.toggle()
        case .clearIdle:
            hideMenu()
            cockpit.clearIdleAgents(now: .now)
        case .clearAll:
            hideMenu()
            cockpit.clear()
        case .tasks:
            hideMenu()
            overlay = .tasks
        case .settings:
            hideMenu()
            openSettings()
        case .none:
            break
        }
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
    static let tank = InkTank()
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

/// 02 STRUCTURE の絞り込み。メニューの Structure の葉から選ぶ
enum StructFilter: Equatable {
    case all
    case category(FileCategory)
    case ties
    case hot
}

// MARK: - 面の形

/// 青い面。白い五角形（右端が W-394 で尖る）をくり抜いた残り
private struct Chassis: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, apexY = (56 + h - 44) / 2
        var p = Path()
        p.addRect(r)
        var hole = Path()
        hole.move(to: CGPoint(x: 0, y: 56))
        hole.addLine(to: CGPoint(x: w - 540, y: 56))
        hole.addLine(to: CGPoint(x: w - 394, y: apexY))
        hole.addLine(to: CGPoint(x: w - 540, y: h - 44))
        hole.addLine(to: CGPoint(x: 0, y: h - 44))
        hole.closeSubpath()
        p.addPath(hole)
        return p
    }

    static func edge(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 56))
        p.addLine(to: CGPoint(x: w - 540, y: 56))
        p.addLine(to: CGPoint(x: w - 394, y: (56 + h - 44) / 2))
        p.addLine(to: CGPoint(x: w - 540, y: h - 44))
        p.addLine(to: CGPoint(x: 0, y: h - 44))
        return p
    }

    static func apex(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: w - 540, y: 56))
        p.addLine(to: CGPoint(x: w - 394, y: (56 + h - 44) / 2))
        p.addLine(to: CGPoint(x: w - 540, y: h - 44))
        return p
    }
}

/// 墨流しの切り抜き。尖りの左の三角だけを落とす（`polygon(0 0,540 0,540 h,0 h,146 h/2)`）
private struct InkClip: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 146, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 上帯

/// 青帯 56。`AT22_ GLASS COCKPIT ✳ ▮▮▮ SESSION/SPEND …… [GATE 門 Wake W6? 応答する↵] 日付 ＋`
private struct TopBand: View {
    let cockpit: Cockpit
    let mode: CockpitMode
    let now: Date
    let onGate: () -> Void
    let onNew: () -> Void

    /// 信号機の幅＋余白。ここより左に何か置くと窓のボタンに重なる（OS が同じ位置に描く）
    static let trafficLightInset: CGFloat = 78

    var body: some View {
        let id = cockpit.selectedSession.map { String($0.prefix(8)).uppercased() } ?? "—"
        HStack(spacing: 16) {
            Text("AT22_").font(.mono(20))
            Text("GLASS COCKPIT").font(.mono(11)).tracking(11 * 0.24)
            RegMark(kind: .star, size: 12)
            HStack(spacing: 10) {
                Barcode(value: "AT22-" + id, width: 96, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SESSION " + id)
                    Text("SPEND \(Snowman.short(Int(cockpit.spendTotal(session: cockpit.selectedSession)))) · \(mode.label)")
                        .foregroundStyle(Palette.Blue.fg3)
                }
                .font(.mono(9)).tracking(Palette.caps(9))
            }
            Spacer(minLength: 0)
            if let request = cockpit.gates.min(by: { $0.issued < $1.issued }) {
                gatePill(request)
            } else {
                HStack(spacing: 10) {
                    RegMark(kind: .target, size: 12, color: Palette.Blue.fg2)
                    Text("GATE 00 · 止まっている指示なし")
                }
                .font(.mono(10)).tracking(Palette.caps(10))
                .foregroundStyle(Palette.Blue.fg2)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .overlay(Rectangle().stroke(Palette.Blue.fg3, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(now.formatted(.iso8601.year().month().day()))
                Text(now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) + " "
                     + (TimeZone.current.abbreviation() ?? "")).foregroundStyle(Palette.Blue.fg3)
            }
            .font(.mono(9)).tracking(Palette.caps(9))
            .padding(.leading, 8)
            // 十字は新しいセッションを起こす口
            Button(action: onNew) { RegMark(kind: .cross, size: 12).padding(6).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("新しいセッションを起こす")
        }
        .foregroundStyle(Palette.white)
        .padding(.leading, Self.trafficLightInset)
        .padding(.trailing, 24)
    }

    private func gatePill(_ request: Gate.Request) -> some View {
        let label = Cockpit.gateLabel(chips: cockpit.snapshot(now: now, mode: .work).chips)
        return Button(action: onGate) {
            HStack(spacing: 12) {
                Starburst(size: 20, points: 4, color: Palette.pink, fill: true, spin: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GATE 門 · \(cockpit.gates.count) 件止まっています").font(.mono(9)).tracking(9 * 0.16)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Wake \(label)?").font(.display(20))
                        Text("\(Int(request.waited(now: now)))s").font(.mono(10)).tracking(0.8)
                    }
                }
                Text("応答する ↵").font(.mono(10)).tracking(Palette.caps(10))
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.Light.line).frame(width: 1) }
            }
            .foregroundStyle(Palette.blue)
            .padding(.leading, 16)
            .padding(.trailing, 34)
            .frame(height: 40)
            .background { Chevron(notch: 10, head: 18).fill(Palette.white) }
            .contentShape(Chevron(notch: 10, head: 18))
        }
        .buttonStyle(PressStyle())
    }
}

/// 押すと 1px ずれるだけのボタン（面と色は中身が持つ）
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

extension CockpitMode {
    /// `01 WORK 作業`
    var label: String {
        switch self {
        case .work: "01 WORK 作業"
        case .structure: "02 STRUCTURE 構造"
        case .memory: "03 SPARRING 壁打ち"
        }
    }
}

// MARK: - 鶴

/// 左下の1羽。鶴 = メニューボタン = 読み込み表示。押すとメニュー（M）
private struct CraneButton: View {
    let mode: CockpitMode
    let status: CraneStatus
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(status.sub).font(.bodyJP(13)).lineSpacing(3)
                Text(status.state).font(.mono(10)).tracking(Palette.caps(10))
                Text(mode.label + " · M").font(.mono(10)).tracking(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
            }
            Mascot(pitch: 9, lookRight: true, pose: status.pose, busy: status.busy)
                .reportRect("crane")
        }
        .foregroundStyle(Palette.Light.fg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help("メニュー (M)")
    }
}
