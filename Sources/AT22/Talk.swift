import SwiftUI

// MARK: - 01 TALK

/// 会話。見出し → ログ（自分＝青い矢羽／C0＝2px の枠）→ 門のカード → 処理中の箱 → 入力欄。
///
/// **答える口はここ1つ。** 門のカードで許可・書換・却下が完結する。
/// 答えを書けなかった時は必ずカードに出す（`gateFailed`）——黙って消すと司令塔が待ち続ける
struct TalkScreen: View {
    let cockpit: Cockpit
    @AppStorage(SettingsScreen.agentKey) private var defaultAgent = "claude|opus"
    @AppStorage(SettingsScreen.effortKey) private var defaultEffort = ""
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
    /// 新しい会話を起こす先（いまの worktree）。管制塔では nil
    var workspace: String? = nil
    /// 一覧（右列の履歴）から「新しい会話」を選んで、最初の1通を書いている間
    @Binding var composing: Bool
    /// 人の承認なしに書き換える段（Lv.3/4）を選んだ時。確かめてから効かせる（CockpitView の確認）
    var onRiskyLevel: (Gate.Level) -> Void = { _ in }
    /// 発言の URL の札を押した時（内蔵ブラウザ）
    var onBrowse: (URL) -> Void = { _ in }
    /// 壁打ちの板（採った手順・決めたこと）。壁打ち中は返事の下に札を出し、右列に暫定プラン・決定事項を出す
    var spar: SparModel? = nil
    var fly: (CGRect?, CGRect?) -> Void = { _, _ in }
    var rects: [String: CGRect] = [:]

    @State private var draft = ""
    @State private var failed = false
    /// 会話の一番下が見えているか（「最新へ ↓」と、引き戻すかどうか）
    @State private var atBottom = true
    @AppStorage(SettingsScreen.levelKey) private var defaultLevel = Gate.defaultLevel.rawValue
    /// 新しい会話を壁打ち（読むだけ）で起こすか
    @State private var planNext = false
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
    /// ponytail: 行を全部その場で組む（VStack）ので、流すのは新しい方から150件まで
    static let maxEntries = 150

