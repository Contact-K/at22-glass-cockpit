import SwiftUI

// MARK: - 01 TALK

/// 会話。見出し → ログ（自分＝青い矢羽／C0＝2px の枠）→ 門のカード → 処理中の箱 → 入力欄。
///
/// **答える口はここ1つ。** 門のカードで許可・書換・却下が完結する。
/// 答えを書けなかった時は必ずカードに出す（`gateFailed`）——黙って消すと司令塔が待ち続ける
struct TalkScreen: View {
    let cockpit: Cockpit
    let headline: String
    let subtitle: String
    let showThinking: Bool
    let verdicts: [VerdictLine]
    @Binding var gate: GateUI
    let gateFailed: Bool
    let request: Gate.Request?
    let gateLabel: String
    let pendingGates: Int
    let trail: [(path: String, kind: TouchKind)]
    let ctxAlarm: Bool
    let height: CGFloat
    let width: CGFloat
    let onChoose: (Int) -> Void
    let onRewrite: () -> Void
    let onNew: () -> Void

    @State private var draft = ""
    @State private var failed = false
    @Environment(\.frozenTime) private var frozen

    /// 処理の段の和名（v10 の `STL`）
    static let stepLabel: [String: String] = [
        "think": "考えています", "search": "探しています", "write": "書いています", "reply": "返します",
        "transfer": "渡しています", "error": "つまずきました", "upload": "送っています",
        "wait": "承認を待っています", "handoff": "引き継いでいます", "reread": "読み返しています",
        "duplicate": "複製しています", "idle": "うたた寝しています", "done": "終わりました",
        "build": "組み立てています", "overload": "文脈があふれそうです",
    ]

    /// 画面に流す件数の上限。ponytail: 実測で1セッション数百件。数千に届いたら窓で切る
    static let maxEntries = 200

    var body: some View {
        if cockpit.selectedSession == nil {
            SessionPicker(cockpit: cockpit, width: width, onNew: onNew)
                .frame(width: width, height: height, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                log.frame(width: width, height: max(120, height - 164))
                if failed, let reason = cockpit.launchError {
                    Text(reason).font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                        .lineLimit(2)
                }
                input
            }
            .frame(width: width, alignment: .topLeading)
        }
    }

    // MARK: ログ

