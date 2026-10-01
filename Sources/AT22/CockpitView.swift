import SwiftUI
import AppKit
import Combine

// MARK: - 画面の状態

/// 02 // STRUCTURE の絞り込み。メニューの Structure の葉から選ぶ
enum StructFilter: Equatable {
    case all
    case category(FileCategory)
    case ties
    case hot
}

/// 会話の流れに挟む「門にこう答えた」の1行。答えはファイルに書くだけなので、
/// 画面に残すのはこのセッションの間だけ
struct VerdictLine: Identifiable {
    let id = UUID()
    let at: Date
    let gate: String
    let verdict: String
}

/// 画面だけが持つ状態（どのモーダルが開いているか、遷移の相、決定のドット…）。
/// モデル（`Cockpit`）とは分けてあり、こちらは消えても何も失わない
@MainActor @Observable
final class Stage {
    let cockpit: Cockpit
    init(cockpit: Cockpit) { self.cockpit = cockpit }

    var mode: CockpitMode = .work

    // 遷移（DotWipe と大見出し）
    var wipe: WipePhase = .idle
    var wipeStart = Date()
    var wipeOrigin = CGPoint(x: 720, y: 450)
    var titleTo: CockpitMode?
    var titleFrom: CockpitMode = .work
    var titleStart = Date()
    var titleOut: Date?

    // メニュー
    var menuOpen = false
    var menuClosing = false
    var menuSettled = false
    var menuStart = Date()
    var menuPath: [Int] = []
    var menuHi = 0
    var bladeStart = Date()
    /// 刃が伸び切ったか。伸びている間だけメニューの時計を回す
    var bladeSettled = true
    var bandStart: Date?
    var bandForward = true
    var menuNudge = CGSize.zero

    // モーダル
    var showTasks = false
    var fileModal: String?
    var agentModal: String?
    var sessionsOpen = false
    var newSessionOpen = false
    var keysOpen = false
    /// 確認が要る承認レベル（Lv.4 / Lv.5）。確かめてから書く
    var riskyLevel: Gate.Level?

    // 門
    var hc = 0
    var rewriting = false
    var revised = ""
    /// 答えを書けなかった門。**黙って消さない**（司令塔は待ったまま）
    var gateFailed: String?
    var crumble: Int?
    var cardNudge = CGSize.zero
    var verdicts: [VerdictLine] = []

    // 決定のドット
    var flights: [Flight] = []

    // 構造・壁打ち
    var structFilter = StructFilter.all
    var hovered: String?
    var editing: String?
    var memoryDirty = false
    var sendFailed = false

    /// 決定のドットの行き先を引くための矩形（根の座標）。描画に使わないので観測から外す——
    /// 外さないと、矩形が届くたびに画面全体が組み直る
    @ObservationIgnored var rects: [String: CGRect] = [:]
    @ObservationIgnored var rootSize = CGSize(width: 1440, height: 900)
    /// 右の青い面の墨流し（540×800 相当・96 格子）。
    /// ponytail: 最適化なしのビルドだと 96 格子で1歩 24ms（Linux 実測）かかり 30Hz で1コアの7割を食う。
    /// `swift run`（debug）の間だけ 48 格子に落とす。release は 1.5ms/歩
    @ObservationIgnored let tank = InkTank(res: Stage.inkRes, aspect: 800.0 / 540.0, ink: 0x1212EE, accent: 0xFF3DCC,
                                           bg: 0xFFFFFF, dropEvery: 7, spread: 0.08)
    #if DEBUG
    nonisolated static let inkRes = 48
    #else
    nonisolated static let inkRes = 96
    #endif
    /// メニューの背後に立つ鶴の形の墨流し
    @ObservationIgnored let craneTank = InkTank(res: Stage.inkRes + 16, aspect: 1, ink: 0x08085C, accent: 0xFF3DCC,
                                                bg: 0xFFFFFF, dropEvery: 7)

    // MARK: 門

    /// いま答える1件。**複数溜まっていても待たせている順に1件だけ**——
    /// 並べると「どれに答えているか」が曖昧になる
    var currentGate: Gate.Request? { cockpit.gates.min { $0.issued < $1.issued } }

    /// 門のボタン（0=Allow 1=Rewrite 2=Reject）。Rewrite はその場で書換欄を開く
    func choose(_ i: Int) {
        guard let gate = currentGate else { return }
        if i == 1 {
            hc = 1
            nudgeCard()
            if revised.isEmpty { revised = Cockpit.plainLine(gate.instruction) }
            after(0.11) { self.rewriting = true }
            return
        }
        hc = i
        crumble = i
        nudgeCard()
        answer(gate, i == 0 ? .allow : .deny, revised: "", from: "gate-btn-\(i)",
               ink: i == 2 ? Palette.Light.fg3 : Palette.blue)
    }

