import SwiftUI

// MARK: - 03 SPARRING の状態

/// worktree ごとの壁打ち。会話そのものは読むだけのセッション（plan モード）の transcript から読み、
/// ここが持つのは「どの会話か・採った・決めた・答えた」の印だけ。**UserDefaults に残す**——
/// 以前はメモリだけで、アプリを閉じるたびに壁打ちが消えていた。開き直したら会話は transcript から読み直す
@MainActor @Observable
final class SparModel {
    struct Step: Equatable, Codable {
        var text: String
        var ok: Bool
        /// 司令塔が計画（TaskCreate）に積んだのを確かめた
        var planned = false
    }
    struct Decision: Equatable, Codable {
        let text: String
        let why: String
        let source: String
        let at: Date
        /// 問いに答えて決めたもの。取り消すとその問いが未決に戻る
        let question: String?
    }
    struct Board: Codable {
        var session: String?
        var mode = Sparring.Mode.propose
        /// 壁打ちのセッションを起こす前に選んだモデルとエフォート（起こした後はセッションの値を見る）
        var model = ""
        var effort = ""
        var steps: [Step] = []
        var decisions: [Decision] = []
        var taken: Set<String> = []
        var answered: Set<String> = []
        /// 05 PLAN に送って、司令塔が積むのを待っている手順と、送った時のタスク数（残さない）
        var sending: (steps: [String], base: Int)?

        private enum CodingKeys: String, CodingKey {
            case session, mode, model, effort, steps, decisions, taken, answered
        }
    }

    private static let key = "sparBoards"

    var boards: [String: Board] = SparModel.restore() {
        didSet { Self.save(boards) }
    }

    private static func restore() -> [String: Board] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let boards = try? JSONDecoder().decode([String: Board].self, from: data) else { return [:] }
        return boards
    }

    private static func save(_ boards: [String: Board]) {
        if let data = try? JSONEncoder().encode(boards) { UserDefaults.standard.set(data, forKey: key) }
    }
    var fresh: Int?

    func board(_ ws: String) -> Board { boards[ws] ?? Board() }
}

/// 計画を練る場所。案を採ると右の暫定プランに積まれ、合意したものだけ 05 PLAN（司令塔の TaskCreate）へ送る。書込はしない
struct SparScreen: View {
    let cockpit: Cockpit
    let model: SparModel
    let workspace: String?
    let lead: String?
    let width: CGFloat
    let height: CGFloat
    let fly: (CGRect?, CGRect?) -> Void
    let rects: [String: CGRect]

    @State private var draft = ""
    @State private var problem: String?
    @Environment(\.frozenTime) private var frozen

    private var ws: String { workspace ?? "" }
    private var board: SparModel.Board { model.board(ws) }