    @ViewBuilder
    private var log: some View {
        let items = entries
        if frozen != nil {
            // `--shot` は ScrollView の中身を焼かないので、素の VStack に積んで下端を見せる
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(items.suffix(6)) { entry in row(entry) }
                tail
            }
            .padding(.trailing, 16)
            .frame(width: width, height: max(120, height - 164), alignment: .bottomLeading)
            .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(items) { entry in row(entry).id(entry.id) }
                        tail
                        Color.clear.frame(height: 8).id(Self.bottomID)
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
                .defaultScrollAnchor(.bottom)
                .onChange(of: items.count) { scrollDown(proxy) }
                .onChange(of: request?.id) { scrollDown(proxy) }
                .onChange(of: gate.rewriting) { scrollDown(proxy) }
                .onChange(of: cockpit.isWorking(cockpit.selectedSession)) { scrollDown(proxy) }
            }
        }
    }

    private static let bottomID = "at22.bottom"

    private func scrollDown(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionMark(number: "01", title: "TALK", jp: "会話")
            Text(headline).font(.display(52)).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.Light.fg)
            Text(subtitle).font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var tail: some View {
        if let request {
            GateCard(request: request, label: gateLabel, pending: pendingGates, failed: gateFailed,
                     gate: $gate, onChoose: onChoose, onRewrite: onRewrite)
        }
        if cockpit.isWorking(cockpit.selectedSession) {
            BusyBox(trail: trail, streaming: cockpit.streaming)
        }
    }

    // MARK: 流れに載せるもの

    /// 言葉・呼び出し・門の印を時刻順に混ぜたもの。
    /// 別々の一覧にすると、どの発言の流れで誰を呼んだのかが読めなくなる
    private enum Entry: Identifiable {
        case human(Message)
        case model(Message, label: String, refs: [String])
        case call(Cockpit.AgentCall)
        case verdict(VerdictLine)

        var id: String {
            switch self {
            case let .human(m), let .model(m, _, _): "m\(m.id)"
            case let .call(c): "c" + c.id
            case let .verdict(v): "v" + v.id
            }
        }
    }

    private var entries: [Entry] {
        let session = cockpit.selectedSession
        let said = cockpit.messages.filter { $0.session == session && (showThinking || !$0.thinking) }
        let calls = cockpit.agentCalls(session: session)
        let marks = verdicts.filter { $0.session == session }

        // 司令塔の発言ごとに、その前の人の発言からの足跡を拾う（1回の走査で済ませる）
        let root = cockpit.touches.filter { $0.session == session && $0.agent == session }
        var cursor = 0
        var since = Date.distantPast
        var out: [(Date, Entry)] = []
        for message in said {
            if message.speaker == .human {
                since = message.at
                out.append((message.at, .human(message)))
                continue
            }
            while cursor < root.count, root[cursor].started < since { cursor += 1 }
            var turn: [(path: String, kind: TouchKind)] = []
            var k = cursor
            while k < root.count, root[k].started <= message.at {
                turn.append((root[k].path, root[k].kind))
                k += 1
            }
            let trail = message.thinking ? (label: "C0 // THINK", refs: [String]()) : Cockpit.turnTrail(turn)
            out.append((message.at, .model(message, label: trail.label, refs: trail.refs)))
        }
        out += calls.map { ($0.at, .call($0)) }
        out += marks.map { ($0.at, .verdict($0)) }
        return out.sorted { $0.0 < $1.0 }.suffix(Self.maxEntries).map(\.1)
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        switch entry {
        case let .human(message):
            HStack {
                Spacer(minLength: 0)
                Text(message.text)
                    .font(.bodyJP(15)).lineSpacing(15 * 0.6 - 4)
                    .foregroundStyle(Palette.Light.bg)
                    .textSelection(.enabled)
                    .padding(EdgeInsets(top: 11, leading: 32, bottom: 12, trailing: 18))
                    .background { Chevron(point: 18).fill(Palette.Light.fg) }
                    .frame(maxWidth: 560, alignment: .trailing)
            }
            .reportRect(isLastHuman(message) ? "melast" : "me:\(message.id)")
        case let .model(message, label, refs):
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
                Text(message.text.isEmpty ? AttributedString("（本文は残っていない。考えた時刻だけ分かる）")
                                          : Self.formatted(message.text))
                    .font(.bodyJP(15)).lineSpacing(15 * 0.8 - 4)
                    .foregroundStyle(message.thinking ? Palette.Light.fg3 : Palette.Light.fg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !refs.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(refs, id: \.self) { ref in
                            Text("参照 · " + ref).font(.bodyJP(12))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .overlay(Rectangle().stroke(Palette.Light.line, lineWidth: 1))
                        }
                    }
                }
            }
            .foregroundStyle(Palette.Light.fg)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: 680, alignment: .leading)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg,
                                              style: StrokeStyle(lineWidth: 2, dash: message.thinking ? [4, 3] : [])))
            .reportRect(isLastReply(message) ? "c0last" : "c0:\(message.id)")
        case let .call(call):
            let finished = cockpit.callFinished(call.id)
            rule("CALL // \(call.type.isEmpty ? "AGENT" : call.type.uppercased()) → \(call.title)",
                 tail: finished == nil ? "起動" : (finished! ? "終了" : "実行中"))
        case let .verdict(mark):
            rule(mark.text, tail: nil)
        }
    }

    /// 罫で挟んだ1行（門の印・呼び出し）
    private func rule(_ text: String, tail: String?) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.Light.fg).frame(width: 40, height: 1)
            Text(text).lineLimit(1)
            Rectangle().fill(Palette.Light.line).frame(height: 1)
            if let tail { Text(tail) }
        }
        .font(.mono(10)).tracking(1.2)
        .foregroundStyle(Palette.Light.fg2)
    }

    private func isLastReply(_ message: Message) -> Bool {
        let session = cockpit.selectedSession
        return cockpit.messages.last { $0.session == session && $0.speaker == .model && !$0.thinking }?.id == message.id
    }

    private func isLastHuman(_ message: Message) -> Bool {
        let session = cockpit.selectedSession
        return cockpit.messages.last { $0.session == session && $0.speaker == .human }?.id == message.id
    }

    /// Markdown を解釈しつつ改行を保つ。`**` や `` ` `` の記号が消えるだけで長い発言はだいぶ読める。
    /// ponytail: 見出しの大きさや表組みまでは再現しない
    nonisolated static func formatted(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }

    // MARK: 入力欄

    private var input: some View {
        let working = cockpit.isWorking(cockpit.selectedSession)
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let now = trail.last.map { $0.kind == .write ? "write" : "search" } ?? "think"
        return HStack(spacing: 0) {
            Text("// ASK C0").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
                .padding(.horizontal, 14)
            if frozen != nil {
                Text(draft.isEmpty ? "司令塔に聞く" : draft).font(.bodyJP(16)).foregroundStyle(Palette.Light.fg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(working ? (Self.stepLabel[now] ?? "") + "…" : "司令塔に聞く", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.bodyJP(16))
                    .foregroundStyle(Palette.Light.fg)
                    .onSubmit { if !working { send() } }
            }
            Button { working ? interrupt() : send() } label: {
                Text(working ? "止める ■" : "送る ↵").font(.mono(11)).tracking(0.9)
                    .foregroundStyle(Palette.Light.bg)
                    .padding(.horizontal, 22)
                    .frame(maxHeight: .infinity)
                    .background(Palette.Light.fg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!cockpit.canSend(to: cockpit.selectedSession) && !working || (!working && empty))
            .help(working ? "生成を止める（セッションは終わらない）" : "送る（Return / ⌘Return）")
        }
        .frame(height: 48)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(ctxAlarm ? Palette.Light.danger : Palette.Light.fg, lineWidth: 2))
    }

    private func send() {
        if cockpit.send(draft, to: cockpit.selectedSession) {
            draft = ""
            failed = false
        } else {
            failed = true
        }
    }

    private func interrupt() {
        if !cockpit.interrupt(cockpit.selectedSession) { failed = true }
    }
}

