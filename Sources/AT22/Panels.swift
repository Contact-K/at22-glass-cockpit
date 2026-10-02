import SwiftUI
import UniformTypeIdentifiers

// MARK: - 右の列（04 ACTIONS ／ 05 PLAN）

/// 青い面の上に浮かぶ白い2枚。ACTIONS は上、PLAN は下帯から 117pt 上に据える。
/// 窓が低い時は間の空きが縮むだけで、2枚は重ならない
struct RightColumn: View {
    let cockpit: Cockpit
    let actions: [ActionRow]
    let doneCount: Int
    let snapshot: CockpitSnapshot
    let tasks: [RoadmapTask]
    let height: CGFloat
    let onOpen: (ActionRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ActionsPanel(cockpit: cockpit, rows: actions, doneCount: doneCount, snapshot: snapshot, onOpen: onOpen)
            Spacer(minLength: 12)
            PlanPanel(tasks: tasks)
        }
        .frame(height: max(300, height - 76 - 117), alignment: .top)
    }
}

/// 04 // ACTIONS 誰が・何を・どこに。司令塔の見出し（モデル・承認レベル・文脈）＋最大4行
private struct ActionsPanel: View {
    let cockpit: Cockpit
    let rows: [ActionRow]
    let doneCount: Int
    let snapshot: CockpitSnapshot
    let onOpen: (ActionRow) -> Void

    var body: some View {
        let cells = snapshot.cards.flatMap(\.files)
        VStack(spacing: 0) {
            header
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                ActionLine(row: row, flagged: row.path.map { path in cells.first { $0.id == path }?.state == .flagged } ?? false)
                    .onTapGesture { onOpen(row) }
                    .reportRect("act:\(i)")
                    .reportRect(i == rows.count - 1 ? "act:last" : "act-\(i)")
            }
            if rows.isEmpty {
                Text("動いているエージェントはいない")
                    .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            }
            HStack(spacing: 12) {
                Text("+\(doneCount) DONE")
                Spacer(minLength: 0)
                Text("QUIET \(cells.filter { $0.state == .idle }.count) FILES")
            }
            .font(.mono(10)).tracking(0.8)
            .foregroundStyle(Palette.Light.fg2)
            .padding(EdgeInsets(top: 7, leading: 14, bottom: 9, trailing: 14))
        }
        .foregroundStyle(Palette.Light.fg)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
    }

    private var header: some View {
        let reading = cockpit.reading
        let pct = Int((reading.growth * 100).rounded())
        let alarm = reading.stage == .warning
        let model = snapshot.chips.first { $0.depth == 0 }?.model ?? ""
        let level = cockpit.gateLevel.title
        let no = String(level.prefix { $0 != " " }).uppercased()
        let name = String(level.drop { $0 != " " }.dropFirst())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("04").foregroundStyle(Palette.pink)
                Text("// ACTIONS")
                Text("誰が・何を・どこに").font(.brush(14)).tracking(0)
            }
            .font(.mono(10)).tracking(Palette.caps(10))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("C0").font(.mono(22))
                Text(Cockpit.rootRole).font(.bodyJP(13))
                Text(model.isEmpty ? "—" : model).font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                Spacer(minLength: 0)
                Text(no).font(.mono(10)).tracking(0.8)
                Text(name).font(.bodyJP(11))
            }
            HStack(spacing: 8) {
                if alarm { InkLoader(status: "overload", pitch: 1.6) }
                Text("CTX").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { i in
                        Rectangle().fill(i < Int(jsRound(Double(pct) / 5))
                                         ? (alarm ? Palette.Light.danger : Palette.Light.fg) : Palette.ctxEmpty)
                            .frame(height: 8)
                    }
                }
                Text("\(pct)%").font(.display(20)).foregroundStyle(alarm ? Palette.Light.danger : Palette.Light.fg2)
            }
            .help(reading.caption + (reading.stage.advice.isEmpty ? "" : " — " + reading.stage.advice))
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
    }
}

/// ACTIONS の1行。`├ W5 ◼ WRITE 書込中 … +42 −7` ／ `→ CockpitCanvas.swift`
private struct ActionLine: View {
    let row: ActionRow
    let flagged: Bool
    @State private var hover = false
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.branch).font(.mono(12)).foregroundStyle(Palette.Light.fg3).frame(width: 16, alignment: .leading)
            Text(row.label).font(.mono(18)).frame(width: 34, alignment: .leading)
            Group {
                if row.waiting {
                    Ticker(fps: 4) { now in
                        Rectangle().fill(Palette.pink).frame(width: 16, height: 16)
                            .opacity(frozen != nil || now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.6 ? 1 : 0)
                    }
                    .padding(3)
                } else {
                    InkLoader(status: row.loader, pitch: 2)
                }
            }
            .frame(width: 22, height: 22, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.verb).font(.mono(10)).tracking(Palette.caps(10))
                    Text(row.jp).font(.bodyJP(12))
                    Spacer(minLength: 0)
                    Text(row.note).font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("→").font(.mono(12)).foregroundStyle(Palette.Light.fg3)
                    Text(row.file).font(.mono(14)).lineLimit(1).truncationMode(.middle)
                    if flagged { Text("⚑").font(.system(size: 12)).foregroundStyle(Palette.pink) }
                }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 7, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? Palette.hover : Palette.Light.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// 05 // PLAN 計画。5行の窓。進行中の行だけ青く反転する