    var body: some View {
        if cockpit.selectedSession == nil && !composing {
            SessionPicker(cockpit: cockpit, width: width, workspace: workspace,
                          onFresh: { composing = true; failed = false }, onNew: onNew)
                .frame(width: width, height: height, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                log.frame(width: width, height: max(120, height - 164 - 34 - (handoffShown ? 44 : 0)))
                if handoffShown { handoffBar }
                if failed, let reason = cockpit.launchError {
                    Text(reason).font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                        .lineLimit(2)
                }
                // 段と壁打ちは入力欄のすぐ上（会話の先頭に置くと、遡らないと切り替えられなかった）
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    levelSwitch
                    planToggle
                }
                .frame(height: 24)
                input
            }
            .frame(width: width, alignment: .topLeading)
            .onChange(of: cockpit.selectedSession) { failed = false; composing = false }
        }
    }

    // MARK: ログ

    @ViewBuilder
    private var log: some View {
        let items = entries
        // 最後の人の発言は1回だけ求める。行ごとに全メッセージを走ると、遡るほど重くなって固まった
        let lastHuman = cockpit.messages.last { $0.session == cockpit.selectedSession && $0.speaker == .human }?.id
        let lastReply = cockpit.messages.last { $0.session == cockpit.selectedSession && $0.speaker == .model && !$0.thinking }?.id
        if frozen != nil {
            // `--shot` は ScrollView の中身を焼かないので、素の VStack に積んで下端を見せる
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(items.suffix(6)) { entry in row(entry, lastHuman: lastHuman, lastReply: lastReply) }
                tail
            }
            .padding(.trailing, 16)
            .frame(width: width, height: max(120, height - 164 - 34), alignment: .bottomLeading)
            .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // LazyVStack は使わない。高さの違う行を遡る・下へ送る（scrollTo）たびに、組んでいない行の高さを
                    // 見積もり直して並べ直しが終わらず固まった（2026-10-05、sample で LazySubviewPlacements が回り続けていた）
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        ForEach(items) { entry in row(entry, lastHuman: lastHuman, lastReply: lastReply).id(entry.id) }
                        tail
                        Color.clear.frame(height: 8).id(Self.bottomID)
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
                // defaultScrollAnchor(.bottom) は使わない。高さの違う行の LazyVStack で遡ると、行が組まれるたびに
                // 下端へ合わせ直して並べ直しが終わらず固まった（2026-10-05 に sample で確認）。開いた時に下へ送る
                .onAppear { scrollDown(proxy) }
                .onChange(of: cockpit.selectedSession) { scrollDown(proxy) }
                // 一番下が見えているか。遡っている間は、新しい発言や流れ込みで引き戻さない
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 60
                } action: { _, bottom in atBottom = bottom }
                .overlay(alignment: .bottomTrailing) {
                    if !atBottom {
                        Button { atBottom = true; withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) } } label: {
                            Text("最新へ ↓").font(.mono(11)).tracking(0.9).foregroundStyle(Palette.Light.bg)
                                .padding(.horizontal, 12).padding(.vertical, 7).background(Palette.Light.fg)
                        }
                        .buttonStyle(PressStyle())
                        .padding(.trailing, 24).padding(.bottom, 10)
                        .help("いちばん新しいところへ戻る")
                    }
                }
                .onChange(of: items.last?.id) { if atBottom { scrollDown(proxy) } }
                .onChange(of: cockpit.streaming[cockpit.selectedSession ?? ""]?.count) { if atBottom { scrollDown(proxy) } }
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionMark(number: "01", title: "TALK", jp: "会話")
                // 題（最初の指示から自動で付く）
                Text(cockpit.selectedSession.flatMap { cockpit.title(for: $0) } ?? (composing ? "新しい会話" : ""))
                    .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                Spacer(minLength: 8)
            }
            Text(composing && cockpit.selectedSession == nil ? "New talk." : headline)
                .font(.display(52)).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.Light.fg)
            Text(composing && cockpit.selectedSession == nil
                 ? "最初の1通を送ると、\((workspace.map { ($0 as NSString).lastPathComponent }) ?? "worktree") で新しい会話が立ち上がります。"
                 : subtitle)
                .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
        }
        .padding(.vertical, 8)
    }

    // MARK: 引き継ぎ（文脈 85%）

    private var handoffShown: Bool {
        guard let s = cockpit.selectedSession else { return false }
        return cockpit.handoffs[s] != nil || cockpit.handoffProblem[s] != nil
            || (cockpit.contextStage(s) == .warning && cockpit.canHandOff(s))
    }

    /// 文脈が 85% を越えた会話の札。Lv.1/2 は押した時だけ、Lv.3/4 は自動で書かせて新しい会話へ移る
    private var handoffBar: some View {
        let s = cockpit.selectedSession ?? ""
        let auto = cockpit.level(of: s).needsConfirmation
        return HStack(spacing: 10) {
            if cockpit.handoffs[s] != nil {
                InkLoader(status: "handoff", pitch: 1.4)
                Text("引き継ぎを書いています。終わったら新しい会話を起こします").font(.bodyJP(13))
            } else if let problem = cockpit.handoffProblem[s] {
                Text(problem).font(.bodyJP(13)).foregroundStyle(Palette.Light.danger)
            } else {
                Text("文脈が 85% を越えました。" + (auto ? "ターンが終わったら自動で引き継ぎます" : "引き継いで新しい会話へ移れます"))
                    .font(.bodyJP(13))
            }
            Spacer(minLength: 8)
            if cockpit.handoffs[s] == nil && cockpit.canHandOff(s) {
                Button("引き継いで移る ▸") { cockpit.requestHandoff(s) }
                    .buttonStyle(SumiButtonStyle(primary: true, size: 11))
                    .disabled(cockpit.isWorking(s))
                    .help("記憶DB の sessions/each/<ID>.md に引き継ぎを書かせ、そのノートから新しい会話を起こす（古い会話は残る）")
            }
        }
        .padding(.horizontal, 14).frame(height: 34)
        .foregroundStyle(Palette.Light.fg)
        .overlay(Rectangle().strokeBorder(Palette.Light.danger, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    /// 壁打ちが入っているか（いまの会話の worktree の段が plan）
    private var planOn: Bool { cockpit.selectedSession == nil ? planNext : cockpit.gateLevel == .plan }

    /// 段（ハーネス）の切り替え。Lv.1〜4。壁打ちは隣のトグル
    private var levelSwitch: some View {
        let current = cockpit.selectedSession == nil
            ? (Gate.Level(rawValue: defaultLevel) ?? Gate.defaultLevel) : cockpit.gateLevel
        return SumiPicker(sections: [.init(title: "段（いまの会話の worktree）", items: Gate.Level.ladder.map {
            .init(id: $0.rawValue, text: $0.title, on: $0 == current)
        })], onPick: { _, id in
            guard let l = Gate.Level(rawValue: id) else { return }
            if l.needsConfirmation { onRiskyLevel(l); return }
            if cockpit.selectedSession == nil { defaultLevel = l.rawValue } else { cockpit.applyLevel(l, to: cockpit.selectedSession) }
        }) {
            Text((current == .plan ? "段 ─" : current.title) + " ▾").font(.mono(11)).tracking(0.6)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
        }
        .help("承認の段。次に送った時から効く")
    }

    /// 壁打ち（読むだけ・書かない）のトグル。段とは別枠
    private var planToggle: some View {
        Button(planOn ? "■ 壁打ち" : "□ 壁打ち") {
            if cockpit.selectedSession == nil { planNext.toggle() } else { cockpit.setPlanMode(!planOn, session: cockpit.selectedSession) }
        }
        .buttonStyle(SumiButtonStyle(primary: planOn, size: 11))
        .help("壁打ち: claude を plan モード（読むだけ・書かない）で動かす。切ると元の段に戻る")
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
    private func row(_ entry: Entry, lastHuman: Int?, lastReply: Int?) -> some View {
        switch entry {
        case let .human(message):
            HStack {
                Spacer(minLength: 0)
                // 壁打ちで送った分は、添えた約束を外して打った言葉だけ
                Text(SparReplyStrip.typed(message.text))
                    .font(.bodyJP(15)).lineSpacing(15 * 0.6 - 4)
                    .foregroundStyle(Palette.Light.bg)
                    .textSelection(.enabled)
                    .padding(EdgeInsets(top: 11, leading: 32, bottom: 12, trailing: 18))
                    .background { Chevron(point: 18).fill(Palette.Light.fg) }
                    .frame(maxWidth: 560, alignment: .trailing)
            }
            // 行ごとの矩形は誰も読まない（読むのは最後の返事の c0last だけ）。全行に付けるとスクロールで固まった
            .reportRect(when: message.id == lastHuman, "melast")
        case let .model(message, label, refs):
            // 壁打ち中は返事の末尾の STEP / DECIDE / ASK を札に分け、本文はそれ以外
            let sparred = planOn && !message.thinking && spar != nil && workspace != nil ? Sparring.parse(message.text) : nil
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
                Text(message.text.isEmpty ? AttributedString("（本文は残っていない。考えた時刻だけ分かる）")
                                          : MarkdownCache.text(message.id, sparred?.body ?? message.text))
                    .font(.bodyJP(15)).lineSpacing(15 * 0.8 - 4)
                    .foregroundStyle(message.thinking ? Palette.Light.fg3 : Palette.Light.fg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                let links = message.thinking ? [] : LinkCache.links(message.id, message.text)
                if !refs.isEmpty || !links.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(refs, id: \.self) { ref in
                            Text("参照 · " + ref).font(.bodyJP(12))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .overlay(Rectangle().stroke(Palette.Light.line, lineWidth: 1))
                        }
                        // 開発サーバーや PR の URL は、押すと内蔵ブラウザで開く
                        ForEach(links, id: \.self) { url in
                            Button { onBrowse(url) } label: {
                                Text("↗ " + (url.host.map { $0 + (url.port.map { ":\($0)" } ?? "") } ?? url.absoluteString) + url.path)
                                    .font(.mono(11)).lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .foregroundStyle(Palette.Light.bg).background(Palette.Light.fg)
                            }
                            .buttonStyle(PressStyle())
                            .help(url.absoluteString)
                        }
                    }
                }
                if let sparred, let spar, let workspace {
                    SparReplyStrip(model: spar, workspace: workspace, reply: sparred,
                                   offerNext: message.id == lastReply && !cockpit.isWorking(cockpit.selectedSession),
                                   onNext: { mode in
                                       spar.boards[workspace, default: .init()].mode = mode
                                       draft = ""
                                       send()
                                   },
                                   fly: fly, rects: rects)
                }
            }
            .foregroundStyle(Palette.Light.fg)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: 680, alignment: .leading)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg,
                                              style: StrokeStyle(lineWidth: 2, dash: message.thinking ? [4, 3] : [])))
            .reportRect(when: message.id == lastReply, "c0last")
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

    /// Markdown を解釈しつつ改行を保つ。`**` や `` ` `` の記号が消えるだけで長い発言はだいぶ読める。
    /// ponytail: 見出しの大きさや表組みまでは再現しない
    nonisolated static func formatted(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }

    // MARK: 入力欄

    /// 打っている途中の「/名前」（codex は「$名前」）に合うスキル。空白を打ったら閉じる
    private var slashMatches: [String] {
        guard let head = draft.first, head == "/" || head == "$", !draft.contains(where: \.isWhitespace) else { return [] }
        let backend = cockpit.selectedSession.map(cockpit.backend(of:)) ?? .claude
        let names = Skills.visible(cockpit.skills, to: backend).map { Skills.invocation($0, for: backend) }
        return Array(Set(names)).filter { $0.lowercased().hasPrefix(draft.lowercased()) }.sorted().prefix(8).map { $0 }
    }

    private var slashList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(slashMatches, id: \.self) { name in
                Button { draft = name + " " } label: {
                    Text(name).font(.mono(12)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .foregroundStyle(Palette.Light.fg)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
        .frame(width: 320)
    }

    private var input: some View {
        let working = cockpit.isWorking(cockpit.selectedSession)
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let now = cockpit.liveInk(cockpit.selectedSession)
        let fresh = cockpit.selectedSession == nil && workspace != nil
        return HStack(spacing: 0) {
            Group {
                if let s = cockpit.selectedSession {
                    ModelPicker(backend: cockpit.backend(of: s), models: cockpit.models(cockpit.backend(of: s)),
                                model: cockpit.model(of: s) ?? "",
                                effort: cockpit.effort(of: s) ?? "",
                                onModel: { cockpit.setModel($0, for: s) }, onEffort: { cockpit.setEffort($0, for: s) })
                } else {
                    // 会話を選ぶ前は、新しく起こす時の既定を選ぶ（壁打ちの入力欄と同じ）
                    let parts = defaultAgent.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    let backend = Backend(rawValue: parts.first ?? "") ?? .claude
                    ModelPicker(backend: backend, models: cockpit.models(backend),
                                model: parts.count > 1 ? parts[1] : "", effort: defaultEffort,
                                onModel: { defaultAgent = backend.rawValue + "|" + $0 }, onEffort: { defaultEffort = $0 },
                                backends: cockpit.usableBackends(),
                                onBackend: { b in defaultAgent = b.rawValue + "|" + (cockpit.models(b).first?.id ?? "") })
                }
            }
            .padding(.leading, 14).padding(.trailing, 4)
            SkillPicker(backend: cockpit.selectedSession.map(cockpit.backend(of:)) ?? .claude, skills: cockpit.skills,
                        onPick: { draft = $0 + draft })
                .padding(.trailing, 6)
            if frozen != nil {
                Text(draft.isEmpty ? "司令塔に聞く" : draft).font(.bodyJP(16)).foregroundStyle(Palette.Light.fg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(working ? (Self.stepLabel[now] ?? "") + "…" : "司令塔に聞く", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.bodyJP(16))
                    .foregroundStyle(Palette.Light.fg)
                    .onSubmit {
                        // 候補が出ている間の Return は1つ目で補う
                        if let first = slashMatches.first { draft = first + " "; return }
                        if !working && !empty { send() }
                    }
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
            .disabled(!(cockpit.canSend(to: cockpit.selectedSession) || fresh) && !working || (!working && empty) || modalOpen)
            .help(working ? "生成を止める（セッションは終わらない）" : "送る（Return / ⌘Return）")
        }
        .frame(height: 48)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(ctxAlarm ? Palette.Light.danger : Palette.Light.fg, lineWidth: 2))
        // 「/」の候補は入力欄の真上に
        .overlay(alignment: .topLeading) {
            if !slashMatches.isEmpty { slashList.alignmentGuide(.top) { $0[.bottom] + 4 }.padding(.leading, 14) }
        }
    }

    private func send() {
        // 壁打ち中は、型の合図・決まっていること・返し方（STEP / DECIDE / ASK）を添えて送る
        let typed = draft
        if planOn, let spar, let workspace {
            let board = spar.board(workspace)
            draft = Sparring.prompt(typed.trimmingCharacters(in: .whitespacesAndNewlines), mode: board.mode,
                                    decided: board.decisions.map(\.text))
        }
        defer {
            // 送れなかった時は打った言葉に戻す。送れたら板にこの会話を覚える（右列の未決の問いを拾う）
            if failed { draft = typed }
            if !failed, planOn, let spar, let workspace, let s = cockpit.selectedSession { spar.boards[workspace, default: .init()].session = s }
        }
        if cockpit.selectedSession == nil {
            // 新しい会話: いまの worktree で、入力欄の左で選んだエージェントとモデルで起こす。
            // 起こした会話は launch が選択中にする
            guard let workspace else { failed = true; return }
            let parts = defaultAgent.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let backend = Backend(rawValue: parts.first ?? "") ?? .claude
            let level = planNext ? Gate.Level.plan : (Gate.Level(rawValue: defaultLevel) ?? Gate.defaultLevel)
            if cockpit.launch(prompt: draft, cwd: workspace, backend: backend,
                              model: parts.count > 1 ? parts[1] : "", level: level, effort: defaultEffort) != nil {
                draft = ""
                failed = false
            } else {
                failed = true
            }
            return
        }
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
            Ticker(fps: 1) { now in
                // 気にかけてる（Lv.2）の猶予中は、通るまでの残りを数える
                if let auto = stop.autoAt { Text("AUTO \(Int(max(0, auto.timeIntervalSince(now)).rounded(.up)))s") }
                else { Text("WAIT \(Int(max(0, now.timeIntervalSince(stop.since))))s") }
            }
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
                let lines = stop.diffLines
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Text(stop.diffPath).lineLimit(1).truncationMode(.middle)
                        if stop.isNewFile { Text("NEW").font(.mono(9)).padding(.horizontal, 5).overlay(Rectangle().stroke(lineWidth: 1)) }
                        Spacer(minLength: 0)
                        Text("+\(lines.filter { $0.kind == "+" }.count) −\(lines.filter { $0.kind == "-" }.count)")
                            .foregroundStyle(Palette.Light.fg2)
                    }
                    .font(.mono(11)).tracking(0.2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Palette.Light.bg2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.prefix(40).enumerated()), id: \.offset) { _, line in
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
    /// いまの worktree。nil（管制塔）の時は「新しい会話」を出さない
    var workspace: String? = nil
    var onFresh: () -> Void = {}
    let onNew: () -> Void
    @AppStorage(Cockpit.SessionOrigin.key) private var origin = Cockpit.SessionOrigin.all

    private func shows(_ id: String) -> Bool { origin.shows(at22: cockpit.isAT22(id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionMark(number: "01", title: "TALK", jp: "会話")
            Text("Pick a session.").font(.display(52)).foregroundStyle(Palette.Light.fg)
            Text("どの会話を見るかを選ぶと、司令塔とのやり取りがここに流れます。")
                .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
            HStack(spacing: 8) {
                if let workspace {
                    Button("＋ 新しい会話", action: onFresh).buttonStyle(SumiButtonStyle(primary: true))
                        .help((workspace as NSString).lastPathComponent + " で新しい会話を始める")
                }
                Button("＋ 新しいワークスペース", action: onNew).buttonStyle(SumiButtonStyle(primary: workspace == nil))
                    .help("worktree を作ってエージェントを起こす")
            }
            OriginSwitch(origin: $origin)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let live = cockpit.liveSessions.filter { shows($0.id) }
                    if !live.isEmpty {
                        group("実行中")
                        ForEach(live) { session in
                            line(title: cockpit.title(for: session.id) ?? session.name,
                                 sub: (session.cwd as NSString).lastPathComponent,
                                 live: session.busy) { cockpit.selectedSession = session.id }
                        }
                    }
                    let recent = cockpit.recentSessions.filter { shows($0.id) }
                    let byProject = Dictionary(grouping: recent) { $0.project }
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
                    let codex = cockpit.runRecords.filter { !liveIDs.contains($0.id) && shows($0.id) }
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
                    if live.isEmpty && recent.isEmpty && codex.isEmpty {
                        Text(origin == .all ? "履歴はまだない" : "\(origin.label)の会話はない").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg3).padding(.top, 12)
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

/// 発言の Markdown を解釈した結果を覚えておく。画面は毎秒描き直すので、毎回解釈し直すと
/// 遡って行が増えるほど重くなる。ponytail: 2000件で丸ごと捨てる（数千件の会話になったら LRU に）
@MainActor
enum MarkdownCache {
    private static var store: [Int: (count: Int, text: AttributedString)] = [:]

    static func text(_ id: Int, _ raw: String) -> AttributedString {
        // utf8.count は数えずに出る（count は全文を歩く）
        if let hit = store[id], hit.count == raw.utf8.count { return hit.text }
        if store.count > 2000 { store.removeAll() }
        let text = TalkScreen.formatted(raw)
        store[id] = (raw.utf8.count, text)
        return text
    }
}

/// 発言の URL を覚えておく（毎秒の描き直しで NSDataDetector を回さない）
@MainActor
enum LinkCache {
    private static var store: [Int: (count: Int, links: [URL])] = [:]

    static func links(_ id: Int, _ text: String) -> [URL] {
        if let hit = store[id], hit.count == text.utf8.count { return hit.links }
        if store.count > 2000 { store.removeAll() }
        let links = BrowserSheet.links(in: text)
        store[id] = (text.utf8.count, links)
        return links
    }
}
