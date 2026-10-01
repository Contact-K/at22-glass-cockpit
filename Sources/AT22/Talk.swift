import SwiftUI

// MARK: - 01 // TALK

/// 01 // TALK。大見出し・会話ログ・門のカード・処理中の箱・入力欄。
///
/// 会話には**言葉と「呼び出した」と「門にこう答えた」を時刻順に混ぜる**——
/// 別々の一覧にすると、どの発言の流れで誰を呼んだのかが読めなくなる
struct Talk: View {
    let cockpit: Cockpit
    let stage: Stage
    let width: CGFloat
    let height: CGFloat

    @AppStorage("showThinking") private var showThinking = false
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @Environment(\.sumiFixedTime) private var fixedTime
    @Environment(\.openSettings) private var openSettings
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    /// 会話の1件
    private enum Entry: Identifiable {
        case said(Message, trail: String, refs: [String])
        case called(Cockpit.AgentCall)
        case verdict(VerdictLine)

        var id: String {
            switch self {
            case let .said(m, _, _): "m\(m.id)"
            case let .called(c): "c" + c.id
            case let .verdict(v): "v" + v.id.uuidString
            }
        }
        var at: Date {
            switch self {
            case let .said(m, _, _): m.at
            case let .called(c): c.at
            case let .verdict(v): v.at
            }
        }
    }

