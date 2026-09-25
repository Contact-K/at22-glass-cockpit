import SwiftUI
import AppKit

// MARK: - 画面

struct CockpitView: View {
    let cockpit: Cockpit

    /// クリックで開いているもの。矩形は吹き出しを出す位置に使う
    private enum Picked: Identifiable {
        case file(path: String, rect: CGRect)
        case agent(AgentChip, rect: CGRect)

        var id: String {
            switch self {
            case let .file(path, _): return "f:" + path
            case let .agent(agent, _): return "a:" + agent.id
            }
        }
        var rect: CGRect {
            switch self {
            case let .file(_, rect), let .agent(_, rect): return rect
            }
        }
    }
    @State private var picked: Picked?
    /// ホバー中のファイル。線を引かずに関係を出すための状態（構造モードだけ）
    @State private var hovered: String?
    /// エゴビューを開いているファイル。開いている間はグリッドを触らせない
    @State private var ego: String?
    /// 右の欄で開いている記憶DBのノート。壁打ちモードだけ
    @State private var editing: String?
    /// 未保存の本文がある間は、別ノートや別セッションへの切り替えで捨てない
    @State private var memoryDirty = false
    /// 右の欄で開いている門（`gate/<id>.md` のパス）。作業モードだけ
    @State private var answering: String?


    /// 設定画面（⌘,）と同じ鍵を見る。畳み込みは派生状態を持たないので、
    /// 入れ直せば次のフレームからフラグも右端の点も追従する
    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    @AppStorage("cockpitMode") private var mode = CockpitMode.work
    /// 起動機能は既定オフ。**入れただけで LLM を起こすアプリにはしない**
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    /// `claude` / `codex` の場所を人が指定する口。空ならログインシェルに訊く
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""
    /// 左側に会話サイドバーを表示するか（既定ON）
    @AppStorage("showConversation") private var showConversation = true
    /// 右側にタスクパネルを表示するか（既定OFF）
    @AppStorage("showTasks") private var showTasks = false
    /// 左側の会話サイドバーの幅（既定 400、範囲 300〜640）
    @AppStorage("sidebarWidth") private var sidebarWidth = 400.0
    /// ドラッグ開始時のサイドバー幅
    @State private var dragStartWidth: Double?
    /// 門に答えられなかった時の印。**黙って消さない**（司令塔は待ったまま）
    @State private var gateFailed: String?
    /// ✕ で畳んだ門。答えたわけではないので、レールの G から開き直せる
    @State private var dismissedGate: String?

    private static let canvasSpace = "cockpit"

    /// 筐体。上から タイトルバー / （レール・サイドバー・盤面） / ステータスバー
    private var chassis: some View {
        VStack(spacing: 0) {
            TitleBar(cockpit: cockpit, mode: mode)
            HStack(spacing: 0) {
                ModeRail(showConversation: $showConversation, showTasks: $showTasks)
                shelf
            }
            StatusBar(cockpit: cockpit)
        }
    }

    var body: some View {
        chassis
        // **`onKeyPress` はフォーカスを持つ View にしか来ない。** これが無いと
        // `a` / `b` / `c` も Esc も一生発火せず、`keyboardShortcut` 系（⇧⌘M / ⇧⌘T / ⇧⌘G）
        // だけが効く——「効く鍵と効かない鍵が混ざる」状態になる。
        // 焦点の輪は筐体の意匠と合わないので消す。入力欄に焦点がある間は
        // 文字がそちらへ吸われるので、ここへは落ちてこない（既存の挙動のまま）
        .focusable()
        .focusEffectDisabled()
        .modifier(CockpitKeys(showConversation: $showConversation, showTasks: $showTasks,
                              mode: $mode, locked: memoryDirty))
        // **`.toolbar` は付けない。** `.windowStyle(.hiddenTitleBar)` を指定しても、
        // ツールバーがあると macOS はタイトルバー帯を出し続ける——自作の `TitleBar` と二重になり、
        // 信号機がそちらへ行くので `TitleBar.trafficLightInset` の 78pt が意味のない空白になる。
        // 掃除の2つは `TitleBar` の中へ移した
        .onChange(of: threshold, initial: true) { cockpit.flagReadThreshold = threshold }
        // モードを切り替えても**門の答えかけだけは畳まない**。門が止まっている間は
        // 表示モードに関係なく司令塔が待っているので、畳むと答える口が消える
        .onChange(of: mode) { ego = nil; hovered = nil }
        // 答えた門は消えるので、欄も一緒に閉じる（答えた後に空の欄が残らない）
        .onChange(of: cockpit.gates.map(\.id)) { _, ids in
            if let answering, !ids.contains(answering) { self.answering = nil }
        }
        // 連携設定を変えたら探し直す。トグルをオンにした後やパスを変えた後に即座に見つかるように。
        // **codex 側は呼び出し元が1つも無く、`codexFound` が永久に nil だった**——
        // バックエンド選択が常に「CLI が見つからない」になっていた原因
        .onChange(of: launcherEnabled) { findCLIs(force: true) }
        .onChange(of: claudePath) { findCLIs(force: true) }
        .onChange(of: codexPath) { findCLIs(force: true) }
        // Esc は手前から順に畳む。重なっているものを一度に全部消すと、
        // 「戻る」つもりで押した時に土台まで戻ってしまう
        .onKeyPress(.escape) {
            if picked != nil { picked = nil; return .handled }
            if showTasks { showTasks = false; return .handled }
            if ego != nil { ego = nil; return .handled }
            return .ignored
        }
        .task {
            findCLIs(force: false)
            while !Task.isCancelled {
                cockpit.housekeeping()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// claude と codex を両方探す。**片方だけ呼ぶ書き方をやめた**——
    /// codex 側は呼び出し元が抜け落ちたまま気づかれず、Codex 経路が丸ごと到達不能だった
    private func findCLIs(force: Bool) {
        cockpit.findClaudeIfNeeded(override: claudePath.isEmpty ? nil : claudePath, force: force)
        cockpit.findCodexIfNeeded(override: codexPath.isEmpty ? nil : codexPath, force: force)
    }

    /// レールが押した「門を開け」。作業タブへ移して、いちばん古い門を開き直す。
    /// ✕ で畳んだ後もここから戻せる（答えていない門を閉じきりにしない）
    private func openGate() {
        mode = .work
        dismissedGate = nil
        answering = cockpit.gates.min { $0.issued < $1.issued }?.id
    }

    /// レールの右側ぜんぶ。会話サイドバー ＋（タブ・進行表・盤面）
    private var shelf: some View {
        HStack(spacing: 0) {
            if showConversation {
                // 門はキャンバス側の `GatePanel` で答える。サイドバーは会話だけを持つ
                ConversationSidebar(cockpit: cockpit, onOpenWork: { mode = .work })
                    .frame(width: sidebarWidth)
                // 掴む帯は 6pt に固定する。`Divider` は横幅を主張しないので、
                // 枠を与えないと ZStack が残り幅の取り合いに参加して盤面を半分持っていく
                ZStack {
                    // `Divider()` は暗い地の上で白く出て主張しすぎる。DS の罫を使う
                    Rectangle().fill(Palette.border).frame(width: Palette.Stroke.hair)
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    if dragStartWidth == nil {
                                        dragStartWidth = sidebarWidth
                                    }
                                    let translation = gesture.translation.width
                                    let newWidth = (dragStartWidth ?? sidebarWidth) + translation
                                    sidebarWidth = min(640, max(300, newWidth))
                                }
                                .onEnded { _ in
                                    dragStartWidth = nil
                                }
                        )
                }
                .frame(width: 6)
            }
            VStack(spacing: 0) {
                TabBar(cockpit: cockpit, mode: $mode, locked: memoryDirty)
                ProgressStripBar(cockpit: cockpit) { showTasks.toggle() }
                canvas
            }
            // タブ行と進行表の帯は地を持たない（沈めた面と罫線だけで出す）ので、
            // 列そのものに地を敷く。敷かないと窓の素の白が透ける
            .background(Palette.field)
            // タスク一覧は中央のモーダル。**手を止めて確かめるもの**なので、
            // 横目で見る側（最上段の帯）とは出し方を分けてある
            .overlay {
                if showTasks {
                    TaskPanel(cockpit: cockpit) { showTasks = false }
                }
            }
        }
    }

    private var canvas: some View {
        // 壁打ちの編集欄は GeometryReader の外に置く。中で safeAreaInset を使うと
        // 「欄で幅が縮む → geo.size が変わる → 組み直す」の輪ができるうえ、
        // レイアウトは縮む前の幅で組まれるので右の列が欄の下に潜る
        HStack(spacing: 0) {
            board
            if mode == .memory, let editing, let node = cockpit.memoryNode(at: editing) {
                Divider()
                MemoryEditor(node: node,
                             onSave: { text, expected, overwrite in
                                 cockpit.saveNote(path: editing, text: text,
                                                  expectedText: expected, overwrite: overwrite)
                             },
                             onClose: { self.editing = nil },
                             onDirtyChange: { memoryDirty = $0 })
                    .frame(width: 420)
            }
        }
        // 門は**エージェント帯の右**に立てる。レールの上の紙と同じ高さに並ぶので、
        // どの行が止まったのかが目で繋がる。許可・書換・却下はここで完結する
        .overlay(alignment: .topTrailing) {
            if let request = stoppedGate {
                GatePanel(request: request,
                          failed: gateFailed == request.id,
                          onAnswer: { verdict, revised in
                              // 書けたかどうかは必ず見る。黙って消すと司令塔が待ち続ける
                              if cockpit.answer(request, verdict, revised: revised) == .saved {
                                  gateFailed = nil
                                  answering = nil
                              } else {
                                  gateFailed = request.id
                              }
                          },
                          onClose: { dismissedGate = request.id })
                    .padding(.top, Palette.Space.small)
                    .padding(.trailing, Palette.Space.s3)
                    .transition(.opacity)
            }
        }
    }

    /// いま答えを出す1件。**複数溜まっていても出すのは待たせている順に1件だけ**——
    /// 並べると「どれに答えているか」が曖昧になる。閉じた門は次が来るまで出さない
    private var stoppedGate: Gate.Request? {
        guard mode == .work else { return nil }
        let pending = cockpit.gates.filter { $0.id != dismissedGate }
        // 明示的に開いた門があればそれを優先する（レールの G キーや紙を押した時）
        if let answering, let picked = pending.first(where: { $0.id == answering }) { return picked }
        return pending.min { $0.issued < $1.issued }
    }

    /// 盤面。**セッションを選ぶまでは組まない。**
    ///
    /// 絞り込みが無いと、そのマシンが触った全プロジェクトのファイルが1枚に並ぶ——
    /// 起動直後にいちばん情報量が多い画面が出るのは逆で、まず「どの会話を見るか」を選ばせる。
    /// `CockpitLayout.compute` を呼ばないので、集計そのものが走らない
    @ViewBuilder
    private var board: some View {
        if cockpit.selectedSession == nil { emptyBoard } else { liveBoard }
    }

    private var emptyBoard: some View {
        VStack(spacing: Palette.Space.s2) {
            Text("セッションを選択すると表示されます")
                .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)
            Text("左の一覧から選ぶか、＋新規で起こす")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkDisabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CockpitCanvas.background)
    }

