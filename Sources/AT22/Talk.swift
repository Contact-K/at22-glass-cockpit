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
    let stop: Stop?
    /// 別の worktree で止まっているもの（カードの下に並べる）
    var others: [TowerStop] = []
    var onOther: (TowerStop) -> Void = { _ in }
    let pendingGates: Int
    let trail: [(path: String, kind: TouchKind)]
    let ctxAlarm: Bool
    let height: CGFloat
    let width: CGFloat
    /// 板が開いている間は ⌘Return を板の側（「起こす」）に譲る
    let modalOpen: Bool
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
            .onChange(of: cockpit.selectedSession) { failed = false }
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
                .onChange(of: items.last?.id) { scrollDown(proxy) }
                .onChange(of: cockpit.streaming[cockpit.selectedSession ?? ""]?.count) { scrollDown(proxy) }
                .onChange(of: stop?.id) { scrollDown(proxy) }
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
        if let stop {
            GateCard(stop: stop, pending: pendingGates, failed: gateFailed, others: others,
                     gate: $gate, onChoose: onChoose, onRewrite: onRewrite, onOther: onOther)
        }
        if cockpit.isWorking(cockpit.selectedSession) {
            BusyBox(trail: trail, live: cockpit.liveInk(cockpit.selectedSession),
                    streaming: cockpit.streaming[cockpit.selectedSession ?? ""] ?? "")
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
        let now = cockpit.liveInk(cockpit.selectedSession)
        return HStack(spacing: 0) {
            Group {
                if let s = cockpit.selectedSession {
                    ModelPicker(backend: cockpit.backend(of: s), model: cockpit.model(of: s) ?? "",
                                effort: cockpit.effort(of: s) ?? "",
                                onModel: { cockpit.setModel($0, for: s) }, onEffort: { cockpit.setEffort($0, for: s) })
                } else {
                    Text("// ASK C0").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
                }
            }
            .padding(.horizontal, 14)
            if frozen != nil {
                Text(draft.isEmpty ? "司令塔に聞く" : draft).font(.bodyJP(16)).foregroundStyle(Palette.Light.fg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(working ? (Self.stepLabel[now] ?? "") + "…" : "司令塔に聞く", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.bodyJP(16))
                    .foregroundStyle(Palette.Light.fg)
                    .onSubmit { if !working && !empty { send() } }
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
            .disabled(!cockpit.canSend(to: cockpit.selectedSession) && !working || (!working && empty) || modalOpen)
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

/// 止まっている1件。**複数溜まっていても出すのは待たせている順に1件だけ**——
/// 並べると「どれに答えているか」が曖昧になる。道具の承認は入力を読める形で出す
/// （Bash はコマンド、Edit / Write は差分、門は行き先）。書き換えは道具なら入力の JSON、門なら指示の文
private struct GateCard: View {
    let stop: Stop
    let pending: Int
    let failed: Bool
    let others: [TowerStop]
    @Binding var gate: GateUI
    let onChoose: (Int) -> Void
    let onRewrite: () -> Void
    let onOther: (TowerStop) -> Void
    @State private var showJSON = false
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar
            VStack(alignment: .leading, spacing: 10) {
                Text(stop.title).font(.display(40)).lineLimit(1)
                if !stop.body.isEmpty { Text(stop.body).font(.bodyJP(14)).lineSpacing(14 * 0.6 - 4).lineLimit(4) }
                if !gate.rewriting {
                    input
                    if stop.kind != .gate {
                        Button(showJSON ? "▾ 読める形に戻す" : "▸ 入力 JSON を見る") { showJSON.toggle() }
                            .buttonStyle(.plain)
                            .font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2)
                    }
                }
                if failed {
                    Text("答えを届けられなかった。相手は待ったままなので、置き場か接続を直してもう一度")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
            if gate.rewriting { rewrite } else { choices }
            if !others.isEmpty { elsewhere }
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(maxWidth: 660, alignment: .leading)
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

    private var bar: some View {
        HStack(spacing: 10) {
            Blink(size: 8)
            Text(stop.who.uppercased() + " // " + (stop.kind == .gate ? "GATE" : "TOOL"))
            Text(stop.kind == .gate ? "門" : "道具").font(.brush(14)).tracking(0)
            Text("· " + stop.target + (stop.kind == .acp ? " · ACP" : "")).lineLimit(1)
            if pending > 1 { Text("· 他 \(pending - 1) 件") }
            Spacer(minLength: 8)
            Ticker(fps: 1) { now in Text("WAIT \(Int(max(0, now.timeIntervalSince(stop.since))))s") }
        }
        .font(.mono(10)).tracking(1.2)
        .foregroundStyle(Palette.Light.bg)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Palette.Light.fg)
    }

    /// 道具の入力を読める形に。JSON の表示に切り替えられる
    @ViewBuilder
    private var input: some View {
        if showJSON {
            Text(stop.prettyInput).font(.mono(12)).lineSpacing(6).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 180, alignment: .top).clipped()
                .background(Palette.Light.bg2)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
        } else {
            switch stop.kind {
            case .gate:
                Text(stop.meta).font(.mono(10)).tracking(0.8).foregroundStyle(Palette.Light.fg2)
            case .bash:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("$").foregroundStyle(Palette.Light.fg2)
                        Text(stop.command).textSelection(.enabled)
                    }
                    .font(.mono(15)).lineSpacing(6)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    HStack(spacing: 16) {
                        Text("cwd " + stop.place)
                        if let t = stop.timeout { Text("timeout \(t)s") }
                        Spacer(minLength: 0)
                        Text(stop.inputDescription).lineLimit(1)
                    }
                    .font(.mono(10)).tracking(0.6).foregroundStyle(Palette.Light.fg2)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(alignment: .top) {
                        Rectangle().stroke(Palette.Light.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.Light.bg2)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
            case .diff, .acp:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Text(stop.diffPath).lineLimit(1).truncationMode(.middle)
                        if stop.isNewFile { Text("NEW").font(.mono(9)).padding(.horizontal, 5).overlay(Rectangle().stroke(lineWidth: 1)) }
                        Spacer(minLength: 0)
                        let lines = stop.diffLines
                        Text("+\(lines.filter { $0.kind == "+" }.count) −\(lines.filter { $0.kind == "-" }.count)")
                            .foregroundStyle(Palette.Light.fg2)
                    }
                    .font(.mono(11)).tracking(0.2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Palette.Light.bg2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(stop.diffLines.prefix(40).enumerated()), id: \.offset) { _, line in
                            DiffRow(kind: line.kind, old: line.old, new: line.new, text: line.text, dense: true)
                        }
                    }
                    .frame(maxHeight: 170, alignment: .top).clipped()
                }
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
            case .other:
                Text(stop.inputLine).font(.mono(12)).lineLimit(3)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.hover)
            }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ForEach(Array(stop.options.enumerated()), id: \.offset) { i, option in choice(i, option) }
            }
            .padding(EdgeInsets(top: 10, leading: 20, bottom: 8, trailing: 22))
            HStack(spacing: 14) {
                Text("←→ 選ぶ · ENTER 決定 · 1–\(stop.options.count) · ⇧⌘G 許可")
                if stop.kind == .acp {
                    Text("ACP · \(stop.who) は入力の書き換えができないので Rewrite はありません").foregroundStyle(Palette.Light.fg2)
                }
            }
            .font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg3)
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
        }
    }

    private func choice(_ i: Int, _ option: Int) -> some View {
        let on = gate.choice == i
        let (en, jp) = [("Allow", "許可"), ("Rewrite", "書き換え"), ("Reject", "却下")][option]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(i + 1)").font(.mono(10)).tracking(1)
            Text(en).font(.display(24)).lineLimit(1).minimumScaleFactor(0.6)
            Text(jp).font(.bodyJP(11))
        }
        .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
        .padding(.leading, 14).padding(.trailing, 26)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background {
            if on { Chevron(head: 16).fill(Palette.Light.fg) }
            else { Chevron(head: 16).stroke(Palette.Light.fg, lineWidth: 1) }
        }
        .contentShape(Rectangle())
        .onTapGesture { onChoose(i) }
        .onHover { if $0 { gate.choice = i } }
        .reportRect("gateBtn:\(i)")
    }

    private var rewrite: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stop.kind == .gate ? "指示を書き換える" : "REWRITE // 道具の入力（JSON）を書き換えて許可")
                .font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2)
            Group {
                if frozen != nil {
                    Text(gate.revised).frame(maxWidth: .infinity, alignment: .topLeading)
                } else if stop.kind == .gate {
                    TextField("書き換えた指示", text: $gate.revised)
                        .textFieldStyle(.plain)
                        .onSubmit(onRewrite)
                        // 書換欄に焦点がある間は Esc が根まで来ないので、欄の側で畳む
                        .onExitCommand { gate.rewriting = false }
                } else {
                    TextEditor(text: $gate.revised).scrollContentBackground(.hidden)
                        .onExitCommand { gate.rewriting = false }
                }
            }
            .font(stop.kind == .gate ? .bodyJP(14) : .mono(12))
            .padding(.horizontal, 10).padding(.vertical, stop.kind == .gate ? 0 : 8)
            .frame(height: stop.kind == .gate ? 38 : 150)
            .background(Palette.Light.bg2)
            .overlay(Rectangle().stroke(Palette.Light.fg, lineWidth: 1))
            HStack(spacing: 8) {
                Button("書き換えて許可 ↵", action: onRewrite)
                    .buttonStyle(SumiButtonStyle(primary: true))
                    .disabled(gate.revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .reportRect("gateBtn:rw")
                Button("戻る") { gate.rewriting = false }
                    .buttonStyle(SumiButtonStyle(primary: false))
            }
        }
        .padding(EdgeInsets(top: 6, leading: 16, bottom: 14, trailing: 16))
    }

    /// 別の worktree で止まっているもの。押すとそこへ
    private var elsewhere: some View {
        HStack(spacing: 8) {
            Text("別の worktree \(others.count)").font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2)
                .frame(width: 120, alignment: .leading)
            FlowLayout(spacing: 8, lineSpacing: 6) {
                ForEach(Array(others.prefix(6).enumerated()), id: \.offset) { _, other in
                    Text("\(other.name) ▸ \(other.stop.who) · \(other.stop.target)").font(.mono(11)).tracking(0.2)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .overlay(Rectangle().strokeBorder(Palette.Light.fg, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Rectangle())
                        .onTapGesture { onOther(other) }
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 12, trailing: 16))
        .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
    }
}

