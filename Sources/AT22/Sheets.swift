import SwiftUI

// MARK: - 新規ワークスペース（斜線の板・6段）

/// 全面の青い板。斜線（286→578）から外へドットが育って覆い（ピンク → 白 → 青）、
/// 左に段（リポジトリ・分岐元・名前・エージェント・最初の指示・承認の段）を斜線に沿って並べ、右で今の段を編む。
/// エージェントを2体以上選ぶと競走（同じ指示で別々の worktree を作り、管制塔で1組に束ねる）
struct NewWorkspaceSheet: View {
    let cockpit: Cockpit
    let projects: [TowerProject]
    /// 分岐元の初期値（タイルの ⋯「ここから生やす」・会話中の worktree）
    let from: String?
    var prompt0 = ""
    let launcherReady: Bool
    let onClose: () -> Void
    let onCreated: () -> Void
    let onOpenSettings: () -> Void

    struct Pick: Hashable {
        let backend: Backend
        let model: String
    }

    @State private var repo = ""
    @State private var fromID = ""
    @State private var name = "new-task"
    @State private var picks: [Pick] = [Pick(backend: .claude, model: "opus")]
    @State private var prompt = ""
    @State private var level = Gate.defaultLevel
    @State private var step = 0
    @State private var org: Backend = .claude
    @State private var opened = Date()
    @State private var closing: Date?
    @State private var full = false
    @Environment(\.frozenTime) private var frozen