    var body: some View {
        let entries = log
        let lastReply = entries.last { if case .reply = $0.kind { return true } else { return false } }?.id
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                LiveScroll {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionMark(number: "03", title: "SPARRING", jp: "壁打ち")
                            Text("Shape the plan before anyone writes.").font(.display(52)).lineLimit(2)
                                .minimumScaleFactor(0.6)
                            Text("Claude と計画を練る場所です。案を採ると右の暫定プランに積まれ、合意したものだけ 05 PLAN に送ります。書込はしません。")
                                .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        if workspace == nil {
                            Text("管制塔で worktree を選ぶと、そこで壁打ちできます。").font(.bodyJP(14))
                        }
                        ForEach(entries) { entry in
                            switch entry.kind {
                            case let .me(text): MeBubble(text: text)
                            case let .reply(reply): replyCard(entry.id, reply, last: entry.id == lastReply)
                            }
                        }
                        if let s = board.session, cockpit.isWorking(s) {
                            HStack(spacing: 12) {
                                InkLoader(status: "think", pitch: 2)
                                Text("考えています").font(.bodyJP(14))
                                Text(board.mode.en).font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg3)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .overlay(Rectangle().strokeBorder(Palette.Light.fg, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        }
                        if let problem { Text(problem).font(.bodyJP(13)).foregroundStyle(Palette.Light.danger) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(EdgeInsets(top: 12, leading: 0, bottom: 20, trailing: 16))
                    .frame(width: width, alignment: .leading)
                }
                .onChange(of: entries.count) { proxy.scrollTo("end", anchor: .bottom) }
            }
            // 会話の箱は 72〜702（900 の時）、その下に型と入力
            .frame(height: height - 270)
            input.padding(.top, 10)
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
        // 開き直した後: 覚えておいた壁打ちの会話を transcript から読み直す（選択中の会話は動かさない）
        .task(id: workspace) {
            guard frozen == nil, let ws = workspace, let s = model.board(ws).session else { return }
            await cockpit.adoptSparring(s, cwd: ws)
        }
    }

    // MARK: 会話

    struct Entry: Identifiable {
        enum Kind { case me(String), reply(Sparring.Reply) }
        let id: Int
        let kind: Kind
    }

    /// 壁打ちのセッションの発言。人の側は送った約束事を外して、打った言葉だけ見せる
    private var log: [Entry] {
        guard let s = board.session else { return [] }
        return cockpit.messages.filter { $0.session == s && !$0.thinking }.map { m in
            if m.speaker == .human {
                var t = m.text
                if t.hasPrefix("[壁打ち"), let close = t.firstIndex(of: "]") { t = String(t[t.index(after: close)...]) }
                if let cut = t.range(of: "\n\n") { t = String(t[..<cut.lowerBound]) }
                return Entry(id: m.id, kind: .me(t.trimmingCharacters(in: .whitespaces)))
            }
            return Entry(id: m.id, kind: .reply(Sparring.parse(m.text)))
        }
    }

    /// - Parameter last: いちばん新しい返事。訊きたいことが無ければ、ここに「次に」の札を出す
    private func replyCard(_ id: Int, _ reply: Sparring.Reply, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SPAR // THINK → REPLY").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
                Text(reply.body).font(.bodyJP(15)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
            ForEach(Array(reply.proposals.enumerated()), id: \.offset) { i, p in
                // 案の文で覚える（返事の通し番号はアプリを開くたびに変わる）
                let key = (p.kind == .step ? "S:" : "D:") + p.text
                let taken = board.taken.contains(key)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.kind == .step ? "STEP" : "DECIDE").font(.mono(9)).tracking(1.1)
                        Text(p.kind == .step ? "手順" : "決定").font(.bodyJP(11))
                    }
                    .foregroundStyle(Palette.Light.fg2).frame(width: 68, alignment: .leading)
                    Text(p.text).font(.bodyJP(14)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if taken {
                        Text("採った ✓").font(.mono(10)).tracking(1).padding(.horizontal, 10)
                    } else {
                        Button(p.kind == .step ? "暫定プランに採る ▸" : "決めたことに ▸") { take(key, p) }
                            .buttonStyle(SumiButtonStyle(primary: true, size: 10))
                            .reportRect("prop:\(key)")
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
                .opacity(taken ? 0.45 : 1)
                .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            }
            // 簡易な質問の札。訊きたいことがあればその選択肢、無ければ（最新の返事にだけ）次の型
            if let q = reply.question {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("? 訊きたい").font(.mono(10)).tracking(1.2)
                        Text(q.text).font(.bodyJP(14)).fixedSize(horizontal: false, vertical: true)
                    }
                    if board.answered.contains(q.text) {
                        Text("決めた ✓").font(.mono(10)).tracking(1)
                    } else {
                        ChipRow(items: q.options.map { ("", $0) }, onTap: { answer(q, q.options[$0]) })
                    }
                }
                .modifier(AskStrip())
            } else if last, !busy {
                VStack(alignment: .leading, spacing: 8) {
                    Text("▸ 次に").font(.mono(10)).tracking(1.2)
                    SparModeChips(mode: nil, onPick: { next($0) })
                }
                .modifier(AskStrip())
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
    }

    private var input: some View {
        // 型の札（SparModeChips）は本人の指示（2026-10-03）で外した。部品は後で使うので下に残してある
        VStack(alignment: .trailing, spacing: 8) {
            Text("読むだけ · 書込なし").font(.mono(9)).tracking(1).foregroundStyle(Palette.Light.fg3)
            HStack(spacing: 0) {
                sparPicker.padding(.horizontal, 14)
                Group {
                    if frozen != nil {
                        Text("相談したいこと — 空のまま送ると案を出します").foregroundStyle(Palette.Light.fg3)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("相談したいこと — 空のまま送ると案を出します", text: $draft)
                            .textFieldStyle(.plain).lineLimit(1).onSubmit(send)
                    }
                }
                .font(.bodyJP(16))
                Button(action: send) {
                    Text("送る ↵").font(.mono(11)).tracking(0.9).foregroundStyle(Palette.Light.bg)
                        .padding(.horizontal, 22).frame(maxHeight: .infinity).background(Palette.Light.fg)
                }
                .buttonStyle(PressStyle())
                .disabled(workspace == nil)
            }
            .frame(height: 48)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
        }
    }

    // MARK: 操作

    private var busy: Bool { board.session.map { cockpit.isWorking($0) } ?? false }

    /// 壁打ちのモデルとエフォート。起こした後はそのセッションに、起こす前は板に覚えておく
    private var sparPicker: some View {
        let b = board
        if let s = b.session, cockpit.liveSessions.contains(where: { $0.id == s }) {
            return ModelPicker(backend: .claude, models: cockpit.models(.claude),
                               model: cockpit.model(of: s) ?? "", effort: cockpit.effort(of: s) ?? "",
                               onModel: { cockpit.setModel($0, for: s) }, onEffort: { cockpit.setEffort($0, for: s) })
        }
        return ModelPicker(backend: .claude, models: cockpit.models(.claude), model: b.model, effort: b.effort,
                           onModel: { model.boards[ws, default: .init()].model = $0 },
                           onEffort: { model.boards[ws, default: .init()].effort = $0 })
    }

    /// 「次に」の札から: 文は空のまま、その型で送る
    private func next(_ mode: Sparring.Mode) {
        model.boards[ws, default: .init()].mode = mode
        draft = ""
        send()
    }

    private func send() {
        guard let workspace else { return }
        let b = board
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = Sparring.prompt(text, mode: b.mode, decided: b.decisions.map(\.text))
        problem = nil
        if let s = b.session, cockpit.liveSessions.contains(where: { $0.id == s }) {
            guard cockpit.send(prompt, to: s) else { problem = "いまは送れません（前の返事を待っています）"; return }
        } else {
            guard let s = cockpit.launchSparring(prompt: prompt, cwd: workspace, model: b.model, effort: b.effort) else {
                problem = cockpit.launchError ?? "壁打ちのセッションを起こせませんでした"
                return
            }
            model.boards[workspace, default: .init()].session = s
        }
        draft = ""
    }

    private func take(_ key: String, _ p: Sparring.Proposal) {
        let from = rects["prop:\(key)"]
        model.boards[ws, default: .init()].taken.insert(key)
        switch p.kind {
        case .step:
            model.boards[ws, default: .init()].steps.append(.init(text: p.text, ok: false))
            let n = board.steps.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fly(from, rects["draft:\(n)"]) }
        case .decide:
            decide(.init(text: p.text, why: p.why, source: "SPAR · " + board.mode.en, at: Date(), question: nil), from: from)
        }
    }

    private func answer(_ q: Sparring.Question, _ option: String) {
        model.boards[ws, default: .init()].answered.insert(q.text)
        let t = q.text.trimmingCharacters(in: CharacterSet(charactersIn: "？? ")) + " → " + option
        decide(.init(text: t, why: "あなたが選択", source: "YOU", at: Date(), question: q.text), from: nil)
    }

    private func decide(_ d: SparModel.Decision, from: CGRect?) {
        model.boards[ws, default: .init()].decisions.append(d)
        let n = board.decisions.count - 1
        model.fresh = n
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fly(from, rects["dec:\(n)"]) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { if model.fresh == n { model.fresh = nil } }
    }
}

/// 壁打ちの型の札（PROPOSE 案を出して / OBJECT 反論して / BREAK DOWN 分解して / DECIDE 決めて）。
/// 入力欄の上からは外し（2026-10-03）、返事の下の「次に」の札として使う
struct SparModeChips: View {
    /// 選ばれている型（無ければどれも白抜き）
    var mode: Sparring.Mode?
    let onPick: (Sparring.Mode) -> Void