    func issueRewrite() {
        guard let gate = currentGate else { return }
        let text = revised.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        answer(gate, .revise, revised: text, from: "gate-btn-rw", ink: Palette.blue)
    }

    /// 書けたかどうかは必ず見る。書けなければ欄に残す（黙って消すと司令塔が待ち続ける）
    private func answer(_ gate: Gate.Request, _ verdict: Gate.Verdict, revised: String,
                        from key: String, ink: Color) {
        let from = rects[key]
        guard cockpit.answer(gate, verdict, revised: revised) == .saved else {
            gateFailed = gate.id
            crumble = nil
            return
        }
        gateFailed = nil
        rewriting = false
        self.revised = ""
        let word = switch verdict {
        case .allow: "ALLOWED"
        case .deny: "REJECTED"
        case .revise: "REWRITTEN"
        }
        verdicts.append(VerdictLine(at: Date(), gate: "G1", verdict: word))
        // 押したボタン → PLAN のいまの行 → ACTIONS の先頭へ渡る
        if let from, let plan = rects["plan-now"] {
            fly(from, plan, ink: ink)
            after(0.95) {
                if let plan = self.rects["plan-now"], let act = self.rects["act-0"] { self.fly(plan, act) }
            }
        }
        after(1.3) { self.crumble = nil; self.hc = 0 }
    }

    /// 門のカードを揺らす（sm-shake: 120ms・steps(2)）
    func nudgeCard() {
        cardNudge = CGSize(width: 3, height: 2)
        after(0.06) { self.cardNudge = CGSize(width: -2, height: 0) }
        after(0.12) { self.cardNudge = .zero }
    }

    func nudgeMenu() {
        menuNudge = CGSize(width: 3, height: 2)
        after(0.055) { self.menuNudge = CGSize(width: -2, height: 0) }
        after(0.11) { self.menuNudge = .zero }
    }

    // MARK: 決定のドット

    func fly(_ from: CGRect, _ to: CGRect, ink: Color = Palette.blue) {
        let flight = Flight(from: from, to: to, start: Date(), ink: ink)
        flights.append(flight)
        after(flight.duration + 0.3) { self.flights.removeAll { $0.id == flight.id } }
    }

    func fly(from: String, to: String) {
        if let a = rects[from], let b = rects[to] { fly(a, b) }
    }

    // MARK: 遷移

    /// タブを移る。DotWipe が覆い（380ms）→ 大見出しを掲げ（1100ms）→ 剥がれる（380ms）
    func go(_ to: CockpitMode, from point: CGPoint? = nil, viaMenu: Bool = false) {
        if wipe != .idle || (to == mode && !viaMenu) {
            if viaMenu { closeMenu() }
            return
        }
        // 壁打ちに未保存があると離れない（書きかけを黙って捨てない）
        if memoryDirty, mode == .memory, to != .memory {
            if viaMenu { closeMenu() }
            return
        }
        let cover = 0.38, hold = 1.1, reveal = 0.38
        wipeOrigin = point ?? CGPoint(x: rootSize.width / 2, y: rootSize.height / 2)
        wipeStart = Date()
        wipe = .cover
        titleFrom = mode
        titleTo = to
        titleStart = Date()
        titleOut = nil
        after(cover) {
            self.wipe = .hold
            self.wipeStart = Date()
            self.mode = to
            self.menuOpen = false
            self.menuClosing = false
            self.hovered = nil
        }
        after(cover + hold - 0.24) { self.titleOut = Date() }
        after(cover + hold) { self.wipe = .reveal; self.wipeStart = Date() }
        after(cover + hold + reveal) { self.wipe = .idle; self.titleTo = nil }
    }

    // MARK: メニュー

    func openMenu() {
        menuOpen = true
        menuClosing = false
        menuSettled = false
        menuStart = Date()
        menuPath = []
        menuHi = [CockpitMode.work, .structure, .memory].firstIndex(of: mode) ?? 0
        bladeStart = Date()
        bandStart = nil
        nudgeMenu()
        let opened = menuStart
        after(0.9) { if self.menuStart == opened, !self.menuClosing { self.menuSettled = true } }
    }

