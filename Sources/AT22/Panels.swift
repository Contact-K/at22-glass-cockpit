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
    /// いまの worktree（履歴の欄に、その会話を並べる）
    var workspace: String? = nil
    var onNew: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ActionsPanel(cockpit: cockpit, rows: actions, doneCount: doneCount, snapshot: snapshot, onOpen: onOpen)
            if let workspace {
                HistoryPanel(cockpit: cockpit, workspace: workspace, onNew: onNew).padding(.top, 12)
            }
            Spacer(minLength: 12)
            PlanPanel(tasks: tasks)
        }
        .frame(height: max(300, height - 76 - 117), alignment: .top)
    }
}

/// 01 // HISTORY いまの worktree の会話。題は最初の指示から自動で付く。押すと切り替わる
private struct HistoryPanel: View {
    let cockpit: Cockpit
    let workspace: String
    let onNew: () -> Void
    /// 並びを固定する。管制塔の並び（動いているもの順）のままだと、裏で状態が変わるたびに行が入れ替わり、
    /// 選んでいる青が動いて見えた。初めて見えた順に固定し、新しい会話だけ上に足す
    @State private var order: [String] = []

    var body: some View {
        // 中身は管制塔のタイルと同じ（動いているもの＋過去5本）。並びだけ固定する
        let found = cockpit.workspaceTree().flatMap(\.workspaces).first { $0.id == workspace }?.agents ?? []
        let ids = found.map(\.id)
        let rows = found.sorted { (order.firstIndex(of: $0.id) ?? -1) < (order.firstIndex(of: $1.id) ?? -1) }
        SumiPanel(number: "01", title: "HISTORY", jp: "履歴", right: "\(rows.count)") {
            ForEach(rows.prefix(6)) { row in
                let on = row.id == cockpit.selectedSession
                HStack(spacing: 8) {
                    Text(on ? "■" : "□").font(.mono(11))
                    Text(row.title).font(.bodyJP(13)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.backend.title).font(.mono(9)).foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg3)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
                .background(on ? Palette.Light.fg : .clear)
                .contentShape(Rectangle())
                .onTapGesture { Task { await cockpit.open(row) } }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            }
            if rows.isEmpty {
                Text("この worktree の会話はまだない").font(.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
                    .padding(.horizontal, 14).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Button("＋ 新しい会話", action: onNew).buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .onAppear { order = ids }
        .onChange(of: ids) { _, now in order = now.filter { !order.contains($0) } + order.filter(now.contains) }
        .onChange(of: workspace) { order = [] }
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

            Text(tasks.isEmpty ? "タスクはまだない · 司令塔が PLAN: 行で計画を書くと出る"
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

// MARK: - 計画のティック

/// 上帯の `05 // PLAN` とティック（押すとタスク一覧 ⇧⌘T）。済みは白い面、進行中は白い枠、これからは淡い枠
struct PlanTicks: View {
    let tasks: [RoadmapTask]
    let width: CGFloat
    let onTasks: () -> Void

    var body: some View {
        let count = max(1, Int((width + 4) / 40))
        let window = Cockpit.planWindow(tasks: tasks, size: count)
        let doneTicks = window.rows.filter { $0.status == .completed }.count
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) { Text("05").foregroundStyle(Palette.pink); Text(" // PLAN") }
                    .font(.mono(10)).tracking(Palette.caps(10))
                Text("\(window.current ?? window.done) / \(window.total) · ⇧⌘T")
                    .font(.mono(9)).tracking(0.9).foregroundStyle(Palette.Blue.fg3)
            }
            .frame(width: 118, alignment: .leading)

            Button(action: onTasks) {
                ZStack(alignment: .topLeading) {
                    Ruler(length: width).offset(y: 35)
                    HStack(spacing: 4) {
                        ForEach(window.rows) { task in tick(task) }
                    }
                    .offset(y: 6)
                    Rectangle().fill(Palette.white)
                        .frame(width: max(0, CGFloat(doneTicks) * 40 - 4), height: 1)
                        .offset(y: -1)
                }
                .frame(width: width, height: 44, alignment: .topLeading)
                .contentShape(Rectangle())
                .reportRect("planTicks")
                .reportRect("planBand")
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .help("タスク一覧（⇧⌘T）")
        }
    }

    /// 36×22 の升
    private func tick(_ task: RoadmapTask) -> some View {
        let act = task.status == .inProgress, done = task.status == .completed
        return Text(String(format: "%02d", task.number))
            .font(.mono(9)).tracking(0.4)
            .foregroundStyle(done ? Palette.blue : Palette.white)
            .frame(width: 36, height: 22)
            .background(done ? Palette.white : Color.clear)
            .overlay(Rectangle().strokeBorder(act ? Palette.white : done ? .clear : Palette.white.opacity(0.4),
                                              lineWidth: act ? 2 : 1))
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
                case .newWorkspace, .delete, .pick, .quickOpen: EmptyView()
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
                Text(all.isEmpty ? "まだタスクが無い。司令塔が返事に PLAN: 行（または TaskCreate）で計画を書くと出る"
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
