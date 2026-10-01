import SwiftUI
import AppKit

// MARK: - メニュー

/// メニューの1項目。葉は `tab`（そこへ遷移）と `act`（その場の仕事）を持つ
struct MenuItem {
    let en: String
    let jp: String
    let desc: String
    var kids: [MenuItem]?
    var tab: CockpitMode?
    var act: (@MainActor @Sendable () -> Void)?
}

/// P5 風のメニュー。白い斜線（18°）が引かれる → 線から離れる順にドットが育って青い面になる →
/// 項目が線に沿って並ぶ。選択は白い板（右端が尖る）＋刃。下層は面の色が深くなり、白帯が横切る間に差し替える。
///
/// 葉は実データ: Work▸Agents = エージェント、Sparring▸Memory = 記憶DBのノート、
/// Sparring▸Sessions = 過去の回＋New session、Settings▸Approval = 承認レベル、Models = モデル
struct SumiMenu: View {
    let cockpit: Cockpit
    let stage: Stage
    let size: CGSize

    // MARK: 木

    static func tree(cockpit: Cockpit, stage: Stage) -> [MenuItem] {
        let snap = cockpit.snapshot(now: Date(), mode: .work)
        var worker = 0
        let agents: [MenuItem] = snap.chips.map { chip in
            let id: String
            if chip.depth == 0 { id = "C0" } else { worker += 1; id = "W\(worker)" }
            let state = chip.done ? "終了" : chip.busy ? "稼働中" : "待機"
            let key = chip.id
            return MenuItem(en: id, jp: chip.role, desc: "\(chip.model.isEmpty ? "—" : chip.model) · \(state)",
                            tab: nil, act: { stage.agentModal = key })
        }
        let tasks = cockpit.allTasks(session: cockpit.selectedSession)
        let work = MenuItem(en: "Work", jp: "作業", desc: "会話と門 · いま動いているもの", kids: [
            MenuItem(en: "Conversation", jp: "会話", desc: "司令塔とのやり取り", tab: .work),
            MenuItem(en: "Agents", jp: "エージェント", desc: "C0 と配下 · \(snap.chips.count) 体",
                     kids: agents.isEmpty ? nil : agents, tab: agents.isEmpty ? .work : nil),
            MenuItem(en: "Gates", jp: "門", desc: "止まっている指示 · \(cockpit.gates.count) 件", tab: .work,
                     act: { stage.hc = 0 }),
            MenuItem(en: "Tasks", jp: "タスク", desc: "計画 · \(tasks.count) 件 · ⇧⌘T", act: { stage.showTasks = true }),
            MenuItem(en: "Clear idle", jp: "非アクティブを消す", desc: "動いていないエージェントだけを畳む",
                     act: { cockpit.clearIdleAgents(now: .now) }),
            MenuItem(en: "Clear", jp: "クリア", desc: "実装の区切りで、終了済みとファイルの集計を落とす",
                     act: { cockpit.clear() }),
        ], tab: .work)

        func filter(_ f: StructFilter) -> @MainActor @Sendable () -> Void { { stage.structFilter = f } }
        let structure = MenuItem(en: "Structure", jp: "構造", desc: "ファイルの関係 · ホバーで浮かぶ", kids: [
            MenuItem(en: "Files", jp: "ファイル", desc: "種類で分ける", kids: [
                MenuItem(en: "All", jp: "全部", desc: "絞り込みを外す", tab: .structure, act: filter(.all)),
                MenuItem(en: "Sources", jp: "実装", desc: FileCategory.source.title, tab: .structure, act: filter(.category(.source))),
                MenuItem(en: "Docs", jp: "ノート", desc: FileCategory.note.title, tab: .structure, act: filter(.category(.note))),
                MenuItem(en: "Config", jp: "設定", desc: FileCategory.config.title, tab: .structure, act: filter(.category(.config))),
            ]),
            MenuItem(en: "Ties", jp: "依存", desc: "依存のあるファイルだけ", tab: .structure, act: filter(.ties)),
            MenuItem(en: "Hot spots", jp: "熱い所", desc: "書込量の上位 2%", tab: .structure, act: filter(.hot)),
        ], tab: .structure)

        let notes = cockpit.memory.filter { !$0.isIndex }
        let noteItems: [MenuItem] = notes.prefix(12).map { n in
            let path = n.id
            return MenuItem(en: n.name, jp: n.kind, desc: n.summary.isEmpty ? n.relative : n.summary,
                            tab: .memory, act: { if !stage.memoryDirty { stage.editing = path } })
        }
        var sessionItems: [MenuItem] = cockpit.liveSessions.prefix(6).map { s in
            let id = s.id
            return MenuItem(en: String(id.prefix(8)).uppercased(), jp: cockpit.title(for: id) ?? s.name,
                            desc: "LIVE · " + (s.cwd as NSString).lastPathComponent, tab: .work,
                            act: { cockpit.selectedSession = id })
        }
        let liveIDs = Set(cockpit.liveSessions.map(\.id))
        sessionItems += cockpit.recentSessions.filter { !liveIDs.contains($0.id) }.prefix(10).map { s in
            let session = s
            return MenuItem(en: String(s.id.prefix(8)).uppercased(), jp: cockpit.title(for: s.id) ?? s.project,
                            desc: s.project + " · " + s.modifiedAt.formatted(.dateTime.month().day().hour().minute()),
                            tab: .work, act: {
                                cockpit.selectedSession = session.id
                                Task { await cockpit.loadSession(session) }
                            })
        }
        sessionItems.append(MenuItem(en: "All sessions", jp: "全部", desc: "Codex を含む一覧", act: { stage.sessionsOpen = true }))
        sessionItems.append(MenuItem(en: "New session", jp: "新しい回", desc: "バックエンド・モデル・最初の指示",
                                     act: { stage.newSessionOpen = true }))
        let sparring = MenuItem(en: "Sparring", jp: "壁打ち", desc: "引き継ぎと記憶", kids: [
            MenuItem(en: "Handoff", jp: "引き継ぎ", desc: SparringScreen.defaultNote(notes)?.relative ?? "記憶DB は空",
                     tab: .memory, act: {
                         if !stage.memoryDirty, let n = SparringScreen.defaultNote(notes) { stage.editing = n.id }
                     }),
            MenuItem(en: "Memory", jp: "記憶", desc: "記憶DB · \(notes.count) 件",
                     kids: noteItems.isEmpty ? nil : noteItems, tab: noteItems.isEmpty ? .memory : nil),
            MenuItem(en: "Sessions", jp: "過去の回", desc: "\(cockpit.recentSessions.count) 回 · New session", kids: sessionItems),
        ], tab: .memory)

        let levels: [MenuItem] = Gate.Level.allCases.map { level in
            let parts = level.title.split(separator: " ", maxSplits: 1).map(String.init)
            return MenuItem(en: parts.first ?? level.title, jp: parts.count > 1 ? parts[1] : "",
                            desc: (level == cockpit.gateLevel ? "いま · " : "") + level.permissionMode
                                + (level.needsConfirmation ? " · 確認が要る" : ""),
                            act: {
                                if level.needsConfirmation { stage.riskyLevel = level } else { cockpit.setGateLevel(level) }
                            })
        }
        let session = cockpit.selectedSession
        let codex = session.map { cockpit.backend(of: $0) == .codex } ?? false
        let current = session.flatMap { cockpit.model(of: $0) } ?? ""
        let modelItems: [MenuItem] = (codex ? ModelChoice.codexModels : ModelChoice.claudeModels).map { choice in
            let id = choice.id
            return MenuItem(en: choice.title, jp: "", desc: (id == current ? "いま · " : "") + "次に繋いだ時から効く",
                            act: {
                                // 選び直しは繋ぎ直しになるので、走っている間は触らせない
                                if let session, !cockpit.isWorking(session) { cockpit.setModel(id, for: session) }
                            })
        }
        let settings = MenuItem(en: "Settings", jp: "設定", desc: "承認レベル · モデル · 鍵", kids: [
            MenuItem(en: "Approval", jp: "承認レベル", desc: cockpit.gateLevel.title, kids: levels),
            MenuItem(en: "Models", jp: "モデル", desc: current.isEmpty ? "このセッションのモデル" : current,
                     kids: session == nil ? nil : modelItems),
            MenuItem(en: "Thinking", jp: "思考", desc: "会話に thinking を出す／畳む", tab: .work, act: {
                let key = "showThinking"
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
            }),
            MenuItem(en: "Keys", jp: "鍵", desc: "ショートカット一覧", act: { stage.keysOpen = true }),
            // ponytail: 静的関数からは `openSettings` の環境値に届かないので、AppKit の口で開く
            MenuItem(en: "Preferences", jp: "環境設定", desc: "しきい値 · 連携 · ⌘,", act: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }),
        ])
        return [work, structure, sparring, settings]
    }

    static func level(cockpit: Cockpit, stage: Stage, path: [Int]) -> [MenuItem] {
        var items = tree(cockpit: cockpit, stage: stage)
        for i in path {
            guard i < items.count, let kids = items[i].kids else { return items }
            items = kids
        }
        return items
    }

    static func dive(cockpit: Cockpit, stage: Stage, index: Int) {
        let items = level(cockpit: cockpit, stage: stage, path: stage.menuPath)
        guard index < items.count else { return }
        let item = items[index]
        if let kids = item.kids, !kids.isEmpty {
            stage.menuShift(to: stage.menuPath + [index], hi: 0)
            return
        }
        stage.nudgeMenu()
        let act = item.act, tab = item.tab
        stage.after(0.11) {
            act?()
            if let tab { stage.go(tab, from: CGPoint(x: 500, y: 450), viaMenu: true) } else { stage.closeMenu() }
        }
    }

    static func up(stage: Stage) {
        guard let last = stage.menuPath.last else { stage.closeMenu(); return }
        stage.menuShift(to: Array(stage.menuPath.dropLast()), hi: last)
    }

    // MARK: 絵

    private static let tones: [Color] = [Palette.blue, Palette.OnBlue.fg2, Palette.OnBlue.fg3, Palette.OnBlue.deep]

    var body: some View {
        let items = Self.level(cockpit: cockpit, stage: stage, path: stage.menuPath)
        let depth = stage.menuPath.count
        ZStack(alignment: .topLeading) {
            MenuDots(start: stage.menuStart, closing: stage.menuClosing, settled: stage.menuSettled)
                .contentShape(Rectangle())
                .onTapGesture { stage.closeMenu() }
            if let band = stage.bandStart {
                SumiClock(fps: 60) { now in
                    let p = steps(now.timeIntervalSince(band) / 0.26, 8)
                    let x = stage.bandForward ? -300 + p * 2000 : 1700 - p * 2100
                    Plate(skew: -18).fill(Palette.white)
                        .frame(width: 220, height: size.height + 80)
                        .offset(x: x, y: -40)
                }
                .allowsHitTesting(false)
            }
            Palette.depth[min(2, depth)].opacity(depth > 0 ? 1 : 0)
                .allowsHitTesting(false)
            SumiClock(fps: 30, running: !stage.menuSettled || stage.menuClosing || !stage.bladeSettled) { now in
                let t = now.timeIntervalSince(stage.menuStart)
                let out = stage.menuClosing ? steps(t / 0.14, 3) : 0
                ZStack(alignment: .topLeading) {
                    if stage.menuClosing || t > 0.42 || stage.menuSettled {
                        Suminagashi(tank: stage.craneTank, hover: false)
                            .frame(width: 512, height: 512)
                            .mask { Mascot(pitch: 64, lookRight: false, color: .black, accent: .black) }
                            .offset(x: size.width - 512 + 40, y: size.height - 512 + 60)
                            .allowsHitTesting(false)
                    }
                    slash(t)
                    if t > 0.3 || stage.menuSettled || stage.menuClosing { crumbs.offset(x: 310, y: 24) }
                    list(items, depth: depth, t: t, now: now)
                        .offset(stage.menuNudge)
                    if t > 0.3 || stage.menuSettled || stage.menuClosing {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("[×] CLOSE · ESC").caps(10).foregroundStyle(Palette.white)
                            Mascot(pitch: 9, pose: "one", color: Palette.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 40).padding(.bottom, 64)
                        .allowsHitTesting(false)
                    }
                }
                .opacity(1 - out)
                .offset(x: 14 * out, y: 4 * out)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 白い斜線。開く時は 120ms で引かれ、閉じる時は 300ms 後に 130ms で抜ける
    private func slash(_ t: Double) -> some View {
        let from = stage.menuClosing ? steps((t - 0.3) / 0.13, 4) : 0
        let to = stage.menuClosing ? 1 : steps(t / 0.12, 4)
        return Path { p in
            p.move(to: CGPoint(x: 286, y: 0))
            p.addLine(to: CGPoint(x: 286 + size.height * Palette.slant, y: size.height))
        }
        .trim(from: from, to: to)
        .stroke(Palette.white, lineWidth: 3)
        .allowsHitTesting(false)
    }

    private var crumbs: some View {
        HStack(spacing: 0) {
            Button { stage.menuShift(to: [], hi: 0) } label: {
                Text("00 MENU").caps(10).foregroundStyle(Palette.blue)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Palette.white)
            }
            .buttonStyle(.plain)
            ForEach(Array(stage.menuPath.enumerated()), id: \.offset) { k, p in
                let names = Self.level(cockpit: cockpit, stage: stage, path: Array(stage.menuPath.prefix(k)))
                Rectangle().fill(Palette.white).frame(width: 28, height: 1)
                Button { stage.menuShift(to: Array(stage.menuPath.prefix(k + 1)), hi: 0) } label: {
                    Text(String(format: "%02d ", p + 1) + (p < names.count ? names[p].en.uppercased() : ""))
                        .caps(10).foregroundStyle(Palette.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(Rectangle().stroke(Palette.white, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if !stage.menuPath.isEmpty {
                Button { Self.up(stage: stage) } label: {
                    Text("◂ BACK · ←").caps(10).foregroundStyle(Palette.white).padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
            }
        }
    }

    /// 項目を斜線に沿って並べる。選択から離れるほど小さく・淡く
    private func list(_ items: [MenuItem], depth: Int, t: Double, now: Date) -> some View {
        let hi = min(stage.menuHi, max(0, items.count - 1))
        let fonts: [CGFloat] = items.indices.map { i in
            let d = abs(i - hi)
            return d == 0 ? (depth > 0 ? 96 : 112) : d == 1 ? 44 : 34
        }
        let heights: [CGFloat] = items.indices.map { i in abs(i - hi) == 0 ? fonts[i] * 1.12 + 40 : fonts[i] * 1.32 }
        let total = heights.reduce(0, +) + 12
        var ys: [CGFloat] = []
        var y = size.height / 2 - total / 2
        for h in heights { ys.append(y); y += h + 6 }
        let fresh = stage.menuPath.isEmpty && stage.bandStart == nil && !stage.menuSettled && !stage.menuClosing
        let prefix = stage.menuPath.map { "\($0 + 1)-" }.joined()
        return ZStack(alignment: .topLeading) {
            ForEach(items.indices, id: \.self) { i in
                let d = abs(i - hi), on = d == 0
                let p = fresh ? steps((t - 0.38 - Double(i) * 0.045) / 0.15, 3) : 1
                item(items[i], number: prefix + String(format: "%02d", i + 1), size: fonts[i], d: d, on: on, now: now)
                    .onTapGesture {
                        stage.setHi(i)
                        Self.dive(cockpit: cockpit, stage: stage, index: i)
                    }
                    .onHover { if $0 { stage.setHi(i) } }
                    .opacity(p)
                    .offset(x: 310 + ys[i] * Palette.slant - 12 * (1 - p), y: ys[i] - 4 * (1 - p))
            }
        }
    }

    private func item(_ m: MenuItem, number: String, size f: CGFloat, d: Int, on: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(number).caps(11).foregroundStyle(on ? Palette.Light.fg2 : Self.tones[min(d, 3)])
                Text(m.en).font(Palette.display(f)).foregroundStyle(on ? Palette.blue : Self.tones[min(d, 3)])
                    .lineLimit(1).fixedSize()
                Text(m.jp).font(Palette.brush(14)).foregroundStyle(on ? Palette.blue : Self.tones[min(d + 1, 3)])
                    .lineLimit(1).fixedSize()
            }
            .padding(.leading, on ? 20 : 8).padding(.trailing, on ? 44 : 8)
            .padding(.top, on ? 4 : 0).padding(.bottom, on ? 2 : 0)
            if on {
                HStack(spacing: 14) {
                    Text(m.desc + ((m.kids?.isEmpty == false) ? "  ▸ \(m.kids!.count)" : ""))
                        .font(Palette.bodyJP(13)).foregroundStyle(Palette.Light.fg2).lineLimit(1).fixedSize()
                    Text("→ 開く · ← 戻る · M 閉じる").caps(9).foregroundStyle(Palette.Light.fg3).fixedSize()
                }
                .padding(.leading, 20).padding(.trailing, 44).padding(.top, 2).padding(.bottom, 10)
            }
        }
        .background { if on { Plate(tip: 22, skew: 18, anchor: 1).fill(Palette.white) } }
        .overlay(alignment: .trailing) {
            if on {
                Rectangle().fill(Palette.white).frame(width: 150, height: 4)
                    .scaleEffect(x: steps(now.timeIntervalSince(stage.bladeStart) / 0.17, 4), y: 1, anchor: .leading)
                    .offset(x: 156)
            }
        }
        .contentShape(Rectangle())
    }
}