    func closeMenu() {
        guard menuOpen, !menuClosing else { return }
        menuClosing = true
        menuStart = Date()
        after(0.56) {
            if self.menuClosing { self.menuOpen = false; self.menuClosing = false }
        }
    }

    /// 下層へ／上層へ。白帯が横切る間（130ms）に中身を差し替える
    func menuShift(to path: [Int], hi: Int) {
        bandForward = path.count > menuPath.count
        let band = Date()
        bandStart = band
        after(0.13) {
            self.menuPath = path
            self.menuHi = hi
            self.restartBlade()
            self.nudgeMenu()
        }
        after(0.3) { if self.bandStart == band { self.bandStart = nil } }
    }

    func setHi(_ i: Int) {
        guard i != menuHi else { return }
        menuHi = i
        restartBlade()
    }

    private func restartBlade() {
        let start = Date()
        bladeStart = start
        bladeSettled = false
        after(0.2) { if self.bladeStart == start { self.bladeSettled = true } }
    }

    /// v10 の動きは全部「時間で区切って状態を進める」形。Task で寝てから戻る
    func after(_ seconds: Double, _ work: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            work()
        }
    }
}

/// 根の座標系の名前。決定のドットの出発点と行き先はここで測る
enum SumiSpace { static let root = "sumi-root" }

extension View {
    /// この部品の矩形を `stage.rects[key]` に記録する（決定のドット用）
    func sumiAnchor(_ stage: Stage, _ key: String) -> some View {
        background {
            GeometryReader { g in
                Color.clear
                    .onAppear { stage.rects[key] = g.frame(in: .named(SumiSpace.root)) }
                    .onChange(of: g.frame(in: .named(SumiSpace.root))) { _, f in stage.rects[key] = f }
            }
        }
    }
}

// MARK: - 根

/// 1440×900 の v10 を窓の大きさに合わせて組む根。
///
/// ```
/// ┌ 青帯 56 ──────────────────────────────────────────────┐
/// │ 白い五角形（右端が W-394 で尖る）│ 青＋墨流し            │
/// │  鶴 01 // TALK …               │ 04 // ACTIONS ×最大4 │
/// │                                │ 05 // PLAN 5行       │
/// └ 青帯 44 ──────────────────────────────────────────────┘
/// ```
/// 重なり順（v10 の z-index）: メニュー 30 → タスク 40 → 各モーダル 45 → // FILE 50 →
/// 決定のドット 60 → DotWipe 200 → 大見出し
struct CockpitView: View {
    let cockpit: Cockpit
    /// `--shot` の固定時刻。立っている間は時計も周回も回さない
    var shotTime: Date?

    @State private var stage: Stage
    @State private var occluded = false
    @FocusState private var rootFocused: Bool

    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    @AppStorage("cockpitMode") private var savedMode = CockpitMode.work
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""