    var body: some View {
        let session = cockpit.selectedSession
        VStack(alignment: .leading, spacing: 10) {
            if session == nil {
                header(headline: Cockpit.headline(rows: [], hasSession: false), sub: "まだ会話を選んでいません。")
                emptyState
                Spacer(minLength: 0)
            } else {
                log
                    .frame(width: width, height: max(200, height - 270))
                input
                    .frame(width: width)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    // MARK: 見出し

    private func header(headline: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(no: "01", en: "TALK", jp: "会話")
            Text(headline)
                .font(Palette.display(52))
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(Palette.bodyJP(15))
                .foregroundStyle(Palette.Light.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8).padding(.bottom, 12)
    }

    private var subtitle: String {
        let tasks = cockpit.allTasks(session: cockpit.selectedSession)
        if let now = tasks.first(where: { $0.status == .inProgress }) {
            return "▸\(now.number) \(now.subject) — 司令塔とのやり取りと、止まった指示はここに流れます。"
        }
        let title = cockpit.selectedSession.flatMap { cockpit.title(for: $0) } ?? ""
        return (title.isEmpty ? "" : "▸ \(title) — ") + "司令塔とのやり取りと、止まった指示はここに流れます。"
    }

    // MARK: ログ

    private var entries: [Entry] {
        let session = cockpit.selectedSession
        let all = cockpit.messages.filter { $0.session == session }
        // 返答の頭（C0 // SEARCH → THINK → REPLY）は、直前の人の発言からこの返答までに起きたことで決める。
        // ponytail: ファイルは「最後に触った時刻」でしか引けないので、同じファイルを何度も触った時は最後の1回で数える
        let cells = cockpit.snapshot(now: Date(), mode: .work).cards.flatMap(\.files)
        var out: [Entry] = []
        var since = Date.distantPast
        var thought = false
        for m in all {
            if m.speaker == .human { since = m.at; thought = false; out.append(.said(m, trail: "", refs: [])); continue }
            if m.thinking {
                thought = true
                if showThinking { out.append(.said(m, trail: "C0 // THINK", refs: [])) }
                continue
            }
            let touched = cells.filter { $0.lastAt > since && $0.lastAt <= m.at }
            let wrote = touched.contains { ($0.lastWriteAt ?? .distantPast) > since }
            let read = touched.contains { $0.reads > 0 }
            let agent = m.agent == m.session ? "C0" : String(m.agent.prefix(6)).uppercased()
            out.append(.said(m, trail: Cockpit.turnTrail(agent: agent, read: read, thought: thought, wrote: wrote),
                             refs: Array(touched.prefix(3).map(\.name))))
            since = m.at
            thought = false
        }
        out += cockpit.agentCalls(session: session).map(Entry.called)
        out += stage.verdicts.map(Entry.verdict)
        return out.sorted { $0.at < $1.at }
    }

    @ViewBuilder
    private var log: some View {
        let items = entries
        let lastModel = items.last(where: Talk.isReply)?.id
        if fixedTime != nil {
            // ImageRenderer は ScrollView の中身を組まない。焼く時は末尾だけを素の VStack で
            VStack(alignment: .leading, spacing: 14) {
                header(headline: headline, sub: subtitle)
                ForEach(items.suffix(6)) { row($0, lastModel: lastModel) }
                tail
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header(headline: headline, sub: subtitle)
                        ForEach(items.suffix(300)) { row($0, lastModel: lastModel).id($0.id) }
                        tail
                        Color.clear.frame(height: 20).id("end")
                    }
                    .padding(.trailing, 16)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom)
                .onChange(of: items.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: cockpit.gates.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: stage.rewriting) { proxy.scrollTo("end", anchor: .bottom) }
                // 返答が届いたら、鶴から返答の枠へドットが渡る
                .onChange(of: lastModel) { _, new in
                    guard new != nil else { return }
                    let st = stage
                    st.after(0.12) { st.fly(from: "crane", to: "c0-last") }
                }
            }
        }
    }

    private static func isReply(_ entry: Entry) -> Bool {
        if case let .said(m, _, _) = entry { return m.speaker == .model && !m.thinking }
        return false
    }

    private var headline: String {
        let snap = cockpit.snapshot(now: Date(), mode: .work)
        let rows = Cockpit.actionRows(chips: snap.chips, gates: snap.gates, now: Date()).rows
        return Cockpit.headline(rows: rows, hasSession: true)
    }

    @ViewBuilder
    private var tail: some View {
        if let gate = stage.currentGate { GateCard(cockpit: cockpit, stage: stage, gate: gate) }
        if cockpit.isWorking(cockpit.selectedSession) { BusyBox(cockpit: cockpit) }
    }

    @ViewBuilder
    private func row(_ entry: Entry, lastModel: String?) -> some View {
        switch entry {
        case let .said(m, trail, refs):
            if m.speaker == .human {
                Text(m.text)
                    .font(Palette.bodyJP(15)).lineSpacing(15 * 0.6)
                    .foregroundStyle(Palette.white)
                    .textSelection(.enabled)
                    .padding(.leading, 32).padding(.trailing, 18).padding(.vertical, 11)
                    .background(Plate(leftTip: 18).fill(Palette.Light.fg))
                    .frame(maxWidth: 560, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                let box = VStack(alignment: .leading, spacing: 10) {
                    Text(trail).caps(10, tracking: 0.1).foregroundStyle(Palette.Light.fg2)
                    Text(m.text.isEmpty ? AttributedString("（本文は残っていない。考えた時刻だけ分かる）")
                                        : Talk.formatted(m.text))
                        .font(Palette.bodyJP(15)).lineSpacing(15 * 0.8)
                        .foregroundStyle(m.thinking ? Palette.Light.fg3 : Palette.Light.fg)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !refs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(refs, id: \.self) { ref in
                                Text("参照 · \(ref)").font(Palette.bodyJP(12))
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .overlay(Rectangle().stroke(Palette.Light.line, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: 680, alignment: .leading)
                .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 2))
                if entry.id == lastModel { box.sumiAnchor(stage, "c0-last") } else { box }
            }
        case let .called(call):
            let finished = cockpit.callFinished(call.id)
            ruleLine("CALL // \(call.type.isEmpty ? "AGENT" : call.type.uppercased()) → \(call.title)",
                     trailing: finished == nil ? "起動" : (finished! ? "終了" : "実行中"))
        case let .verdict(v):
            ruleLine("GATE // \(v.gate) → \(v.verdict)", trailing: "")
        }
    }

    /// 細い罫に乗せた1行（呼び出しと門の答え）
    private func ruleLine(_ text: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.Light.fg).frame(width: 40, height: 1)
            Text(text).caps(10, tracking: 0.12).foregroundStyle(Palette.Light.fg2).lineLimit(1)
            Rectangle().fill(Palette.Light.line).frame(height: 1)
            if !trailing.isEmpty { Text(trailing).font(Palette.bodyJP(11)).foregroundStyle(Palette.Light.fg3) }
        }
    }

    // MARK: 入力

    private var working: Bool { cockpit.isWorking(cockpit.selectedSession) }
    private var alarm: Bool { cockpit.reading.stage == .warning }

    private var input: some View {
        VStack(alignment: .leading, spacing: 6) {
            if stage.sendFailed, let reason = cockpit.launchError {
                Text(reason).font(Palette.bodyJP(12)).foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 0) {
                Text("// ASK C0").caps(10, tracking: 0.1).foregroundStyle(Palette.Light.fg2)
                    .padding(.horizontal, 14)
                if fixedTime != nil {
                    Text(placeholder).font(Palette.bodyJP(16)).foregroundStyle(Palette.Light.fg3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: $draft)
                        .textFieldStyle(.plain)
                        .font(Palette.bodyJP(16))
                        .focused($inputFocused)
                        .onSubmit(send)
                        .onExitCommand { inputFocused = false }
                }
                Button(action: { working ? interrupt() : send() }) {
                    Text(working ? "止める ■" : "送る ↵")
                        .caps(11, tracking: 0.08)
                        .foregroundStyle(Palette.white)
                        .padding(.horizontal, 22)
                        .frame(maxHeight: .infinity)
                        .background(Palette.Light.fg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressNudge())
                .keyboardShortcut(.return, modifiers: .command)
                .help(working ? "生成を止める（セッションは終わらない）" : "送る（Return / ⌘Return）")
            }
            .frame(height: 48)
            .background(Palette.white)
            .overlay(Rectangle().stroke(alarm ? Palette.danger : Palette.Light.fg, lineWidth: 2))
        }
    }

    private var placeholder: String { working ? "考えています…" : "司令塔に聞く" }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if cockpit.send(draft, to: cockpit.selectedSession) {
            draft = ""
            stage.sendFailed = false
        } else {
            stage.sendFailed = true
        }
    }

    private func interrupt() {
        stage.sendFailed = !cockpit.interrupt(cockpit.selectedSession)
    }

    // MARK: 未選択

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SumiButton(title: "Sessions 過去の回") { stage.sessionsOpen = true }
                SumiButton(title: "New 新しい回", variant: .secondary) {
                    if launcherEnabled, cockpit.claude != nil || cockpit.codexFound != nil {
                        stage.newSessionOpen = true
                    } else {
                        openSettings()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cockpit.liveSessions.prefix(4)) { s in
                    SessionRow(title: cockpit.title(for: s.id) ?? s.name,
                               sub: (s.cwd as NSString).lastPathComponent, live: s.busy) {
                        cockpit.selectedSession = s.id
                    }
                }
                ForEach(cockpit.recentSessions.prefix(6)) { s in
                    SessionRow(title: cockpit.title(for: s.id) ?? s.project,
                               sub: s.project + " · " + s.modifiedAt.formatted(.dateTime.month().day().hour().minute()),
                               live: false) {
                        Task {
                            cockpit.selectedSession = s.id
                            await cockpit.loadSession(s)
                        }
                    }
                }
            }
            Text("M でメニュー → Sparring ▸ Sessions からも選べます。")
                .font(Palette.bodyJP(12)).foregroundStyle(Palette.Light.fg3)
        }
    }

    /// Markdown を解釈しつつ改行を保つ（旧 `AgentDetail.formatted`）。
    /// ponytail: 見出しの大きさや表組みまでは再現しない。Text 1つで済ませるための割り切り
    nonisolated static func formatted(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }
}

