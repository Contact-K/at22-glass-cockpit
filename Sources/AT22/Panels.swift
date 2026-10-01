import SwiftUI
import AppKit

// MARK: - 上の青帯

/// 56pt の青帯。`AT22_ GLASS COCKPIT ✳ ▮▮▮ SESSION/SPEND …… [GATE 門 Wake?] 日付 ＋`。
/// 左端 78pt は信号機に空ける（OS が同じ位置に描く）
struct TopBand: View {
    let cockpit: Cockpit
    let stage: Stage
    let size: CGSize

    static let trafficLightInset: CGFloat = 78

    var body: some View {
        HStack(spacing: 16) {
            Text("AT22_").font(Palette.mono(20))
            Text("GLASS COCKPIT").caps(11, tracking: 0.24)
            RegMark(kind: "star", size: 12)
            HStack(spacing: 10) {
                Barcode(value: "AT22-" + sessionID)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SESSION \(sessionID)")
                    Text("SPEND \(Snowman.short(Int(cockpit.spendTotal(session: cockpit.selectedSession)))) · \(modeNow(stage.mode))")
                        .foregroundStyle(Palette.OnBlue.fg3)
                }
                .caps(9)
            }
            Spacer(minLength: 0)
            if let gate = stage.currentGate { gateChip(gate) } else { idleChip }
            SumiClock(fps: 1) { now in
                VStack(alignment: .trailing, spacing: 3) {
                    Text(now.formatted(.iso8601.year().month().day()))
                    Text(now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + " "
                         + (TimeZone.current.abbreviation() ?? ""))
                        .foregroundStyle(Palette.OnBlue.fg3)
                }
                .caps(9)
            }
            .padding(.leading, 8)
            RegMark(kind: "cross", size: 12)
        }
        .foregroundStyle(Palette.white)
        .padding(.leading, Self.trafficLightInset)
        .padding(.trailing, 24)
        .frame(width: size.width, height: 56)
    }

    private var sessionID: String {
        cockpit.selectedSession.map { String($0.prefix(8)).uppercased() } ?? "--------"
    }

    private func gateChip(_ gate: Gate.Request) -> some View {
        Button {
            stage.go(.work)
            stage.hc = 0
        } label: {
            HStack(spacing: 12) {
                Starburst(size: 20, color: Palette.pink, spin: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GATE 門 · \(cockpit.gates.count) 件止まっています").caps(9, tracking: 0.16)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Wake G1?").font(Palette.display(20))
                        SumiClock(fps: 1) { now in
                            Text("\(Int(gate.waited(now: now)))s").caps(10, tracking: 0.08)
                        }
                    }
                }
                Text("応答する ↵").caps(10)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.Light.line).frame(width: 1) }
            }
            .foregroundStyle(Palette.Light.fg)
            .padding(.leading, 16).padding(.trailing, 34)
            .frame(height: 40)
            .background(Plate(tip: 18, notch: 10).fill(Palette.white))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressNudge())
        .help("門へ（⇧⌘G で許可）")
    }

    private var idleChip: some View {
        HStack(spacing: 10) {
            RegMark(kind: "target", size: 12, color: Palette.OnBlue.fg2)
            Text("GATE 00 · 止まっている指示なし")
        }
        .caps(10)
        .foregroundStyle(Palette.OnBlue.fg2)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .overlay(Rectangle().stroke(Palette.OnBlue.fg3, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// `01 WORK 作業` の形
func modeNow(_ mode: CockpitMode) -> String {
    let w = WipeTitle.words(mode)
    return "\(w.no) \(w.en) \(w.jp)"
}

// MARK: - 鶴（メニュー）

/// 左下の鶴。押すとメニュー。処理中は四角に畳まれて InkLoader になる
struct CraneButton: View {
    let cockpit: Cockpit
    let stage: Stage

    var body: some View {
        let working = cockpit.isWorking(cockpit.selectedSession)
        let gate = stage.currentGate != nil
        let alarm = cockpit.reading.stage == .warning
        let busy: String? = working ? (cockpit.streaming.isEmpty ? "think" : "reply")
            : gate ? "wait" : alarm ? "overload" : nil
        Button { stage.openMenu() } label: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(working ? (cockpit.streaming.isEmpty ? "考えています" : "返します")
                         : gate ? "門の応答を待っています" : "C0 司令塔")
                        .font(Palette.bodyJP(13))
                    Text(working ? (cockpit.streaming.isEmpty ? "THINK" : "REPLY") : gate ? "ASKING · MENU" : "MENU")
                        .caps(10)
                    Text("\(modeNow(stage.mode)) · M").caps(10, tracking: 0.1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                }
                Mascot(pitch: 9, pose: gate && !working ? "one" : "idle", busy: busy)
                    .sumiAnchor(stage, "crane")
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.Light.fg)
        .help("メニュー (M)")
    }
}

// MARK: - 右の列

/// 04 // ACTIONS と 05 // PLAN。窓が低い時は2枚の間を詰めて、重ならせない
struct RightColumn: View {
    let cockpit: Cockpit
    let stage: Stage
    let size: CGSize

    var body: some View {
        let snap = cockpit.snapshot(now: Date(), mode: .work)
        let picked = Cockpit.actionRows(chips: snap.chips, gates: snap.gates, now: Date())
        let rows = picked.rows, done = picked.done
        let busyFiles = Set(rows.compactMap(\.path))
        let quiet = snap.cards.flatMap(\.files).filter { !busyFiles.contains($0.id) && $0.state == .idle }.count
        let tasks = cockpit.allTasks(session: cockpit.selectedSession)
        let bottomGap = max(12, min(118, size.height - 782))
        VStack(spacing: 0) {
            ActionsPanel(cockpit: cockpit, stage: stage, rows: rows, done: done, quiet: quiet,
                         root: snap.chips.first { $0.depth == 0 })
            Spacer(minLength: 12)
            PlanPanel(stage: stage, tasks: tasks)
        }
        .frame(width: 352)
        .padding(.top, 76)
        .padding(.bottom, 44 + bottomGap)
        .frame(height: size.height, alignment: .top)
        .offset(x: size.width - 376)
        .foregroundStyle(Palette.Light.fg)
    }
}

/// 04 // ACTIONS。誰が・何を・どこに。行を押すと // FILE（ファイルの無い行はエージェント）
struct ActionsPanel: View {
    let cockpit: Cockpit
    let stage: Stage
    let rows: [ActionRow]
    let done: [String]
    let quiet: Int
    let root: AgentChip?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(no: "04", en: "ACTIONS", jp: "誰が・何を・どこに")
                HStack(spacing: 10) {
                    Text("C0").font(Palette.mono(22))
                    Text(root?.role ?? Cockpit.rootRole).font(Palette.bodyJP(13))
                    Text(root?.model ?? "—").font(Palette.mono(10)).foregroundStyle(Palette.Light.fg2)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(Gate.Level.allCases, id: \.self) { level in
                            Button(level.title) {
                                if level.needsConfirmation { stage.riskyLevel = level } else { cockpit.setGateLevel(level) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(levelNo).caps(10, tracking: 0.08)
                            Text(levelName).font(Palette.bodyJP(11))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("承認レベルを変える（Lv.4/5 は確認が要る）")
                }
                ctx
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }

            if rows.isEmpty {
                Text(cockpit.selectedSession == nil ? "会話を選ぶと、ここに動きが並びます" : "いま動いている者はいません")
                    .font(Palette.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
            ForEach(Array(rows.enumerated()), id: \.element.key) { i, row in
                ActionLine(row: row) { open(row) }
                    .sumiAnchor(stage, "act-\(i)")
            }
            HStack(spacing: 12) {
                Text(done.isEmpty ? "+0 DONE" : "+\(done.count) DONE · \(done.prefix(4).joined(separator: " "))")
                Spacer(minLength: 0)
                Text("QUIET \(quiet) FILES")
            }
            .caps(10, tracking: 0.08)
            .foregroundStyle(Palette.Light.fg2)
            .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 9)
        }
        .background(Palette.white)
        .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
    }

    private var levelNo: String { String(cockpit.gateLevel.title.prefix { $0 != " " }).uppercased() }
    private var levelName: String { String(cockpit.gateLevel.title.drop { $0 != " " }.dropFirst()) }

    /// CTX の 20 升。85% を超えたら危険の色と overload のローダー
    private var ctx: some View {
        let reading = cockpit.reading
        let pct = Int((reading.growth * 100).rounded())
        let alarm = reading.stage == .warning
        let filled = Int((reading.growth * 20).rounded())
        return HStack(spacing: 8) {
            if alarm { InkLoader(status: "overload", pitch: 1.6, color: Palette.danger) }
            Text("CTX").caps(10, tracking: 0.1).foregroundStyle(Palette.Light.fg2)
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    Rectangle().fill(i < filled ? (alarm ? Palette.danger : Palette.blue) : Palette.Light.empty)
                        .frame(height: 8)
                }
            }
            Text("\(pct)%").font(Palette.display(20)).foregroundStyle(alarm ? Palette.danger : Palette.Light.fg2)
        }
        .help(reading.caption + (reading.stage.advice.isEmpty ? "" : " — " + reading.stage.advice))
    }

    private func open(_ row: ActionRow) {
        if let path = row.path { stage.fileModal = path }
        else if row.wait { stage.go(.work); stage.hc = 0 }
        else { stage.agentModal = row.key }
    }
}

/// ACTIONS の1行: `├ W5 ◼ WRITE 書込中 … +42 −7` / `→ CockpitCanvas.swift`
struct ActionLine: View {
    let row: ActionRow
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Text(row.branch).font(Palette.mono(12)).foregroundStyle(Palette.Light.fg3).frame(width: 16)
                Text(row.id).font(Palette.mono(18)).frame(width: 34, alignment: .leading)
                Group {
                    if row.wait {
                        Blink(period: 1.2) { Rectangle().fill(Palette.pink).frame(width: 16, height: 16) }
                            .padding(3)
                    } else {
                        InkLoader(status: row.loader, pitch: 2)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.verb).caps(10)
                        Text(row.jp).font(Palette.bodyJP(12))
                        Spacer(minLength: 0)
                        Text(row.note).font(Palette.mono(10)).foregroundStyle(Palette.Light.fg2)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("→").font(Palette.mono(12)).foregroundStyle(Palette.Light.fg3)
                        Text(row.file).font(Palette.mono(14)).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .padding(.leading, 10).padding(.trailing, 14).padding(.top, 6).padding(.bottom, 7)
            .background(hover ? Palette.Light.hover : Palette.white)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.Light.fg)
        .onHover { hover = $0 }
    }
}