    init(cockpit: Cockpit, shotTime: Date? = nil, mode: CockpitMode? = nil) {
        self.cockpit = cockpit
        self.shotTime = shotTime
        let stage = Stage(cockpit: cockpit)
        if let mode { stage.mode = mode }
        _stage = State(initialValue: stage)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Chassis(size: size, tank: stage.tank)
                TopBand(cockpit: cockpit, stage: stage, size: size)
                screen(size)
                CraneButton(cockpit: cockpit, stage: stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 40).padding(.bottom, 64)
                RightColumn(cockpit: cockpit, stage: stage, size: size)
                BottomBand(cockpit: cockpit, stage: stage, size: size)
                    .offset(y: size.height - 44)
                if stage.menuOpen {
                    SumiMenu(cockpit: cockpit, stage: stage, size: size)
                }
                Modals(cockpit: cockpit, stage: stage)
                FlightLayer(flights: stage.flights)
                DotWipeLayer(phase: stage.wipe, start: stage.wipeStart, origin: stage.wipeOrigin)
                if let to = stage.titleTo {
                    WipeTitle(to: to, from: stage.titleFrom, start: stage.titleStart, outStart: stage.titleOut)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .coordinateSpace(.named(SumiSpace.root))
            .onAppear { stage.rootSize = size }
            .onChange(of: size) { _, s in stage.rootSize = s }
        }
        .foregroundStyle(Palette.Light.fg)
        .environment(\.sumiFixedTime, shotTime)
        .environment(\.sumiPaused, occluded)
        // **`onKeyPress` はフォーカスを持つ View にしか来ない。** 焦点の輪は意匠に合わないので消す。
        // 入力欄に焦点がある間は文字がそちらへ吸われるので、ここへは落ちてこない
        .focusable()
        .focused($rootFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .background { shortcuts }
        .alert("この段は人間の承認なしにファイルを書き換える", isPresented: Binding(
            get: { stage.riskyLevel != nil }, set: { if !$0 { stage.riskyLevel = nil } }
        )) {
            Button("やめる", role: .cancel) { stage.riskyLevel = nil }
            Button("承知した", role: .destructive) {
                if let level = stage.riskyLevel { cockpit.setGateLevel(level) }
                stage.riskyLevel = nil
            }
        } message: {
            Text("\(stage.riskyLevel?.title ?? "") では、起こしたセッションが確認を求めずに編集します。")
        }
        .onChange(of: threshold, initial: true) { cockpit.flagReadThreshold = threshold }
        .onChange(of: stage.mode) { _, m in if shotTime == nil { savedMode = m } }
        // 連携設定を変えたら探し直す（codex 側の呼び出しを落とすと Codex 経路が丸ごと到達不能になる）
        .onChange(of: launcherEnabled) { findCLIs(force: true) }
        .onChange(of: claudePath) { findCLIs(force: true) }
        .onChange(of: codexPath) { findCLIs(force: true) }
        // 答えた門は消えるので、書換欄と失敗の印も畳む
        .onChange(of: cockpit.gates.map(\.id)) { _, ids in
            if let failed = stage.gateFailed, !ids.contains(failed) { stage.gateFailed = nil }
            if ids.isEmpty { stage.rewriting = false; stage.revised = "" }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
            occluded = !NSApp.windows.contains { $0.title == "AT22 Glass Cockpit" && $0.occlusionState.contains(.visible) }
        }
        .task {
            guard shotTime == nil else { return }
            stage.mode = savedMode
            rootFocused = true
            findCLIs(force: false)
            while !Task.isCancelled {
                cockpit.housekeeping()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task {
            // 2.6 秒ごとに ACTIONS の行の高さへ墨を落とす（書込=青、それ以外=ピンク）
            guard shotTime == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2600))
                if !occluded { drip() }
            }
        }
    }

    @ViewBuilder
    private func screen(_ size: CGSize) -> some View {
        let width = max(380, min(660, size.width - 780))
        switch stage.mode {
        case .work:
            Talk(cockpit: cockpit, stage: stage, width: width, height: size.height)
                .offset(x: 220, y: 72)
        case .structure:
            StructureScreen(cockpit: cockpit, stage: stage, width: width, height: size.height - 84 - 72)
                .offset(x: 220, y: 84)
        case .memory:
            SparringScreen(cockpit: cockpit, stage: stage, width: width, height: size.height - 84 - 72)
                .offset(x: 220, y: 84)
        }
    }