    private static let tan18 = CGFloat(tan(18 * Double.pi / 180))
    private static let steps = [("01", "Repository", "リポジトリ"), ("02", "Branch from", "分岐元"), ("03", "Name", "名前"),
                                ("04", "Agents", "エージェント"), ("05", "Prompt", "最初の指示"), ("06", "Approval", "承認の段")]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if full || frozen != nil {
                    Palette.blue
                    if closing == nil { sheet(size: geo.size) }
                } else {
                    Color.clear
                }
                SlashDots(opened: opened, closing: closing, onCovered: { full = true })
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: seed)
        .onKeyPress(phases: .down) { press in key(press) }
    }

    // MARK: 中身

    private func sheet(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 286, y: 0))
                p.addLine(to: CGPoint(x: 286 + size.height * Self.tan18, y: size.height))
            }
            .stroke(Palette.white, lineWidth: 3)
            HStack(spacing: 16) {
                Text("N // NEW WORKSPACE").font(.mono(10)).tracking(Palette.caps(10))
                    .foregroundStyle(Palette.blue).padding(.horizontal, 10).padding(.vertical, 6).background(Palette.white)
                Text("新規ワークスペース").font(.brush(14))
                Text("↑↓ 段 · ENTER 次へ · ⌘↵ 立ち上げ · ESC やめる").font(.mono(9)).tracking(1.1)
                    .foregroundStyle(Palette.Blue.fg3)
            }
            .offset(x: 310, y: 24)
            Button(action: close) {
                Text("[×] CLOSE · ESC").font(.mono(11)).tracking(1.1)
                    .padding(.horizontal, 14).frame(height: 36)
                    .overlay(Rectangle().strokeBorder(Palette.white, lineWidth: 1))
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 40).offset(y: 18)

            ForEach(Self.steps.indices, id: \.self) { i in
                let y = 110 + CGFloat(i) * 96
                stepPlate(i)
                    .onTapGesture { step = i }
                    .offset(x: 286 + (y + 30) * Self.tan18 + 28, y: y)
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Self.steps[step].0 + " //").foregroundStyle(Palette.pink)
                    Text(Self.steps[step].1.uppercased())
                }
                .font(.mono(12)).tracking(1.6)
                editor
            }
            .frame(width: min(520, size.width - 920), alignment: .topLeading)
            .offset(x: size.width - 560, y: 110)
            .id(step)

            footer(size: size)
                .frame(width: size.width - (size.width - 560) - 40)
                .offset(x: size.width - 560, y: size.height - 56 - 100)
        }
        .foregroundStyle(Palette.white)
    }

    private func stepPlate(_ i: Int) -> some View {
        let on = i == step
        let (n, en, jp) = Self.steps[i]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(n).font(.mono(12)).tracking(1.2).foregroundStyle(on ? Palette.pink : Palette.white)
                Text(en).font(.display(32))
                Text(jp).font(.brush(13))
            }
            Text(value(i)).font(.mono(12)).tracking(0.2).opacity(on ? 0.8 : 0.65)
                .lineLimit(1).truncationMode(.tail).padding(.leading, 38)
        }
        .foregroundStyle(on ? Palette.blue : Palette.white)
        .padding(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 50))
        .frame(width: 360, alignment: .leading)
        .background { if on { Chevron(head: 28).fill(Palette.white) } }
        .contentShape(Rectangle())
    }

    private func value(_ i: Int) -> String {
        switch i {
        case 0: return projectName
        case 1: return fromTile.map { ($0.isMain ? "◆ " : "") + ($0.branch ?? $0.name) } ?? "HEAD"
        case 2: return names.map(Worktree.branch(for:)).joined(separator: " · ")
        case 3: return picks.map { "\($0.backend.title) \($0.model)" }.joined(separator: " · ") + (picks.count > 1 ? " — 競走" : "")
        case 4: return Cockpit.plainLine(prompt)
        default: return level.title
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(projects) { p in
                    bigPlate(on: repo == p.id) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(p.name).font(.display(44))
                            Text("\(p.tiles.count) WORKTREES").font(.mono(11)).tracking(0.9)
                        }
                    }
                    .onTapGesture {
                        repo = p.id
                        fromID = p.main?.id ?? p.tiles.first?.id ?? ""
                    }
                }
                if projects.isEmpty {
                    Text("リポジトリがまだ無い。管制塔にプロジェクトが並ぶと選べる。").font(.bodyJP(14))
                }
            }
        case 1:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(repoTiles) { t in
                    let on = fromID == t.id
                    HStack(spacing: 10) {
                        Text(t.isMain ? "◆" : "└").font(.mono(12)).opacity(0.6).frame(width: 14)
                        Text(t.isMain ? (t.branch ?? "HEAD") : t.name).font(.mono(16)).tracking(0.3)
                        Spacer(minLength: 0)
                        Text(t.state.jp).font(.bodyJP(12)).opacity(0.8)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 12)
                    .padding(.leading, t.isMain ? 0 : 26)
                    .foregroundStyle(on ? Palette.blue : Palette.white)
                    .background(on ? Palette.white : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.white.opacity(0.2)).frame(height: 1) }
                    .contentShape(Rectangle())
                    .onTapGesture { fromID = t.id }
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                if frozen != nil {
                    Text(name).font(.mono(40))
                } else {
                    TextField("", text: $name).textFieldStyle(.plain).font(.mono(40))
                        .onChange(of: name) { name = name.replacingOccurrences(of: " ", with: "-") }
                        .onSubmit { step = 3 }
                }
                Rectangle().fill(Palette.white).frame(height: 3)
                ForEach(names, id: \.self) { n in
                    HStack(spacing: 10) {
                        Text("branch").opacity(0.6)
                        Text(Worktree.branch(for: n))
                        Text("← " + (fromTile?.branch ?? "HEAD")).opacity(0.6)
                    }
                    .font(.mono(14)).tracking(0.3)
                }
                Text("名前はそのまま枝の名前になります。2体以上選ぶと -claude -grok が付きます。")
                    .font(.bodyJP(13)).opacity(0.8)
            }
        case 3:
            agentsEditor
        case 4:
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if frozen != nil {
                        Text(prompt).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        TextEditor(text: $prompt).scrollContentBackground(.hidden)
                    }
                }
                .font(.bodyJP(17)).foregroundStyle(Palette.blue)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(height: 240)
                .background(Palette.white)
                Text("⌘↵ で立ち上げ。空のままだと worktree だけ作って、エージェントは起こさない。")
                    .font(.bodyJP(12)).opacity(0.8)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                ForEach([Gate.Level.each, .normal, .auto, .unattended], id: \.self) { l in
                    bigPlate(on: level == l) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(String(l.title.prefix { $0 != " " }).uppercased()).font(.mono(14)).tracking(1.1)
                            Text(String(l.title.drop { $0 != " " }.dropFirst())).font(.display(34))
                            Text(Self.levelNote[l] ?? "").font(.bodyJP(13))
                        }
                    }
                    .onTapGesture { level = l }
                }
            }
        }
    }

    private static let levelNote: [Gate.Level: String] = [
        .each: "道具はすべて訊く", .normal: "書き込みと実行を訊く", .auto: "門だけ訊く", .unattended: "何も訊かない",
    ]

    /// プロバイダ → モデルの2段。左でプロバイダを選び、右でモデルを足し外し
    private var agentsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(picks.count > 1 ? "⑂ RACE ×\(picks.count)" : "1 体").font(.mono(10)).tracking(1.2).opacity(0.75)
                ForEach(Array(picks.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", i + 1)).foregroundStyle(Palette.pink)
                        Text(p.backend.title).font(.mono(13))
                        Text(p.model).font(.mono(11)).foregroundStyle(Palette.Light.fg2)
                    }
                    .font(.mono(10))
                    .foregroundStyle(Palette.blue)
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(Palette.white)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Backend.allCases, id: \.self) { b in
                        let on = org == b
                        HStack(spacing: 10) {
                            Text(b.title).font(.display(24))
                            Spacer(minLength: 0)
                            let n = picks.filter { $0.backend == b }.count
                            if n > 0 { Text("\(n)").font(.mono(10)).padding(.horizontal, 6).overlay(Rectangle().stroke(lineWidth: 1)) }
                            Text("▸").font(.mono(11)).opacity(on ? 1 : 0.4)
                        }
                        .foregroundStyle(on ? Palette.blue : Palette.white)
                        .padding(.leading, 12).padding(.trailing, 30)
                        .frame(height: 44)
                        .background { if on { Chevron(head: 16).fill(Palette.white) } }
                        .contentShape(Rectangle())
                        .onTapGesture { org = b }
                    }
                }
                .frame(width: 200)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(org.title).font(.display(30))
                        Text(cockpit.found[org] == nil ? "見つからない" : org.isACP ? "ACP · 書換なし" : "")
                            .font(.mono(10)).tracking(1).opacity(0.7)
                    }
                    ForEach(models(org), id: \.self) { m in
                        let on = picks.contains(Pick(backend: org, model: m))
                        HStack(spacing: 12) {
                            Text(on ? "■" : "□").font(.mono(13))
                            Text(m.isEmpty ? "既定" : m).font(.mono(15))
                            Spacer(minLength: 0)
                            Text(on ? "選択中 · 外す" : "足す").font(.mono(9)).tracking(1).opacity(0.7)
                        }
                        .foregroundStyle(on ? Palette.blue : Palette.white)
                        .padding(.horizontal, 12).frame(height: 38)
                        .background(on ? Palette.white : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(Pick(backend: org, model: m)) }
                    }
                }
                .padding(.leading, 22)
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.white.opacity(0.5)).frame(height: 1) }
            Text(picks.count > 1 ? "同じ指示で \(picks.count) 本の worktree を作り、管制塔で 1 組に束ねます。"
                                 : "2 体以上選ぶと競走。同じエージェントをモデル違いで並べることもできます。")
                .font(.bodyJP(13)).opacity(0.85)
        }
    }

    private func bigPlate<C: View>(on: Bool, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .foregroundStyle(on ? Palette.blue : Palette.white)
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 40))
            .background(Chevron(head: 22).fill(on ? Palette.white : Palette.white.opacity(0.12)))
            .contentShape(Rectangle())
    }

    private func footer(size: CGSize) -> some View {
        VStack(alignment: .trailing, spacing: 14) {
            Rectangle().fill(Palette.white.opacity(0.5)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(names.map(Worktree.branch(for:)).joined(separator: " · ") + " ← " + (fromTile?.branch ?? "HEAD"))
                    .font(.mono(12)).lineLimit(1)
                Text(picks.map(\.backend.title).joined(separator: " · ") + " · " + level.title + " · " + Cockpit.plainLine(prompt))
                    .font(.bodyJP(12)).opacity(0.8).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                if !launcherReady {
                    Button("設定で連携を入にする", action: onOpenSettings).buttonStyle(.plain)
                        .font(.mono(10)).tracking(1).underline()
                }
                Button("やめる", action: close).buttonStyle(.plain).font(.mono(11)).tracking(1.1)
                if step < 5 {
                    Button("このまま立ち上げ ⌘↵", action: launch).buttonStyle(.plain)
                        .font(.mono(11)).tracking(1.1).underline().disabled(!canLaunch)
                }
                Button { step < 5 ? (step += 1) : launch() } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if step < 5 {
                            Text(Self.steps[step + 1].0).font(.mono(11)).foregroundStyle(Palette.pink)
                            Text(Self.steps[step + 1].1).font(.display(26))
                            Text(Self.steps[step + 1].2).font(.brush(14))
                            Text("ENTER ▸").font(.mono(10)).tracking(1)
                        } else {
                            Text("Launch").font(.display(26))
                            Text("立ち上げる").font(.brush(14))
                            Text((picks.count > 1 ? "×\(picks.count) " : "") + "↵").font(.mono(10))
                        }
                    }
                    .fixedSize()
                    .foregroundStyle(Palette.blue)
                    .padding(.leading, 20).padding(.trailing, 40).frame(height: 48)
                    .background(Chevron(head: 22).fill(Palette.white))
                }
                .buttonStyle(PressStyle())
                .disabled(step == 5 && !canLaunch)
                .opacity(step == 5 && !canLaunch ? 0.5 : 1)
            }
        }
    }

    // MARK: 値

    private var project: TowerProject? { projects.first { $0.id == repo } }
    private var projectName: String { project?.name ?? "—" }
    private var repoTiles: [WsTile] {
        let tiles = project?.tiles.filter { !$0.creating && $0.failed == nil } ?? []
        return tiles.filter(\.isMain) + tiles.filter { !$0.isMain }
    }
    private var fromTile: WsTile? { repoTiles.first { $0.id == fromID } }

    /// 競走の時は `<名前>-<相手>`、同じ相手が2体なら `-<モデル>` も足す
    private var names: [String] {
        guard picks.count > 1 else { return [name] }
        let counts = Dictionary(grouping: picks, by: \.backend).mapValues(\.count)
        return picks.map { p in
            name + "-" + p.backend.rawValue
                + ((counts[p.backend] ?? 0) > 1 ? "-" + p.model.filter { $0.isLetter || $0.isNumber } : "")
        }
    }

    private var canLaunch: Bool { launcherReady && project != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func models(_ backend: Backend) -> [String] {
        let list = ModelChoice.models(for: backend).map(\.id)
        return list.isEmpty ? [""] : list
    }

    private func toggle(_ p: Pick) {
        if let i = picks.firstIndex(of: p) {
            if picks.count > 1 { picks.remove(at: i) }
        } else {
            picks.append(p)
        }
    }

    private func seed() {
        prompt = prompt0
        let start = projects.first { p in p.tiles.contains { $0.id == from } } ?? projects.first
        repo = start?.id ?? ""
        fromID = from.flatMap { id in start?.tiles.first { $0.id == id }?.id } ?? start?.main?.id ?? ""
        opened = Date()
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape { close(); return .handled }
        if press.key == .return, press.modifiers.contains(.command) { launch(); return .handled }
        return .ignored
    }

    private func close() {
        guard closing == nil else { return }
        closing = Date()
        full = false
        Task { try? await Task.sleep(for: .seconds(SlashDots.closeTime + 0.12)); onClose() }
    }

    private func launch() {
        guard canLaunch, let project else { return }
        let base = fromTile?.branch ?? "HEAD"
        let racers = zip(names, picks).map { Cockpit.Racer(name: $0, backend: $1.backend, model: $1.model) }
        cockpit.createWorkspaces(repo: project.id, base: base, racers: racers, prompt: prompt, level: level)
        onCreated()
    }
}