/// 05 // PLAN。いまの1件を先頭に5行。読み取り専用（TaskUpdate が更新する）
struct PlanPanel: View {
    let stage: Stage
    let tasks: [RoadmapTask]

    var body: some View {
        let window = Cockpit.planWindow(tasks: tasks)
        let now = tasks.first { $0.status == .inProgress } ?? tasks.first { $0.status == .pending }
        let firstPending = tasks.first { $0.status == .pending }?.id
        let doneCount = tasks.filter { $0.status == .completed }.count
        Button { stage.showTasks = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionLabel(no: "05", en: "PLAN", jp: "計画")
                    Spacer(minLength: 0)
                    Text(now.map { "\($0.number)" } ?? "—").font(Palette.display(28))
                    Text("/ \(tasks.count)").font(Palette.mono(11))
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
                if window.isEmpty {
                    Text("計画はまだありません").font(Palette.bodyJP(13)).foregroundStyle(Palette.Light.fg3)
                        .frame(height: 34).padding(.horizontal, 14)
                }
                ForEach(window) { task in
                    let line = planLine(task, pendingHead: task.id == firstPending)
                    if task.id == now?.id { line.sumiAnchor(stage, "plan-now") } else { line }
                }
                Text(doneCount > 0 ? "#\(tasks.filter { $0.status == .completed }.map(\.number).min() ?? 1)–\(doneCount) DONE · 読み取り専用（TaskUpdate が更新）"
                                   : "読み取り専用（TaskUpdate が更新）")
                    .caps(10, tracking: 0.08).foregroundStyle(Palette.Light.fg2)
                    .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 9)
            }
            .background(Palette.white)
            .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.Light.fg)
        .help("全部のタスク（⇧⌘T）")
    }

    private func planLine(_ task: RoadmapTask, pendingHead: Bool) -> some View {
        let on = task.status == .inProgress, off = task.status == .completed
        let tag = on ? "NOW" : off ? "✓" : pendingHead ? "NEXT" : "—"
        return HStack(spacing: 10) {
            Text("#\(task.number)").font(Palette.mono(12)).frame(width: 30, alignment: .leading)
            Text(on && !task.activeForm.isEmpty ? task.activeForm : task.subject)
                .font(Palette.bodyJP(13)).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if off { InkLoader(status: "done", pitch: 1.4) }
                Text(tag).caps(10, tracking: 0.08)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .foregroundStyle(on ? Palette.white : off ? Palette.Light.fg3 : Palette.Light.fg)
        .background(on ? Palette.blue : Palette.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
    }
}

// MARK: - 下の青帯

/// 44pt の青帯。`05 // PLAN [01][02]…[21] 目盛 ─ 波線 W5 · 書込中  V0.10 · Σ`。押すとタスク一覧
struct BottomBand: View {
    let cockpit: Cockpit
    let stage: Stage
    let size: CGSize

    var body: some View {
        let tasks = cockpit.allTasks(session: cockpit.selectedSession)
        let stripWidth = max(200, min(882, size.width - 24 * 2 - 118 - 16 * 2 - 220))
        let fit = max(1, Int((stripWidth + 4) / 42))
        let shown = tasks.count > fit ? Cockpit.planWindow(tasks: tasks, size: fit) : tasks
        let now = tasks.first { $0.status == .inProgress }
        let doneShown = shown.prefix { $0.status == .completed }.count
        let working = cockpit.isWorking(cockpit.selectedSession)
        let snap = cockpit.snapshot(now: Date(), mode: .work)
        let top = Cockpit.actionRows(chips: snap.chips, gates: snap.gates, now: Date()).rows.first
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) { Text("05").foregroundStyle(Palette.pink); Text(" // PLAN") }.caps(10)
                Text("\(now.map { "\($0.number)" } ?? "—") / \(tasks.count) · ⇧⌘T")
                    .caps(9, tracking: 0.1).foregroundStyle(Palette.OnBlue.fg3)
            }
            .frame(width: 118, alignment: .leading)
            Button { stage.showTasks.toggle() } label: {
                ZStack(alignment: .topLeading) {
                    Ruler(length: stripWidth).offset(y: 35)
                    HStack(spacing: 4) { ForEach(shown) { tick($0) } }.offset(y: 6)
                    Rectangle().fill(Palette.white)
                        .frame(width: max(0, CGFloat(doneShown) * 42 - 4), height: 1).offset(y: -1)
                }
                .frame(width: stripWidth, height: 44, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                WaveLines(animate: working || cockpit.isBusy)
                VStack(alignment: .leading, spacing: 3) {
                    Text(working ? "C0 · " + (cockpit.streaming.isEmpty ? "考えています" : "返します")
                         : top.map { "\($0.id) · \($0.jp) \($0.note)" } ?? "QUIET · 静か")
                    Text("V0.10 · Σ").foregroundStyle(Palette.OnBlue.fg3)
                }
                .caps(9, tracking: 0.12)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .foregroundStyle(Palette.white)
        .padding(.horizontal, 24)
        .frame(width: size.width, height: 44)
    }

    private func tick(_ task: RoadmapTask) -> some View {
        let act = task.status == .inProgress, done = task.status == .completed
        return Text(String(format: "%02d", task.number))
            .font(Palette.mono(10)).tracking(0.4)
            .foregroundStyle(act ? Palette.blue : done ? Palette.OnBlue.fg2 : Palette.white)
            .frame(width: 38, height: 26)
            .background {
                if act { Plate(skew: -18).fill(Palette.white) }
                else if done { Rectangle().fill(Palette.white.opacity(0.18)) }
                else { Rectangle().stroke(Palette.OnBlue.deep, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
            }
            .help("#\(task.number) \(task.subject)")
    }
}

// MARK: - モーダル

/// モーダルを重なり順に置く。幕を押すと閉じる
struct Modals: View {
    let cockpit: Cockpit
    let stage: Stage

    var body: some View {
        ZStack {
            if stage.showTasks {
                veil { stage.showTasks = false } content: { TasksModal(cockpit: cockpit, stage: stage) }
            }
            if stage.sessionsOpen {
                veil { stage.sessionsOpen = false } content: { SessionsModal(cockpit: cockpit, stage: stage) }
            }
            if stage.newSessionOpen {
                veil { stage.newSessionOpen = false } content: { NewSessionModal(cockpit: cockpit, stage: stage) }
            }
            if stage.keysOpen {
                veil { stage.keysOpen = false } content: { KeysModal(stage: stage) }
            }
            if let id = stage.agentModal, let chip = cockpit.snapshot(now: Date(), mode: .work).chips.first(where: { $0.id == id }) {
                veil { stage.agentModal = nil } content: { AgentModal(cockpit: cockpit, stage: stage, agent: chip) }
            }
            if let path = stage.fileModal {
                veil { stage.fileModal = nil } content: { FileModal(cockpit: cockpit, stage: stage, path: path) }
            }
        }
    }

    private func veil<C: View>(_ close: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        ZStack {
            Palette.veil.contentShape(Rectangle()).onTapGesture(perform: close)
            content()
                .background(Palette.white)
                .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                .foregroundStyle(Palette.Light.fg)
                .onTapGesture {}
        }
    }
}

/// モーダルの頭: `06 // Tasks 読み取り専用 ……… [×]`
struct ModalHead: View {
    let no: String
    let title: String
    let jp: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if !no.isEmpty { Text("\(no) //").font(Palette.mono(11)).foregroundStyle(Palette.pink) }
            Text(title).font(Palette.display(36))
            Text(jp).font(Palette.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
            Spacer(minLength: 0)
            CloseKey(action: close)
        }
    }
}

/// `[×]`。ホバーで反転する
struct CloseKey: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text("[×]").font(Palette.mono(11))
                .foregroundStyle(hover ? Palette.white : Palette.Light.fg)
                .background(hover ? Palette.Light.fg : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 06 // Tasks。**1件も畳まない**——畳むと完了ぶんを見返せなくなる
struct TasksModal: View {
    let cockpit: Cockpit
    let stage: Stage

    var body: some View {
        let tasks = cockpit.allTasks(session: cockpit.selectedSession)
        VStack(alignment: .leading, spacing: 14) {
            ModalHead(no: "06", title: "Tasks", jp: "読み取り専用") { stage.showTasks = false }
            ScrollView {
                VStack(spacing: 0) {
                    if tasks.isEmpty {
                        Text("このセッションに計画はまだありません").font(Palette.bodyJP(14)).foregroundStyle(Palette.Light.fg3)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
                    }
                    ForEach(tasks) { t in
                        HStack(spacing: 12) {
                            Text("\(t.number)").font(Palette.mono(12)).foregroundStyle(Palette.Light.fg2).frame(width: 24, alignment: .leading)
                            Text(t.subject).font(Palette.bodyJP(14))
                                .foregroundStyle(t.status == .completed ? Palette.Light.fg3 : Palette.Light.fg)
                                .strikethrough(t.status == .completed)
                                .help(t.detail)
                            Spacer(minLength: 0)
                            Text(t.status == .completed ? "✓" : t.status == .inProgress ? "▸" : "").font(Palette.mono(12))
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
            }
            .frame(maxHeight: 560)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 520)
    }
}

/// // FILE。書き込みの内訳・読んだ相手・依存。数字はここでしか読めない
struct FileModal: View {
    let cockpit: Cockpit
    let stage: Stage
    let path: String

    var body: some View {
        let note = cockpit.structure.notes[path]
        let entries = cockpit.writeHistory(of: path)
        let reads = cockpit.readCounts(of: path)
        let usedBy = cockpit.structure.usedBy[path] ?? []
        let dependsOn = cockpit.structure.dependsOn[path] ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("// FILE").caps(11).foregroundStyle(Palette.Light.fg2)
                Text(FileCategory.classify(path: path).mark).font(Palette.mono(9)).foregroundStyle(Palette.Light.fg2)
                Spacer()
                CloseKey { stage.fileModal = nil }
            }
            Text((path as NSString).lastPathComponent).font(Palette.mono(24)).padding(.top, 8).textSelection(.enabled)
            Text(note?.memo.isEmpty == false ? note!.memo : "このファイルが宣言している型に落として表示します（説明コメントなし）。")
                .font(Palette.bodyJP(14)).lineSpacing(14 * 0.75)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            HStack(spacing: 0) {
                stat("DECLARED", "\(note?.declared.count ?? 0)")
                stat("USED BY", "\(usedBy.count)")
                stat("LAST EDIT", entries.first.map { "+\($0.added) −\($0.removed)" } ?? "—")
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("WRITES 書き込み履歴") {
                        if entries.isEmpty {
                            Text("書き込みなし（読み取りだけ）").font(Palette.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
                        }
                        ForEach(entries.prefix(12)) { e in
                            HStack {
                                Text(e.role).font(Palette.bodyJP(12))
                                Spacer()
                                Text(e.at.formatted(.dateTime.hour().minute().second())).font(Palette.mono(10)).foregroundStyle(Palette.Light.fg3)
                                Text("+\(e.added) −\(e.removed)").font(Palette.mono(11))
                            }
                        }
                    }
                    if !reads.isEmpty {
                        section("READ BY 読んだ相手") {
                            Text(reads.map { "\($0.role) ×\($0.count)" }.joined(separator: " ／ "))
                                .font(Palette.bodyJP(12)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !usedBy.isEmpty { related("USED BY ここを直すと響く先", usedBy) }
                    if !dependsOn.isEmpty { related("DEPENDS ON 使っている", dependsOn) }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 460)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).caps(9).foregroundStyle(Palette.Light.fg3)
            Text(value).font(Palette.display(22))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).caps(9).foregroundStyle(Palette.Light.fg2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 依存の一覧。押すとそのファイルへ移る
    private func related(_ title: String, _ paths: Set<String>) -> some View {
        section(title) {
            ForEach(paths.sorted().prefix(8), id: \.self) { p in
                Button { stage.fileModal = p } label: {
                    Text((p as NSString).lastPathComponent).font(Palette.mono(12)).underline()
                }
                .buttonStyle(.plain)
            }
            if paths.count > 8 { Text("ほか \(paths.count - 8) 件").font(Palette.bodyJP(11)).foregroundStyle(Palette.Light.fg3) }
        }
    }
}

/// エージェントの省略前の指示と作業先
struct AgentModal: View {
    let cockpit: Cockpit
    let stage: Stage
    let agent: AgentChip

    var body: some View {
        let files = cockpit.touchedFiles(by: agent.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("// AGENT").caps(11).foregroundStyle(Palette.Light.fg2)
                Spacer()
                CloseKey { stage.agentModal = nil }
            }
            Text(agent.role).font(Palette.display(32))
            Text("\(agent.model.isEmpty ? "—" : agent.model) · \(agent.work) CALLS · \(agent.done ? "DONE" : agent.busy ? "BUSY" : "IDLE")"
                 + (agent.share > 0 ? " · \(Int((agent.share * 100).rounded()))% (\(Snowman.short(Int(agent.spent))))" : ""))
                .caps(10).foregroundStyle(Palette.Light.fg2)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("INSTRUCTION 受けた指示").caps(9).foregroundStyle(Palette.Light.fg2)
                    Text(Talk.formatted(agent.instruction)).font(Palette.bodyJP(13)).lineSpacing(3)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if !agent.counts.isEmpty {
                        Text("WORK 作業の内訳").caps(9).foregroundStyle(Palette.Light.fg2)
                        Text(agent.counts.map { "\($0.kind.rawValue) \($0.count)" }.joined(separator: " · "))
                            .font(Palette.bodyJP(12))
                    }
                    Text("FILES 触ったファイル \(files.count)").caps(9).foregroundStyle(Palette.Light.fg2)
                    ForEach(files.prefix(20), id: \.path) { f in
                        Button { stage.agentModal = nil; stage.fileModal = f.path } label: {
                            HStack {
                                Text((f.path as NSString).lastPathComponent).font(Palette.mono(12))
                                Spacer()
                                Text("R\(f.reads) W\(f.writes)").font(Palette.mono(10)).foregroundStyle(Palette.Light.fg3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 460)
    }
}

/// 過去の回。動いているもの → 履歴（プロジェクト別）→ Codex の順
struct SessionsModal: View {
    let cockpit: Cockpit
    let stage: Stage

    var body: some View {
        let liveCodex = Set(cockpit.liveSessions.filter { cockpit.backend(of: $0.id) == .codex }.map(\.id))
        let codex = cockpit.codexRecords.filter { !liveCodex.contains($0.id) }.sorted { $0.lastUsed > $1.lastUsed }
        VStack(alignment: .leading, spacing: 14) {
            ModalHead(no: "07", title: "Sessions", jp: "過去の回") { stage.sessionsOpen = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !cockpit.liveSessions.isEmpty { group("LIVE 実行中") }
                    ForEach(cockpit.liveSessions) { s in
                        SessionRow(title: cockpit.title(for: s.id) ?? s.name, sub: (s.cwd as NSString).lastPathComponent,
                                   live: s.busy, selected: cockpit.selectedSession == s.id) {
                            cockpit.selectedSession = s.id
                            stage.sessionsOpen = false
                        }
                    }
                    if !cockpit.recentSessions.isEmpty { group("HISTORY 履歴") }
                    ForEach(cockpit.recentSessions) { s in
                        SessionRow(title: cockpit.title(for: s.id) ?? s.project,
                                   sub: s.project + " · " + s.modifiedAt.formatted(.dateTime.month().day().hour().minute()),
                                   live: false, selected: cockpit.selectedSession == s.id) {
                            stage.sessionsOpen = false
                            Task {
                                cockpit.selectedSession = s.id
                                await cockpit.loadSession(s)
                            }
                        }
                    }
                    if !codex.isEmpty { group("CODEX") }
                    ForEach(codex) { r in
                        SessionRow(title: cockpit.title(for: r.id) ?? String(r.id.prefix(8)),
                                   sub: (r.cwd as NSString).lastPathComponent, live: false,
                                   selected: cockpit.selectedSession == r.id) {
                            cockpit.selectedSession = r.id
                            cockpit.resumeCodexRecord(r)
                            stage.sessionsOpen = false
                        }
                    }
                    if cockpit.liveSessions.isEmpty && cockpit.recentSessions.isEmpty && codex.isEmpty {
                        Text("履歴はまだありません").font(Palette.bodyJP(14)).foregroundStyle(Palette.Light.fg3)
                    }
                }
            }
            .frame(maxHeight: 480)
            HStack {
                Spacer()
                SumiButton(title: "New session 新しい回") { stage.sessionsOpen = false; stage.newSessionOpen = true }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 560)
    }

    private func group(_ title: String) -> some View {
        Text(title).caps(9).foregroundStyle(Palette.Light.fg2).padding(.top, 10).padding(.bottom, 4)
    }
}

/// 新しい回を起こす。中身は旧サイドバーの「＋新規」と同じ（バックエンド・モデル・実行モード・場所・最初の指示）
struct NewSessionModal: View {
    let cockpit: Cockpit
    let stage: Stage

    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @AppStorage("launchBackend") private var launchBackend: String = Backend.claude.rawValue
    @AppStorage("launchModel") private var launchModel = ""
    @Environment(\.openSettings) private var openSettings
    @State private var prompt = ""
    @State private var directory = ""
    @State private var customModel = ""
    @State private var level = Gate.defaultLevel
    @State private var failed = false
    @State private var launching = false
    @State private var picking = false
    @State private var risky: Gate.Level?

    static let custom = "__custom__"

    private var models: [ModelChoice] {
        launchBackend == Backend.codex.rawValue ? ModelChoice.codexModels : ModelChoice.claudeModels
    }
    private var ready: Bool { launcherEnabled && (cockpit.claude != nil || cockpit.codexFound != nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModalHead(no: "08", title: "New session", jp: "新しい回を起こす") { stage.newSessionOpen = false }
            if !ready {
                Button { openSettings() } label: {
                    Text(launcherEnabled ? "claude / codex のコマンドが見つからない。設定で場所を指定する（押すと設定へ）"
                                         : "設定の「連携」で「セッションを起こす」を入にすると使える（押すと設定へ）")
                        .font(Palette.bodyJP(12)).foregroundStyle(Palette.danger).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
            field("BACKEND") {
                Picker("", selection: $launchBackend) {
                    Text("Claude").tag(Backend.claude.rawValue)
                    // 見つかっていない側は出さない（`.disabled` は Picker の中身に効かない）
                    if cockpit.codexFound != nil { Text("Codex (OpenAI)").tag(Backend.codex.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            field("MODEL") {
                Picker("", selection: $launchModel) {
                    ForEach(models, id: \.id) { Text($0.title).tag($0.id) }
                    Divider()
                    Text("カスタム…").tag(Self.custom)
                }
                .labelsHidden()
                if launchModel == Self.custom {
                    TextField("モデルID", text: $customModel).textFieldStyle(.roundedBorder)
                }
            }
            field("MODE 実行モード") {
                Picker("", selection: Binding(get: { level }, set: { new in
                    if new.needsConfirmation { risky = new } else { level = new }
                })) {
                    ForEach(Gate.Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            field("DIRECTORY 作業ディレクトリ") {
                HStack {
                    TextField("作業ディレクトリ", text: $directory).textFieldStyle(.roundedBorder)
                    SumiButton(title: "選ぶ…", variant: .secondary) { picking = true }
                }
            }
            field("PROMPT 最初の指示") {
                TextEditor(text: $prompt)
                    .font(Palette.bodyJP(13))
                    .scrollContentBackground(.hidden)
                    .frame(height: 140)
                    .padding(4)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
            }
            if failed {
                Text(cockpit.launchError ?? "起こせなかった。バックエンドの場所と作業ディレクトリを確かめる")
                    .font(Palette.bodyJP(12)).foregroundStyle(Palette.danger).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                SumiButton(title: "やめる", variant: .secondary) { stage.newSessionOpen = false }
                SumiButton(title: "起こす", disabled: !ready || launching
                           || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || directory.isEmpty
                           || (launchModel == Self.custom && customModel.isEmpty)) { launch() }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 520)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { directory = url.path }
        }
        .alert("この段は人間の承認なしにファイルを書き換える", isPresented: Binding(
            get: { risky != nil }, set: { if !$0 { risky = nil } })) {
            Button("やめる", role: .cancel) { risky = nil }
            Button("承知した", role: .destructive) { if let r = risky { level = r }; risky = nil }
        } message: {
            Text("\(risky?.title ?? "") では、起こしたセッションが確認を求めずに編集します。")
        }
        .onAppear {
            // GUI アプリの `currentDirectoryPath` は `/`。そこで起こすと何も見つからない
            if directory.isEmpty {
                directory = cockpit.selectedSession
                    .flatMap { id in cockpit.liveSessions.first { $0.id == id }?.cwd }
                    .flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
            }
            if !models.contains(where: { $0.id == launchModel }), launchModel != Self.custom {
                launchModel = models.first?.id ?? ""
            }
            level = cockpit.gateLevel
        }
        .onChange(of: launchBackend) {
            if !models.contains(where: { $0.id == launchModel }) { launchModel = models.first?.id ?? "" }
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).caps(9).foregroundStyle(Palette.Light.fg2)
            content()
        }
    }

    private func launch() {
        launching = true
        cockpit.setGateLevel(level)
        let model = launchModel == Self.custom ? customModel : launchModel
        let backend = Backend(rawValue: launchBackend) ?? .claude
        if cockpit.launch(prompt: prompt, cwd: directory, backend: backend, model: model) != nil {
            stage.newSessionOpen = false
        } else {
            failed = true
            launching = false
        }
    }
}

/// 鍵の一覧
struct KeysModal: View {
    let stage: Stage

    private let keys: [(String, String)] = [
        ("M", "メニュー（↑↓ 選ぶ · → 開く · ← 戻る）"), ("A / B / C", "WORK / STRUCTURE / SPARRING"),
        ("←→ · ENTER · 1–3", "門を選ぶ・答える"), ("⇧⌘G", "最古の門を許可"), ("⇧⌘T", "タスク一覧"),
        ("RETURN / ⌘RETURN", "送る（処理中は止める）"), ("⌘S", "壁打ちを保存"), ("ESC", "手前から畳む"), ("⌘,", "設定"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModalHead(no: "09", title: "Keys", jp: "鍵") { stage.keysOpen = false }
            VStack(spacing: 0) {
                ForEach(keys, id: \.0) { k in
                    HStack {
                        Text(k.0).caps(11).frame(width: 170, alignment: .leading)
                        Text(k.1).font(Palette.bodyJP(13))
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 520)
    }
}

// MARK: - 02 // STRUCTURE

/// 流し組み。行に収まるだけ左から詰め、溢れたら次の行へ。行の中は下端で揃える
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 18
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let h = rows.reduce(0) { $0 + $1.height } + vSpacing * CGFloat(max(0, rows.count - 1))
        let w = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + row.height - s.height), proposal: ProposedViewSize(s))
                x += s.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], x: CGFloat = 0, h: CGFloat = 0
        for (i, sv) in subviews.enumerated() {
            let s = sv.sizeThatFits(.unspecified)
            if !cur.isEmpty, x + s.width > width {
                rows.append((cur, x - hSpacing, h)); cur = []; x = 0; h = 0
            }
            cur.append(i); x += s.width + hSpacing; h = max(h, s.height)
        }
        if !cur.isEmpty { rows.append((cur, x - hSpacing, h)) }
        return rows
    }
}

/// 02 // STRUCTURE。書込量で字が育つファイル名の流し組み。ホバーで関係だけが浮かび、無関係は沈む
struct StructureScreen: View {
    let cockpit: Cockpit
    let stage: Stage
    let width: CGFloat
    let height: CGFloat

    @Environment(\.sumiFixedTime) private var fixedTime

    /// 流し組みに並べる上限。400 本を全部組むと字が潰れて読めない
    static let limit = 160

    var body: some View {
        let snap = cockpit.snapshot(now: Date(), mode: .structure)
        let all = snap.cards.flatMap(\.files)
        let hot = Cockpit.hotThreshold(snap)
        let graph = cockpit.structure
        let files = filtered(all, hot: hot, graph: graph)
        let shown = Array(files.prefix(Self.limit))
        let ids = Set(shown.map(\.id))
        let ties = shown.reduce(0) { $0 + (graph.dependsOn[$1.id] ?? []).intersection(ids).count }
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(no: "02", en: "STRUCTURE", jp: "構造")
            Text("\(Self.spell(shown.count, "file")), \(Self.spell(ties, "tie")).")
                .font(Palette.display(52)).padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("ホバーで関係だけが浮かび、無関係は沈みます。大きさは書込量です。")
                    .font(Palette.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
                if stage.structFilter != .all {
                    Button { stage.structFilter = .all } label: {
                        Text("FILTER · \(filterName) [×]").caps(10)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            Group {
                if fixedTime != nil {
                    flow(shown, hot: hot, graph: graph)
                } else {
                    ScrollView { flow(shown, hot: hot, graph: graph) }.scrollIndicators(.hidden)
                }
            }
            .padding(.top, 36)
            if files.count > shown.count {
                Text("ほか \(files.count - shown.count) 件").font(Palette.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func flow(_ files: [FileCell], hot: Int, graph: Structure.Graph) -> some View {
        FlowLayout {
            ForEach(files) { f in
                StructFile(file: f, weight: Cockpit.writeWeight(added: f.added, removed: f.removed),
                           hot: f.added + f.removed >= hot, related: related(f.id, graph: graph)) {
                    stage.fileModal = f.id
                } hover: { on in
                    if on { stage.hovered = f.id } else if stage.hovered == f.id { stage.hovered = nil }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func related(_ id: String, graph: Structure.Graph) -> Bool {
        guard let h = stage.hovered else { return true }
        return h == id || graph.dependsOn[h]?.contains(id) == true || graph.usedBy[h]?.contains(id) == true
    }

    private func filtered(_ files: [FileCell], hot: Int, graph: Structure.Graph) -> [FileCell] {
        switch stage.structFilter {
        case .all: files
        case let .category(c): files.filter { FileCategory.classify(path: $0.id) == c }
        case .ties: files.filter { !(graph.dependsOn[$0.id] ?? []).isEmpty || !(graph.usedBy[$0.id] ?? []).isEmpty }
        case .hot: files.filter { $0.added + $0.removed >= hot }
        }
    }

    private var filterName: String {
        switch stage.structFilter {
        case .all: "ALL"
        case let .category(c): c.title
        case .ties: "TIES"
        case .hot: "HOT SPOTS"
        }
    }

    /// `Thirteen files` の形。英語の数詞で書く
    static func spell(_ n: Int, _ noun: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US")
        let word = f.string(from: NSNumber(value: n)) ?? "\(n)"
        return word.prefix(1).uppercased() + word.dropFirst() + " " + noun + (n == 1 ? "" : "s")
    }
}

/// 流し組みの1語。字の大きさは 16 + 書込段×4、熱い所は二重下線
struct StructFile: View {
    let file: FileCell
    let weight: Int
    let hot: Bool
    let related: Bool
    let open: () -> Void
    let hover: (Bool) -> Void

    @State private var over = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(FileCategory.classify(path: file.id).mark).font(Palette.mono(9)).foregroundStyle(Palette.Light.fg2)
                if file.state == .writing { InkLoader(status: "write", pitch: 1.4) }
                Text(file.name)
                    .font(Palette.mono(CGFloat(16 + weight * 4)))
                    .foregroundStyle(weight == 0 ? Palette.Light.fg3 : Palette.Light.fg)
                    .overlay(alignment: .bottom) { underline }
                if file.state == .flagged { Text("⚑").font(.system(size: 12)).foregroundStyle(Palette.pink) }
            }
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(over ? Palette.Light.bg3 : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(related ? 1 : 0.22)
        .onHover { over = $0; hover($0) }
        .help(file.flaggedBy.map { "\($0) が何度も読んでいる" } ?? file.id)
    }

    @ViewBuilder
    private var underline: some View {
        if hot {
            VStack(spacing: 2) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(Palette.Light.fg)
            .offset(y: 5)
        } else if weight >= 2 {
            Rectangle().fill(Palette.Light.fg3).frame(height: 1).offset(y: 2)
        }
    }
}

// MARK: - 03 // SPARRING

/// 03 // SPARRING。記憶DBのノートを md のまま編集する。
/// 衝突（エージェントが先に書き換えた）は「読み直す／上書き」を人に返す——旧 `MemoryEditor` の扱いを移した
struct SparringScreen: View {
    let cockpit: Cockpit
    let stage: Stage
    let width: CGFloat
    let height: CGFloat

    @Environment(\.sumiFixedTime) private var fixedTime
    @State private var text = ""
    @State private var loaded = ""
    @State private var saved = false
    @State private var failed = false
    @State private var conflicted = false
    @State private var readFailed = false

    var body: some View {
        let nodes = cockpit.memory.filter { !$0.isIndex }
        let node = stage.editing.flatMap { cockpit.memoryNode(at: $0) }
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(no: "03", en: "SPARRING", jp: "壁打ち")
            Text("What the next one should know.").font(Palette.display(52))
                .fixedSize(horizontal: false, vertical: true)
            if nodes.isEmpty {
                Text(cockpit.selectedSession == nil ? "会話を選ぶと、そのプロジェクトの記憶DBが開きます。"
                                                    : "記憶DB はまだ空です（~/.claude/projects/<プロジェクト>/memory/）。")
                    .font(Palette.bodyJP(14)).foregroundStyle(Palette.Light.fg3)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(nodes) { n in
                            Button { pick(n.id) } label: {
                                Text(n.name).font(Palette.mono(11)).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(n.id == stage.editing ? Palette.white : Palette.Light.fg)
                                    .background(n.id == stage.editing ? Palette.Light.fg : .clear)
                                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(stage.memoryDirty && n.id != stage.editing)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                editor
                    .frame(height: max(200, min(420, height - 230)))
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 2))
                footer(node)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .onAppear {
            if stage.editing == nil { stage.editing = Self.defaultNote(nodes)?.id }
            load()
        }
        .onChange(of: stage.editing) { load() }
        // エージェントが書き換えたら取り込む。ただし人間が編集中の分は潰さない
        .onChange(of: node?.modified) { if text == loaded { load() } }
        .onChange(of: text) { stage.memoryDirty = text != loaded; if text != loaded { saved = false } }
        .onDisappear { stage.memoryDirty = false }
    }

    @ViewBuilder
    private var editor: some View {
        if fixedTime != nil {
            Text(text).font(Palette.mono(14)).lineSpacing(14 * 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18).padding(.vertical, 16)
                .clipped()
        } else {
            TextEditor(text: $text)
                .font(Palette.mono(14))
                .lineSpacing(14 * 0.8)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .disabled(readFailed)
        }
    }

    private func footer(_ node: Memory.Node?) -> some View {
        HStack(spacing: 12) {
            Text("\(node?.relative ?? "—") — md のまま編集").caps(10, tracking: 0.1).foregroundStyle(Palette.Light.fg3)
                .lineLimit(1)
            Spacer(minLength: 0)
            if readFailed {
                Text("実ファイルを読めないため編集できない").font(Palette.bodyJP(12)).foregroundStyle(Palette.danger)
            } else if conflicted {
                Text("エージェントが書き換えた").font(Palette.bodyJP(12)).foregroundStyle(Palette.danger)
                SumiButton(title: "読み直す", variant: .secondary) { load() }
                SumiButton(title: "上書き", variant: .secondary) { save(overwrite: true) }
            } else if failed {
                Text("保存できなかった").font(Palette.bodyJP(12)).foregroundStyle(Palette.danger)
                    .help("置き場の外か、書き込みが弾かれている")
            } else if saved {
                Text("保存しました").font(Palette.bodyJP(12)).foregroundStyle(Palette.success)
            }
            SumiButton(title: "Save", disabled: text == loaded || readFailed) { save() }
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    /// 引き継ぎらしいものを先に開く（HANDOFF → SHARED → PROJECT → 先頭）
    static func defaultNote(_ nodes: [Memory.Node]) -> Memory.Node? {
        nodes.first { $0.file.uppercased().contains("HANDOFF") }
            ?? nodes.first { $0.file == Memory.sharedNote }
            ?? nodes.first { Memory.projectNotes.contains($0.file) }
            ?? nodes.first
    }

    private func pick(_ id: String) {
        guard !stage.memoryDirty || stage.editing == id else { return }
        stage.editing = id
    }

    private func load() {
        saved = false
        guard let path = stage.editing else { text = ""; loaded = ""; return }
        do {
            let raw = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            text = raw; loaded = raw
            failed = false; conflicted = false; readFailed = false
        } catch {
            text = ""; loaded = ""
            failed = false; conflicted = false; readFailed = true
        }
        stage.memoryDirty = false
    }

    private func save(overwrite: Bool = false) {
        guard let path = stage.editing else { return }
        switch cockpit.saveNote(path: path, text: text, expectedText: loaded, overwrite: overwrite) {
        case .saved:
            loaded = text; saved = true; failed = false; conflicted = false
            stage.memoryDirty = false
        case .conflict:
            failed = false; conflicted = true
        case .failed:
            failed = true; conflicted = false
        }
    }
}
