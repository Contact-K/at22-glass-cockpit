import SwiftUI

// 会話サイドバー。セッションの会話表示・新規起動・履歴切替をメインウィンドウ左側で完結させる

struct ConversationSidebar: View {
    let cockpit: Cockpit
    /// 呼び出しの行を押した時に作業画面へ移す。**作業そのものはあちらが持つ**
    var onOpenWork: () -> Void = {}
    /// 門を「書き換えて発行」したい時に、本文を編み直す欄を開いてもらう。
    /// **答える口はサイドバーの1つに寄せてある**（5a）。許可と却下はここで完結し、
    /// 書き換えだけは文章を編む場所が要るのでキャンバス側の欄に渡す。
    /// 答える経路を2つ持つと「どっちで答えたか」が分からなくなる

    enum Pane {
        case conversation
        case newSession
        case history
    }

    @State private var pane = Pane.conversation
    @AppStorage("showThinking") private var showThinking = false
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    @AppStorage("launchBackend") private var launchBackend: String = Backend.claude.rawValue
    @AppStorage("launchModel") private var launchModel = ""
    @State private var draft = ""
    @State private var failed = false
    @State private var launchPrompt = ""
    @State private var launchDirectory = ""
    @State private var launchFailed = false
    @State private var launching = false
    @State private var selectedGateLevel = Gate.defaultLevel
    @State private var confirmingLevel = false
    @State private var riskyLevel: Gate.Level?
    @State private var customModelID = ""
    @State private var pickDirectory = false
    /// 起こす口が塞がっている時に、その場から設定へ飛ばす
    @Environment(\.openSettings) private var openSettings

    /// セッションを起こせる状態か。**塞がっていてもボタンは消さない**——
    /// 消すと「なぜ出ないのか」が画面のどこにも無くなる
    private var launcherReady: Bool {
        launcherEnabled && !cockpit.found.isEmpty
    }

    private var launcherBlocked: String {
        launcherEnabled
            ? "claude / codex のコマンドが見つからない。設定で場所を指定する（押すと設定へ）"
            : "設定の「連携」で「セッションを起こす」を入にすると使える（押すと設定へ）"
    }