// MARK: - 門のカード

/// 止まっている指示1件。**複数溜まっていても出すのは待たせている順に1件だけ**——
/// 並べると「どれに答えているか」が曖昧になる
private struct GateCard: View {
    let request: Gate.Request
    let label: String
    let pending: Int
    let failed: Bool
    @Binding var gate: GateUI
    let onChoose: (Int) -> Void
    let onRewrite: () -> Void
    @Environment(\.frozenTime) private var frozen

    private static let choices = [("Allow", "許可して起動"), ("Rewrite", "書き換えて発行"), ("Reject", "却下")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar
            VStack(alignment: .leading, spacing: 6) {
                Text("Wake \(label)?").font(.display(40))
                Text(Cockpit.plainLine(request.instruction)).font(.bodyJP(14)).lineSpacing(14 * 0.6 - 4)
                    .lineLimit(4)
                Text(meta).font(.mono(10)).tracking(0.8).foregroundStyle(Palette.Light.fg2)
                if failed {
                    Text("答えを書けなかった。司令塔は待ったままなので、置き場を直してもう一度")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            if gate.rewriting { rewrite } else { choices }
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(maxWidth: 640, alignment: .leading)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
        .modifier(Shake(trigger: gate.shake))
        .background {
            // ⇧⌘G で許可。⌘Return は入力欄の「送る」が持っているので、同じ鍵にすると
            // 門に答えたつもりで割り込みが飛ぶ
            Button("") { onChoose(0) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .opacity(0)
                .disabled(gate.rewriting)
        }
    }

    private var meta: String {
        [request.risk.isEmpty ? nil : request.risk, request.by.isEmpty ? nil : String(request.by.prefix(8)),
         "→ " + (request.to.isEmpty ? request.call : request.to)].compactMap { $0 }.joined(separator: " · ")
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Ticker(fps: 4) { now in
                let on = frozen != nil || now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) < 0.6
                Rectangle().fill(Palette.pink).frame(width: 8, height: 8).opacity(on ? 1 : 0)
            }
            .frame(width: 8, height: 8)
            Text("C0 // GATE")
            Text("門").font(.brush(14)).tracking(0)
            Text("· " + (request.to.isEmpty ? request.call : request.to)).lineLimit(1)
            if pending > 1 { Text("· 他 \(pending - 1) 件") }
            Spacer(minLength: 8)
            Ticker(fps: 1) { now in Text("WAIT \(Int(request.waited(now: now)))s") }
        }
        .font(.mono(10)).tracking(1.2)
        .foregroundStyle(Palette.Light.bg)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Palette.Light.fg)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in choice(i) }
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 22))
            Text("←→ 選ぶ · ENTER 決定 · 1–3 · ⇧⌘G 許可")
                .font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg3)
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
        }
    }

    private func choice(_ i: Int) -> some View {
        let on = gate.choice == i
        let (en, jp) = Self.choices[i]
        return VStack(alignment: .leading, spacing: 3) {
            Text("#\(i + 1)").font(.mono(10)).tracking(1)
            Text(en).font(.display(on ? 30 : 24)).foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
            Text(jp).font(.bodyJP(11))
        }
        .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg2)
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 10, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let plate = Chevron(head: on ? 14 : 0, skew: -18)
            plate.fill(on ? Palette.Light.fg : Palette.Light.bg)
                .overlay(plate.stroke(on ? Palette.Light.fg : Palette.Light.line, lineWidth: 1))
        }
        .offset(y: on ? -2 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onChoose(i) }
        .onHover { if $0 { gate.choice = i } }
        .reportRect("gateBtn:\(i)")
    }

    private var rewrite: some View {
        VStack(alignment: .leading, spacing: 8) {
            if frozen != nil {
                Text(gate.revised).font(.bodyJP(14)).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .padding(.horizontal, 10).background(Palette.Light.bg2)
            } else {
                TextField("書き換えた指示", text: $gate.revised)
                    .textFieldStyle(.plain)
                    .font(.bodyJP(14))
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Palette.Light.bg2)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                    .onSubmit(onRewrite)
            }
            HStack(spacing: 8) {
                Button("書き換えて発行 ↵", action: onRewrite)
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .disabled(gate.revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .reportRect("gateBtn:rw")
                Button("戻る") { gate.rewriting = false }
                    .buttonStyle(SumiButtonStyle(primary: false))
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
    }
}

/// 揺れ。`translate(3px,2px) → (-2px,0) → 0` を 110ms・2コマで
struct Shake: ViewModifier {
    let trigger: Int
    @State private var offset = CGSize.zero

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .task(id: trigger) {
                guard trigger > 0 else { return }
                offset = CGSize(width: 3, height: 2)
                try? await Task.sleep(for: .milliseconds(55))
                offset = CGSize(width: -2, height: 0)
                try? await Task.sleep(for: .milliseconds(55))
                offset = .zero
            }
    }
}