/// 斜線から外へ育つドット（v11 `V11NewSlash` の canvas）。開く 320ms・閉じる 240ms、24fps。
/// 覆いきったら `onCovered`（その後ろの面が見えるようになる）
private struct SlashDots: View {
    let opened: Date
    let closing: Date?
    let onCovered: () -> Void

    static let openTime = 0.32, closeTime = 0.24
    @State private var covered = false
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        if frozen != nil || (covered && closing == nil) {
            Color.clear
        } else {
            Ticker(fps: 24) { now in
                Canvas { ctx, size in
                    let frame = 1.0 / 24
                    let start = closing.map { $0.addingTimeInterval(0.12) } ?? opened
                    let duration = closing == nil ? Self.openTime : Self.closeTime
                    let k = max(0, min(1, floor(now.timeIntervalSince(start) / frame) * frame / duration))
                    Self.draw(&ctx, size: size, p: closing == nil ? k : 1 - k)
                }
            }
            .task {
                guard closing == nil else { return }
                try? await Task.sleep(for: .seconds(Self.openTime + 0.05))
                covered = true
                onCovered()
            }
        }
    }

    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, p: Double) {
        guard p > 0 else { return }
        let pc: CGFloat = 16
        func line(_ y: CGFloat) -> CGFloat { 286 + y * 0.325 }
        let maxD = max(line(0), size.width - line(0), line(size.height), size.width - line(size.height))
        let p2 = p * 1.4
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let f = p2 - Double(abs(x + 8 - line(y + 8)) / maxD)
                let s = max(0, min(1, f / 0.4))
                if s > 0 {
                    let sz = ceil(CGFloat(s) * pc), inset = floor((pc - sz) / 2)
                    let color = f < 0.08 ? Palette.pink : f < 0.4 ? Palette.white : Palette.blue
                    ctx.fill(Path(CGRect(x: x + inset, y: y + inset, width: sz, height: sz)), with: .color(color))
                }
                x += pc
            }
            y += pc
        }
    }
}

