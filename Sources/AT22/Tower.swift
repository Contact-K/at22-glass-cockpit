import SwiftUI

// MARK: - 管制塔のタイルの中身

/// ワークスペースの状態。並べる順（あなた待ちが先）
enum TileState: Int, Comparable {
    case wait, fail, work, done, idle
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var jp: String { ["あなた待ち", "失敗", "作業中", "完了", "待機"][rawValue] }
    var en: String { ["YOUR TURN", "FAILED", "WORKING", "DONE", "IDLE"][rawValue] }
    /// InkLoader の状態
    var ink: String { ["wait", "error", "write", "done", "idle"][rawValue] }
}

/// InkLoader の状態の和名（v11 `V11_ACT`）
enum ActWords {
    static let jp: [String: String] = [
        "think": "考えています", "search": "探しています", "write": "書いています", "reply": "返します",
        "transfer": "渡しています", "download": "取り寄せています", "upload": "送っています",
        "error": "つまずきました", "wait": "承認を待っています", "handoff": "引き継いでいます",
        "reread": "読み返しています", "duplicate": "複製しています", "idle": "うたた寝しています",
        "done": "終わりました", "build": "組み立てています", "overload": "文脈があふれそうです",
    ]
}

/// 管制塔の1枚。`Cockpit.WorkspaceNode` に、状態・最後の発言・差分の量・分岐元を足したもの
struct WsTile: Identifiable {
    let id: String
    let project: String
    let name: String
    let branch: String?
    let isMain: Bool
    let state: TileState
    let unread: Bool
    let act: String
    /// 最初の指示（セッションの題）。同じ指示で束ねる鍵にもなる
    let task: String
    let last: String
    let agentsLine: String
    let stat: Worktree.Stat?
    let creating: Bool
    let failed: String?
    let race: String?
    let parent: String?
    let rows: [Cockpit.AgentRow]

    var lead: Cockpit.AgentRow? { rows.first }
    var rank: Int { state == .done && !unread ? 4 : [0, 1, 2, 3, 5][state.rawValue] }
    var quiet: Bool { state == .idle || (state == .done && !unread) }
    var item: TowerItem { TowerItem(id: id, parent: parent, race: race, isMain: isMain, rank: rank, quiet: quiet) }
}

struct TowerProject: Identifiable {
    let id: String
    let name: String
    let registered: Bool
    let tiles: [WsTile]
    var main: WsTile? { tiles.first(where: \.isMain) }
}

@MainActor
enum TowerData {
    static func projects(_ cockpit: Cockpit) -> [TowerProject] {
        cockpit.workspaceTree().map { project in
            TowerProject(id: project.id, name: project.name, registered: project.registered,
                         tiles: project.workspaces.map { tile($0, project: project.name, cockpit: cockpit) })
        }
    }