private struct PlanPanel: View {
    let tasks: [RoadmapTask]

    var body: some View {
        let window = Cockpit.planWindow(tasks: tasks)
        let firstPending = tasks.first { $0.status == .pending }?.id
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 0) {
                    Text("05").foregroundStyle(Palette.pink)
                    Text("// PLAN")
                }
                .font(.mono(10)).tracking(Palette.caps(10))
                Text("計画").font(.brush(14))
                Spacer(minLength: 0)
                Text("\(window.current ?? window.done)").font(.display(28))
                Text("/ \(window.total)").font(.mono(11))
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }

            ForEach(Array(window.rows.enumerated()), id: \.element.id) { i, task in
                let on = task.status == .inProgress
                let done = task.status == .completed
                HStack(spacing: 10) {
                    Text("#\(task.number)").font(.mono(12)).frame(width: 30, alignment: .leading)
                    Text(task.subject).font(.bodyJP(13)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if done { InkLoader(status: "done", pitch: 1.4, color: Palette.Light.fg3) }
                        Text(on ? "NOW" : done ? "✓" : task.id == firstPending ? "NEXT" : "—")
                    }
                    .font(.mono(10)).tracking(0.8)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(on ? Palette.Light.bg : done ? Palette.Light.fg3 : Palette.Light.fg)
                .background(on ? Palette.Light.fg : Palette.Light.bg)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                .reportRect("plan:\(i)")
                .reportRect(on ? "plan:current" : "plan-\(i)")
            }

            Text(tasks.isEmpty ? "タスクはまだない · TaskCreate が呼ばれると出る"
                               : "\(window.done) DONE · 読み取り専用（TaskUpdate が更新）")
                .font(.mono(10)).tracking(0.8)
                .foregroundStyle(Palette.Light.fg2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 7, leading: 14, bottom: 9, trailing: 14))
        }
        .foregroundStyle(Palette.Light.fg)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
    }
}

// MARK: - 下帯

/// 青帯 44。`05 // PLAN` ＋ ティック（押すとタスク一覧 ⇧⌘T）＋ 波線と「いま誰が何を」
struct BottomBand: View {
    let tasks: [RoadmapTask]
    let actions: [ActionRow]
    let busy: Bool
    let width: CGFloat
    let onTasks: () -> Void