/// 節番号の型: ピンクの `01` ＋ `// TALK` ＋ 青柳の小さな和名
struct SectionLabel: View {
    let no: String
    let en: String
    let jp: String
    var onBlue = false

    var body: some View {
        HStack(spacing: 10) {
            Text(no).foregroundStyle(Palette.pink)
            Text("// \(en)").foregroundStyle(onBlue ? Palette.white : Palette.Light.fg2)
            Text(jp).font(Palette.brush(14)).tracking(0)
                .foregroundStyle(onBlue ? Palette.white : Palette.Light.fg)
        }
        .caps(11)
    }
}

/// セッションの1行（未選択の画面と Sessions のモーダルで共用）
struct SessionRow: View {
    let title: String
    let sub: String
    let live: Bool
    var selected = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle().fill(live ? Palette.pink : Palette.Light.line).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Palette.bodyJP(14)).lineLimit(1)
                    Text(sub).caps(9, tracking: 0.1).foregroundStyle(Palette.Light.fg3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .background(hover || selected ? Palette.Light.hover : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.Light.fg)
        .onHover { hover = $0 }
    }
}

// MARK: - 門のカード

/// C0 // GATE。許可・書換・却下がここで完結する。**答えを書けなかった時は必ずカードに出す**——
/// 黙って消すと司令塔は答えが来ないまま待ち続ける
struct GateCard: View {
    let cockpit: Cockpit
    let stage: Stage
    let gate: Gate.Request