    /// 修飾キー付きの鍵。入力欄に焦点があっても効くように、見えないボタンに付ける
    private var shortcuts: some View {
        ZStack {
            Button("") { stage.showTasks.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            // ⇧⌘G で最古の門を許可（⌘Return は「送る」が持っている）
            Button("") { stage.choose(0) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(cockpit.gates.isEmpty)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    private func findCLIs(force: Bool) {
        cockpit.findClaudeIfNeeded(override: claudePath.isEmpty ? nil : claudePath, force: force)
        cockpit.findCodexIfNeeded(override: codexPath.isEmpty ? nil : codexPath, force: force)
    }

    // MARK: 鍵

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if stage.menuOpen { return menuKey(press) }
        let plain = press.modifiers.isEmpty
        if press.key == .escape {
            // 手前から順に畳む。一度に全部消すと「戻る」つもりで土台まで戻ってしまう
            if stage.fileModal != nil { stage.fileModal = nil; return .handled }
            if stage.agentModal != nil { stage.agentModal = nil; return .handled }
            if stage.newSessionOpen { stage.newSessionOpen = false; return .handled }
            if stage.sessionsOpen { stage.sessionsOpen = false; return .handled }
            if stage.keysOpen { stage.keysOpen = false; return .handled }
            if stage.showTasks { stage.showTasks = false; return .handled }
            if stage.rewriting { stage.rewriting = false; return .handled }
            return .ignored
        }
        let modal = stage.fileModal != nil || stage.agentModal != nil || stage.newSessionOpen
            || stage.sessionsOpen || stage.keysOpen || stage.showTasks
        guard plain, !modal else { return .ignored }
        let gateKeys = stage.currentGate != nil && !stage.rewriting && stage.mode == .work
        switch press.characters {
        case "m": stage.openMenu(); return .handled
        case "a": stage.go(.work); return .handled
        case "b": stage.go(.structure); return .handled
        case "c": stage.go(.memory); return .handled
        case "1", "2", "3":
            guard gateKeys else { return .ignored }
            stage.choose((Int(press.characters) ?? 1) - 1); return .handled
        default: break
        }
        guard gateKeys else { return .ignored }
        switch press.key {
        case .rightArrow: stage.hc = (stage.hc + 1) % 3; stage.nudgeCard(); return .handled
        case .leftArrow: stage.hc = (stage.hc + 2) % 3; stage.nudgeCard(); return .handled
        case .return: stage.choose(stage.hc); return .handled
        default: return .ignored
        }
    }

    private func menuKey(_ press: KeyPress) -> KeyPress.Result {
        let count = SumiMenu.level(cockpit: cockpit, stage: stage, path: stage.menuPath).count
        guard count > 0 else { stage.closeMenu(); return .handled }
        switch press.key {
        case .downArrow: stage.setHi((stage.menuHi + 1) % count)
        case .upArrow: stage.setHi((stage.menuHi + count - 1) % count)
        case .return, .rightArrow: SumiMenu.dive(cockpit: cockpit, stage: stage, index: stage.menuHi)
        case .leftArrow, .delete, .escape: SumiMenu.up(stage: stage)
        default:
            if press.characters == "m" { stage.closeMenu() } else { return .ignored }
        }
        return .handled
    }

    // MARK: 墨

    /// ACTIONS の各行の高さに、行ごと 420ms ずらして 10 滴ずつ落とす（v10 の `drip`）
    private func drip() {
        let st = stage          // self（View）を Task に持ち込まない
        let size = st.rootSize
        let snap = cockpit.snapshot(now: Date(), mode: .work)
        let rows = Cockpit.actionRows(chips: snap.chips, gates: snap.gates, now: Date()).rows
        let left = size.width - 540, top: CGFloat = 56, h = size.height - 100
        for (i, row) in rows.enumerated() {
            guard let r = stage.rects["act-\(i)"] else { continue }
            let y = r.midY
            let edge = left + (y < size.height / 2 ? (y - top) : (size.height - 44 - y)) * Palette.slant
            let x = Double(((edge + size.width - 376) / 2 - left) / 540)
            let yy = Double((y - top) / h)
            let delay = Double(i + 1) * 0.42
            for k in 0..<10 {
                st.after(delay + Double(k) * 0.09) {
                    st.tank.drop(x + .random(in: -0.005...0.005), yy + Double(k) * 0.0025,
                                    radius: 0.03 + Double(k) * 0.002, accent: row.accent,
                                    amount: Float(row.accent ? 0.8 : 0.7) * 0.09)
                }
            }
        }
    }
}

// MARK: - 地

/// 白い五角形と青い地、右の墨流し、縁の白線。v10 の `clip-path` をそのまま窓の大きさへ伸ばす
struct Chassis: View {
    let size: CGSize
    let tank: InkTank

    var body: some View {
        let W = size.width, H = size.height
        ZStack(alignment: .topLeading) {
            Palette.white
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addLines([CGPoint(x: 0, y: 56), CGPoint(x: W - 540, y: 56), CGPoint(x: W - 394, y: H / 2),
                            CGPoint(x: W - 540, y: H - 44), CGPoint(x: 0, y: H - 44)])
                p.closeSubpath()
            }
            .fill(Palette.blue, style: FillStyle(eoFill: true))
            Suminagashi(tank: tank)
                .frame(width: 540, height: H - 100)
                .clipShape(InkWindow())
                .offset(x: W - 540, y: 56)
            Path { p in
                p.addLines([CGPoint(x: 0, y: 56), CGPoint(x: W - 540, y: 56), CGPoint(x: W - 394, y: H / 2),
                            CGPoint(x: W - 540, y: H - 44), CGPoint(x: 0, y: H - 44)])
            }
            .stroke(Palette.white, lineWidth: 3)
            Path { p in
                p.addLines([CGPoint(x: W - 540, y: 56), CGPoint(x: W - 394, y: H / 2), CGPoint(x: W - 540, y: H - 44)])
            }
            .stroke(Palette.blue, lineWidth: 3)
        }
        .frame(width: W, height: H)
        .allowsHitTesting(true)
    }
}

/// 墨流しの窓。左辺が五角形の尖りに合わせて内へ折れる（`146px 394px`）
struct InkWindow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addLines([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
                    CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX + 146, y: r.midY)])
        p.closeSubpath()
        return p
    }
}