// MARK: - 板（削除・採る）

/// 幕 `rgba(8,8,92,.8)` の上の白い板。見出しは青い帯（右端が尖る）
struct SumiSheet<Content: View>: View {
    let mark: String
    let en: String
    let jp: String
    var width: CGFloat = 620
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Palette.scrim.contentShape(Rectangle()).onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(mark + " //").foregroundStyle(Palette.pink)
                    Text(en)
                    Text(jp).font(.brush(14)).tracking(0)
                    Spacer(minLength: 0)
                    Button("[×] ESC", action: onClose).buttonStyle(.plain)
                }
                .font(.mono(11)).tracking(Palette.caps(11))
                .foregroundStyle(Palette.Light.bg)
                .padding(.leading, 20).padding(.trailing, 40)
                .frame(height: 44)
                .background(Chevron(head: 22).fill(Palette.Light.fg))
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(EdgeInsets(top: 20, leading: 24, bottom: 22, trailing: 24))
            }
            .foregroundStyle(Palette.Light.fg)
            .frame(width: width)
            .background(Palette.Light.bg)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
        }
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}

/// 削除の確認。未コミットの変更を見せ、あれば「確かめた」を押すまで消させない。枝は -d（マージ済みだけ消える）
struct DeleteSheet: View {
    let cockpit: Cockpit
    let tile: WsTile
    let onClose: () -> Void