    private var liveBoard: some View {
        GeometryReader { geo in
            ScrollView {
                // 動いている時だけ 30fps。止まったら 3fps に落とす。
                // ponytail: 常時30fps以上だと、何も起きていない間も全ファイル名を
                // 毎フレーム組み直して常時20%以上CPUを食う
                TimelineView(.periodic(from: .now, by: cockpit.isBusy ? 1.0 / 30.0 : 1.0 / 3.0)) { timeline in
                    let snapshot = cockpit.snapshot(now: timeline.date, mode: mode)
                    let layout = CockpitLayout.compute(snapshot, width: geo.size.width)
                    // 止まっている方は遅い刻みに丸める。ここが変わった時だけ描き直す
                    let steady = CockpitLayout.steadyDate(timeline.date)
                    ZStack(alignment: .topLeading) {
                        StillLayer(layout: layout, snapshot: snapshot, mode: mode,
                                   structure: cockpit.structure,
                                   hovered: ego == nil ? hovered : nil,
                                   steady: steady)
                            .equatable()
                        // 動く方は地を持たない。ビーム・流れる紙・脈打つセルとチップだけ
                        Canvas { context, size in
                            CockpitCanvas.draw(&context, size: size, layout: layout,
                                               snapshot: snapshot, now: timeline.date,
                                               mode: mode, structure: cockpit.structure,
                                               hovered: ego == nil ? hovered : nil,
                                               layer: .live, steady: steady)
                        }
                    }
                    .frame(width: geo.size.width,
                           height: max(geo.size.height, layout.contentHeight))
                }
                .coordinateSpace(.named(Self.canvasSpace))
                // セルをクリックすると書き込みの内訳を出す。当たり判定はその場で組み直す。
                // 描画中の layout を @State に写すと毎フレーム更新になるので、押された時だけ計算する
                // 構造モードは押した1件のまわりを開く（エゴビュー）。
                // 作業モードは触った履歴を吹き出しで出す。同じクリックでも軸が違う
                .onContinuousHover(coordinateSpace: .named(Self.canvasSpace)) { phase in
                    guard mode == .structure, ego == nil else { hovered = nil; return }
                    guard case let .active(point) = phase else { hovered = nil; return }
                    let layout = CockpitLayout.compute(cockpit.snapshot(now: .now, mode: mode),
                                                       width: geo.size.width)
                    let hit = layout.file(at: point)
                    if hit != hovered { hovered = hit }
                }
                .onTapGesture(coordinateSpace: .named(Self.canvasSpace)) { point in
                    if ego != nil { ego = nil; return }        // 重なっている間はどこを押しても戻る
                    let snapshot = cockpit.snapshot(now: .now, mode: mode)
                    let layout = CockpitLayout.compute(snapshot, width: geo.size.width)
                    // 門が最優先。紙はチップの通り道に立つので、チップより先に見ないと下に取られる
                    if let id = layout.gate(at: point) {
                        answering = id
                    } else if let id = layout.chip(at: point),
                              let chip = snapshot.chips.first(where: { $0.id == id }) {
                        picked = .agent(chip, rect: layout.chipRect(forAgent: id) ?? .zero)
                    } else if let path = layout.file(at: point) {
                        // 記憶DBは吹き出しではなく右の欄で開く。読むだけでなく書くため
                        if mode == .memory {
                            // 実体のない見出しは touched が false なので、押しても何も開かない
                            if snapshot.cards.flatMap(\.files).first(where: { $0.id == path })?.touched == true {
                                if !memoryDirty || editing == path { editing = path }
                            }
                        } else if mode == .structure { ego = path; hovered = nil }
                        else { picked = .file(path: path, rect: layout.rect(forFile: path) ?? .zero) }
                    } else {
                        picked = nil
                    }
                }
            }
            .background(CockpitCanvas.background)
            // 押した先は**中央のモーダル**。吹き出しで出していた頃は、
            // 画面の端のセルを押すと吹き出しが窓の外へ逃げて半分しか読めなかった
            .overlay {
                if let picked {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { self.picked = nil }
                        .overlay {
                            switch picked {
                            case let .file(path, _):
                                FileHistory(path: path, entries: cockpit.writeHistory(of: path),
                                            reads: cockpit.readCounts(of: path),
                                            note: cockpit.structure.notes[path],
                                            dependsOn: cockpit.structure.dependsOn[path] ?? [],
                                            usedBy: cockpit.structure.usedBy[path] ?? [],
                                            onClose: { self.picked = nil })
                                    .onTapGesture {}
                            case let .agent(agent, _):
                                AgentDetail(agent: agent, files: cockpit.touchedFiles(by: agent.id))
                                    .frame(width: 440)
                                    .background(Palette.fieldSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.sm))
                                    .overlay(RoundedRectangle(cornerRadius: Palette.Radius.sm)
                                        .stroke(Palette.border, lineWidth: Palette.Stroke.border))
                                    .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
                                    .onTapGesture {}
                            }
                        }
                }
            }
            // エゴビューはスクロールの外に重ねる。中に描くと、下までスクロールした状態で
            // 開いたときに内容の先頭（＝画面外）に出てしまう
            .overlay {
                if let ego {
                    Canvas { context, size in
                        CockpitCanvas.drawEgo(&context, size: size,
                            view: CockpitLayout.ego(path: ego, graph: cockpit.structure,
                                                    lastEdit: cockpit.writeHistory(of: ego).first?.added,
                                                    size: size))
                    }
                    .contentShape(Rectangle())
                    // 行を押したらそのファイルの解説へ移る。何も無いところなら閉じる。
                    // 呼んでいる先・呼ばれている元から辿れないと、隣を見るのに一度戻る羽目になる
                    .onTapGesture(coordinateSpace: .local) { point in
                        let view = CockpitLayout.ego(path: ego, graph: cockpit.structure,
                                                     lastEdit: cockpit.writeHistory(of: ego).first?.added,
                                                     size: geo.size)
                        if let next = view.file(at: point), next != ego { self.ego = next }
                        else if !view.holdsFocus(at: point) { self.ego = nil }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.22), value: ego)
        }
    }
}

/// 記憶DBの1本を整形して読み、必要な時だけ Markdown を編集する欄。
///
/// 吹き出しをやめてここに据えたのは、読むだけでなく**人間も書く**ため。
/// エージェントが書いたものに人間が直接手を入れ、その結果をまたエージェントが読む——
/// 相互に積んでいくのがこの DB の使い方なので、開いて閉じる吹き出しでは形が合わない
/// 止まっている方の層。**文字はここにしかない**。
///
/// `Equatable` にして `.equatable()` を掛けてあるので、SwiftUI は `==` が真の間 body を作らず、
/// Canvas も描き直さない。判定は丸めた時刻だけで、`layout` / `snapshot` は毎フレーム
/// 作り直された別物が来るが、丸めた時刻が同じなら中身も同じなので比較しない
/// （中身の比較の方が組版より高く付く）。
private struct StillLayer: View, Equatable {
    let layout: CockpitLayout
    let snapshot: CockpitSnapshot
    let mode: CockpitMode
    let structure: Structure.Graph
    let hovered: String?
    let steady: Date

    // 比べているのは値だけで MainActor の状態には触らないので、隔離の外に出す
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.steady == b.steady && a.mode == b.mode && a.hovered == b.hovered
            && a.layout.contentHeight == b.layout.contentHeight
    }

    var body: some View {
        Canvas { context, size in
            CockpitCanvas.draw(&context, size: size, layout: layout, snapshot: snapshot,
                               now: steady, mode: mode, structure: structure,
                               hovered: hovered, layer: .still, steady: steady)
        }
    }
}

private struct MemoryEditor: View {
    let node: Memory.Node
    let onSave: (String, String, Bool) -> NoteSaveResult
    let onClose: () -> Void
    let onDirtyChange: (Bool) -> Void