// MARK: - 処理中の箱

/// 司令塔が考えている・書いている間。段の並び、いまの段の和名、12 コマのゲージ。
/// ponytail: 何段で終わるかは分からないので、ゲージは 1 秒 1 コマで回すだけ
private struct BusyBox: View {
    let trail: [(path: String, kind: TouchKind)]
    let streaming: String
    @State private var since = Date()
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let steps = Self.steps(trail)
        let now = steps.last ?? "think"
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { k in
                    if k > 0 { Rectangle().fill(Palette.Light.fg).frame(width: 18, height: 1) }
                    let current = k == steps.count - 1
                    HStack(spacing: 6) {
                        if current {
                            Ticker(fps: 4) { t in
                                Rectangle().frame(width: 6, height: 6)
                                    .opacity(frozen != nil || t.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.6) < 0.3 ? 1 : 0)
                            }
                            .frame(width: 6, height: 6)
                        }
                        Text(steps[k].uppercased())
                    }
                    .font(.mono(10))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(current ? Palette.Light.fg : Palette.Light.bg)
                    .background(current ? Color.clear : Palette.Light.fg)
                    .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
                }
            }
            Ticker(fps: 1) { t in
                let seconds = frozen != nil ? 3 : Int(max(0, t.timeIntervalSince(since)))
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(TalkScreen.stepLabel[now] ?? "").font(.bodyJP(15))
                        Text("STEP \(steps.count) · \(seconds)s").font(.mono(10)).foregroundStyle(Palette.Light.fg3)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<12, id: \.self) { k in
                            Rectangle().fill(k <= seconds % 12 ? Palette.Light.fg : Palette.Light.bg3).frame(height: 4)
                        }
                    }
                }
            }
            if !streaming.isEmpty {
                Text(String(streaming.suffix(240))).font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                    .lineLimit(3)
            }
        }
        .foregroundStyle(Palette.Light.fg)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: 680, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    /// 足跡を段の名前へ。読む＝search、書く＝write、最後は必ず考えている段で終える
    static func steps(_ trail: [(path: String, kind: TouchKind)]) -> [String] {
        var out: [String] = []
        for touch in trail {
            let step = touch.kind == .write ? "write" : "search"
            if out.last != step { out.append(step) }
        }
        out = Array(out.suffix(3))
        return out.isEmpty ? ["think"] : out
    }
}