/// 差分の1行。旧い行番号・新しい行番号・記号・本文。追加は淡い青の地、削除は打ち消し線
struct DiffRow: View {
    let kind: Character
    let old: Int?
    let new: Int?
    let text: String
    var dense = false
    var commented = false
    var dim = false

    var body: some View {
        let num: CGFloat = dense ? 34 : 46
        HStack(spacing: 0) {
            Text(old.map(String.init) ?? "").frame(width: num, alignment: .trailing).padding(.trailing, 8)
                .foregroundStyle(Palette.Light.fg3)
            Text(new.map(String.init) ?? "").frame(width: num, alignment: .trailing).padding(.trailing, 8)
                .foregroundStyle(Palette.Light.fg3)
                .overlay(alignment: .trailing) { Rectangle().fill(Palette.Light.line).frame(width: 1) }
            Text(kind == " " ? "" : kind == "-" ? "−" : "+").frame(width: dense ? 14 : 16)
            Text(text).lineLimit(1).truncationMode(.tail)
                .strikethrough(kind == "-", color: Palette.Blue.fg3)
                .foregroundStyle(kind == "-" ? Palette.Light.fg3 : Palette.Light.fg)
            Spacer(minLength: 0)
            if commented { Rectangle().fill(Palette.Light.fg).frame(width: 8, height: 8).padding(.trailing, 6) }
        }
        .font(.mono(dense ? 11 : 12))
        .frame(minHeight: dense ? 20 : 22)
        .background(kind == "+" ? Color(hex: 0xDCDCFF) : .clear)
        .opacity(dim ? 0.4 : 1)
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
    /// いまの動作（`Cockpit.liveInk`）。段の並びの最後に置く
    let live: String
    let streaming: String
    @State private var since = Date()
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let steps = Self.steps(trail, live: live)
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

    /// 足跡を段の名前へ。読む＝search、書く＝write、最後はいまの動作（ビルド中なら build）で終える
    static func steps(_ trail: [(path: String, kind: TouchKind)], live: String) -> [String] {
        var out: [String] = []
        for touch in trail {
            let step = touch.kind == .write ? "write" : "search"
            if out.last != step { out.append(step) }
        }
        if out.last != live { out.append(live) }
        return Array(out.suffix(3))
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
                    let codex = cockpit.runRecords.filter { !liveIDs.contains($0.id) }
                    if !codex.isEmpty {
                        group("CODEX · GROK")
                        ForEach(codex.sorted { $0.lastUsed > $1.lastUsed }) { record in
                            line(title: cockpit.title(for: record.id) ?? String(record.id.prefix(8)),
                                 sub: (record.cwd as NSString).lastPathComponent, live: false) {
                                cockpit.selectedSession = record.id
                                cockpit.resumeRunRecord(record)
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