    @State private var text = ""
    @State private var loaded = ""
    @State private var failed = false
    @State private var conflicted = false
    @State private var readFailed = false
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isEditing {
                    if text != loaded {
                        Button("保存") { save() }.keyboardShortcut("s", modifiers: .command)
                    }
                    Button("表示") { isEditing = false }
                } else {
                    Button("編集") { isEditing = true }
                        .disabled(readFailed)
                }
                Button("閉じる") { onClose() }
                    .disabled(text != loaded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Text(header)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CockpitCanvas.dim)
                .padding(.horizontal, 12)

            if readFailed {
                Text("実ファイルを読めないため編集できない")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.error)
                    .padding(.horizontal, 12).padding(.top, 4)
            } else if conflicted {
                HStack(spacing: 8) {
                    Text("エージェントが書き換えた。読み直すか上書きするか")
                    Spacer(minLength: 4)
                    Button("読み直す") { load() }
                    Button("上書き") { save(overwrite: true) }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CockpitCanvas.error)
                .padding(.horizontal, 12).padding(.top, 4)
            } else if failed {
                Text("保存できなかった。置き場の外か、書き込みが弾かれている")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.error)
                    .padding(.horizontal, 12).padding(.top, 4)
            }

            Divider().padding(.top, 8)

            if isEditing {
                HStack(spacing: 5) {
                    ribbon("見出し") { appendLine("## ") }
                    ribbon("太字") { appendInline("**太字**") }
                    ribbon("箇条書き") { appendLine("- ") }
                    ribbon("コード") { appendInline("`コード`") }
                    ribbon("水平線") { appendLine("---\n") }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editorFocused)
            } else {
                ScrollView {
                    Text(AgentDetail.formatted(Memory.body(text)))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .background(CockpitCanvas.panel)
        .onAppear { load() }
        .onChange(of: node.id) { isEditing = false; load() }
        // エージェントが書き換えたら取り込む。ただし人間が編集中の分は潰さない
        .onChange(of: node.modified) { if text == loaded { load() } }
        .onChange(of: text) { onDirtyChange(text != loaded) }
        .onDisappear { onDirtyChange(false) }
    }

    private func load() {
        do {
            let raw = try String(contentsOf: URL(fileURLWithPath: node.id), encoding: .utf8)
            text = raw
            loaded = raw
            failed = false
            conflicted = false
            readFailed = false
            onDirtyChange(false)
        } catch {
            text = ""
            loaded = ""
            failed = false
            conflicted = false
            readFailed = true
            isEditing = false
            onDirtyChange(false)
        }
    }

    private func save(overwrite: Bool = false) {
        switch onSave(text, loaded, overwrite) {
        case .saved:
            loaded = text
            failed = false
            conflicted = false
            isEditing = false
            onDirtyChange(false)
        case .conflict:
            failed = false
            conflicted = true
        case .failed:
            failed = true
            conflicted = false
        }
    }

    private func ribbon(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, design: .monospaced))
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    // ponytail: SwiftUI の TextEditor から選択範囲を取れないため末尾へ足す。
    // 選択を囲む必要が出たら NSTextView の薄いラッパーへ置き換える
    private func appendInline(_ markdown: String) {
        text += markdown
        editorFocused = true
    }

    private func appendLine(_ markdown: String) {
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += markdown
        editorFocused = true
    }

    private var header: String {
        var parts = [node.relative]
        if !node.kind.isEmpty { parts.append(node.kind) }
        if let session = node.session { parts.append("\(session.prefix(8)) が書いた") }
        if let stage = node.state.first(where: { $0.key.lowercased() == "stage" })?.value {
            parts.append("状態 \(stage)")
        }
        return parts.joined(separator: "  ")
    }
}

/// チップの省略前の指示と作業先。キャンバス上の2行では落ちる情報をここで読む。
/// `private` を外してあるのは `formatted(_:)`（Markdown の整形）を会話サイドバーからも
/// 使うため——**同じ整形を2箇所に書かない**
struct AgentDetail: View {
    let agent: AgentChip
    let files: [(path: String, reads: Int, writes: Int)]

    var body: some View {
        // 中身の丈は指示の長さで決まる（codex に渡すプロンプトは実測で5000字近い md）。
        // 全体を1枚のスクロールに入れる。入れ子のスクロールは中と外のどちらが動くか読めない
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(agent.role)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("\(agent.model.isEmpty ? "—" : agent.model)  労働 \(agent.work)  \(state)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                if agent.share > 0 {
                    // 重み付きトークン消費。公式の価格比（入力1:キャッシュ書き1.25:キャッシュ読み0.1:出力5）を代理指標に計算
                    let percentage = Int((agent.share * 100).rounded(.toNearestOrAwayFromZero))
                    let spent = Snowman.short(Int(agent.spent))
                    Text("このセッションの消費の \(percentage)%（\(spent)相当）")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                }

                Divider()
                Text("受けた指示")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                // 指示は文章なので等幅をやめ、Markdown も解釈する。
                // 生の `**` や `#` がそのまま並ぶと、長いプロンプトはまず読めない
                Text(Self.formatted(agent.instruction))
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !agent.counts.isEmpty {
                    Divider()
                    Text("作業の内訳")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                    ForEach(agent.counts, id: \.kind) { item in
                        HStack {
                            Text(item.kind.rawValue)
                            Spacer()
                            Text("\(item.count)回").foregroundStyle(CockpitCanvas.dim)
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }

                Divider()
                Text("触ったファイル \(files.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                if files.isEmpty {
                    Text("なし")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                } else {
                    ForEach(files, id: \.path) { file in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(file.path).lineLimit(2).textSelection(.enabled)
                            Spacer(minLength: 6)
                            Text("読\(file.reads) 書\(file.writes)")
                                .foregroundStyle(CockpitCanvas.dim)
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .padding(12)
            .frame(width: 400, alignment: .leading)
        }
        .frame(maxHeight: 520)
    }

    /// Markdown を解釈しつつ改行を保つ。見出しや表は行として残るが、
    /// `**` や `` ` `` の記号が消えるだけで長い指示はだいぶ読める。
    /// ponytail: 見出しの大きさや表組みまでは再現しない。Text 1つで済ませるための割り切り
    nonisolated static func formatted(_ raw: String) -> AttributedString {
        (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }

    private var state: String {
        agent.done ? "終了" : (agent.busy ? "稼働" : "待機")
    }
}

/// セルをクリックした時に出る内訳。
/// キャンバス側は量も回数も見た目（点・掃引・波・虹）でしか出さないので、数字はここでしか読めない
private struct FileHistory: View {
    let path: String
    let entries: [WriteEntry]
    let reads: [(role: String, count: Int)]
    let note: Structure.FileNote?
    let dependsOn: Set<String>
    let usedBy: Set<String>

    /// 閉じる口。モーダルなので、押した先が自分で畳めないと戻れない
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair)

            // 「何をするやつか」。セルには1行しか入らないので、全文はここで出す
            Text(note?.memo.isEmpty == false ? note!.memo
                 : "このファイルが宣言している型に落として表示（説明コメントなし）。")
                .font(.system(size: Palette.FontSize.body))
                .lineSpacing(2)
                .foregroundStyle(Palette.inkSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Palette.Space.s3)
                .padding(.vertical, Palette.Space.small)

            statRow
            Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair)

            ScrollView {
                VStack(alignment: .leading, spacing: Palette.Space.small) {
                    writes
                    if !reads.isEmpty {
                        section("読んだ相手") {
                            Text(reads.map { "\($0.role) ×\($0.count)" }.joined(separator: " ／ "))
                                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                                .foregroundStyle(Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // 辺は両端が見えている時しか引けないので、画面に出ていないファイルも含めて出す
                    if !usedBy.isEmpty { related("ここを直すと響く先 \(usedBy.count)", usedBy) }
                    if !dependsOn.isEmpty { related("使っている \(dependsOn.count)", dependsOn) }
                    if let note, !note.exported.isEmpty {
                        related("使われている名前 \(note.exported.count)", Set(note.exported))
                    }
                }
                .padding(.horizontal, Palette.Space.s3)
                .padding(.vertical, Palette.Space.small)
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 440)
        .background(Palette.fieldSubtle)
        .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Palette.Radius.sm)
            .stroke(Palette.border, lineWidth: Palette.Stroke.border))
        .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
    }

    private var header: some View {
        HStack(spacing: Palette.Space.s2) {
            Text(FileCategory.classify(path: path).mark)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: Palette.Radius.xs)
                    .stroke(Palette.border, lineWidth: Palette.Stroke.hair))
                .foregroundStyle(Palette.inkTertiary)
            Text((path as NSString).lastPathComponent)
                .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            Spacer(minLength: Palette.Space.tiny)
            Button(action: onClose) {
                Text("✕")
                    .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Palette.Space.s3)
        .padding(.vertical, Palette.Space.small)
    }

    /// 3つの数。**直近の編集だけが計器の赤**——ここだけが最近動いた量を語る
    private var statRow: some View {
        HStack(spacing: 0) {
            stat("定義した型", "\(note?.declared.count ?? 0)", Palette.ink)
            Rectangle().fill(Palette.hairline).frame(width: Palette.Stroke.hair, height: 40)
            stat("被参照", "\(usedBy.count)", Palette.ink)
            Rectangle().fill(Palette.hairline).frame(width: Palette.Stroke.hair, height: 40)
            stat("直近の編集",
                 entries.first.map { "+\($0.added)" } ?? "—",
                 entries.isEmpty ? Palette.inkTertiary : Palette.readout)
        }
    }

    private func stat(_ title: String, _ value: String, _ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: Palette.Space.hair) {
            Text(title)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Palette.Space.s3)
        .padding(.vertical, Palette.Space.small)
    }