    /// 字面だけのボタン。素の `.plain` は当たり判定が字の箱ぴったりで掴みにくいので、
    /// 余白ぶんまで押せる形にしておく
    private func link(_ title: String, tone: Color = Palette.ink,
                      help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(tone)
                .padding(.horizontal, Palette.Space.s1)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var messages: [Message] {
        let session = cockpit.selectedSession
        guard session != nil else { return [] }
        return cockpit.messages.filter {
            $0.session == session && (showThinking || !$0.thinking)
        }
    }

    /// 会話に流すもの。**言葉と「呼び出した」を時刻順に混ぜる**——
    /// 別々の一覧にすると、どの発言の流れで誰を呼んだのかが読めなくなる
    private enum Entry: Identifiable {
        case said(Message)
        case called(Cockpit.AgentCall)

        var id: String {
            switch self {
            case let .said(m):   "m\(m.id)"
            case let .called(c): "c" + c.id
            }
        }
        var at: Date {
            switch self {
            case let .said(m):   m.at
            case let .called(c): c.at
            }
        }
    }

    private var entries: [Entry] {
        let calls = cockpit.agentCalls(session: cockpit.selectedSession).map(Entry.called)
        return (messages.map(Entry.said) + calls).sorted { $0.at < $1.at }
    }

    /// セッションを選ぶまでは履歴を出す。**起動直後にいちばん先に決めることは
    /// 「どの会話を見るか」**で、空の会話画面を見せても次の一手が無い
    private var shownPane: Pane {
        cockpit.selectedSession == nil ? .history : pane
    }

    var body: some View {
        VStack(spacing: 0) {
            switch shownPane {
            case .conversation:
                conversationView
            case .newSession:
                newSessionView
            case .history:
                historyView
            }
        }
        .background(CockpitCanvas.background)
        // 左の木から別のセッションを選んだら会話を出す。履歴や新規の画面のままだと、選んだのに何も変わらない
        .onChange(of: cockpit.selectedSession) { _, selected in
            if selected != nil { pane = .conversation }
        }
        .alert("この段は人間の承認なしにファイルを書き換える", isPresented: Binding(
            get: { confirmingLevel && riskyLevel != nil },
            set: { if !$0 { confirmingLevel = false; riskyLevel = nil } }
        )) {
            Button("やめる", role: .cancel) { riskyLevel = nil }
            Button("承知した", role: .destructive) {
                if let level = riskyLevel {
                    selectedGateLevel = level
                    cockpit.setGateLevel(level)
                }
                riskyLevel = nil
            }
        } message: {
            Text("\(riskyLevel?.title ?? "") では、起こしたセッションが確認を求めずに編集します。")
        }
    }

    // MARK: - 会話表示

    private var conversationView: some View {
        VStack(spacing: 0) {
            // 章見出し。5a は画面の区画に 01/02/03/04 の通し番号を振り、
            // 「番号 → 章名 → 件数」の順で必ず同じ形に並べる。
            // どの区画を見ているかが、目を上げずに分かる
            HStack(alignment: .firstTextBaseline, spacing: Palette.Space.s2) {
                Text("01")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
                Text("会話")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .tracking(Palette.Tracking.wider)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: Palette.Space.tiny)
                Text("\(messages.count)")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, Palette.Space.s3)
            .padding(.top, Palette.Space.small)
            .padding(.bottom, Palette.Space.s1)

            // ヘッダバー
            VStack(alignment: .leading, spacing: Palette.Space.s1) {
                HStack(spacing: Palette.Space.s2) {
                    if let sessionID = cockpit.selectedSession {
                        if let title = cockpit.title(for: sessionID) {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .lineLimit(1)
                        } else {
                            Text(String(sessionID.prefix(8)))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                    } else {
                        Text("未選択")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }

                    // バックエンド/モデルバッジ
                    if let sessionID = cockpit.selectedSession {
                        if cockpit.backend(of: sessionID) != .claude {
                            Text(cockpit.backend(of: sessionID).title)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 2).fill(CockpitCanvas.dim.opacity(0.2)))
                        }
                    }

                    Spacer(minLength: Palette.Space.tiny)
                    modelMenu
                }

                // 計器帯。**3つとも「いま見ているセッション」の数字**なので、
                // タイトルバーとタブ行に散らさずここへ集めた——
                // セッションを選び直した時に、数字が入れ替わるのが目で追える
                HStack(spacing: Palette.Space.s3) {
                    LevelKnob(cockpit: cockpit,
                              confirmingLevel: $confirmingLevel, riskyLevel: $riskyLevel)
                    Spacer(minLength: Palette.Space.s1)
                    SpendReadout(cockpit: cockpit)
                }
                ContextGauge(cockpit: cockpit, track: 96)

                HStack(spacing: 8) {
                    Toggle("思考も出す", isOn: $showThinking)
                        .font(.system(size: 10, design: .monospaced))
                        .scaleEffect(0.9, anchor: .trailing)
                    Spacer(minLength: 6)
                    link("履歴", help: "セッション一覧へ") { pane = .history }
                    link("＋新規",
                         tone: launcherReady ? Palette.ink : Palette.inkTertiary,
                         help: launcherReady ? "新しいセッションを起こす" : launcherBlocked) {
                        if launcherReady { pane = .newSession } else { openSettings() }
                    }
                }
            }
            .padding(.horizontal, Palette.Space.s3)
            .padding(.bottom, Palette.Space.s2)
            Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair)