    private static func tile(_ node: Cockpit.WorkspaceNode, project: String, cockpit: Cockpit) -> WsTile {
        let creating = node.pending == "作成中"
        let failed = node.pending.flatMap { $0 == "作成中" ? nil : $0 }
        let state: TileState = {
            if failed != nil { return .fail }
            if creating { return .work }
            switch node.agents.map(\.status).min() {
            case .waiting?: return .wait
            case .failed?: return .fail
            case .working?: return .work
            case .done?: return .done
            default: return .idle
            }
        }()
        let lead = node.agents.first
        let act: String = {
            switch state {
            case .wait: return "wait"
            case .fail: return "error"
            case .done: return "done"
            case .idle: return "idle"
            case .work:
                if creating { return "download" }
                guard let session = node.agents.first(where: { $0.status == .working })?.id else { return "think" }
                return cockpit.liveInk(session)
            }
        }()
        let last = lead.flatMap { row in
            cockpit.messages.last { $0.session == row.id && $0.speaker == .model && !$0.thinking }
        }.map { Cockpit.plainLine($0.text) } ?? ""
        return WsTile(
            id: node.id, project: project, name: node.isMain ? (node.branch ?? "本体") : node.name,
            branch: node.branch, isMain: node.isMain, state: state,
            unread: node.agents.contains(where: \.unread), act: act,
            task: lead.flatMap { cockpit.title(for: $0.id) } ?? lead?.title ?? "",
            last: last,
            agentsLine: node.agents.prefix(3).map { row in
                [row.backend.title, cockpit.model(of: row.id) ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            }.joined(separator: " · "),
            stat: cockpit.diffStats[node.id], creating: creating, failed: failed,
            race: cockpit.raceKey(of: node.id), parent: cockpit.towerParent(of: node.id), rows: node.agents)
    }

    /// 管制塔の見出し。`Two wait for you.`
    static func headline(waits: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        guard waits > 0 else { return "Nothing waits." }
        return "\(waits < words.count ? words[waits] : String(waits)) wait\(waits > 1 ? "" : "s") for you."
    }

    /// ⌘J と ←→ の順。プロジェクトごとに本体 → 木の行の順 → 静か
    /// 静かな worktree を畳むのは、本体以外が `foldFrom` 本以上ある時だけ。数本しか無いのに子が全部
    /// 「静か」の1行に隠れると、本体しか無いように見えた（2026-10-03）
    static let foldFrom = 7
    static func folds(_ project: TowerProject, _ fold: Bool) -> Bool {
        fold && project.tiles.filter { !$0.isMain }.count >= foldFrom
    }

    static func order(_ projects: [TowerProject], fold: Bool) -> [WsTile] {
        projects.flatMap { project -> [WsTile] in
            let lane = Cockpit.towerLane(project.tiles.map(\.item), fold: folds(project, fold))
            let byID = Dictionary(uniqueKeysWithValues: project.tiles.map { ($0.id, $0) })
            let placed = lane.placed.sorted { ($0.row, $0.depth) < ($1.row, $1.depth) }.compactMap { byID[$0.id] }
            return (project.main.map { [$0] } ?? []) + placed + lane.quiet.compactMap { byID[$0] }
        }
    }
}

// MARK: - 管制塔

/// タイルの ⋯ から選ぶもの
enum TileAction { case branch, terminal, pick, delete, forget, retry }

/// 00 // TOWER。見出し・数、プロジェクトごとの木（本体は見出し行、子は分岐元の右、競走は点線の枠）
struct TowerScreen: View {
    let projects: [TowerProject]
    let width: CGFloat
    let height: CGFloat
    let focus: String?
    @Binding var hover: String?
    let onEnter: (WsTile) -> Void
    let onAct: (TileAction, WsTile) -> Void

    @AppStorage("towerFold") private var fold = true
    @State private var open: Set<String> = []

    static let w: CGFloat = 262, h: CGFloat = 100, cw: CGFloat = 290, gap: CGFloat = 16
    static let raceH: CGFloat = 30, x0: CGFloat = 30

    var body: some View {
        let tiles = projects.flatMap(\.tiles)
        ZStack(alignment: .topLeading) {
            header(tiles)
                .frame(width: max(400, width - 376 - 184), height: 84)
                .offset(x: 184, y: 74)
            LiveScroll {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(projects) { project in lane(project) }
                    if projects.isEmpty {
                        Text("ワークスペースはまだない。上帯の ＋ でリポジトリから作るか、エージェントを動かすとここに並ぶ。")
                            .font(.bodyJP(14)).foregroundStyle(Palette.Blue.fg2)
                    }
                }
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: max(300, width - 564), height: max(200, height - 172 - 52))
            .offset(x: 172, y: 172)
        }
        .foregroundStyle(Palette.white)
    }