    @ViewBuilder
    private var writes: some View {
        section("書き込み履歴") {
            if entries.isEmpty {
                Text("書き込みなし（読み取りだけ）")
                    .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
            } else {
                ForEach(entries) { e in row(e) }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Palette.Space.s1) {
            Text(title)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 依存の一覧。多いと縦に伸びるので頭から数件で切る
    private func related(_ title: String, _ paths: Set<String>) -> some View {
        // パスでも型名でも同じ見せ方にする（型名に "/" は入らないので lastPathComponent は素通し）
        let names = paths.map { ($0 as NSString).lastPathComponent }.sorted()
        let shown = names.prefix(6)
        return section(title) {
            Text(shown.joined(separator: "  ")
                 + (names.count > shown.count ? "  他\(names.count - shown.count)" : ""))
                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ e: WriteEntry) -> some View {
        HStack(spacing: Palette.Space.s2) {
            Text(e.at.formatted(.dateTime.hour().minute()))
                .foregroundStyle(Palette.inkTertiary)
            Text(e.role).lineLimit(1).foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: Palette.Space.tiny)
            // 進行中の触りは行数がまだ来ていない
            if e.added == 0, e.removed == 0 {
                Text("進行中").foregroundStyle(Palette.accentText)
            } else {
                Text("+\(e.added)").foregroundStyle(Palette.success)
                Text("−\(e.removed)").foregroundStyle(Palette.inkTertiary)
            }
        }
        .font(.system(size: Palette.FontSize.readout, design: .monospaced))
    }
}

// MARK: - 描画

/// 上段＝エージェントのチップ、下段＝ディレクトリごとのファイルカード。
/// チップから今触っているファイルへビームが伸びる（実線＝書き込み / 破線＝読み取り）。
/// 色と寸法は at22_canvas_recommended_detail.html に合わせてある。
enum CockpitCanvas {

    // 色は `Palette` に集約した（デザイン案 5a のトークン層）。
    // ここに残っている名前は画面じゅうから参照されている呼び名なので、
    // 値だけ差し替えて名前は動かしていない。**意味の対応は次のとおり**:
    //   いま動いている（書き込み中・稼働中・門の停止） → accent（赤）。画面に1系統だけ
    //   注意（フラグ）                                → warning（琥珀）
    //   失敗                                          → danger
    //   それ以外（地・線・文字・読み取り）             → 無彩色の明度差だけ

    static let background = Palette.field
    static let label = Palette.ink
    static let dim = Palette.inkSecondary
    /// 罫線・アイドル・未接触。**呼び出し側が `.opacity()` を掛ける前提なので不透明にしておく**——
    /// ここに半透明トークン（`Palette.hairline` / `Palette.border`）を入れると
    /// `Color.opacity` の乗算で二重に薄まり、罫線も状態ドットも画面から消える。
    /// 直に敷く半透明の線が要る場所では `Palette.hairline` / `Palette.border` を名指しで使うこと
    static let rule = Palette.inkTertiary
    /// 書き込み中。**5a で緑をやめ、赤ひとつに寄せた**。
    /// 緑は「増えた行数（+42）」のような差分の符号だけに残してある
    static let live = Palette.accent
    static let liveDeep = Palette.accentText
    static let flag = Palette.warning
    static let flagBeam = Palette.warning
    static let flagDeep = Palette.warning.opacity(0.75)
    /// チップの稼働枠・選択。稼働＝いまなので accent と同じ系統に置いた
    static let agentOn = Palette.accent
    /// 失敗の色。**以前は `calledBy`（エゴビューの意味色）を流用していた**が、
    /// 「呼ばれている元」と「エラー」が同じ色だと、構造画面でエラーが出た時に
    /// どちらの意味で赤いのか読めない。別トークンに切り出した
    static let error = Palette.danger
    /// エゴビューの3方向。ここだけは色が意味そのもの（同じ四角の印を
    /// 3つ並べるので、色を取ると区別が付かない）。DS の値に載せ替えてある
    static let calledBy = Palette.warning
    static let calling  = Palette.accentText
    /// 関連ノート。コードではなく企画・計画の側なので、依存の2色とは別系統
    static let noteMark = Palette.success

    /// ファイルカテゴリの刻印。**色分けを廃止して記号にした**（5a）。
    /// 6色を配ると状態の色（書き込み中・フラグ・稼働中）と同じ画面で競り合い、
    /// 「色が付いている＝何か起きている」が読めなくなる。記号は無彩色で置けるので、
    /// 色の予算を状態だけに残せる。記号の実体は `FileCategory.mark`
    static func categoryMark(_ category: FileCategory) -> String { category.mark }

    /// 書かれた瞬間の光の帯。
    /// 以前は地の明暗が分からなかったので `labelColor` に乗せて明度を反転させていたが、
    /// 5a で地をカーボン黒に固定したため、反転させる相手がいなくなった。
    /// 暗い地の上を通る帯なので明るい側に固定する
    static let sweepInk = Palette.ink
    /// 指示の紙。暗い地の上で唯一の明るい面。ここだけ明暗が逆になるので、
    /// 紙に載る文字は `Palette.paperInk` を使うこと（`label` だと白地に白になる）
    static let paper = Palette.paper
    /// 画面の中で一段持ち上げた面（欄・カード・ホバー中の行）。
    /// **`paper` とは別物**。`paper` はキャンバスの上に置く「紙」で、暗い地の中で
    /// 唯一の明るい面。こちらは地と同系の暗い面で、明度差だけで浮かせる
    static let panel = Palette.fieldSubtle
    static let panelRaised = Palette.surfaceRaised
    /// 実体は CockpitLayout 側。層の振り分けが掃引の窓に依存していて、
    /// 振り分けは SwiftUI 抜きで叩けないと検査できない
    static let sweepDuration = CockpitLayout.sweepDuration

    /// 特大の書き込みに掛ける虹。琥珀と朱はフラグ色と衝突するので抜いた5色
    /// 明度を上げてある。元の5色は暗すぎて、虹を掛けたはずの「特大」が
    /// 周りのアイドル文字より沈んで見えた（強調のつもりが後退して見える）
    static let rainbow: [(r: Double, g: Double, b: Double)] = [
        (0.494, 0.451, 0.902),   // #7E73E6
        (0.204, 0.541, 0.847),   // #348AD8
        (0.129, 0.639, 0.514),   // #21A383
        (0.396, 0.647, 0.153),   // #65A527
        (0.816, 0.353, 0.494),   // #D05A7E
    ]
    static let rainbowPeriod: TimeInterval = 2.6
    static let rainbowStagger: TimeInterval = 0.2
    static let wavePeriod: TimeInterval = 1.6
    static let waveStagger: TimeInterval = 0.07

    /// 文字ごとの見せ方。量と状態を明度チャンネルを使わずに分ける
    enum NameStyle {
        case plain
        case wave        // 書き込み中：不透明度が文字の上を走る
        case rainbow     // 特大：色が文字の上を循環する
    }

    typealias Layer = CockpitLayout.Layer

    static func moves(_ box: CockpitLayout.CellBox, steady: Date) -> Bool {
        CockpitLayout.moves(box, steady: steady)
    }
    static func moves(_ box: CockpitLayout.ChipBox) -> Bool { CockpitLayout.moves(box) }
    static func draws(_ layer: Layer, moving: Bool) -> Bool {
        CockpitLayout.draws(layer, moving: moving)
    }

    /// 文字を1つずつ描く。等幅なので送り幅は文字幅の計算そのまま
    private static func drawName(_ ctx: inout GraphicsContext, _ text: String,
                                 at origin: CGPoint, base: Color,
                                 style: NameStyle, now: Date) {
        guard style != .plain else {
            ctx.draw(ctx.resolve(Text(text)
                .font(.system(size: CockpitLayout.font, design: .monospaced))
                .foregroundStyle(base)), at: origin, anchor: .leading)
            return
        }

        var x = origin.x
        for (i, character) in text.enumerated() {
            let piece = String(character)
            let advance = CockpitLayout.textWidth(piece)
            let color: Color
            switch style {
            case .plain:
                color = base
            case .wave:
                // 0…25% で明るくなり、55% で戻る。以降は薄いまま待つ。
                // 下限を 0.45 から 0.18 まで下げてある。地の緑と近い明るさだと
                // 波が「動いている」と読めず、ただ薄い文字に見える
                let phase = cycle(now, period: wavePeriod, delay: Double(i) * waveStagger)
                let opacity: Double
                if phase < 0.25 { opacity = 0.18 + 0.82 * (phase / 0.25) }
                else if phase < 0.55 { opacity = 1.0 - 0.82 * ((phase - 0.25) / 0.30) }
                else { opacity = 0.18 }
                color = base.opacity(opacity)
            case .rainbow:
                let phase = cycle(now, period: rainbowPeriod, delay: -Double(i) * rainbowStagger)
                color = rainbowColor(phase)
            }
            ctx.draw(ctx.resolve(Text(piece)
                .font(.system(size: CockpitLayout.font, weight: style == .rainbow ? .medium : .regular,
                              design: .monospaced))
                .foregroundStyle(color)),
                     at: CGPoint(x: x, y: origin.y), anchor: .leading)
            x += advance
        }
    }

    private static func cycle(_ now: Date, period: TimeInterval, delay: TimeInterval) -> Double {
        let t = (now.timeIntervalSince1970 + delay).truncatingRemainder(dividingBy: period)
        return (t < 0 ? t + period : t) / period
    }

    private static func rainbowColor(_ phase: Double) -> Color {
        let scaled = phase * Double(rainbow.count)
        let index = Int(scaled) % rainbow.count
        let next = (index + 1) % rainbow.count
        let f = scaled - Double(Int(scaled))
        let a = rainbow[index], b = rainbow[next]
        return Color(red: a.r + (b.r - a.r) * f,
                     green: a.g + (b.g - a.g) * f,
                     blue: a.b + (b.b - a.b) * f)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, layout: CockpitLayout,
                     snapshot: CockpitSnapshot, now: Date,
                     mode: CockpitMode,
                     structure: Structure.Graph = Structure.Graph(), hovered: String? = nil,
                     layer: Layer = .both, steady: Date? = nil) {
        // 動く／動かないの振り分けに使う時刻。両方の層で同じ値を渡す
        let steady = steady ?? now
        // 動く層は下の層に重ねるので地を塗らない。塗ると止まっている方を隠してしまう
        if layer != .live {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
        }

        guard !snapshot.chips.isEmpty || !snapshot.cards.isEmpty else {
            if layer != .live { drawEmpty(&ctx, size: size, mode: mode) }
            return
        }

        if mode == .work, layer != .live {
            // 章見出し。5a は区画に通し番号を振る（01 会話 / 03 エージェント / 04 ファイル）
            drawSectionHeading(&ctx, "03", "エージェント", count: snapshot.chips.count,
                               at: CGPoint(x: CockpitLayout.margin,
                                           y: CockpitLayout.margin + 8))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: CockpitLayout.margin, y: layout.busY))
                p.addLine(to: CGPoint(x: size.width - CockpitLayout.margin, y: layout.busY))
            }, with: .color(rule), lineWidth: 0.8)
        }
        let faded = hovered.map { structure.related(to: $0) }
        for card in layout.cards {
            drawCard(&ctx, card: card, now: now, steady: steady,
                     hovered: hovered, related: faded, layer: layer)
        }
        if mode == .work {
            drawAgentTree(&ctx, layout: layout, size: size, now: now, layer: layer)
            for chip in layout.chips where draws(layer, moving: moves(chip)) {
                // セルと同じく、重ねる前に静止版を拭う（稼働枠は 1.4pt なので余白は2で足りる）
                if layer == .live {
                    ctx.fill(Path(chip.rect.insetBy(dx: -2, dy: -2)), with: .color(background))
                }
                drawChip(&ctx, box: chip, now: now)
            }
            // 紙はレールの上に立つので、行より後に描いて上に出す
            if layer != .still { drawGates(&ctx, layout: layout, snapshot: snapshot, now: now) }
        }
        if layer != .live {
            drawLegend(&ctx, size: size, layout: layout, mode: mode, flagCount: snapshot.flagCount)
        }
    }


    // MARK: エージェントのチップ

    /// 章見出し「03 エージェント 4」。番号 → 章名 → 件数の順で必ず同じ形に並べる
    private static func drawSectionHeading(_ ctx: inout GraphicsContext, _ number: String,
                                           _ title: String, count: Int, at origin: CGPoint) {
        var x = origin.x
        for (text, ink, tracking) in [(number, Palette.inkTertiary, 0.0),
                                      (title, Palette.inkSecondary, Palette.Tracking.wider),
                                      ("\(count)", Palette.inkTertiary, 0.0)] {
            ctx.draw(ctx.resolve(Text(text)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(tracking)
                .foregroundStyle(ink)),
                     at: CGPoint(x: x, y: origin.y), anchor: .leading)
            x += CockpitLayout.textWidth(text, size: Palette.FontSize.label)
               + tracking * CGFloat(text.count) + Palette.Space.s2
        }
    }

    /// 指揮系統。**縦1本の点線レール＋行への横枝**。
    ///
    /// 稼働中の枝だけが accent で流れる。終わった枝は無彩色の静かな線に戻る——
    /// 「色が付いている＝いま動いている」を画面じゅうで1つの意味に保つ
    private static func drawAgentTree(_ ctx: inout GraphicsContext, layout: CockpitLayout,
                                      size: CGSize, now: Date, layer: Layer = .both) {
        guard layout.railBottom > layout.railTop else { return }

        // 縦のレールは動かないので、止まっている層だけが引く
        if layer != .live {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: layout.railX, y: layout.railTop))
                p.addLine(to: CGPoint(x: layout.railX, y: layout.railBottom))
            }, with: .color(rule.opacity(0.45)),
               style: StrokeStyle(lineWidth: 0.9, dash: [4, 4]))
        }

        for box in layout.chips where !box.isRoot && draws(layer, moving: moves(box)) {
            let y = CockpitLayout.branchY(box.rect)
            let branch = Path { p in
                p.move(to: CGPoint(x: layout.railX, y: y))
                p.addLine(to: CGPoint(x: box.rect.minX, y: y))
            }
            guard box.chip.busy else {
                ctx.stroke(branch, with: .color(rule.opacity(box.chip.done ? 0.25 : 0.45)),
                           style: StrokeStyle(lineWidth: 0.9, dash: [4, 4]))
                continue
            }
            // 動いている枝だけ破線を流す。丸を走らせるより「送り続けている」感じが出る
            ctx.stroke(branch, with: .color(agentOn),
                       style: StrokeStyle(lineWidth: 1.2, dash: [4, 4],
                                          dashPhase: -now.timeIntervalSince1970 * 12))
        }
    }

    /// 止まった指示の印。**28×40 の無地の紙**。
    ///
    /// 以前は紙に指示の本文を刷っていたが、同じ文が行の meta にも門のパネルにも出るので
    /// 3箇所で同じものを読ませていた。ここは「そこで止まっている」ことだけを指す。
    /// 止まっているのは絵ではなく司令塔の方（Bash の待ちループの中で本当に停止している）なので、
    /// 待たせている長さは紙の上に添える
    private static func drawGates(_ ctx: inout GraphicsContext, layout: CockpitLayout,
                                  snapshot: CockpitSnapshot, now: Date) {
        for gate in snapshot.gates {
            guard let rect = layout.paper(forGate: gate.id) else { continue }
            let accent = gate.risk.lowercased() == "high" ? error : agentOn
            let sheet = Path(roundedRect: rect, cornerRadius: 2)

            // 影が無いと地に溶けて枠だけの箱になる
            ctx.fill(Path(roundedRect: rect.offsetBy(dx: 1, dy: 1.5), cornerRadius: 2),
                     with: .color(.black.opacity(0.3)))
            ctx.fill(sheet, with: .color(paper))

            // 脈打つ枠。押せることと、放っておかれていることの両方をこれで示す
            let pulse = 0.55 + 0.45 * (sin(now.timeIntervalSince1970 * 2.2) + 1) / 2
            ctx.stroke(sheet, with: .color(accent.opacity(pulse)), lineWidth: 1.2)

            // 紙の上の罫。文字は入らないので、書いてあることは本数だけで示す
            var y = rect.minY + 7
            let inks = [Palette.inkDisabled, Palette.inkTertiary, Palette.inkTertiary, Palette.inkSecondary]
            for i in 0..<CockpitLayout.gatePaperLines(gate.instruction) {
                let w = rect.width - 8 - CGFloat(i) * 4
                ctx.fill(Path(CGRect(x: rect.minX + 4, y: y, width: max(6, w), height: 2)),
                         with: .color(inks[min(i, inks.count - 1)]))
                y += 5
            }

            // 待たせている長さ。**必ず出す**——司令塔は本当に止まっている
            ctx.draw(ctx.resolve(Text("待機 " + waited(gate.waited(now: now)))
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.readout)),
                     at: CGPoint(x: rect.minX, y: rect.minY - 7), anchor: .leading)
        }
    }

    /// 待たせている長さ。桁を増やさず、秒→分→時で1つだけ出す
    nonisolated static func waited(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "\(s)秒" }
        if s < 3600 { return "\(s / 60)分" }
        return "\(s / 3600)時間"
    }

    private static func drawChip(_ ctx: inout GraphicsContext, box: CockpitLayout.ChipBox, now: Date) {
        if box.isRoot { drawRootCard(&ctx, box: box, now: now) }
        else { drawAgentRow(&ctx, box: box, now: now) }
    }

    /// 司令塔。**唯一の箱**。ここから下の行が全部ぶら下がっているので、面を持たせて根に見せる
    private static func drawRootCard(_ ctx: inout GraphicsContext, box: CockpitLayout.ChipBox, now: Date) {
        let shape = Path(roundedRect: box.rect, cornerRadius: Palette.Radius.xs)
        let on = box.chip.busy
        let done = box.chip.done
        let fade = done && !box.summary ? 0.55 : 1.0
        // 返事待ち。稼働（accent）とは別の色にして、「動いている」と「人を待っている」を取り違えさせない
        let waiting = box.chip.waiting != nil

        // 地は明度差だけで作る。稼働中は accent の枠1本だけが色を持つ
        ctx.fill(shape, with: .color(Palette.surface))
        ctx.fill(shape, with: .color(Palette.ink.opacity(box.summary ? 0.06 : (done ? 0.02 : 0.04))))
        ctx.stroke(shape,
                   with: .color(waiting ? Palette.warning : (on ? agentOn : rule.opacity(0.45 * fade))),
                   lineWidth: on || waiting ? Palette.Stroke.state : Palette.Stroke.hair)

        let topY = box.rect.minY + 15
        var x = box.rect.minX + CockpitLayout.chipPad
        if !box.shortID.isEmpty, !box.summary {
            ctx.draw(ctx.resolve(Text(box.shortID)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.accentText.opacity(fade))),
                     at: CGPoint(x: x, y: topY), anchor: .leading)
            x += CockpitLayout.textWidth(box.shortID, size: Palette.FontSize.label) + Palette.Space.tiny
        }
        ctx.draw(ctx.resolve(Text(box.role)
            .font(.system(size: CockpitLayout.font, design: .monospaced))
            .foregroundStyle((on ? label : dim).opacity(fade))),
                 at: CGPoint(x: x, y: topY), anchor: .leading)

        if box.summary { return }

        drawTrailing(&ctx, box.trailing, right: box.dot.x - 10, y: topY, on: on, fade: fade)

        // 2行目。線が引けない作業（検索・ビルド）はここでしか見えない
        if !box.doing.isEmpty {
            ctx.draw(ctx.resolve(Text(box.doing)
                .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
                .foregroundStyle((waiting ? Palette.warning : (on ? live : dim)).opacity(fade))),
                     at: CGPoint(x: box.rect.minX + CockpitLayout.chipPad, y: box.rect.maxY - 13),
                     anchor: .leading)
        }

        drawLamp(&ctx, at: box.dot, on: on, fade: fade, now: now)
    }

    /// レールに吊る1行。`ID │ 名前 │ いま何をしているか │ モデルと割合 │ バッジ`。
    ///
    /// 箱をやめたので枠は持たず、**下端の罫だけ**で行を切る。稼働中の行だけ罫が accent になる
    private static func drawAgentRow(_ ctx: inout GraphicsContext, box: CockpitLayout.ChipBox, now: Date) {
        let on = box.chip.busy
        let done = box.chip.done
        let fade = done && !box.summary ? 0.55 : 1.0
        let r = box.rect

        // 行の下端の罫。門で止まっている行だけ破線にして「まだ始まっていない」を出す
        let ruleInk = on ? agentOn.opacity(0.5)
                    : (box.gate ? error.opacity(0.45) : rule.opacity(done ? 0.2 : 0.35))
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }, with: .color(ruleInk),
           style: box.gate ? StrokeStyle(lineWidth: 1, dash: [4, 3]) : StrokeStyle(lineWidth: 1))

        var x = r.minX
        // ID。**稼働中だけ赤**
        if !box.shortID.isEmpty {
            ctx.draw(ctx.resolve(Text(box.shortID)
                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                .foregroundStyle((on ? Palette.accentText : Palette.inkTertiary).opacity(fade))),
                     at: CGPoint(x: x, y: r.midY), anchor: .leading)
        }
        x += CockpitLayout.rowIDColumn

        ctx.draw(ctx.resolve(Text(box.role)
            .font(.system(size: Palette.FontSize.body, design: .monospaced))
            .foregroundStyle((on ? label : (box.gate ? dim : Palette.inkTertiary)).opacity(fade))),
                 at: CGPoint(x: x, y: r.midY), anchor: .leading)
        x += CockpitLayout.rowNameColumn

        // いま何をしているか。**ビームを外したので、どのファイルを触っているかはここが唯一の手掛かり**
        if !box.doing.isEmpty {
            ctx.draw(ctx.resolve(Text(box.doing)
                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                .foregroundStyle((box.gate ? Palette.accentText
                                           : (on ? dim : Palette.inkTertiary)).opacity(fade))),
                     at: CGPoint(x: x, y: r.midY), anchor: .leading)
        }

        let badgeX = r.maxX - CockpitLayout.rowBadgeColumn
        drawTrailing(&ctx, box.trailing, right: badgeX - 10, y: r.midY, on: on, fade: fade)
        drawBadge(&ctx, box.badge, at: CGPoint(x: badgeX, y: r.midY), on: on, fade: fade)
    }

    /// `opus-5 70 62%`。**割合だけが秒ごとに動く数字**なので、そこだけ計器の赤に載せる
    private static func drawTrailing(_ ctx: inout GraphicsContext, _ trailing: String,
                                     right: CGFloat, y: CGFloat, on: Bool, fade: Double) {
        guard !trailing.isEmpty else { return }
        let parts = trailing.split(separator: " ").map(String.init)
        let hasShare = parts.last?.hasSuffix("%") == true
        let share = hasShare ? parts.last! : ""
        let head = hasShare ? parts.dropLast().joined(separator: " ") : trailing

        var x = right
        if !share.isEmpty {
            ctx.draw(ctx.resolve(Text(share)
                .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
                .foregroundStyle((on ? Palette.readout : Palette.inkTertiary).opacity(fade))),
                     at: CGPoint(x: x, y: y), anchor: .trailing)
            x -= CockpitLayout.textWidth(share, size: CockpitLayout.badgeFont) + 5
        }
        if !head.isEmpty {
            ctx.draw(ctx.resolve(Text(head)
                .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
                .foregroundStyle(dim.opacity(fade))),
                     at: CGPoint(x: x, y: y), anchor: .trailing)
        }
    }

    /// 状態のバッジ。**実行中だけが色を持つ**。終了・待機は枠と字だけの無彩色
    private static func drawBadge(_ ctx: inout GraphicsContext, _ text: String,
                                  at point: CGPoint, on: Bool, fade: Double) {
        guard !text.isEmpty else { return }
        let w = CockpitLayout.textWidth(text, size: Palette.FontSize.label) + 12
        let rect = CGRect(x: point.x, y: point.y - 9, width: w, height: 18)
        let shape = Path(roundedRect: rect, cornerRadius: Palette.Radius.xs)
        if on {
            ctx.fill(shape, with: .color(Palette.accentSubtle))
            ctx.stroke(shape, with: .color(agentOn.opacity(0.7)), lineWidth: Palette.Stroke.hair)
        } else {
            ctx.stroke(shape, with: .color(rule.opacity(0.4 * fade)), lineWidth: Palette.Stroke.hair)
        }
        ctx.draw(ctx.resolve(Text(text)
            .font(.system(size: Palette.FontSize.label, design: .monospaced))
            .tracking(Palette.Tracking.wide)
            .foregroundStyle((on ? Palette.accentText : Palette.inkTertiary).opacity(fade))),
                 at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    /// 状態ランプ。稼働中は脈を打つ。**色が付くのは稼働中だけ**——
    /// 止まっているランプまで色を持つと、画面の赤が「いま」を指さなくなる
    private static func drawLamp(_ ctx: inout GraphicsContext, at point: CGPoint,
                                 on: Bool, fade: Double, now: Date) {
        let alpha = on ? 0.55 + 0.45 * (0.5 + 0.5 * sin(now.timeIntervalSince1970 * 4)) : 1
        let r = 4.0
        ctx.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                 with: .color(on ? live.opacity(alpha) : Palette.inkDisabled.opacity(fade)))
    }

    // MARK: ファイルのカード

    private static func drawCard(_ ctx: inout GraphicsContext, card: CockpitLayout.CardBox, now: Date,
                                 steady: Date, hovered: String? = nil, related: Set<String>? = nil,
                                 layer: Layer = .both) {
        if layer != .live {
            let shape = Path(roundedRect: card.rect, cornerRadius: Palette.Radius.xs)
            // 背景で塗ってからでないと、下に敷いたビームがカードの中を素通りして見える
            ctx.fill(shape, with: .color(background))
            // カードは「囲い」であって面ではない。細い罫1本だけで区画を示し、
            // 中のセルとの明度差を潰さないようにする（5a）
            ctx.stroke(shape, with: .color(Palette.hairline), lineWidth: Palette.Stroke.hair)

            // 見出しは `…/Sources/AT22/ 9` の形。件数は一段落として、
            // ディレクトリ名と数字が同じ強さで competing しないようにする
            let titleY = card.rect.minY + CockpitLayout.cardPad + 6
            let titleX = card.rect.minX + CockpitLayout.cardPad
            ctx.draw(ctx.resolve(Text(card.title)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)),
                     at: CGPoint(x: titleX, y: titleY), anchor: .leading)
            ctx.draw(ctx.resolve(Text("\(card.cells.count)")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkDisabled)),
                     at: CGPoint(x: titleX + CockpitLayout.textWidth(card.title,
                                                                     size: Palette.FontSize.label)
                                    + Palette.Space.tiny, y: titleY),
                     anchor: .leading)
        }

        for box in card.cells where draws(layer, moving: moves(box, steady: steady)) {
            // 動く層は下の層に重ねて描くので、前の刻みで描かれた静止版を先に消す。
            // 読み取り中のリング（-4）とホバーの縁（-2）まで含めて拭う。
            // cellGapY が6なので、-5 に広げても隣のセルの矩形には届かない
            if layer == .live {
                ctx.fill(Path(box.rect.insetBy(dx: -5, dy: -5)), with: .color(background))
            }
            drawCell(&ctx, box: box, now: now, hovered: hovered, related: related)
        }
    }

    private static func drawCell(_ ctx: inout GraphicsContext, box: CockpitLayout.CellBox, now: Date,
                                 hovered: String? = nil, related: Set<String>? = nil) {
        let shape = Path(roundedRect: box.rect, cornerRadius: 3)
        if !box.cell.touched, box.cell.id.hasPrefix("group:") {
            // 実体のない区切りはセル枠を付けず、ノートと取り違えない見出しとして描く
            ctx.fill(Path(CGRect(x: box.rect.minX, y: box.rect.maxY - 1,
                                 width: box.rect.width, height: 1)),
                     with: .color(rule.opacity(0.7)))
            let title = Text(box.display)
                .font(.system(size: CockpitLayout.font, weight: .semibold, design: .monospaced))
                .foregroundStyle(label)
            ctx.draw(ctx.resolve(title),
                     at: CGPoint(x: box.rect.minX + CockpitLayout.cellPad,
                                 y: box.rect.midY),
                     anchor: .leading)
            return
        }
        // 進行中は脈打たせる。止まっているものは静止させて、放置した画面が完全に静止するようにする
        let pulse = 0.6 + 0.4 * (0.5 + 0.5 * sin(now.timeIntervalSince1970 * 5))

        // ホバー中は、関係のあるファイルだけを残して他を沈める。
        // 線を引かずに「どこと繋がっているか」を出すのがこの画面のやり方
        let id = box.cell.id
        var layerOpacity: Double = 1
        var highlighted = false
        if let hovered {
            if id == hovered { highlighted = true }
            else if related?.contains(id) == true { highlighted = true }
            else { layerOpacity = 0.22 }
        }
        if highlighted {
            // ホバーの持ち上げは**明度差だけ**でやる。ここに accent（赤）を敷くと、
            // 触っただけのセルと「いま書き込まれている」セルが同じ色になる
            ctx.fill(Path(roundedRect: box.rect.insetBy(dx: -2, dy: -2),
                          cornerRadius: Palette.Radius.sm),
                     with: .color(Palette.ink.opacity(id == hovered ? 0.16 : 0.09)))
        }
        var ctx = ctx
        ctx.opacity = layerOpacity

        // 地と枠で状態を出す。**色が付くのは「書き込み中」と「フラグ」の2つだけ**。
        // 読み取りとアイドルは無彩色の明度差で語る（5a：色は意味のときだけ）
        switch box.cell.state {
        case .writing:
            ctx.fill(shape, with: .color(live.opacity(0.10 + 0.08 * pulse)))
            ctx.stroke(shape, with: .color(live.opacity(pulse)),
                       lineWidth: Palette.Stroke.state)
        case .reading:
            ctx.fill(shape, with: .color(Palette.ink.opacity(0.08)))
            // 読み取り中はセルの外側にリングを出す（HTML の state.ts と同じ表現）。
            // 書き込みと違って色は載せない——読むのは「起きている」だけで「変わった」ではない
            let ring = box.rect.insetBy(dx: -4, dy: -4)
            ctx.stroke(Path(roundedRect: ring, cornerRadius: Palette.Radius.sm),
                       with: .color(Palette.inkSecondary.opacity(pulse * 0.8)),
                       lineWidth: Palette.Stroke.hair)
        case .flagged:
            ctx.fill(shape, with: .color(flag.opacity(0.22)))
            ctx.stroke(shape, with: .color(flagBeam.opacity(0.8)),
                       lineWidth: Palette.Stroke.border)
        case .idle:
            ctx.fill(shape, with: .color(Palette.ink.opacity(box.cell.touched ? 0.06 : 0.02)))
            if box.cell.touched {
                ctx.stroke(shape, with: .color(Palette.hairline),
                           lineWidth: Palette.Stroke.hair)
            }
        }

        // 構造画面は idle が大半なので、未接触は背景だけでなく文字も半分以下まで落とす
        let ink: Color = !box.cell.touched
            ? dim.opacity(0.45)
            : (box.cell.state == .idle ? dim : label)

        // 左端にカテゴリの刻印を打つ（実・検・ノ・設・資・他）。
        // **色分けをやめて記号にした**（5a）。6色を配ると状態の色——書き込み中・
        // フラグ・稼働中——と同じ画面で競り合い、「色が付いている＝何か起きている」が
        // 読めなくなる。記号なら無彩色で置けるので、色の予算を状態だけに残せる。
        // 名前より先に目に入らないよう、文字は一段落とす
        ctx.draw(ctx.resolve(Text(categoryMark(box.category))
            .font(.system(size: Palette.FontSize.label, design: .monospaced))
            .foregroundStyle(box.cell.touched ? Palette.inkTertiary : Palette.inkDisabled)),
                 at: CGPoint(x: box.rect.minX + CockpitLayout.cellPad, y: box.rect.midY),
                 anchor: .leading)

        // 刻印と名前を縦の罫で仕切る。刻印は「欄」であって名前の一部ではない
        let divider = box.rect.minX + CockpitLayout.cellPad + CockpitLayout.markColumn - 3
        ctx.fill(Path(CGRect(x: divider, y: box.rect.minY + 7,
                             width: Palette.Stroke.hair, height: box.rect.height - 14)),
                 with: .color(Palette.hairline))

        // 誰が触っているか。**行の meta と対**（ビームを外した代わり）。
        // 書き込み中だけ赤——読み取りは起きているだけで、変わってはいない
        if !box.tag.isEmpty {
            ctx.draw(ctx.resolve(Text(box.tag)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wide)
                .foregroundStyle(box.tag.hasSuffix("書込中") ? Palette.accentText : Palette.inkSecondary)),
                     at: CGPoint(x: box.rect.maxX - CockpitLayout.cellPad - CockpitLayout.tickColumn,
                                 y: box.rect.midY), anchor: .trailing)
        }

        // 左＝書き込み量（四角）、右＝参照回数（丸）。どちらも固定寸法なので
        // ファイル名の長さに左右されず、名前と幅を取り合わない。形を変えるのは
        // 同じ縦3点が左右に並ぶと、どちらがどちらか見分けが付かないため
        let tickInk = box.cell.state == .flagged ? flagDeep : ink
        drawTicks(&ctx, count: CockpitLayout.writeTicks(box.cell.added + box.cell.removed),
                  x: box.rect.minX + CockpitLayout.cellPad + CockpitLayout.markColumn,
                  midY: box.rect.midY, round: false, color: tickInk)
        drawTicks(&ctx, count: box.readTicks,
                  x: box.rect.maxX - CockpitLayout.cellPad - CockpitLayout.tickSize,
                  midY: box.rect.midY, round: true, color: tickInk)

        let nameX = box.rect.minX + CockpitLayout.cellPad
                  + CockpitLayout.markColumn + CockpitLayout.tickColumn
        // 3行のセル（記憶モード）は名前を上に寄せ、下を要約と来歴に明け渡す
        let namePoint = CGPoint(x: nameX,
                                y: box.note.isEmpty && box.trace.isEmpty ? box.rect.midY
                                                                         : box.rect.minY + 15)
        // 掃引のマスクと幅の計測に、飾り無しの実体を1つ用意しておく
        let resolved = ctx.resolve(Text(box.display)
            .font(.system(size: CockpitLayout.font, design: .monospaced))
            .foregroundStyle(ink))

        // 特大は虹、書き込み中は波。どちらでもなければ普通に1回で描く
        let style: NameStyle = box.huge ? .rainbow : (box.cell.state == .writing ? .wave : .plain)
        drawName(&ctx, box.display, at: namePoint, base: ink, style: style, now: now)
        drawNoteLines(&ctx, box: box, x: nameX, ink: ink)

        // 量は 点 → 下線 → 虹 の順に足す。点だけだと3段で頭打ちになり、
        // 100行と1000行が同じ見え方になっていた。下線は名前の長さに引きずられるので
        // 単独では量に使えないが、段階を持つ点の上に重ねる印としてなら効く
        let tier = CockpitLayout.writeTier(box.cell.added + box.cell.removed, huge: box.huge)
        if let rule = tier.underline {
            let width = CockpitLayout.textWidth(box.display)
            let y = namePoint.y + 9
            func line(_ offset: CGFloat, _ thickness: CGFloat) {
                ctx.fill(Path(CGRect(x: nameX, y: y + offset, width: width, height: thickness)),
                         with: .color(tier.rainbow ? rainbowColor(cycle(now, period: rainbowPeriod, delay: 0))
                                                   : ink.opacity(0.75)))
            }
            line(0, rule.thickness)
            if rule.double { line(rule.thickness + 1.6, rule.thickness) }
        }

        // 書かれた瞬間だけ、名前の上を光の帯が1回流れる（発火通知）。
        // 所要時間は固定なので、名前が長くても短くても同じ速さで通る
        if let wrote = box.cell.lastWriteAt {
            let age = now.timeIntervalSince(wrote)
            if age >= 0, age < Self.sweepDuration {
                let extent = resolved.measure(in: CGSize(width: 500, height: 40))
                let progress = age / Self.sweepDuration
                ctx.drawLayer { layer in
                    layer.clipToLayer { mask in
                        mask.draw(resolved, at: namePoint, anchor: .leading)
                    }
                    // 右から左へ抜ける
                    let span = extent.width + 90
                    let x = nameX + extent.width + 45 - span * progress
                    let band = CGRect(x: x - 22, y: box.rect.minY, width: 44, height: box.rect.height)
                    layer.fill(Path(band), with: .linearGradient(
                        Gradient(colors: [.clear, sweepInk, .clear]),
                        startPoint: CGPoint(x: band.minX, y: 0),
                        endPoint: CGPoint(x: band.maxX, y: 0)))
                }
            }
        }

    }

    /// ノートの1行要約と来歴。記憶モードのセルはここが本体で、名前だけでは何なのか分からない
    private static func drawNoteLines(_ ctx: inout GraphicsContext, box: CockpitLayout.CellBox,
                                      x: CGFloat, ink: Color) {
        if !box.note.isEmpty {
            ctx.draw(ctx.resolve(Text(box.note)
                .font(.system(size: CockpitLayout.badgeFont))
                .foregroundStyle(ink)),
                     at: CGPoint(x: x, y: box.rect.minY + 32), anchor: .leading)
        }
        if !box.trace.isEmpty {
            ctx.draw(ctx.resolve(Text(box.trace)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(dim)),
                     at: CGPoint(x: x, y: box.rect.maxY - 11), anchor: .leading)
        }
    }

    /// セルの左右に積む固定寸法の印。四角＝書き込み量、丸＝参照回数
    ///
    /// （記憶モードの2行目・3行目は drawCell の末尾で描く）
    private static func drawTicks(_ ctx: inout GraphicsContext, count: Int,
                                  x: CGFloat, midY: CGFloat, round: Bool, color: Color) {
        guard count > 0 else { return }
        let size = CockpitLayout.tickSize, gap = CockpitLayout.tickGap
        var y = midY - (CGFloat(count) * size + CGFloat(count - 1) * gap) / 2
        for _ in 0..<count {
            let box = CGRect(x: x, y: y, width: size, height: size)
            ctx.fill(round ? Path(ellipseIn: box) : Path(roundedRect: box, cornerRadius: 1),
                     with: .color(color))
            y += size + gap
        }
    }

    // MARK: コード構造

    /// 1ファイルの解説画面。左＝呼ばれている元とノート、中央＝そのファイル、右＝呼んでいる先。
    /// 中央の下の余白に解説と数値を入れてある（矢印の配置を保ったまま読み物を足した形）
    static func drawEgo(_ ctx: inout GraphicsContext, size: CGSize,
                        view: CockpitLayout.EgoView) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
        ctx.draw(ctx.resolve(Text("解説　—　Esc で戻る　/　名前を押すとそのファイルへ移る")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(dim)),
                 at: CGPoint(x: CockpitLayout.margin, y: 24), anchor: .leading)

        func caption(_ text: String, at point: CGPoint, size: CGFloat = 11.5) {
            ctx.draw(ctx.resolve(Text(text)
                .font(.system(size: size))
                .foregroundStyle(dim)),
                     at: point, anchor: .leading)
        }

        // 矢印は箱より先に敷く。線が名前の上を横切らない
        for link in view.links {
            let color: Color = switch link.marker {
            case .calling:  calling
            case .calledBy: calledBy
            case .note:     noteMark
            default:        dim
            }
            let cx = (link.from.x + link.to.x) / 2
            var path = Path()
            path.move(to: link.from)
            path.addCurve(to: link.to,
                          control1: CGPoint(x: cx, y: link.from.y),
                          control2: CGPoint(x: cx, y: link.to.y))
            // 実線＝こちらから出る呼び出し、破線＝向こうから来るもの
            ctx.stroke(path, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.4,
                                          dash: link.marker == .calling ? [] : [3, 2]))
            arrowHead(&ctx, at: link.to, pointingRight: link.to.x > link.from.x, color: color)
        }

        // MARK: 中央（そのファイル）
        if let hub = view.panels.first {
            let shape = Path(roundedRect: hub, cornerRadius: 10)
            ctx.fill(shape, with: .color(background))
            ctx.stroke(shape, with: .color(agentOn), lineWidth: 2)
            ctx.draw(ctx.resolve(Text(view.name)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(label)),
                     at: view.namePoint, anchor: .center)

            var y = hub.minY - 10 - CGFloat(view.breadcrumb.count) * 15
            for line in view.breadcrumb {
                ctx.draw(ctx.resolve(Text(line)
                    .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
                    .foregroundStyle(dim)),
                         at: CGPoint(x: hub.midX, y: y), anchor: .center)
                y += 15
            }
        }

        // 余白に入れた解説。ここだけプロポーショナル——等幅だと文章が読みにくい
        let textLeft = view.stats.first?.rect.minX ?? CockpitLayout.margin
        for (i, line) in view.memo.enumerated() {
            ctx.draw(ctx.resolve(Text(line)
                .font(.system(size: 14))
                .foregroundStyle(label)),
                     at: CGPoint(x: textLeft, y: view.memoTop + CGFloat(i) * 21), anchor: .leading)
        }
        for stat in view.stats {
            let shape = Path(roundedRect: stat.rect, cornerRadius: 8)
            ctx.fill(shape, with: .color(rule.opacity(0.10)))
            for (i, line) in stat.title.enumerated() {
                caption(line, at: CGPoint(x: stat.rect.minX + 12,
                                          y: stat.rect.minY + 16 + CGFloat(i) * 15), size: 11)
            }
            ctx.draw(ctx.resolve(Text(stat.value)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(label)),
                     at: CGPoint(x: stat.rect.minX + 12, y: stat.rect.maxY - 20), anchor: .leading)
        }

        // MARK: 左右（関係）
        for group in view.groups { caption(group.title, at: group.point) }
        for row in view.relations { drawEgoRow(&ctx, row: row) }
    }

    /// 曲線の先の三角。向きが読めないと色だけが頼りになる
    private static func arrowHead(_ ctx: inout GraphicsContext, at tip: CGPoint,
                                  pointingRight: Bool, color: Color) {
        let d: CGFloat = pointingRight ? 1 : -1
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - 6 * d, y: tip.y - 3.2))
        head.addLine(to: CGPoint(x: tip.x - 6 * d, y: tip.y + 3.2))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }

    /// 一覧の1行。色付きの四角が種類を表す（呼んでいる＝紫 / 呼ばれている＝橙 / ノート＝緑）
    private static func drawEgoRow(_ ctx: inout GraphicsContext, row: CockpitLayout.EgoView.Row) {
        if row.selected {
            ctx.fill(Path(roundedRect: row.rect.insetBy(dx: -4, dy: 0), cornerRadius: 6),
                     with: .color(agentOn.opacity(0.22)))
        }
        let markerColor: Color? = switch row.marker {
        case .none:      nil
        case .calling:   calling
        case .calledBy:  calledBy
        case .note:      noteMark
        }
        var x = row.rect.minX + row.indent
        if let markerColor {
            let s = CockpitLayout.egoMarker
            let box = CGRect(x: row.rect.minX + max(0, row.indent - 20),
                             y: row.rect.midY - s / 2, width: s, height: s)
            ctx.stroke(Path(roundedRect: box, cornerRadius: 2),
                       with: .color(markerColor), lineWidth: 1.3)
            x = box.maxX + 9
        }
        ctx.draw(ctx.resolve(Text(row.label)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(row.selected ? agentOn : label)),
                 at: CGPoint(x: x, y: row.rect.midY), anchor: .leading)
    }

    // ビーム（チップとファイルを結ぶ折れ線）はここにあった。
    //
    // エージェント帯とファイル帯を1本の罫で断ち切る形にしたので、線が通る道が無くなった。
    // 関係は**文字で語る**——行の側が「CockpitCanvas.swift を編集中」と言い、
    // セルの側が「W5 書込中」と返す。読む手掛かりはこの2つだけになったので、
    // どちらかを削るとどのエージェントが何を触っているかが辿れなくなる。

    // MARK: 凡例

    /// 章見出しと凡例。**下端ではなく見出しの右**に1行で出す（5a）。
    ///
    /// 以前は画面の下端に2段で置いていたが、ファイルが縦に伸びると凡例を見るのに
    /// スクロールが要り、「この点は何だったか」を確かめる時にいちばん遠い場所にあった。
    /// 見出しと同じ行に置けば、区画の名前と読み方が一緒に目に入る
    private static func drawLegend(_ ctx: inout GraphicsContext, size: CGSize,
                                   layout: CockpitLayout, mode: CockpitMode, flagCount: Int) {
        guard let first = layout.cards.first else { return }
        let y = first.rect.minY - CockpitLayout.agentHeader / 2 - 2
        let fileCount = layout.cards.reduce(0) { $0 + $1.cells.count }

        switch mode {
        case .work:
            drawSectionHeading(&ctx, "04", "ファイル", count: fileCount,
                               at: CGPoint(x: CockpitLayout.margin, y: y))
        case .structure:
            drawSectionHeading(&ctx, "03", "構造", count: fileCount,
                               at: CGPoint(x: CockpitLayout.margin, y: y))
        case .memory:
            drawSectionHeading(&ctx, "06", "記憶DB", count: fileCount,
                               at: CGPoint(x: CockpitLayout.margin, y: y))
        }

        // 右端に読み方を1行。入らない分は右から順に落とす
        var parts: [String] = []
        if mode == .work {
            parts = ["点=書込量", "丸=参照", "二重線=上位2%"]
            if flagCount > 0 { parts.append("⚑=読み返し \(flagCount)") }
        } else {
            parts = ["ホバー＝関係が浮かぶ", "クリック＝解説"]
        }

        // 出ているカテゴリだけを `allCases` 順で。**色見本ではなく記号の対応表**（5a）——
        // セルの左端に打ってある字と同じ字を同じ書体で並べる（凡例と実物がずれると照合できない）
        var seen: [FileCategory] = []
        for card in layout.cards {
            for cell in card.cells where !seen.contains(cell.category) { seen.append(cell.category) }
        }
        seen.sort { a, b in
            (FileCategory.allCases.firstIndex(of: a) ?? -1) < (FileCategory.allCases.firstIndex(of: b) ?? -1)
        }
        if !seen.isEmpty {
            // 区切りは空白。中黒で区切ると「他」の刻印（・）と並んで「· ・ 他」と崩れて見えた
            parts.append(seen.map { "\($0.mark) \($0.title)" }.joined(separator: "  "))
        }

        let font = Palette.FontSize.label
        let maxX = size.width - CockpitLayout.margin
        // 右端から書くので、入る分だけ後ろから落とす
        while parts.count > 1,
              CockpitLayout.textWidth(parts.joined(separator: " ／ "), size: font)
                > maxX - CockpitLayout.margin - 160 {
            parts.removeLast()
        }
        ctx.draw(ctx.resolve(Text(parts.joined(separator: " ／ "))
            .font(.system(size: font, design: .monospaced))
            .foregroundStyle(Palette.inkTertiary)),
                 at: CGPoint(x: maxX, y: y), anchor: .trailing)
    }

    private static func drawEmpty(_ ctx: inout GraphicsContext, size: CGSize, mode: CockpitMode) {
        let message = switch mode {
        case .memory:
            "記憶DBを読み込んでいます\nプロジェクトとセッションのノートがここに並びます"
        case .work:
            "動きを待っています\nClaude Code がファイルを読み書きするとここに出ます"
        case .structure:
            "ソースの走査を待っています\n稼働中セッションのプロジェクトが見つかるとここに出ます"
        }
        let text = Text(message)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(dim)
        ctx.draw(ctx.resolve(text), at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }
}