    @State private var dirty: [String]?
    @State private var ok = false
    @State private var result: String?
    @State private var working = false

    var body: some View {
        SumiSheet(mark: "D", en: "DELETE WORKTREE", jp: "削除の確認", onClose: onClose) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delete \(tile.name)?").font(.display(34))
                Text((tile.branch ?? "切り離し") + " · " + tile.id).font(.mono(11)).tracking(0.6)
                    .foregroundStyle(Palette.Light.fg2).lineLimit(1).truncationMode(.middle)
            }
            if tile.failed != nil {
                Text("作れなかった worktree です。一覧から外すだけで、ファイルには触りません。").font(.bodyJP(14))
            } else if let dirty {
                if dirty.isEmpty {
                    Text("未コミットの変更はありません。").font(.bodyJP(14))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("UNCOMMITTED · 未コミット \(dirty.count) 件").font(.mono(10)).tracking(1.2)
                            .foregroundStyle(Palette.Light.bg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8).background(Palette.Light.fg)
                        ForEach(dirty.prefix(12), id: \.self) { path in
                            Text(path).font(.mono(12)).lineLimit(1).truncationMode(.middle)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                        }
                    }
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
                }
            } else {
                HStack(spacing: 10) { InkLoader(status: "search", pitch: 1.6); Text("未コミットの変更を数えています").font(.bodyJP(13)) }
            }
            if tile.failed == nil {
                Text("枝 \(tile.branch ?? "") はマージされていなければ残ります。消えるのは worktree のフォルダだけです。")
                    .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
            }
            if dirty?.isEmpty == false {
                HStack(spacing: 10) {
                    Rectangle().fill(ok ? Palette.Light.fg : .clear).frame(width: 18, height: 18)
                        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                    Text("未コミットの \(dirty?.count ?? 0) 件も消えることを確かめた").font(.bodyJP(14))
                }
                .contentShape(Rectangle())
                .onTapGesture { ok.toggle() }
            }
            if let result { Text(result).font(.bodyJP(13)).foregroundStyle(Palette.Light.danger) }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("やめる", action: onClose).buttonStyle(SumiButtonStyle(primary: false))
                Button(tile.failed != nil ? "外す" : dirty?.isEmpty == false ? "変更ごと消す" : "消す", action: delete)
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .disabled(working || (tile.failed == nil && (dirty == nil || (dirty?.isEmpty == false && !ok))))
            }
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1).offset(y: -16) }
        }
        .task {
            guard tile.failed == nil else { return }
            dirty = await cockpit.dirtyFiles(of: tile.id)
        }
    }

    private func delete() {
        if tile.failed != nil { cockpit.dismissPending(tile.id); onClose(); return }
        working = true
        Task {
            let note = await cockpit.deleteWorkspace(tile.id, force: dirty?.isEmpty == false, deleteBranch: true)
            working = false
            // 枝を残した旨は失敗ではない。消せなかった時だけ板に残して伝える
            if let note, note.contains("できない") || note.contains("無い") { result = note } else { onClose() }
        }
    }
}