    var body: some View {
        let ticksWidth = max(160, min(882, width - 48 - 118 - 32 - 220))
        let count = max(1, Int((ticksWidth + 4) / 42))
        let window = Cockpit.planWindow(tasks: tasks, size: count)
        let doneTicks = window.rows.filter { $0.status == .completed }.count
        let moving = actions.first { !$0.waiting && $0.verb != "IDLE" && $0.verb != "DONE" }
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) { Text("05").foregroundStyle(Palette.pink); Text(" // PLAN") }
                    .font(.mono(10)).tracking(Palette.caps(10))
                Text("\(window.current ?? window.done) / \(window.total) · ⇧⌘T")
                    .font(.mono(9)).tracking(0.9).foregroundStyle(Palette.Blue.fg3)
            }
            .frame(width: 118, alignment: .leading)

            Button(action: onTasks) {
                ZStack(alignment: .topLeading) {
                    Ruler(length: ticksWidth).offset(y: 35)
                    HStack(spacing: 4) {
                        ForEach(window.rows) { task in tick(task) }
                    }
                    .offset(y: 6)
                    Rectangle().fill(Palette.white)
                        .frame(width: max(0, CGFloat(doneTicks) * 42 - 4), height: 1)
                        .offset(y: -1)
                }
                .frame(width: ticksWidth, height: 44, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .help("タスク一覧（⇧⌘T）")

            HStack(spacing: 10) {
                WaveLines(width: 120, height: 24, lines: 4, amp: 4, freq: 2, animate: busy || moving != nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(moving.map { "\($0.label) · \($0.jp) \($0.verb == "WRITE" ? $0.note : "")" } ?? "C0 · 待機")
                    Text(Self.version).foregroundStyle(Palette.Blue.fg3)
                }
                .font(.mono(9)).tracking(1.1)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.white)
        .padding(.horizontal, 24)
    }

    private static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "V" + (v ?? "DEV") + " · Σ"
    }

    /// 38×26 の升。進行中は白い斜め板、済みは薄い面、これからは破線
    private func tick(_ task: RoadmapTask) -> some View {
        let act = task.status == .inProgress, done = task.status == .completed
        return Text(String(format: "%02d", task.number))
            .font(.mono(10)).tracking(0.4)
            .foregroundStyle(act ? Palette.blue : done ? Palette.Blue.fg2 : Palette.white)
            .frame(width: 38, height: 26)
            .background {
                if act { Chevron(skew: -18).fill(Palette.white) }
                else if done { Rectangle().fill(Palette.white.opacity(0.18)) }
                else { Rectangle().strokeBorder(Palette.Blue.dim, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
            }
            .help("#\(task.number) \(task.subject)")
    }
}

// MARK: - モーダル

/// 幕 `rgba(8,8,92,.8)` の上に1枚。幕を押すと閉じる（Esc と同じ口）
struct Modals: View {
    let cockpit: Cockpit
    let overlay: CockpitView.Overlay
    let snapshot: CockpitSnapshot
    let onClose: () -> Void
    let onLaunched: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            Palette.scrim.contentShape(Rectangle()).onTapGesture(perform: onClose)
            Group {
                switch overlay {
                case .tasks: TasksModal(cockpit: cockpit, onClose: onClose)
                case let .file(path): FileModal(cockpit: cockpit, path: path, onClose: onClose)
                case let .agent(id): AgentModal(cockpit: cockpit, chip: snapshot.chips.first { $0.id == id },
                                                label: Cockpit.agentLabels(snapshot.chips)[id] ?? "", onClose: onClose)
                case .newSession: NewSessionModal(cockpit: cockpit, onClose: onClose, onLaunched: onLaunched,
                                                  onOpenSettings: onOpenSettings)
                }
            }
            .foregroundStyle(Palette.Light.fg)
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24))
            .background(Palette.Light.bg)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
            // 幕の tap が下まで抜けると、板を押しただけで閉じる
            .onTapGesture {}
        }
    }
}

/// 板の見出し。`06 // Tasks 読み取り専用 [×]`
@MainActor
private func modalHead(_ number: String?, _ title: String, display: Bool, sub: String?,
                       onClose: @escaping () -> Void) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let number { Text(number + " //").font(.mono(11)).foregroundStyle(Palette.pink) }
        Text(title).font(display ? .display(36) : .mono(11)).tracking(display ? 0 : Palette.caps(11))
            .foregroundStyle(display ? Palette.Light.fg : Palette.Light.fg2)
        if let sub { Text(sub).font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2) }
        Spacer(minLength: 0)
        Button(action: onClose) { Text("[×]").font(.mono(11)).contentShape(Rectangle()) }
            .buttonStyle(PressStyle())
    }
}