    private func header(_ tiles: [WsTile]) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionMark(number: "00", title: "TOWER", jp: "管制塔", ink: Palette.Blue.fg2, jpInk: Palette.white)
                Text(TowerData.headline(waits: tiles.filter { $0.state == .wait }.count))
                    .font(.display(40)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                ForEach([TileState.work, .done, .fail, .idle], id: \.self) { state in
                    let n = tiles.filter { $0.state == state }.count
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(String(format: "%02d", n)).font(.display(24))
                        Text(state.jp).font(.bodyJP(11))
                    }
                    .opacity(n > 0 ? 1 : 0.45)
                }
            }
            // ＋ NEW は上帯の ＋ に統合した。門の窓に数字が付かないよう間を空ける
            .padding(.trailing, 28)
        }
    }

    // MARK: 1つのプロジェクト

    @ViewBuilder
    private func lane(_ project: TowerProject) -> some View {
        let folding = TowerData.folds(project, fold) && !open.contains(project.id)
        let lane = Cockpit.towerLane(project.tiles.map(\.item), fold: folding)
        let byID = Dictionary(uniqueKeysWithValues: project.tiles.map { ($0.id, $0) })
        let heights = (0..<lane.rows).map { (lane.raceRows.contains($0) ? Self.raceH : 0) + Self.h + Self.gap }
        let ys = heights.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }
        let maxDepth = lane.placed.map(\.depth).max() ?? 0
        let canvasW = Self.x0 + CGFloat(maxDepth) * Self.cw + Self.w + 16

        VStack(alignment: .leading, spacing: 0) {
            projectRow(project, count: project.tiles.count)
            if lane.rows > 0 {
                ZStack(alignment: .topLeading) {
                    edges(lane, ys: ys, byID: byID)
                    ForEach(lane.races, id: \.key) { race in raceFrame(race, ys: ys, lane: lane, byID: byID) }
                    ForEach(lane.placed, id: \.id) { placed in
                        if let tile = byID[placed.id] {
                            TowerNode(tile: tile, focused: focus == tile.id, dim: dimmed(tile), onAct: onAct)
                                .onTapGesture { if tile.failed == nil { onEnter(tile) } }
                                .onHover { hover = $0 ? (tile.task.isEmpty ? "@" + tile.id : tile.task) : nil }
                                .offset(x: xOf(placed.depth), y: top(placed.row, ys: ys, lane: lane))
                        }
                    }
                }
                .frame(width: canvasW, height: (ys.last ?? 0) - Self.gap + 14, alignment: .topLeading)
                .padding(.top, 14)
            }
            if !lane.quiet.isEmpty || open.contains(project.id) {
                quietRow(project, ids: lane.quiet, byID: byID, opened: open.contains(project.id))
                    .padding(.top, 12)
                    .padding(.leading, Self.x0)
            }
        }
    }

    private func projectRow(_ project: TowerProject, count: Int) -> some View {
        HStack(spacing: 14) {
            Text(project.name).font(.display(28))
            Text("\(count)").font(.mono(10)).tracking(0.8).foregroundStyle(Palette.Blue.fg3)
            if let main = project.main { mainPill(main) }
            Rectangle().fill(Palette.white.opacity(0.35)).frame(height: 1)
        }
    }

    /// ◆ 本体はプロジェクトの見出し行に置く（木の根は本体の子から始まる）
    private func mainPill(_ main: WsTile) -> some View {
        let wait = main.state == .wait
        return HStack(spacing: 10) {
            InkLoader(status: main.act, pitch: 1.6, color: wait ? Palette.blue : Palette.white)
            Text("◆ " + (main.branch ?? "HEAD")).font(.mono(13)).tracking(0.3)
            Text("本体 · " + (main.rows.isEmpty ? "エージェントなし"
                                : "\(main.rows.count) 体 " + (wait ? ActWords.jp["wait"]! : main.state.jp)))
                .font(.bodyJP(12))
            if wait { Blink(size: 8) }
        }
        .foregroundStyle(wait ? Palette.blue : Palette.white)
        .padding(.leading, 14).padding(.trailing, 22)
        .frame(height: 36)
        .background(wait ? Palette.white : Color.clear)
        .overlay(Rectangle().strokeBorder(Palette.white, lineWidth: 2))
        .overlay(Rectangle().stroke(focus == main.id ? Palette.white : .clear, lineWidth: 2).padding(-5))
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture { onEnter(main) }
        .onHover { hover = $0 ? "@" + main.id : nil }
    }

    private func edges(_ lane: TowerLane, ys: [CGFloat], byID: [String: WsTile]) -> some View {
        // 線は先に組んでおく（Canvas の中は主アクタの外）
        let pos = Dictionary(uniqueKeysWithValues: lane.placed.map { ($0.id, $0) })
        func mid(_ p: TowerLane.Placed) -> CGFloat { top(p.row, ys: ys, lane: lane) + Self.h / 2 }
        func hot(_ id: String) -> Bool { byID[id].map { isHot($0) } ?? false }
        var lines: [(path: Path, lit: Bool, dashed: Bool)] = []
        for edge in lane.edges {
            guard let from = pos[edge.from] else { continue }
            let sx = xOf(from.depth) + Self.w, ex = xOf(from.depth + 1), bx = sx + (ex - sx) / 2
            for id in edge.to {
                guard let to = pos[id] else { continue }
                var path = Path()
                path.move(to: CGPoint(x: sx, y: mid(from)))
                path.addLine(to: CGPoint(x: bx, y: mid(from)))
                path.addLine(to: CGPoint(x: bx, y: mid(to)))
                path.addLine(to: CGPoint(x: ex, y: mid(to)))
                lines.append((path, hover == nil || (hot(id) && hot(edge.from)), edge.toRace))
            }
        }
        // 本体（見出し行）から降りる背骨
        for placed in lane.placed where placed.depth == 0 {
            var path = Path()
            path.move(to: CGPoint(x: 10, y: -14))
            path.addLine(to: CGPoint(x: 10, y: mid(placed)))
            path.addLine(to: CGPoint(x: Self.x0, y: mid(placed)))
            lines.append((path, hover == nil, false))
        }
        return Canvas { ctx, _ in
            for line in lines {
                ctx.stroke(line.path, with: .color(Color.white.opacity(line.lit ? 0.9 : 0.25)),
                           style: StrokeStyle(lineWidth: 2, dash: line.dashed ? [5, 4] : []))
            }
        }
        .allowsHitTesting(false)
    }

    private func raceFrame(_ race: TowerLane.Race, ys: [CGFloat], lane: TowerLane, byID: [String: WsTile]) -> some View {
        let members = race.members.compactMap { byID[$0] }
        let y0 = ys[race.firstRow]
        let height = ys[race.lastRow] - y0 + (lane.raceRows.contains(race.lastRow) && race.lastRow != race.firstRow ? Self.raceH : 0) + Self.h + 8
        let hot = members.first.map(isHot) ?? false
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(Palette.white, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            HStack(spacing: 8) {
                Text("⑂ RACE").font(.mono(11)).tracking(Palette.caps(11))
                Text("同じ指示 ×\(members.count)").font(.bodyJP(12)).opacity(0.85)
                Spacer(minLength: 0)
                Button { if let first = members.first { onAct(.pick, first) } } label: {
                    Text("採る ▸").font(.mono(10)).tracking(1)
                        .foregroundStyle(Palette.blue)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Palette.white)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 8).padding(.top, 5)
        }
        .frame(width: Self.w + 16, height: height)
        .opacity(hover != nil && !hot ? 0.3 : 1)
        .offset(x: xOf(race.depth) - 8, y: y0)
        .onHover { hover = $0 ? members.first?.task : nil }
    }

    private func quietRow(_ project: TowerProject, ids: [String], byID: [String: WsTile], opened: Bool) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Button {
                if opened { open.remove(project.id) } else { open.insert(project.id) }
            } label: {
                HStack(spacing: 8) {
                    Text(opened ? "▾ 畳む" : "▸ 静か \(ids.count)").font(.mono(11)).tracking(Palette.caps(11))
                    if !opened { Text("待機・既読の完了").font(.bodyJP(11)) }
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .overlay(Rectangle().strokeBorder(Palette.white, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .buttonStyle(PressStyle())
            if !opened {
                ForEach(ids, id: \.self) { id in
                    if let tile = byID[id] {
                        Text(tile.name).font(.mono(12)).tracking(0.2)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .overlay(Rectangle().strokeBorder(Palette.Blue.fg3, lineWidth: 1))
                            .overlay(Rectangle().stroke(focus == id || isHot(tile) && hover != nil ? Palette.white : .clear,
                                                        lineWidth: 2).padding(-3))
                            .opacity(hover != nil && !isHot(tile) ? 0.3 : 0.85)
                            .contentShape(Rectangle())
                            .onTapGesture { onEnter(tile) }
                            .onHover { hover = $0 ? (tile.task.isEmpty ? "@" + id : tile.task) : nil }
                    }
                }
            }
        }
        .foregroundStyle(Palette.white)
    }

    // MARK: 寸法

    private func xOf(_ depth: Int) -> CGFloat { Self.x0 + CGFloat(depth) * Self.cw }

    private func top(_ row: Int, ys: [CGFloat], lane: TowerLane) -> CGFloat {
        guard ys.indices.contains(row) else { return 0 }
        return ys[row] + (lane.raceRows.contains(row) ? Self.raceH : 0)
    }

    private func isHot(_ tile: WsTile) -> Bool {
        guard let hover else { return false }
        return hover == "@" + tile.id || (!tile.task.isEmpty && hover == tile.task)
    }

    private func dimmed(_ tile: WsTile) -> Bool { hover != nil && !isHot(tile) }
}

/// 262×100 の1枚。あなた待ちだけ白い面で揺れる
private struct TowerNode: View {
    let tile: WsTile
    let focused: Bool
    let dim: Bool
    let onAct: (TileAction, WsTile) -> Void
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let wait = tile.state == .wait
        let ink = wait ? Palette.blue : Palette.white
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                InkLoader(status: tile.act, pitch: 2.8, color: ink)
                if wait { Blink(size: 7) }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(tile.name).font(.mono(16)).tracking(0.16).fontWeight(tile.unread ? .bold : .regular)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if tile.unread && !wait { Rectangle().fill(Palette.white).frame(width: 7, height: 7) }
                    menu(ink: ink)
                }
                .frame(height: 20)
                Text(tile.task.isEmpty ? " " : tile.task).font(.bodyJP(13)).lineLimit(1)
                    .frame(height: 22, alignment: .bottom)
                HStack(spacing: 8) {
                    Text(statusText).font(.bodyJP(12)).fontWeight(wait || tile.state == .fail ? .bold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let stat = tile.stat, stat.added + stat.removed > 0 {
                        Text("+\(stat.added) −\(stat.removed)").font(.mono(11)).opacity(0.8)
                    }
                }
                .frame(height: 20)
                Text(tile.failed ?? tile.agentsLine).font(.mono(10)).tracking(0.4).opacity(0.7)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(height: 16, alignment: .bottom)
            }
        }
        .foregroundStyle(ink)
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
        .frame(width: TowerScreen.w, height: TowerScreen.h, alignment: .topLeading)
        .background(wait ? Palette.white : Palette.blue)
        .overlay(Rectangle().strokeBorder(border, lineWidth: tile.state == .fail ? 2 : 1))
        .overlay(Rectangle().stroke(focused ? Palette.white : .clear, lineWidth: 2).padding(-5))
        .modifier(Shake(trigger: wait ? 1 : 0))
        .opacity(dim ? 0.28 : 1)
        .contentShape(Rectangle())
        .help(tile.last.isEmpty ? tile.name : tile.last)
    }

    private var border: Color {
        switch tile.state {
        case .wait: .clear
        case .fail, .work: Palette.white
        default: Palette.Blue.fg3
        }
    }

    private var statusText: String {
        if tile.creating { return "作成中" }
        if tile.failed != nil { return "失敗 · ⋯ で再試行か閉じる" }
        return tile.state == .work || tile.state == .wait ? (ActWords.jp[tile.act] ?? tile.state.jp) : tile.state.jp
    }

    @ViewBuilder
    private func menu(ink: Color) -> some View {
        // `--shot` の ImageRenderer は Menu を組めず禁止の印で焼くので、字だけ置く
        if frozen != nil {
            Text("⋯").font(.mono(12)).foregroundStyle(ink).padding(.horizontal, 4)
        } else {
            menuButton(ink: ink)
        }
    }

    private func menuButton(ink: Color) -> some View {
        Menu {
            Button("ここから生やす") { onAct(.branch, tile) }
            Button("Terminal で開く") { onAct(.terminal, tile) }
            if tile.failed != nil { Button("再試行") { onAct(.retry, tile) } }
            if tile.race != nil { Button("採る · 競走の勝者に") { onAct(.pick, tile) } }
            if !tile.isMain { Button(tile.failed != nil ? "閉じる" : "消す") { onAct(.delete, tile) } }
            if tile.isMain { Button("登録を外す") { onAct(.forget, tile) } }
        } label: {
            Text("⋯").font(.mono(12)).foregroundStyle(ink).padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// ピンクの点滅（`steps(1)` 1.2s）
struct Blink: View {
    var size: CGFloat = 8
    var color: Color = Palette.pink
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        Ticker(fps: 4) { now in
            Rectangle().fill(color).frame(width: size, height: size)
                .opacity(frozen != nil || now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.6 ? 1 : 0)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 管制塔の右列

/// 上の枠＝止まっている門（ワークスペースごとに1枚、2枚まで＋「ほか N」）、下の枠＝同じ指示で走っているもの
struct TowerSide: View {
    let stops: [TowerStop]
    let projects: [TowerProject]
    let height: CGFloat
    @Binding var hover: String?
    let onAnswer: (Stop, Gate.Verdict) -> Void
    let onEnter: (String, String?) -> Void
    /// 活動フィード（全 worktree の出来事・新しい順）と、押した時に開く会話
    var activity: [Cockpit.Activity] = []
    var onOpenSession: (String) -> Void = { _ in }

    @State private var all = false
    @State private var feed = false

    var body: some View {
        let lower = max(260, height - 406)
        VStack(alignment: .leading, spacing: 14) {
            gates.frame(height: lower - 76 - 14, alignment: .top)
            instructions.frame(height: height - 60 - lower)
        }
        .frame(width: 352)
    }

    // MARK: 門

    private var gates: some View {
        let groups = Dictionary(grouping: stops, by: \.workspace).values
            .map { $0.sorted { $0.stop.since < $1.stop.since } }
            .sorted { $0[0].stop.since < $1[0].stop.since }
        return VStack(spacing: 10) {
            if groups.isEmpty {
                Text("止まっている門はありません")
                    .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Palette.Light.bg)
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            ForEach(Array(groups.prefix(groups.count > 2 ? 1 : 2).enumerated()), id: \.offset) { _, group in
                gateWindow(group)
            }
            if groups.count > 2 { moreWindow(Array(groups.dropFirst())) }
        }
        .foregroundStyle(Palette.Light.fg)
    }

    private func gateWindow(_ group: [TowerStop]) -> some View {
        let first = group[0]
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("00").foregroundStyle(Palette.pink)
                Text("// GATE")
                Text("門").font(.brush(13)).tracking(0)
                Text("· " + first.name).tracking(0.4).lineLimit(1)
                Spacer(minLength: 0)
                Blink(size: 6)
                Ticker(fps: 1) { now in Text("\(Int(max(0, now.timeIntervalSince(first.stop.since))))s") }
                    .foregroundStyle(Palette.Light.fg2)
            }
            .font(.mono(10)).tracking(Palette.caps(10))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
            TowerGateCard(item: first, more: group.count - 1, hot: hover == "@" + first.workspace,
                          onAnswer: onAnswer, onEnter: onEnter)
        }
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
        .onHover { hover = $0 ? "@" + first.workspace : nil }
    }

    private func moreWindow(_ groups: [[TowerStop]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("00").foregroundStyle(Palette.pink)
                Text("// GATES")
                Spacer(minLength: 0)
                Text("ほか \(groups.count)")
            }
            .font(.mono(10)).tracking(Palette.caps(10))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
            LiveScroll {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        let item = group[0]
                        HStack(spacing: 10) {
                            Blink(size: 6)
                            Text(item.name).font(.mono(12)).tracking(0.2)
                            Text(item.stop.title).font(.display(17)).lineLimit(1)
                            Spacer(minLength: 0)
                            Ticker(fps: 1) { now in Text("\(Int(max(0, now.timeIntervalSince(item.stop.since))))s") }
                                .font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(hover == "@" + item.workspace ? Palette.hover : .clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                        .contentShape(Rectangle())
                        .onTapGesture { onEnter(item.workspace, item.stop.id) }
                        .onHover { hover = $0 ? "@" + item.workspace : nil }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
    }

    // MARK: 同じ指示

    private var instructions: some View {
        let tiles = projects.flatMap(\.tiles).filter { !$0.task.isEmpty }
        let groups = Dictionary(grouping: tiles, by: \.task)
            .map { (task: $0.key, tiles: $0.value) }
            .filter { all || $0.tiles.count > 1 }
            .sorted { (Set($0.tiles.map(\.project)).count, $0.tiles.count) > (Set($1.tiles.map(\.project)).count, $1.tiles.count) }
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 0) { Text("00").foregroundStyle(Palette.pink); Text(feed ? "// ACTIVITY" : "// INSTRUCTIONS") }
                    .font(.mono(10)).tracking(Palette.caps(10))
                Button("同じ指示") { feed = false }.buttonStyle(.plain).font(.brush(14)).opacity(feed ? 0.4 : 1)
                Button("活動") { feed = true }.buttonStyle(.plain).font(.brush(14)).opacity(feed ? 1 : 0.4)
                Spacer(minLength: 0)
                if !feed {
                    Button(all ? "重なりだけ" : "全部") { all.toggle() }
                        .buttonStyle(.plain)
                        .font(.mono(10)).tracking(0.8).foregroundStyle(Palette.Light.fg2)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
            if feed {
                LiveScroll {
                    VStack(spacing: 0) {
                        ForEach(activity.prefix(80)) { a in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(a.at.formatted(.dateTime.hour().minute())).font(.mono(10)).foregroundStyle(Palette.Light.fg3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.title).font(.bodyJP(12)).lineLimit(1)
                                    Text(a.text).font(.bodyJP(11)).foregroundStyle(Palette.Light.fg2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenSession(a.session) }
                            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                        }
                        if activity.isEmpty {
                            Text("まだ何も起きていない").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        }
                    }
                }
            } else {
            LiveScroll {
                VStack(spacing: 0) {
                    ForEach(groups, id: \.task) { group in instruction(group.task, group.tiles) }
                    if groups.isEmpty {
                        Text(all ? "指示はまだない" : "同じ指示で走っているものはない")
                            .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    }
                }
            }
            }
            Text(feed ? "押すとその会話へ · 終わった・止まった・訊いている・失敗した" : "⑂ 同じ枝から競走 · ⇄ 別のプロジェクトでも")
                .font(.mono(10)).tracking(0.8).foregroundStyle(Palette.Light.fg2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 7, leading: 14, bottom: 9, trailing: 14))
                .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        }
        .foregroundStyle(Palette.Light.fg)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
    }

    private func instruction(_ task: String, _ tiles: [WsTile]) -> some View {
        let hot = hover == task
        let projectCount = Set(tiles.map(\.project)).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(task).font(.bodyJP(14)).lineLimit(2)
                Spacer(minLength: 0)
                if tiles.count > 1 {
                    Text("\(projectCount > 1 ? "⇄" : "⑂") ×\(tiles.count)").font(.mono(11)).tracking(0.6)
                }
            }
            if tiles.count > 1 {
                ForEach(tiles) { tile in
                    HStack(spacing: 8) {
                        InkLoader(status: tile.act, pitch: 1.2, color: hot ? Palette.white : Palette.blue)
                        if projectCount > 1 { Text(tile.project + " /").opacity(0.7) }
                        Text(tile.name)
                        Spacer(minLength: 0)
                        Text(tile.state.jp).font(.bodyJP(11)).opacity(0.8)
                    }
                    .font(.mono(11)).tracking(0.2)
                    .contentShape(Rectangle())
                    .onTapGesture { onEnter(tile.id, nil) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .foregroundStyle(hot ? Palette.white : Palette.blue)
        .background(hot ? Palette.blue : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        .onHover { hover = $0 ? task : nil }
    }
}

/// 管制塔で止まっている1件と、それが属するワークスペース
struct TowerStop {
    let stop: Stop
    let workspace: String
    let name: String
}

/// 門の窓の中身。押すとそのワークスペースのカードへ、1 許可 / 書き換え ▸ / 却下
private struct TowerGateCard: View {
    let item: TowerStop
    let more: Int
    let hot: Bool
    let onAnswer: (Stop, Gate.Verdict) -> Void
    let onEnter: (String, String?) -> Void

    var body: some View {
        let stop = item.stop
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(stop.meta).lineLimit(1)
                    Spacer(minLength: 0)
                    if more > 0 { Text("ほか \(more)") }
                }
                .font(.mono(10)).tracking(0.4).foregroundStyle(Palette.Light.fg2)
                Text(stop.title).font(.display(24)).lineLimit(1)
                Text(stop.inputLine).font(.mono(12)).lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.hover)
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: 12))
            .contentShape(Rectangle())
            .onTapGesture { onEnter(item.workspace, stop.id) }
            HStack(spacing: 0) {
                answer("1 許可", filled: true) { onAnswer(stop, .allow) }
                if stop.canRevise { answer("書き換え ▸", filled: false) { onEnter(item.workspace, stop.id) } }
                answer("却下", filled: false) { onAnswer(stop, .deny) }
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
        }
        .background(hot ? Palette.hover : Palette.Light.bg)
    }

    private func answer(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.mono(11)).tracking(1.1)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .foregroundStyle(filled ? Palette.white : Palette.blue)
                .background(filled ? Palette.blue : Color.clear)
                .overlay(alignment: .leading) { filled ? nil : Rectangle().fill(Palette.Light.fg).frame(width: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// 縦の ScrollView。`--shot` の時は ImageRenderer が中身を組まないので、素の VStack を上から切って出す
struct LiveScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        if frozen != nil {
            Color.clear
                .overlay(alignment: .topLeading) { content().fixedSize(horizontal: false, vertical: true) }
                .clipped()
        } else {
            ScrollView { content() }.scrollIndicators(.never)
        }
    }
}