/// 競走の勝者を採る。残す1本を選び、負けは未コミットの数を見せてから変更ごと消す
struct PickSheet: View {
    let cockpit: Cockpit
    let group: [WsTile]
    let onClose: () -> Void

    @State private var winner: String = ""
    @State private var dirty: [String: Int] = [:]
    @State private var notes: [String] = []
    @State private var working = false

    var body: some View {
        let losers = group.filter { $0.id != winner }
        SumiSheet(mark: "P", en: "PICK WINNER", jp: "採る", width: 760, onClose: onClose) {
            Text("Which one stays?").font(.display(34))
            HStack(spacing: 12) {
                ForEach(group) { t in
                    let on = t.id == winner
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(on ? "■ KEEP 残す" : "□")
                            Spacer(minLength: 0)
                            Text(t.agentsLine).lineLimit(1)
                        }
                        .font(.mono(10)).tracking(1)
                        Text(t.name).font(.mono(16))
                        Text(t.last.isEmpty ? t.task : t.last).font(.bodyJP(13)).lineLimit(2)
                        HStack(spacing: 12) {
                            if let s = t.stat { Text("+\(s.added) −\(s.removed)"); Text("\(s.files) files") }
                        }
                        .font(.mono(10)).tracking(0.6)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
                    .background(on ? Palette.Light.fg : .clear)
                    .overlay(Rectangle().strokeBorder(on ? Palette.Light.fg : Palette.Light.line, lineWidth: on ? 3 : 1))
                    .contentShape(Rectangle())
                    .onTapGesture { winner = t.id }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("消えるもの").font(.mono(10)).tracking(1.2).foregroundStyle(Palette.Light.fg2)
                ForEach(losers) { l in
                    let n = dirty[l.id]
                    Text("\(l.name) — 未コミット \(n.map(String.init) ?? "…") 件\((n ?? 0) > 0 ? "（変更ごと消えます）" : "") · 枝 \(l.branch ?? "") は残ります")
                        .font(.bodyJP(14))
                }
            }
            ForEach(notes, id: \.self) { Text($0).font(.bodyJP(13)).foregroundStyle(Palette.Light.danger) }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("やめる", action: onClose).buttonStyle(SumiButtonStyle(primary: false))
                Button("\(group.first { $0.id == winner }?.name ?? "") を採って \(losers.count) 本を消す", action: pick)
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .disabled(working || winner.isEmpty || losers.contains { dirty[$0.id] == nil })
            }
        }
        .task {
            winner = group.first?.id ?? ""
            for t in group { dirty[t.id] = await cockpit.dirtyFiles(of: t.id).count }
        }
    }

    private func pick() {
        working = true
        Task {
            let left = await cockpit.adopt(winner)
            working = false
            if left.isEmpty { onClose() } else { notes = left }
        }
    }
}