// MARK: - セッションを選ぶ

/// セッションを選ぶまでは履歴を出す。**起動直後にいちばん先に決めることは「どの会話を見るか」**で、
/// 空の会話画面を見せても次の一手が無い
struct SessionPicker: View {
    let cockpit: Cockpit
    let width: CGFloat
    let onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionMark(number: "01", title: "TALK", jp: "会話")
            Text("Pick a session.").font(.display(52)).foregroundStyle(Palette.Light.fg)
            Text("どの会話を見るかを選ぶと、司令塔とのやり取りがここに流れます。")
                .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
            Button("＋ NEW SESSION", action: onNew).buttonStyle(SumiButtonStyle(primary: true))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !cockpit.liveSessions.isEmpty {
                        group("実行中")
                        ForEach(cockpit.liveSessions) { session in
                            line(title: cockpit.title(for: session.id) ?? session.name,
                                 sub: (session.cwd as NSString).lastPathComponent,
                                 live: session.busy) { cockpit.selectedSession = session.id }
                        }
                    }
                    let byProject = Dictionary(grouping: cockpit.recentSessions) { $0.project }
                        .sorted { ($0.value.first?.modifiedAt ?? .distantPast) > ($1.value.first?.modifiedAt ?? .distantPast) }
                    ForEach(byProject, id: \.key) { project, sessions in
                        group(project)
                        ForEach(sessions) { session in
                            line(title: cockpit.title(for: session.id) ?? String(session.id.prefix(8)),
                                 sub: session.modifiedAt.formatted(.dateTime.month().day().hour().minute()),
                                 live: false) {
                                cockpit.selectedSession = session.id
                                Task { await cockpit.loadSession(session) }
                            }
                        }
                    }
                    let liveIDs = Set(cockpit.liveSessions.map(\.id))
                    let codex = cockpit.codexRecords.filter { !liveIDs.contains($0.id) }
                    if !codex.isEmpty {
                        group("CODEX")
                        ForEach(codex.sorted { $0.lastUsed > $1.lastUsed }) { record in
                            line(title: cockpit.title(for: record.id) ?? String(record.id.prefix(8)),
                                 sub: (record.cwd as NSString).lastPathComponent, live: false) {
                                cockpit.selectedSession = record.id
                                cockpit.resumeCodexRecord(record)
                            }
                        }
                    }
                    if cockpit.liveSessions.isEmpty && cockpit.recentSessions.isEmpty && codex.isEmpty {
                        Text("履歴はまだない").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg3).padding(.top, 12)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .foregroundStyle(Palette.Light.fg)
        .padding(.top, 20)
    }

    private func group(_ title: String) -> some View {
        Text("// " + title.uppercased()).font(.mono(10)).tracking(Palette.caps(10))
            .foregroundStyle(Palette.Light.fg2)
            .padding(.top, 14).padding(.bottom, 4)
    }

    private func line(title: String, sub: String, live: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle().fill(live ? Palette.pink : Palette.Light.line).frame(width: 6, height: 6)
                Text(title).font(.bodyJP(14)).lineLimit(1)
                Spacer(minLength: 8)
                Text(sub).font(.mono(10)).foregroundStyle(Palette.Light.fg3).lineLimit(1)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        }
        .buttonStyle(PressStyle())
    }
}