    @Environment(\.sumiFixedTime) private var fixedTime

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SumiClock(fps: 1) { now in
                HStack(spacing: 10) {
                    Blink(period: 1.2) { Rectangle().fill(Palette.pink).frame(width: 8, height: 8) }
                    Text("C0 // GATE")
                    Text("門").font(Palette.brush(14)).tracking(0)
                    Text("· \(target)").lineLimit(1)
                    Spacer(minLength: 0)
                    Text("WAIT \(Int(gate.waited(now: now)))s")
                }
                .caps(10, tracking: 0.12)
                .foregroundStyle(Palette.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Palette.Light.fg)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Wake G1?").font(Palette.display(40))
                Text(Cockpit.plainLine(gate.instruction))
                    .font(Palette.bodyJP(14)).lineSpacing(14 * 0.6).lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta).caps(10, tracking: 0.08).foregroundStyle(Palette.Light.fg2)
                if stage.gateFailed == gate.id {
                    Text("答えを書けなかった。司令塔は待ったままなので、置き場を直してもう一度")
                        .font(Palette.bodyJP(12)).foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            if stage.rewriting { rewrite } else { choices }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .background(Palette.white)
        .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 2))
        .offset(stage.cardNudge)
    }

    private var target: String { gate.to.isEmpty ? gate.call : gate.to }
    private var meta: String {
        var parts: [String] = []
        if !gate.risk.isEmpty { parts.append(gate.risk.uppercased()) }
        parts.append(cockpit.gateLevel.permissionMode)
        parts.append("→ \(target)")
        return parts.joined(separator: " · ")
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                choice(0, "Allow", "許可して起動")
                choice(1, "Rewrite", "書き換えて発行")
                choice(2, "Reject", "却下")
            }
            .padding(.leading, 20).padding(.trailing, 22).padding(.top, 12).padding(.bottom, 8)
            Text("←→ 選ぶ · ENTER 決定 · 1–3 · ⇧⌘G 許可")
                .caps(9, tracking: 0.12).foregroundStyle(Palette.Light.fg3)
                .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    private func choice(_ i: Int, _ en: String, _ jp: String) -> some View {
        let on = stage.hc == i
        return Button { stage.choose(i) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(i + 1)").caps(10, tracking: 0.1)
                Text(en).font(Palette.display(on ? 30 : 24))
                    .foregroundStyle(on ? Palette.white : Palette.Light.fg)
                Text(jp).font(Palette.bodyJP(11))
            }
            .foregroundStyle(on ? Palette.white : Palette.Light.fg2)
            .padding(.leading, 14).padding(.trailing, 18).padding(.top, 9).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Plate(tip: on ? 14 : 0, skew: -18).fill(on ? Palette.Light.fg : Palette.white)
                    Plate(tip: on ? 14 : 0, skew: -18).stroke(on ? Palette.Light.fg : Palette.Light.line, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressNudge())
        .offset(y: on ? -2 : 0)
        .opacity(stage.crumble == i ? 0 : 1)
        .onHover { if $0 { stage.hc = i } }
        .sumiAnchor(stage, "gate-btn-\(i)")
    }

    private var rewrite: some View {
        VStack(alignment: .leading, spacing: 8) {
            if fixedTime != nil {
                Text(stage.revised).font(Palette.bodyJP(14))
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(Palette.Light.bg2)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
            } else {
                TextField("書き換えた指示", text: Binding(get: { stage.revised }, set: { stage.revised = $0 }),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Palette.bodyJP(14))
                    .lineLimit(1...5)
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .background(Palette.Light.bg2)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                    .onSubmit { stage.issueRewrite() }
            }
            HStack(spacing: 8) {
                SumiButton(title: "書き換えて発行 ↵",
                           disabled: stage.revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    stage.issueRewrite()
                }
                .sumiAnchor(stage, "gate-btn-rw")
                SumiButton(title: "戻る", variant: .secondary) { stage.rewriting = false }
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
    }
}

/// 点滅（`steps(1)`）。半周期ごとに出る／消える
struct Blink<Content: View>: View {
    var period: Double = 1.2
    @ViewBuilder var content: () -> Content

    var body: some View {
        SumiClock(fps: 2 / period * 2) { now in
            content().opacity(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) < period / 2 ? 1 : 0)
        }
    }
}