/// 小見出し付きの区画
@MainActor
private func block(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// 06 // Tasks。**1件も畳まない**（帯の側が畳むので、こちらは見返せる側）。読むだけ
private struct TasksModal: View {
    let cockpit: Cockpit
    let onClose: () -> Void

    /// 保存値は前の一覧（`TaskPanel`）と同じ鍵・同じ値。変えると選んでいた絞り込みが黙って初期化される
    enum Filter: String, CaseIterable {
        case all, pending, inProgress, completed
        var title: String {
            switch self {
            case .all: "ALL"
            case .pending: "TODO"
            case .inProgress: "NOW"
            case .completed: "DONE"
            }
        }
    }

    @AppStorage("taskListFilter") private var filter = Filter.all
    @State private var hovered: String?
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let all = cockpit.allTasks(session: cockpit.selectedSession)
        let shown = all.filter { task in
            switch filter {
            case .all: true
            case .pending: task.status == .pending
            case .inProgress: task.status == .inProgress
            case .completed: task.status == .completed
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            modalHead("06", "Tasks", display: true, sub: "読み取り専用", onClose: onClose)
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { filter = f } label: {
                        Text(f.title).font(.mono(10)).tracking(1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(filter == f ? Palette.Light.bg : Palette.Light.fg2)
                            .background(filter == f ? Palette.Light.fg : Color.clear)
                            .overlay(Rectangle().stroke(filter == f ? Palette.Light.fg : Palette.Light.line, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer(minLength: 0)
                Text("\(all.count) · DONE \(all.filter { $0.status == .completed }.count)")
                    .font(.mono(10)).foregroundStyle(Palette.Light.fg3)
            }
            .padding(.top, 12)
            Rectangle().fill(Palette.Light.fg).frame(height: 1).padding(.top, 10)
            if shown.isEmpty {
                Text(all.isEmpty ? "まだタスクが無い。Claude Code 側で TaskCreate が呼ばれると出る"
                                 : "この絞り込みに当てはまるタスクが無い")
                    .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg3).padding(.vertical, 24)
            } else if frozen != nil {
                VStack(spacing: 0) { ForEach(shown.prefix(12)) { row($0) } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { ForEach(shown) { row($0) } }
                }
                .frame(maxHeight: 520)
            }
            Text("編集は Claude Code 側の TaskCreate / TaskUpdate が担う")
                .font(.mono(9)).tracking(1).foregroundStyle(Palette.Light.fg3).padding(.top, 10)
        }
        .frame(width: 520)
    }

    private func row(_ task: RoadmapTask) -> some View {
        let done = task.status == .completed, active = task.status == .inProgress
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text("\(task.number)").font(.mono(12)).foregroundStyle(Palette.Light.fg2).frame(width: 24, alignment: .leading)
                Text(active && !task.activeForm.isEmpty ? task.activeForm : task.subject)
                    .font(.bodyJP(14)).strikethrough(done)
                    .foregroundStyle(done ? Palette.Light.fg3 : Palette.Light.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if cockpit.selectedSession == nil {
                    Text(String(task.session.prefix(8))).font(.mono(10)).foregroundStyle(Palette.Light.fg3)
                }
                Text(done ? "✓" : active ? "▸" : "").font(.mono(12))
            }
            if hovered == task.id, !task.detail.isEmpty {
                Text(task.detail).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2)
                    .textSelection(.enabled).padding(.leading, 36)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? task.id : nil }
    }
}

/// // FILE。押したファイルの「何をするやつか」と、書き込み・読み・依存の内訳。
/// 画面の側は量を字の大きさでしか語らないので、数字はここでしか読めない
private struct FileModal: View {
    let cockpit: Cockpit
    let path: String
    let onClose: () -> Void

    var body: some View {
        let note = cockpit.structure.notes[path]
        let entries = cockpit.writeHistory(of: path)
        let reads = cockpit.readCounts(of: path)
        let usedBy = cockpit.structure.usedBy[path] ?? []
        let dependsOn = cockpit.structure.dependsOn[path] ?? []
        VStack(alignment: .leading, spacing: 10) {
            modalHead(nil, "// FILE", display: false, sub: nil, onClose: onClose)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(FileCategory.classify(path: path).mark).font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                Text((path as NSString).lastPathComponent).font(.mono(24)).textSelection(.enabled)
            }
            Text(note?.memo.isEmpty == false ? note!.memo : "このファイルが宣言している型に落として表示します（説明コメントなし）。")
                .font(.bodyJP(14)).lineSpacing(14 * 0.75 - 4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                stat("定義した型", "\(note?.declared.count ?? 0)")
                stat("被参照", "\(usedBy.count)")
                stat("直近の編集", entries.first.map { "+\($0.added)" } ?? "—")
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    block("書き込み履歴") {
                        if entries.isEmpty {
                            Text("書き込みなし（読み取りだけ）").font(.mono(11)).foregroundStyle(Palette.Light.fg3)
                        } else {
                            ForEach(entries) { e in
                                HStack(spacing: 8) {
                                    Text(e.at.formatted(.dateTime.hour().minute())).foregroundStyle(Palette.Light.fg3)
                                    Text(e.role).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if e.added == 0, e.removed == 0 {
                                        Text("進行中").foregroundStyle(Palette.pink)
                                    } else {
                                        Text("+\(e.added)").foregroundStyle(Palette.Light.success)
                                        Text("−\(e.removed)").foregroundStyle(Palette.Light.fg3)
                                    }
                                }
                                .font(.mono(11))
                            }
                        }
                    }
                    if !reads.isEmpty {
                        block("読んだ相手") {
                            Text(reads.map { "\($0.role) ×\($0.count)" }.joined(separator: " ／ ")).font(.mono(11))
                        }
                    }
                    if !usedBy.isEmpty { related("ここを直すと響く先 \(usedBy.count)", usedBy) }
                    if !dependsOn.isEmpty { related("使っている \(dependsOn.count)", dependsOn) }
                    if let note, !note.exported.isEmpty { related("使われている名前 \(note.exported.count)", Set(note.exported)) }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 460)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.mono(9)).tracking(1).foregroundStyle(Palette.Light.fg2)
            Text(value).font(.display(22))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    /// 依存の一覧。多いと縦に伸びるので頭から数件で切る
    private func related(_ title: String, _ paths: Set<String>) -> some View {
        let names = paths.map { ($0 as NSString).lastPathComponent }.sorted()
        let shown = names.prefix(6)
        return block(title) {
            Text(shown.joined(separator: "  ") + (names.count > shown.count ? "  他\(names.count - shown.count)" : ""))
                .font(.mono(11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// エージェントの板。受けた指示（省略前）・作業の内訳・触ったファイル
private struct AgentModal: View {
    let cockpit: Cockpit
    let chip: AgentChip?
    let label: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            modalHead(nil, "// AGENT", display: false, sub: nil, onClose: onClose)
            if let chip {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label).font(.mono(24))
                    Text(chip.role).font(.bodyJP(14))
                    Spacer(minLength: 0)
                    Text(chip.done ? "DONE" : chip.busy ? "BUSY" : "IDLE").font(.mono(10)).tracking(1.4)
                }
                Text("\(chip.model.isEmpty ? "—" : chip.model) · \(chip.work) calls"
                     + (chip.share > 0 ? " · 消費の \(Int((chip.share * 100).rounded()))%（\(Snowman.short(Int(chip.spent)))）" : ""))
                    .font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        block("受けた指示") {
                            Text(TalkScreen.formatted(chip.instruction)).font(.bodyJP(13))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        if !chip.counts.isEmpty {
                            block("作業の内訳") {
                                ForEach(chip.counts, id: \.kind) { item in
                                    HStack {
                                        Text(item.kind.rawValue)
                                        Spacer()
                                        Text("\(item.count)回").foregroundStyle(Palette.Light.fg2)
                                    }
                                    .font(.mono(11))
                                }
                            }
                        }
                        let files = cockpit.touchedFiles(by: chip.id)
                        block("触ったファイル \(files.count)") {
                            ForEach(files.prefix(40), id: \.path) { file in
                                HStack(alignment: .firstTextBaseline) {
                                    Text((file.path as NSString).lastPathComponent).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text("読\(file.reads) 書\(file.writes)").foregroundStyle(Palette.Light.fg2)
                                }
                                .font(.mono(11))
                                .help(file.path)
                            }
                        }
                    }
                }
                .frame(maxHeight: 460)
            } else {
                Text("このエージェントはもう画面に居ない（畳まれたか、消された）")
                    .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg3)
            }
        }
        .frame(width: 460)
    }
}

/// 新しいセッションを起こす板。**起こせない時も板は出す**——理由と設定への口を見せる
private struct NewSessionModal: View {
    let cockpit: Cockpit
    let onClose: () -> Void
    let onLaunched: () -> Void
    let onOpenSettings: () -> Void

    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @AppStorage("launchBackend") private var launchBackend: String = Backend.claude.rawValue
    @AppStorage("launchModel") private var launchModel = ""
    @State private var prompt = ""
    @State private var directory = ""
    @State private var customModelID = ""
    @State private var level = Gate.defaultLevel
    @State private var riskyLevel: Gate.Level?
    @State private var failed = false
    @State private var launching = false
    @State private var pickDirectory = false

    static let customModel = "__custom__"

    private var ready: Bool { launcherEnabled && !cockpit.found.isEmpty }

    private var models: [ModelChoice] {
        ModelChoice.models(for: Backend(rawValue: launchBackend) ?? .claude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modalHead("07", "New session", display: true, sub: "セッションを起こす", onClose: onClose)
            if !ready {
                Text(launcherEnabled
                     ? "claude / codex のコマンドが見つからない。設定で場所を指定する"
                     : "設定の「連携」で「セッションを起こす」を入にすると使える")
                    .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                Button("設定を開く ⌘,", action: onOpenSettings).buttonStyle(SumiButtonStyle(primary: true))
            } else {
                form
            }
        }
        .frame(width: 520)
        .fileImporter(isPresented: $pickDirectory, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { directory = url.path }
        }
        .onAppear {
            // GUI アプリの `currentDirectoryPath` は `/`。そこで起こすと何も見つからない
            if directory.isEmpty {
                directory = cockpit.selectedSession
                    .flatMap { id in cockpit.liveSessions.first { $0.id == id }?.cwd }
                    .flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
            }
            // 既定が空文字だと、どの `tag` にも一致せず Picker が空欄で立ち上がる
            if !models.contains(where: { $0.id == launchModel }), launchModel != Self.customModel {
                launchModel = models.first?.id ?? ""
            }
            level = cockpit.gateLevel
        }
        .onChange(of: launchBackend) {
            if !models.contains(where: { $0.id == launchModel }) { launchModel = models.first?.id ?? "" }
        }
        .alert("この段は人間の承認なしにファイルを書き換える", isPresented: Binding(
            get: { riskyLevel != nil }, set: { if !$0 { riskyLevel = nil } })) {
            Button("やめる", role: .cancel) { riskyLevel = nil }
            Button("承知した", role: .destructive) {
                if let riskyLevel { level = riskyLevel }
                riskyLevel = nil
            }
        } message: {
            Text("\(riskyLevel?.title ?? "") では、起こしたセッションが確認を求めずに編集します。")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("BACKEND") {
                Picker("", selection: $launchBackend) {
                    // 見つかっていない側は出さない（`Picker` の中身に `.disabled` は効かない）
                    ForEach(Backend.allCases.filter { cockpit.found[$0] != nil }, id: \.rawValue) {
                        Text($0.title).tag($0.rawValue)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            field("MODEL") {
                Picker("", selection: $launchModel) {
                    ForEach(models, id: \.id) { Text($0.title).tag($0.id) }
                    Divider()
                    Text("カスタム…").tag(Self.customModel)
                }
                .labelsHidden()
                if launchModel == Self.customModel {
                    TextField("モデルID", text: $customModelID).textFieldStyle(.roundedBorder).font(.mono(11))
                }
            }
            field("APPROVAL") {
                Picker("", selection: Binding(get: { level }, set: { new in
                    if new.needsConfirmation { riskyLevel = new } else { level = new }
                })) {
                    ForEach(Gate.Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            field("DIRECTORY") {
                HStack(spacing: 8) {
                    TextField("作業ディレクトリ", text: $directory).textFieldStyle(.roundedBorder).font(.mono(11))
                    Button("選ぶ…") { pickDirectory = true }.buttonStyle(SumiButtonStyle(primary: false))
                }
            }
            field("FIRST PROMPT") {
                TextEditor(text: $prompt)
                    .font(.bodyJP(13))
                    .scrollContentBackground(.hidden)
                    .frame(height: 140)
                    .padding(6)
                    .background(Palette.Light.bg2)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
            }
            if failed {
                Text(cockpit.launchError ?? "起こせなかった。バックエンドの場所と作業ディレクトリを確かめる")
                    .font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("やめる", action: onClose).buttonStyle(SumiButtonStyle(primary: false))
                Button("起こす ↵") { launch() }
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || directory.isEmpty || launching
                              || (launchModel == Self.customModel && customModelID.isEmpty))
            }
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// " + title).font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.Light.fg2)
            content()
        }
    }

    private func launch() {
        launching = true
        let model = launchModel == Self.customModel ? customModelID : launchModel
        let backend = Backend(rawValue: launchBackend) ?? .claude
        // 段は launch に渡す。先に setGateLevel すると、いま選んでいる別プロジェクトの LEVEL に書かれる
        if cockpit.launch(prompt: prompt, cwd: directory, backend: backend, model: model, level: level) != nil {
            onLaunched()
        } else {
            failed = true
            launching = false
        }
    }
}

// MARK: - 02 STRUCTURE

/// ファイル名の流し組み。**字の大きさが書込量**（16 + w×4 pt）。
/// ホバーで関係（使っている／使われている）だけが浮かび、無関係は沈む。押すと // FILE
struct StructureScreen: View {
    let cockpit: Cockpit
    let filter: StructFilter
    let width: CGFloat
    /// 下帯の上で止める。これが無いと ScrollView が窓の下端まで伸び、最後の行が帯の下に潜る
    let height: CGFloat
    let onOpen: (String) -> Void

    @State private var hovered: String?
    @Environment(\.frozenTime) private var frozen

    /// ponytail: 流し組みに並べる上限。400 件並べると字が小さい側から読めなくなる
    static let maxShown = 160

    var body: some View {
        let graph = cockpit.structure
        let files = shown(graph: graph)
        let paths = Set(files.map(\.id))
        let ties = files.reduce(0) { $0 + (graph.dependsOn[$1.id] ?? []).intersection(paths).count }
        VStack(alignment: .leading, spacing: 0) {
            SectionMark(number: "02", title: "STRUCTURE", jp: "構造")
            Text("\(Self.count(files.count, "file", "files")), \(ties == 0 ? "no ties" : Self.count(ties, "tie", "ties")).")
                .font(.display(52)).foregroundStyle(Palette.Light.fg).padding(.top, 12)
            Text("ホバーで関係だけが浮かび、無関係は沈みます。大きさは書込量です。" + filterNote)
                .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2).padding(.top, 8)
            Group {
                if frozen != nil {
                    flow(files, graph: graph)
                } else {
                    ScrollView { flow(files, graph: graph).padding(.bottom, 24) }.scrollIndicators(.never)
                }
            }
            .padding(.top, 36)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private var filterNote: String {
        switch filter {
        case .all: ""
        case let .category(c): " いまは「\(c.title)」だけ。"
        case .ties: " いまは関係のあるものだけ。"
        case .hot: " いまは書込量の上位だけ。"
        }
    }

    private func shown(graph: Structure.Graph) -> [FileCell] {
        var files = cockpit.snapshot(now: Date(), mode: .structure).cards.flatMap(\.files)
        switch filter {
        case .all: break
        case let .category(c): files = files.filter { FileCategory.classify(path: $0.id) == c }
        case .ties: files = files.filter { !(graph.dependsOn[$0.id] ?? []).isEmpty || !(graph.usedBy[$0.id] ?? []).isEmpty }
        case .hot:
            // 書込量の上位 2%（最低1件）
            let sorted = files.filter { $0.added + $0.removed > 0 }.sorted { $0.added + $0.removed > $1.added + $1.removed }
            files = Array(sorted.prefix(max(1, Int(ceil(Double(files.count) * 0.02)))))
        }
        return Array(files.prefix(Self.maxShown))
    }

    private func flow(_ files: [FileCell], graph: Structure.Graph) -> some View {
        // 二重下線は書込量の上位 2%（最低1件）
        let lines = files.map { $0.added + $0.removed }.filter { $0 > 0 }.sorted(by: >)
        let hotCut = lines.isEmpty ? Int.max : lines[min(lines.count - 1, max(0, Int(ceil(Double(files.count) * 0.02)) - 1))]
        return FlowLayout(spacing: 18, lineSpacing: 6) {
            ForEach(files) { file in
                let w = Cockpit.writeWeight(added: file.added, removed: file.removed)
                let hot = file.added + file.removed >= hotCut
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(FileCategory.classify(path: file.id).mark).font(.mono(9)).foregroundStyle(Palette.Light.fg2)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + CGFloat(1 + w * 3) }
                    Text(file.name)
                        .font(.mono(CGFloat(16 + w * 4)))
                        .foregroundStyle(w == 0 ? Palette.Light.fg3 : Palette.Light.fg)
                        .lineLimit(1)
                        .overlay(alignment: .bottom) {
                            if hot {
                                VStack(spacing: 1.5) {
                                    Rectangle().frame(height: 1.25)
                                    Rectangle().frame(height: 1.25)
                                }
                                .foregroundStyle(Palette.Light.fg)
                                .offset(y: 4)
                            } else if w >= 2 {
                                Rectangle().fill(Palette.Light.fg3).frame(height: 1).offset(y: 2)
                            }
                        }
                }
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(hovered == file.id ? Palette.Light.bg3 : Color.clear)
                .opacity(related(file.id, graph: graph) ? 1 : 0.22)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = file.id } else if hovered == file.id { hovered = nil }
                }
                .onTapGesture { onOpen(file.id) }
                .help(file.id)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func related(_ path: String, graph: Structure.Graph) -> Bool {
        guard let hovered else { return true }
        return path == hovered
            || (graph.dependsOn[hovered] ?? []).contains(path) || (graph.usedBy[hovered] ?? []).contains(path)
            || (graph.dependsOn[path] ?? []).contains(hovered) || (graph.usedBy[path] ?? []).contains(hovered)
    }

    /// `Thirteen files`。20 までは英語の数詞で、それより上は数字で書く
    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
                     "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen",
                     "Eighteen", "Nineteen", "Twenty"]
        let word = n < words.count ? words[n] : "\(n)"
        return word + " " + (n == 1 ? one : many)
    }
}

// MARK: - 03 SPARRING

/// 引き継ぎと記憶。記憶DBの1本を md のまま編集する。
///
/// **AT22 が書くのは記憶DBだけ。** 保存は一時ファイル → 置換 → 読み返しで確かめる（`Cockpit.saveNote`）。
/// エージェントが同じファイルを書き換えていたら上書きせずに止め、読み直すか上書きするかを人に返す
struct SparringScreen: View {
    let cockpit: Cockpit
    @Binding var editing: String?
    @Binding var dirty: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let notes = cockpit.memory.filter { !$0.isIndex }
        let node = editing.flatMap { cockpit.memoryNode(at: $0) }
            ?? notes.first { $0.file.uppercased().contains("HANDOFF") } ?? notes.first
        VStack(alignment: .leading, spacing: 12) {
            SectionMark(number: "03", title: "SPARRING", jp: "壁打ち")
            Text("What the next one should know.").font(.display(52)).foregroundStyle(Palette.Light.fg)
            if notes.isEmpty {
                Text(cockpit.selectedSession == nil
                     ? "セッションを選ぶと、そのプロジェクトの記憶DBが出ます。"
                     : "記憶DBはまだ空。エージェントが memory/ に書くとここに出ます。")
                    .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(notes) { note in
                        let on = note.id == node?.id
                        Button {
                            // 書きかけがある間は別のノートへ移らない（捨てない）
                            if !dirty { editing = note.id }
                        } label: {
                            Text(note.name).font(.mono(10)).tracking(0.6).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg2)
                                .background(on ? Palette.Light.fg : Color.clear)
                                .overlay(Rectangle().stroke(on ? Palette.Light.fg : Palette.Light.line, lineWidth: 1))
                        }
                        .buttonStyle(PressStyle())
                        .help(note.summary)
                    }
                }
                if let node {
                    NoteEditor(node: node,
                               onSave: { text, expected, overwrite in
                                   cockpit.saveNote(path: node.id, text: text, expectedText: expected, overwrite: overwrite)
                               },
                               onDirtyChange: { changed in
                                   dirty = changed
                                   // 書き始めたらこのノートに留める。既定の「HANDOFF を含む先頭」に任せたままだと、
                                   // エージェントが新しいノートを足した瞬間に欄が別のノートへ移り、書きかけが消える
                                   if changed { editing = node.id }
                               })
                        .id(node.id)
                }
            }
        }
        // 欄は残りの高さを取る。固定の引き算だと、見出しの折り返しや札の段数で SAVE が下帯の下へ潜る
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// md の編集欄。読み込み・保存・衝突の扱いは前の `MemoryEditor` をそのまま移した
private struct NoteEditor: View {
    let node: Memory.Node
    let onSave: (String, String, Bool) -> NoteSaveResult
    let onDirtyChange: (Bool) -> Void

    @State private var text = ""
    @State private var loaded = ""
    @State private var failed = false
    @State private var conflicted = false
    @State private var readFailed = false
    @State private var saved = false
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if frozen != nil {
                    Text(text).font(.mono(14)).lineSpacing(14 * 0.8 - 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
                } else {
                    TextEditor(text: $text)
                        .font(.mono(14)).lineSpacing(14 * 0.8 - 4)
                        .scrollContentBackground(.hidden)
                        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                        .disabled(readFailed)
                }
            }
            .foregroundStyle(Palette.Light.fg)
            .frame(minHeight: 160, maxHeight: .infinity)
            .background(Palette.Light.bg)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))

            if readFailed {
                Text("実ファイルを読めないため編集できない").font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
            } else if conflicted {
                HStack(spacing: 8) {
                    Text("エージェントが書き換えた。読み直すか上書きするか").font(.bodyJP(12))
                        .foregroundStyle(Palette.Light.danger)
                    Spacer(minLength: 0)
                    Button("読み直す") { load() }.buttonStyle(SumiButtonStyle(primary: false))
                    Button("上書き") { save(overwrite: true) }.buttonStyle(SumiButtonStyle(primary: true))
                }
            } else if failed {
                Text("保存できなかった。置き場の外か、書き込みが弾かれている").font(.bodyJP(12))
                    .foregroundStyle(Palette.Light.danger)
            }

            HStack(spacing: 12) {
                Text(node.relative + " — md のまま編集").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg3)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if saved { Text("保存しました").font(.bodyJP(12)).foregroundStyle(Palette.Light.success) }
                Button("SAVE") { save() }
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(text == loaded || readFailed)
            }
        }
        .onAppear { load() }
        // エージェントが書き換えたら取り込む。ただし人が編集中の分は潰さない
        .onChange(of: node.modified) { if text == loaded { load() } }
        .onChange(of: text) {
            onDirtyChange(text != loaded)
            if text != loaded { saved = false }
        }
        .onDisappear { onDirtyChange(false) }
    }

    private func load() {
        do {
            let raw = try String(contentsOf: URL(fileURLWithPath: node.id), encoding: .utf8)
            text = raw
            loaded = raw
            readFailed = false
        } catch {
            text = ""
            loaded = ""
            readFailed = true
        }
        failed = false
        conflicted = false
        onDirtyChange(false)
    }

    private func save(overwrite: Bool = false) {
        switch onSave(text, loaded, overwrite) {
        case .saved:
            loaded = text
            failed = false
            conflicted = false
            saved = true
            onDirtyChange(false)
        case .conflict:
            failed = false
            conflicted = true
        case .failed:
            failed = true
            conflicted = false
        }
    }
}

// MARK: - 流し組み

/// 左から詰めて、入らなくなったら折り返す。行の中は**ベースラインで揃える**
/// （大きさの違うファイル名が並ぶので、上揃えだと字の足元がばらつく）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in line.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(at: CGPoint(x: x, y: y + line.baseline - item.baseline),
                                           anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(index: Int, baseline: CGFloat)] = []
        var width: CGFloat = 0
        var baseline: CGFloat = 0
        var descent: CGFloat = 0
        var height: CGFloat { baseline + descent }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let dims = subviews[index].dimensions(in: .unspecified)
            let baseline = dims[VerticalAlignment.firstTextBaseline]
            if !line.items.isEmpty, line.width + spacing + dims.width > width {
                lines.append(line)
                line = Line()
            }
            line.width += (line.items.isEmpty ? 0 : spacing) + dims.width
            line.baseline = max(line.baseline, baseline)
            line.descent = max(line.descent, dims.height - baseline)
            line.items.append((index, baseline))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