    var body: some View {
        let modes = Sparring.Mode.allCases
        ChipRow(items: modes.map { ($0.en, $0.jp) }, selected: mode.flatMap { modes.firstIndex(of: $0) },
                onTap: { onPick(modes[$0]) })
    }
}

/// 札の並び（英字の小見出し＋和文）。壁打ちの型・問いの選択肢が同じ見た目を使う
struct ChipRow: View {
    let items: [(en: String, jp: String)]
    var selected: Int? = nil
    let onTap: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let on = selected == i
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !item.en.isEmpty { Text(item.en).font(.mono(10)).tracking(1) }
                    Text(item.jp).font(.bodyJP(12))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
                .background(on ? Palette.Light.fg : Palette.Light.bg)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { onTap(i) }
            }
        }
    }
}

/// 返事の下の札の帯（点線の上罫・淡い地）
private struct AskStrip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.Light.bg2)
            .overlay(alignment: .top) {
                Rectangle().stroke(Palette.Light.fg, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
            }
    }
}

/// 自分の発言（左に尖った黒い札）
struct MeBubble: View {
    let text: String
    var body: some View {
        Text(text).font(.bodyJP(15)).foregroundStyle(Palette.Light.bg)
            .padding(EdgeInsets(top: 11, leading: 32, bottom: 12, trailing: 18))
            .background(LeftPoint().fill(Palette.Light.fg))
            .frame(maxWidth: 560, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private struct LeftPoint: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r.minX + 18, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + 18, y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.closeSubpath()
            }
        }
    }
}