// MARK: - 処理中の箱

/// 破線の箱。いまの段（THINK → REPLY）と、書いている途中の文の末尾を出す
struct BusyBox: View {
    let cockpit: Cockpit

    @State private var since = Date()

    var body: some View {
        let replying = !cockpit.streaming.isEmpty
        let steps = ["THINK", "REPLY"], now = replying ? 1 : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(0..<steps.count, id: \.self) { k in
                    if k > 0 {
                        Rectangle().fill(k <= now ? Palette.Light.fg : Palette.Light.line).frame(width: 18, height: 1)
                    }
                    HStack(spacing: 6) {
                        if k == now {
                            Blink(period: 0.6) { Rectangle().fill(Palette.Light.fg).frame(width: 6, height: 6) }
                        }
                        Text(steps[k])
                    }
                    .caps(10, tracking: 0)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(k < now ? Palette.white : (k == now ? Palette.Light.fg : Palette.Light.fg3))
                    .background(k < now ? Palette.Light.fg : .clear)
                    .overlay(Rectangle().stroke(k <= now ? Palette.Light.fg : Palette.Light.line, lineWidth: 1))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(replying ? "返します" : "考えています").font(Palette.bodyJP(15))
                Text("STEP \(now + 1) / \(steps.count)").font(Palette.mono(10)).foregroundStyle(Palette.Light.fg3)
            }
            if replying {
                Text(String(cockpit.streaming.suffix(200)))
                    .font(Palette.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SumiClock(fps: 8) { date in
                let filled = Int(date.timeIntervalSince(since) * 4) % 13
                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { k in
                        Rectangle().fill(k < filled ? Palette.Light.fg : Palette.Light.bg3).frame(height: 4)
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: 680, alignment: .leading)
        .overlay(Rectangle().stroke(Palette.Light.fg, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}