            // 会話の流れ。**言葉と「呼び出した」を時刻順に混ぜる**
            if entries.isEmpty {
                Spacer()
                Text(cockpit.messages.isEmpty
                     ? "まだ言葉が来ていない"
                     : "このセッションの言葉は無い（thinking を出すと見えるかもしれない）")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // 吹き出しをやめて、罫線で区切った行にした（5a）。
                        // 300pt 幅の欄で左右に振り分けると、どちらの側も本文が
                        // 半分の幅しか使えない。話者は行の頭のラベルで足りる
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                switch entry {
                                case let .said(message): messageRow(message).id(entry.id)
                                case let .called(call):  callRow(call).id(entry.id)
                                }
                            }
                            if cockpit.isWorking(cockpit.selectedSession) {
                                WorkingNeedle()
                                    .padding(.horizontal, Palette.Space.s3)
                                    .padding(.vertical, Palette.Space.s2)
                                    .id(Self.needleID)
                            }
                        }
                        .padding(.vertical, Palette.Space.tiny)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: entries.count) { _, _ in
                        guard let last = entries.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    .onChange(of: cockpit.isWorking(cockpit.selectedSession)) { _, working in
                        guard working else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.needleID, anchor: .bottom) }
                    }
                }
            }

            Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair)

            // 門の停止カードは**キャンバス側の明るいパネル**（`GatePanel`）に移した。
            // レールの上に立つ紙と同じ高さに並ぶので、どの行が止まったのかが線で繋がる。
            // ここに残すと答える口が2つに割れて、「どちらで答えたか」が曖昧になる
            composer
        }
        .background(Palette.fieldSubtle)
    }

    private static let needleID = "at22.needle"

    /// 打つ場所。**欄もボタンも灰色にしない**——
    /// 以前は「AT22 が起こしたセッションだけ」で止めていたので、履歴から開いた会話は
    /// 一言も送れず画面が行き止まりになっていた。いまは送る直前に `claude --resume` が繋ぐ。
    /// ボタンは1つで、生成中は停止に変わる（割り込みという別概念は畳んだ）
    private var composer: some View {
        VStack(alignment: .leading, spacing: Palette.Space.tiny) {
            if failed, let reason = cockpit.launchError {
                Text(reason)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Palette.Space.s2) {
                TextField("メッセージ", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                    .lineLimit(1...5)
                sendKey
            }
        }
        .padding(Palette.Space.small)
    }

    /// 送信と停止を兼ねる1つのボタン
    private var sendKey: some View {
        let working = cockpit.isWorking(cockpit.selectedSession)
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button { working ? interrupt() : send() } label: {
            Image(systemName: working ? "stop.fill" : "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.accent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(cockpit.selectedSession == nil || (!working && empty))
        .help(working ? "生成を止める（セッションは終わらない）" : "送る（⌘Return）")
    }

    /// 会話の1行。**吹き出しではなく罫線で区切った行**（5a）。
    ///
    /// 話者は色ではなく「行の頭の刻印ラベル」で語る。人の発言だけ地をごくわずかに
    /// 持ち上げて、話者の入れ替わりを明度差で追えるようにしてある——
    /// 色を使うと、いま動いているものを示す赤と競り合う
    private func messageRow(_ message: Message) -> some View {
        let isHuman = message.speaker == .human
        let speaker = message.thinking ? "思考" : (isHuman ? "あなた" : "司令塔")

        return VStack(alignment: .leading, spacing: Palette.Space.s1) {
            HStack(spacing: Palette.Space.tiny) {
                Text(speaker)
                    .font(.system(size: Palette.FontSize.etch, design: .monospaced))
                    .tracking(Palette.Tracking.wider)
                    .foregroundStyle(isHuman ? Palette.inkSecondary : Palette.inkTertiary)
                Text(message.at.formatted(.dateTime.hour().minute().second()))
                    .font(.system(size: Palette.FontSize.etch, design: .monospaced))
                    .foregroundStyle(Palette.inkDisabled)
                if !isHuman && message.agent != message.session {
                    Text(String(message.agent.prefix(8)))
                        .font(.system(size: Palette.FontSize.etch, design: .monospaced))
                        .foregroundStyle(Palette.inkDisabled)
                }
                Spacer(minLength: 0)
            }
            // 人が読む文章はここだけプロポーショナル——等幅だと読みにくい。
            // Markdown は `AgentDetail.formatted` に通す（同じ整形を2箇所に書かない）
            Text(message.text.isEmpty
                 ? AttributedString("（本文は残っていない。考えた時刻だけ分かる）")
                 : AgentDetail.formatted(message.text))
                .font(.system(size: Palette.FontSize.body))
                .lineSpacing(2)
                .textSelection(.enabled)
                .foregroundStyle(message.thinking || message.text.isEmpty
                                 ? Palette.inkTertiary : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Palette.Space.s3)
        .padding(.vertical, Palette.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHuman ? Palette.ink.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: Palette.Stroke.hair)
        }
    }

    /// 呼び出したエージェント。**「呼んだ」ことしか語らない**——
    /// 何をしているか・何を触ったかは盤面のエージェント帯が持っている。
    /// ここで全部語ると同じものが2箇所で語られ、どちらを見ればいいのか決まらない
    private func callRow(_ call: Cockpit.AgentCall) -> some View {
        let finished = cockpit.callFinished(call.id)
        return HStack(alignment: .firstTextBaseline, spacing: Palette.Space.s2) {
            Text("◇")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkDisabled)
            Text(call.type.isEmpty ? "エージェント" : call.type)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wide)
                .foregroundStyle(Palette.inkSecondary)
            if !call.title.isEmpty {
                Text(call.title)
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Palette.Space.s1)
            Text(finished == nil ? "起動" : (finished! ? "終了" : "実行中"))
                .font(.system(size: Palette.FontSize.etch, design: .monospaced))
                .foregroundStyle(finished == false ? Palette.accentText : Palette.inkDisabled)
        }
        .padding(.horizontal, Palette.Space.s3)
        .padding(.vertical, Palette.Space.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenWork)
        .help("作業そのものは a 作業 のエージェント帯で追える（押すとそちらへ）")
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: Palette.Stroke.hair)
        }
    }

    /// このセッションのモデル。**選び直しは繋ぎ直しになる**ので、走っている間は触らせない
    private var modelMenu: some View {
        let session = cockpit.selectedSession
        let current = session.flatMap { cockpit.model(of: $0) } ?? ""
        let backend = session.map { cockpit.backend(of: $0) } ?? .claude
        return Menu {
            ForEach(ModelChoice.models(for: backend), id: \.id) { choice in
                Button(choice.title) { if let session { cockpit.setModel(choice.id, for: session) } }
            }
        } label: {
            HStack(spacing: Palette.Space.s1) {
                Image(systemName: "cpu").font(.system(size: 9))
                Text(current.isEmpty ? "モデル" : current)
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.inkSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(session == nil || cockpit.isWorking(session))
        .help("次に繋いだ時から効く。走っているターンの途中では切り替えられない")
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
        if !cockpit.interrupt(cockpit.selectedSession) {
            failed = true
        }
    }

    // MARK: - 新規セッション

    /// 起こせるモデル。**バックエンドが見つかっている側だけ**を出す
    private var models: [ModelChoice] {
        ModelChoice.models(for: Backend(rawValue: launchBackend) ?? .claude)
    }

    /// **`ScrollView` に入れるのが要点。** 400pt 幅の欄に Picker 3つ・入力欄・120pt の
    /// テキスト欄を素の `VStack` で積んでいたので、下端の「起こす」が枠の外に落ちていた
    private var newSessionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Palette.Space.small) {
                HStack {
                    Text("セッションを起こす")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Spacer()
                    link("戻る", help: "会話へ") { pane = .conversation }
                }

                field("バックエンド") {
                    Picker("バックエンド", selection: $launchBackend) {
                        // 見つかっていない側は出さない。`Picker` の中身に `.disabled` を
                        // 付けても効かないので、以前は「CLI が見つからない」を選べてしまった
                        ForEach(Backend.allCases.filter { $0 == .claude || cockpit.found[$0] != nil }, id: \.self) { backend in
                            Text(backend.title).tag(backend.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                field("モデル") {
                    Picker("モデル", selection: $launchModel) {
                        ForEach(models, id: \.id) { model in
                            Text(model.title).tag(model.id)
                        }
                        Divider()
                        Text("カスタム…").tag(Self.customModel)
                    }
                    .labelsHidden()
                    if launchModel == Self.customModel {
                        TextField("モデルID", text: $customModelID)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                field("実行モード") {
                    Picker("実行モード", selection: $selectedGateLevel) {
                        ForEach(Gate.Level.allCases, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedGateLevel) { oldLevel, newLevel in
                        if newLevel.needsConfirmation {
                            selectedGateLevel = oldLevel
                            riskyLevel = newLevel
                            confirmingLevel = true
                        }
                    }
                }

                field("作業ディレクトリ") {
                    HStack(spacing: Palette.Space.s2) {
                        TextField("作業ディレクトリ", text: $launchDirectory)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        Button("選ぶ…") { pickDirectory = true }
                            .font(.system(size: 11, design: .monospaced))
                    }
                }

                field("最初の指示") {
                    TextEditor(text: $launchPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 140)
                        .padding(Palette.Space.tiny)
                        .inset()
                }

                if launchFailed {
                    Text(cockpit.launchError
                         ?? "起こせなかった。バックエンドの場所と作業ディレクトリを確かめる")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("やめる") { resetLaunchState() }
                    Button("起こす") { launchNew() }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .disabled(launchPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || launchDirectory.isEmpty || launching
                                  || (launchModel == Self.customModel && customModelID.isEmpty))
                }
            }
            .padding(Palette.Space.s3)
        }
        .background(CockpitCanvas.background)
        .fileImporter(isPresented: $pickDirectory, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { launchDirectory = url.path }
        }
        .onAppear {
            // GUI アプリの `currentDirectoryPath` は `/`。そこで起こすと何も見つからない
            if launchDirectory.isEmpty {
                launchDirectory = cockpit.selectedSession
                    .flatMap { id in cockpit.liveSessions.first { $0.id == id }?.cwd }
                    .flatMap { $0.isEmpty ? nil : $0 }
                    ?? NSHomeDirectory()
            }
            // 既定が空文字だと、どの `tag` にも一致せず Picker が空欄で立ち上がる
            if !models.contains(where: { $0.id == launchModel }), launchModel != Self.customModel {
                launchModel = models.first?.id ?? ""
            }
            selectedGateLevel = cockpit.gateLevel
        }
        .onChange(of: launchBackend) {
            // 族をまたぐとモデルIDが通じない。その族の先頭へ寄せ直す
            if !models.contains(where: { $0.id == launchModel }) {
                launchModel = models.first?.id ?? ""
            }
        }
    }

    static let customModel = "__custom__"

    /// ラベル＋中身。同じ形で積むと、どこまでが1項目か目で切れる
    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Palette.Space.s1) {
            Text(title)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wide)
                .foregroundStyle(Palette.inkTertiary)
            content()
        }
    }

    private func launchNew() {
        launching = true

        // 承認の段は `launch` に渡す。ここで `setGateLevel` を呼ぶと、**選択中の別セッション**の
        // プロジェクトに書いてしまっていた（起こす先のプロジェクトへは launch 側が書く）

        // モデルID の取得
        let modelID = launchModel == Self.customModel ? customModelID : launchModel

        // バックエンドの取得
        let backend = Backend(rawValue: launchBackend) ?? .claude

        if cockpit.launch(prompt: launchPrompt, cwd: launchDirectory,
                         backend: backend, model: modelID, level: selectedGateLevel) != nil {
            resetLaunchState()
            pane = .conversation
        } else {
            launchFailed = true
            launching = false
        }
    }

    private func resetLaunchState() {
        launchPrompt = ""
        launchDirectory = ""
        launchFailed = false
        launching = false
        customModelID = ""
        confirmingLevel = false
        riskyLevel = nil
        pane = .conversation
    }

    // MARK: - 履歴・セッションスイッチャー

    private var historyView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("セッション一覧")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Button("戻る") { pane = .conversation }
                    .font(.system(size: 11, design: .monospaced))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if cockpit.liveSessions.isEmpty && cockpit.recentSessions.isEmpty && cockpit.runRecords.isEmpty {
                Spacer()
                Text("履歴はまだない")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ライブセッション
                        if !cockpit.liveSessions.isEmpty {
                            Text("実行中")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CockpitCanvas.dim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)

                            ForEach(cockpit.liveSessions) { session in
                                liveSessionRow(session)
                            }
                            Divider().padding(.vertical, 4)
                        }

                        // 過去セッション（プロジェクト別グルーピング）
                        let recentByProject = Dictionary(grouping: cockpit.recentSessions) { $0.project }
                            .sorted { ($0.value.first?.modifiedAt ?? .distantPast) > ($1.value.first?.modifiedAt ?? .distantPast) }

                        if !recentByProject.isEmpty {
                            Text("履歴")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CockpitCanvas.dim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)

                            ForEach(recentByProject, id: \.key) { project, sessions in
                                Section {
                                    ForEach(sessions) { session in
                                        recentSessionRow(session)
                                    }
                                } header: {
                                    Text(project)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(CockpitCanvas.dim)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                }
                            }
                        }

                        // transcript を AT22 が読まない相手（Codex / Grok）のセッション
                        let liveRecordIDs = Set(cockpit.liveSessions.compactMap { session in
                            cockpit.backend(of: session.id) != .claude ? session.id : nil
                        })
                        let inactiveRunRecords = cockpit.runRecords.filter { !liveRecordIDs.contains($0.id) }

                        if !inactiveRunRecords.isEmpty {
                            if !recentByProject.isEmpty || !cockpit.liveSessions.isEmpty {
                                Divider().padding(.vertical, 4)
                            }
                            Text("Codex・Grok")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CockpitCanvas.dim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)

                            ForEach(inactiveRunRecords.sorted(by: { $0.lastUsed > $1.lastUsed })) { record in
                                recordRow(record)
                            }
                        }
                    }
                }
            }
        }
        .background(CockpitCanvas.background)
    }

    private func liveSessionRow(_ session: LiveSession) -> some View {
        Button {
            cockpit.selectedSession = session.id
            pane = .conversation
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.busy ? CockpitCanvas.live : CockpitCanvas.rule)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    if let title = cockpit.title(for: session.id) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .lineLimit(1)
                    } else {
                        Text(session.name)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    Text(String((session.cwd as NSString).lastPathComponent))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let reading = cockpit.readings[session.id] {
                    SnowmanBadge(reading: reading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cockpit.selectedSession == session.id ? CockpitCanvas.agentOn.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func recentSessionRow(_ session: RecentSession) -> some View {
        Button {
            Task {
                cockpit.selectedSession = session.id
                await cockpit.loadSession(session)
                pane = .conversation
            }
        } label: {
            HStack(spacing: 8) {
                if cockpit.activeSessions.contains(session.id) {
                    Circle()
                        .fill(CockpitCanvas.rule)
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title = cockpit.title(for: session.id) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .lineLimit(1)
                        Text(session.project)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CockpitCanvas.dim)
                            .lineLimit(1)
                    } else {
                        Text(session.project)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    Text(session.modifiedAt.formatted(.dateTime.month().day().hour().minute()))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cockpit.selectedSession == session.id ? CockpitCanvas.agentOn.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func recordRow(_ record: Cockpit.RunRecord) -> some View {
        Button {
            Task {
                cockpit.selectedSession = record.id
                cockpit.resumeRunRecord(record)
                pane = .conversation
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 4, height: 4)
                VStack(alignment: .leading, spacing: 2) {
                    if let title = cockpit.title(for: record.id) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .lineLimit(1)
                    } else {
                        Text(String(record.id.prefix(8)))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                    }
                    Text(record.backend.title + " · " + String((record.cwd as NSString).lastPathComponent))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                        .lineLimit(1)
                    Text(record.lastUsed.formatted(.dateTime.month().day().hour().minute()))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cockpit.selectedSession == record.id ? CockpitCanvas.agentOn.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 生成中の印

/// 「思考中 ●」の代わり。**計器の針が回っている**形にする——
/// 汎用スピナーはこの筐体の語彙に無い。ヘアラインの環の上を accent の弧が1周する。
///
/// 赤は「いま」の1系統なので規律に収まる。面ではなく線なので、
/// `dotRed`（一画面に1つ）の点とも競合しない。
/// ponytail: 針1本。息継ぎも多段のイージングも付けない——速度が合わなければ `turn` だけ触る
struct WorkingNeedle: View {
    /// 1周にかける秒数
    var turn: TimeInterval = 1.2
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSince1970
                .truncatingRemainder(dividingBy: turn) / turn
            HStack(spacing: Palette.Space.s2) {
                Canvas { context, canvas in
                    let inset: CGFloat = 1.5
                    let box = CGRect(x: inset, y: inset,
                                     width: canvas.width - inset * 2,
                                     height: canvas.height - inset * 2)
                    // 目盛りの環。動かない側
                    context.stroke(Path(ellipseIn: box),
                                   with: .color(Palette.inkDisabled), lineWidth: 1)
                    // 針。90度ぶんの弧が回る
                    let start = Angle.degrees(phase * 360 - 90)
                    var needle = Path()
                    needle.addArc(center: CGPoint(x: box.midX, y: box.midY),
                                  radius: box.width / 2,
                                  startAngle: start, endAngle: start + .degrees(90),
                                  clockwise: false)
                    context.stroke(needle, with: .color(Palette.accent),
                                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                .frame(width: size, height: size)

                Text(elapsed(now: timeline.date))
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .tracking(Palette.Tracking.wide)
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    /// 何秒待っているか。回っているだけだと「進んでいるのか固まったのか」が分からない
    @State private var since = Date()
    private func elapsed(now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(since)))
        return seconds < 1 ? "生成中" : "生成中 \(seconds)秒"
    }
}

// MARK: - SnowmanBadge

private struct SnowmanBadge: View {
    let reading: Snowman.Reading

    private var color: Color {
        switch reading.stage {
        case .fresh, .rolling: CockpitCanvas.dim
        case .heavy:           CockpitCanvas.agentOn
        case .warning:         CockpitCanvas.error
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Canvas { context, size in
                let g = reading.growth
                // 器：下の胴（大）と上の頭（小）。外形は常に同じ
                let body = CGRect(x: size.width / 2 - 8, y: size.height - 17, width: 16, height: 16)
                let head = CGRect(x: size.width / 2 - 5, y: size.height - 27, width: 10, height: 10)
                let outline = Path(ellipseIn: body).union(Path(ellipseIn: head))

                context.stroke(outline, with: .color(CockpitCanvas.rule), lineWidth: 0.8)
                // 積もった分だけ下から塗る
                if g > 0 {
                    let top = head.minY + (1 - g) * (body.maxY - head.minY)
                    context.clip(to: Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)))
                    context.fill(outline, with: .color(color.opacity(0.55)))
                }
            }
            .frame(width: 22, height: 30)
            // 警報だけは縁でも分かるようにする。色覚に頼りきらない
            .overlay {
                if reading.stage == .warning {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(CockpitCanvas.error.opacity(0.8), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(reading.stage.title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(reading.stage == .warning ? CockpitCanvas.error : CockpitCanvas.dim)

                // ゲージ
                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(CockpitCanvas.rule.opacity(0.25))
                            let fillWidth = geo.size.width * min(1, reading.growth)
                            let barColor: Color = {
                                if reading.growth < 0.5 { return CockpitCanvas.live }
                                else if reading.growth < 0.8 { return CockpitCanvas.flag }
                                else { return CockpitCanvas.error }
                            }()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor)
                                .frame(width: fillWidth)
                        }
                    }
                    .frame(width: 64, height: 6)
                    Text("\(Int(reading.growth * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                }
            }
        }
        .help(reading.caption)
        .opacity(reading.tokens == 0 ? 0.35 : 1)
    }

}