/// SPARRING の右列。上＝暫定プラン（□ 暫定 · ■ 合意 → 05 PLAN に送る）、下＝未決の問いと決定事項（HANDOFF に書く）
struct SparPanels: View {
    let cockpit: Cockpit
    let model: SparModel
    let workspace: String?
    let lead: String?
    let height: CGFloat
    let onLaunch: (String) -> Void
    let fly: (CGRect?, CGRect?) -> Void
    let rects: [String: CGRect]

    @State private var note: String?

    private var ws: String { workspace ?? "" }

    var body: some View {
        let b = model.board(ws)
        let agreed = b.steps.filter { $0.ok && !$0.planned }
        let planned = lead.map { cockpit.allTasks(session: $0).count } ?? 0
        let working = cockpit.isWorking(lead)
        let lower = max(260, height - 406)
        VStack(spacing: 14) {
            SumiPanel(number: "03", title: "PROVISIONAL", jp: "暫定プラン", right: "合意 \(agreed.count) / \(b.steps.count)") {
                ForEach(Array(b.steps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 6) {
                        Text(s.planned ? "✓" : s.ok ? "■" : "□").font(.mono(14)).frame(width: 22)
                            .onTapGesture { if !s.planned { model.boards[ws]?.steps[i].ok.toggle() } }
                        Text("#\(i + 1)").font(.mono(11)).frame(width: 30, alignment: .leading)
                        Text(s.text).font(.bodyJP(13)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("⑂") { onLaunch(s.text) }.buttonStyle(.plain).font(.mono(11))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .overlay(Rectangle().strokeBorder(s.ok ? Palette.white : Palette.blue, lineWidth: 1))
                            .help("この手順で worktree を立ち上げる")
                        Button("×") { model.boards[ws]?.steps.remove(at: i) }.buttonStyle(.plain).font(.mono(11))
                            .padding(.horizontal, 6)
                    }
                    .padding(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 10))
                    .foregroundStyle(s.ok && !s.planned ? Palette.white : Palette.blue)
                    .background(s.ok && !s.planned ? Palette.blue : .clear)
                    .opacity(s.planned ? 0.5 : 1)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                    .reportRect("draft:\(i)")
                }
                if b.steps.isEmpty {
                    Text("まだ何もありません。会話の案を「暫定プランに採る」で積みます。").font(.bodyJP(13))
                        .foregroundStyle(Palette.Light.fg2).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                HStack(spacing: 8) {
                    if b.sending != nil {
                        InkLoader(status: "transfer", pitch: 1.4)
                        Text("司令塔が積むのを待っています")
                    } else {
                        Text(note ?? "□ 暫定 · ■ 合意 · ✓ 積んだ")
                    }
                    Spacer(minLength: 0)
                    Button("05 PLAN に送る ▸") { toPlan(agreed.map(\.text), base: planned) }
                        .buttonStyle(.plain)
                        .foregroundStyle(agreed.isEmpty ? Palette.Light.fg3 : Palette.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(agreed.isEmpty ? .clear : Palette.blue)
                        .overlay(Rectangle().strokeBorder(agreed.isEmpty ? Palette.Light.line : Palette.blue, lineWidth: 1))
                        .disabled(agreed.isEmpty || b.sending != nil)
                        .reportRect("toPlan")
                }
            }
            .frame(height: lower - 76 - 14)
            decisions(b).frame(height: height - 60 - lower)
        }
        .frame(width: 352)
        // 司令塔が TaskCreate で積んだら確定。ドットを PLAN へ飛ばし、手順に ✓ を付ける
        .onChange(of: planned) { confirmPlan(count: planned, working: working) }
        .onChange(of: working) { confirmPlan(count: planned, working: working) }
    }

    private func decisions(_ b: SparModel.Board) -> some View {
        let open = openQuestions(b)
        return SumiPanel(number: "03", title: "DECISIONS", jp: "決定事項", right: "未決 \(open.count) · 決定 \(b.decisions.count)") {
            ForEach(open, id: \.text) { q in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("?").font(.mono(11))
                        Text(q.text).font(.bodyJP(13)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(q.options, id: \.self) { o in
                            Button(o) { answer(q, o) }.buttonStyle(.plain).font(.bodyJP(12))
                                .foregroundStyle(Palette.white).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Palette.blue)
                        }
                    }
                    .padding(.leading, 18)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.hover)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.blue).frame(height: 1) }
            }
            ForEach(Array(b.decisions.enumerated()), id: \.offset) { i, d in
                let fresh = model.fresh == i
                HStack(alignment: .top, spacing: 8) {
                    Text("✓").font(.mono(12)).frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.text).font(.bodyJP(13)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Text(d.why).font(.bodyJP(11))
                            Spacer(minLength: 0)
                            Text(d.source + " · " + d.at.formatted(.dateTime.hour().minute())).font(.mono(9))
                        }
                        .opacity(0.75)
                    }
                    Button("↺") { undo(i) }.buttonStyle(.plain).font(.mono(10)).opacity(0.7).help("取り消して未決に戻す")
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(fresh ? Palette.white : Palette.blue)
                .background(fresh ? Palette.blue : .clear)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                .reportRect("dec:\(i)")
            }
            if open.isEmpty && b.decisions.isEmpty {
                Text("まだ決めたことはありません。").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            HStack {
                Text("決定は次の壁打ちに前提として渡ります")
                Spacer(minLength: 0)
                Button("HANDOFF に書く ▸") { writeHandoff(b.decisions) }.buttonStyle(.plain).underline()
                    .disabled(b.decisions.isEmpty)
            }
        }
    }

    /// 返事の問いのうち、まだ答えていないもの（同じ問いは1つにまとめる）
    private func openQuestions(_ b: SparModel.Board) -> [Sparring.Question] {
        guard let s = b.session else { return [] }
        var seen = Set<String>()
        return cockpit.messages.filter { $0.session == s && $0.speaker == .model && !$0.thinking }
            .compactMap { Sparring.parse($0.text).question }
            .filter { !b.answered.contains($0.text) && seen.insert($0.text).inserted }
    }

    private func answer(_ q: Sparring.Question, _ option: String) {
        model.boards[ws, default: .init()].answered.insert(q.text)
        let t = q.text.trimmingCharacters(in: CharacterSet(charactersIn: "？? ")) + " → " + option
        model.boards[ws, default: .init()].decisions.append(.init(text: t, why: "あなたが選択", source: "YOU", at: Date(), question: q.text))
    }

    private func undo(_ i: Int) {
        guard let d = model.boards[ws]?.decisions[i] else { return }
        model.boards[ws]?.decisions.remove(at: i)
        if let q = d.question { model.boards[ws]?.answered.remove(q) }
    }

    /// 合意した手順を司令塔に渡し、TaskCreate で計画に積んでもらう（05 PLAN はそれを読む）。
    /// ここではまだ確定させない——積まれたのを見てから `confirmPlan` がドットを飛ばす
    private func toPlan(_ steps: [String], base: Int) {
        guard !steps.isEmpty else { return }
        guard let lead, cockpit.canSend(to: lead), cockpit.send(Sparring.planMessage(steps), to: lead) else {
            flash("司令塔に送れません（会話のセッションがありません）")
            return
        }
        model.boards[ws, default: .init()].sending = (steps, base)
    }

    /// 送った手順の数だけタスクが増えたら確定。増えたが足りないまま司令塔が手を止めた時も、増えた分で確定する。
    /// 1つも積まずに止まったら、積まなかったと伝えて手順は暫定のまま戻す
    private func confirmPlan(count: Int, working: Bool) {
        guard let sending = model.board(ws).sending else { return }
        let added = count - sending.base
        if added >= sending.steps.count || (added > 0 && !working) {
            model.boards[ws]?.sending = nil
            for i in model.board(ws).steps.indices where sending.steps.contains(model.board(ws).steps[i].text) {
                model.boards[ws]?.steps[i].planned = true
            }
            fly(rects["toPlan"], rects["planTicks"])
            flash("05 PLAN に \(added) 件積まれました")
        } else if !working && added <= 0 {
            model.boards[ws]?.sending = nil
            flash("司令塔は計画に積みませんでした（返事は 01 TALK に）")
        }
    }

    private func writeHandoff(_ decided: [SparModel.Decision]) {
        guard let workspace else { return }
        let (result, file) = cockpit.appendHandoff(Sparring.handoff(decided.map { ($0.text, $0.why) }, at: Date()),
                                                   cwd: workspace)
        flash(result == .saved ? "\(file) に書きました" : "書けませんでした（外で書き換えられたかも）")
    }

    private func flash(_ text: String) {
        note = text
        Task { try? await Task.sleep(for: .seconds(2.4)); if note == text { note = nil } }
    }
}
