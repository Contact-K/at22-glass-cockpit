import SwiftUI

// MARK: - 筐体

/// モックの外枠——タイトルバー・左レール・タブ行・進行表の帯・ステータスバー。
///
/// 盤面（`CockpitCanvas`）は Canvas で描いているが、こちらは全部 SwiftUI のビュー。
/// 分けたのは、外枠が「押せるもの」の集まりで、当たり判定を自前で持つ理由が無いため。
///
/// 金属の作り方は DS の指示通り3層で固定する:
/// **面（50%で硬く割れる二段）→ 工具目（1px の筋）→ 艶（上半分だけの白）**、
/// そこへ上端1pt の白と下端1pt の黒。ぼかしは押し込んだ時にしか使わない。

// MARK: 金属の面

/// 機械加工した板。`Metal` のどの面を使うかだけ選ぶ
private struct MetalPlate: ViewModifier {
    let face: LinearGradient
    /// 明るい面（門のパネル）は縁の白黒が入れ替わる
    var light = false
    var corner: CGFloat = 0

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                face
                Texture.hairline.resizable(resizingMode: .tile).opacity(light ? 0.5 : 1)
                Palette.Metal.gloss
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(light ? Palette.Metal.bevelLightOnSilver : Palette.Metal.bevelLight)
                    .frame(height: Palette.Stroke.hair)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(light ? Palette.Metal.bevelDarkOnSilver : Palette.Metal.bevelDark)
                    .frame(height: Palette.Stroke.hair)
            }
        }
    }
}

extension View {
    /// 機械加工した板を敷く
    func metalPlate(_ face: LinearGradient, light: Bool = false, corner: CGFloat = 0) -> some View {
        modifier(MetalPlate(face: face, light: light, corner: corner))
    }

    /// 沈めた窓。入力欄と計器の読み値がこれを着る（.mt-inset--dark）
    func inset(corner: CGFloat = Palette.Radius.xs) -> some View {
        background {
            RoundedRectangle(cornerRadius: corner)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(Color.white.opacity(0.08), lineWidth: Palette.Stroke.hair))
        }
    }

    /// 金属に彫った文字。**上に影を落として凹ませる**のが要点で、
    /// 影を下に置くと途端に「浮いた文字」になる
    func etched(_ size: CGFloat = Palette.FontSize.label, light: Bool = false) -> some View {
        font(.system(size: size, design: .monospaced))
            .tracking(Palette.Etch.tracking(size))
            .foregroundStyle(light ? Palette.Etch.inkOnLight : Palette.Etch.ink)
            .shadow(color: light ? Palette.Etch.shadowOnLight : Palette.Etch.shadow,
                    radius: 0, x: 0, y: light ? 1 : -1)
    }
}

// MARK: 鍵

/// 1文字でタブを飛ぶ（a 作業 / b 構造 / c 壁打ち）。
///
/// ⇧⌘M と ⇧⌘T は**見えている部品の側**に付けてある（レールの K と帯の「タスク一覧」）——
/// 隠しボタンに付けると、鍵とそれが動かすものが画面上で離れる。
///
/// 入力欄に焦点がある間は文字がそちらに吸われるので、ここへは落ちてこない。
struct CockpitKeys: ViewModifier {
    @Binding var showConversation: Bool
    @Binding var showTasks: Bool
    @Binding var mode: CockpitMode
    /// 壁打ちに未保存があると飛ばさない
    let locked: Bool

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            guard !locked, press.modifiers.isEmpty else { return .ignored }
            switch press.key {
            case "a": mode = .work;      return .handled
            case "b": mode = .structure; return .handled
            case "c": mode = .memory;    return .handled
            default:  return .ignored
            }
        }
    }
}

// MARK: 製図のグリッド

/// 金属の上に敷く座標グリッド。**線であって面ではない**
struct BlueprintGrid: View {
    var major = false

    var body: some View {
        Canvas { context, size in
            let cell = Palette.Blueprint.cell
            let ink = major ? Palette.Blueprint.lineMajor : Palette.Blueprint.line
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.addRect(CGRect(x: x, y: 0, width: Palette.Stroke.hair, height: size.height))
                x += cell
            }
            var y: CGFloat = 0
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: Palette.Stroke.hair))
                y += cell
            }
            context.fill(path, with: .color(ink))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - タイトルバー

/// 48pt。左端はシステムの信号機に空けてある——**自前で描かない**。
/// モックの3つの丸は HTML で窓を模した作り物で、実物では OS が同じ位置に描く
struct TitleBar: View {
    let cockpit: Cockpit
    /// 「非アクティブを消す」は作業画面でしか意味を持たないので、軸を見て出し分ける
    let mode: CockpitMode

    /// 信号機の幅＋余白。ここより左に何か置くと窓のボタンに重なる
    static let trafficLightInset: CGFloat = 78
    static let height: CGFloat = 48

    var body: some View {
        HStack(spacing: Palette.Space.s3) {
            Color.clear.frame(width: Self.trafficLightInset - Palette.Space.s3, height: 1)

            // ワードマーク。DS は「印は描かず、型で組む」——2つめの 2 だけが赤
            HStack(spacing: 0) {
                Text("AT2").foregroundStyle(Palette.ink)
                Text("2").foregroundStyle(Palette.accentText)
            }
            .font(.system(size: Palette.FontSize.body, weight: .bold, design: .monospaced))
            .tracking(-0.3)

            Text(centerLabel)
                .etched(Palette.FontSize.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // 掃除。ツールバーを外したぶんの行き先。**筐体の側に彫り込む**ので、
            // システムのボタンには戻さない（戻すとタイトルバーがまた二重になる）
            HStack(spacing: Palette.Space.s1) {
                if mode == .work {
                    plate("非アクティブを消す",
                          help: "動いていないエージェントだけを画面から消す") {
                        cockpit.clearIdleAgents(now: .now)
                    }
                }
                plate("クリア",
                      help: "実装の区切りで、溜まった終了済みエージェントとファイルの集計を落とす") {
                    cockpit.clear()
                }
            }

        }
        .padding(.horizontal, Palette.Space.s3)
        .frame(height: Self.height)
        .metalPlate(Palette.Metal.black)
    }

    /// 筐体に留めた小さな板。押せることは面の立ち上がりで出す（色は使わない）
    private func plate(_ title: String, help: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wide)
                .foregroundStyle(Color.white.opacity(0.85))
                .shadow(color: Palette.Etch.shadow, radius: 0, y: -1)
                .padding(.horizontal, Palette.Space.s2)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(KeyFace(pressed: false))
        .help(help)
    }

    /// `GLASS COCKPIT · 凡例の作り直し · 7E04693D`
    private var centerLabel: String {
        var parts = ["GLASS COCKPIT"]
        if let id = cockpit.selectedSession {
            if let title = cockpit.title(for: id) { parts.append(title) }
            parts.append(String(id.prefix(8)).uppercased())
        }
        return parts.joined(separator: " · ")
    }

    // `Lv ノブ` / `文脈` / `消費` は会話ヘッダの計器帯へ移した（`LevelKnob` / `ContextGauge` /
    // `SpendReadout`）。**3つとも「いま見ているセッション」の数字**なのに、
    // タイトルバーとタブ行に散っていて、セッションを選び直しても対応が目で追えなかった
}

// MARK: - 計器（会話ヘッダに集める）

/// 承認の強さ。**回すもの**なので、押せるキーではなくローレット付きのつまみにする
struct LevelKnob: View {
    let cockpit: Cockpit
    @Binding var confirmingLevel: Bool
    @Binding var riskyLevel: Gate.Level?

    var body: some View {
        Menu {
            ForEach(Gate.Level.allCases, id: \.self) { level in
                Button(level.title) {
                    if level.needsConfirmation {
                        riskyLevel = level
                        confirmingLevel = true
                    } else {
                        cockpit.setGateLevel(level)
                    }
                }
            }
        } label: {
            HStack(spacing: Palette.Space.s2) {
                ZStack(alignment: .top) {
                    Circle().fill(Palette.Metal.gunmetal)
                    Circle().fill(Palette.Metal.glossPart)
                    // つまみの向きを示す刻み。これが無いと「回すもの」に見えない
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 2, height: 7)
                        .padding(.top, 2)
                }
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Palette.Metal.bevelLight, lineWidth: Palette.Stroke.hair))

                VStack(alignment: .leading, spacing: 0) {
                    Text(levelNo)
                        .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                    Text(levelName)
                        .font(.system(size: Palette.FontSize.label, design: .monospaced))
                        .tracking(Palette.Tracking.wide)
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("実行モードを変更（Lv.4/5 は確認が必要）")
    }

    // `Lv.3 気にかけてる` を2段に割る。番号は計器の数字、名前は添え字
    private var levelNo: String {
        String(cockpit.gateLevel.title.prefix { $0 != " " })
    }
    private var levelName: String {
        String(cockpit.gateLevel.title.drop { $0 != " " }.dropFirst())
    }
}

/// 文脈の膨らみ。数字が動くところなので `readout`、警報の位置に危険の目盛りを立てる
struct ContextGauge: View {
    let cockpit: Cockpit
    /// 目盛りの幅。会話ヘッダは横が狭いので呼び出し側から決める
    var track: CGFloat = 72

    var body: some View {
        let reading = cockpit.reading
        let percent = Int((reading.growth * 100).rounded())
        let alarm = reading.stage == .warning
        return HStack(spacing: Palette.Space.s2) {
            Text("文脈")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wider)
                .foregroundStyle(Palette.inkTertiary)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.4)).frame(width: track, height: 6)
                Capsule()
                    .fill(Palette.readout)
                    .frame(width: max(0, min(track, track * reading.growth)), height: 6)
                // 警報の位置。ここを越えたら引き継ぐ、が目で分かる
                Rectangle()
                    .fill(Palette.danger)
                    .frame(width: Palette.Stroke.hair, height: 10)
                    .offset(x: track * Snowman.warningAt)
                    .opacity(0.7)
            }
            .frame(width: track, height: 10)

            Text("\(percent)%")
                .font(.system(size: Palette.FontSize.body, design: .monospaced))
                .foregroundStyle(Palette.readout)
            // 段階の語だけ「文脈 」を落として出す（左のラベルと重なるので）
            Text(reading.stage.title.replacingOccurrences(of: "文脈 ", with: ""))
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(alarm ? Palette.accentText : Palette.inkTertiary)
        }
        .help(reading.caption + (reading.stage.advice.isEmpty ? "" : " — " + reading.stage.advice))
    }
}

/// 消費。**畳んだ分・消した分も含めた**このセッションの重み付き累計
struct SpendReadout: View {
    let cockpit: Cockpit

    var body: some View {
        HStack(spacing: Palette.Space.tiny) {
            Text("消費")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wider)
                .foregroundStyle(Palette.inkTertiary)
            Text(Snowman.short(Int(cockpit.spendTotal(session: cockpit.selectedSession))))
                .font(.system(size: Palette.FontSize.body, design: .monospaced))
                .foregroundStyle(Palette.readout)
        }
        .padding(.horizontal, Palette.Space.s2)
        .padding(.vertical, 3)
        .inset()
        .help("入力1 : キャッシュ書き1.25 : キャッシュ読み0.1 : 出力5 の重みで積んだ代理指標")
    }
}

// MARK: - 左レール

/// 56pt。**モードの切り替えではなく「どこを開くか」**——
/// 見る軸（作業／構造／壁打ち）はタブが持つ
struct ModeRail: View {
    @Binding var showConversation: Bool
    @Binding var showTasks: Bool

    /// 設定を開く公式の口。非公開セレクタ（`showSettingsWindow:`）は macOS 14 以降で
    /// 効かない環境があり、`S` キーが無反応になっていた
    @Environment(\.openSettings) private var openSettings

    static let width: CGFloat = 56

    /// 3つしか無いのは、**枠を埋めるために機能を作らないため**。
    /// `T 作業` は `a` タブと完全に重複していたので落とし、
    /// 門は盤面（行・紙・パネル）に既に3つ出ているのでレールから外した——
    /// 警報は門が実際に居る `a 作業` タブのバッジが持つ。
    /// 履歴と ＋新規 は会話画面の中にある（そこが会話の入口なので）
    var body: some View {
        VStack(spacing: Palette.Space.s1) {
            key("bubble.left.and.bubble.right", label: "会話",
                pressed: showConversation, shortcut: "m") { showConversation.toggle() }
            key("checklist", label: "タスク", pressed: showTasks) { showTasks.toggle() }
            Spacer(minLength: 0)
            // ⌘, と同じ口。設定シーンはアプリ本体が持っている
            key("gearshape", label: "設定", pressed: false) { openSettings() }
        }
        .padding(.vertical, Palette.Space.small)
        .frame(width: Self.width)
        .metalPlate(Palette.Metal.gunmetal)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.black.opacity(0.6)).frame(width: Palette.Stroke.hair)
        }
    }

    /// 36×36 の機械キー。選ばれている間は**押し込んだ面**になる（色を使わない）。
    /// 面はイニシャルから SF Symbols に替えた——1文字だと `K` と `T` の意味を覚える必要がある
    private func key(_ symbol: String, label: String, pressed: Bool,
                     shortcut: KeyEquivalent? = nil,
                     action: @escaping () -> Void) -> some View {
        VStack(spacing: Palette.Space.s1) {
            Button(action: action) {
                ZStack {
                    if pressed {
                        RoundedRectangle(cornerRadius: Palette.Radius.xs)
                            .fill(Palette.surfaceSunken)
                            .shadow(color: Palette.Metal.pressedShadow,
                                    radius: Palette.Metal.pressedRadius, y: 2)
                    }
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(pressed ? Palette.ink : Color.white.opacity(0.9))
                        .shadow(color: Palette.Etch.shadow, radius: 0, y: -1)
                }
                .frame(width: 36, height: 36)
                .modifier(KeyFace(pressed: pressed))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(shortcut.map { KeyboardShortcut($0, modifiers: [.command, .shift]) })

            Text(label)
                .etched(Palette.FontSize.label)
                .lineLimit(1)
        }
        .padding(.bottom, Palette.Space.s1)
    }
}

/// キーの面。押されている間は板を敷かない（沈んだ面が既に下にある）
private struct KeyFace: ViewModifier {
    let pressed: Bool

    func body(content: Content) -> some View {
        if pressed {
            content.overlay(
                RoundedRectangle(cornerRadius: Palette.Radius.xs)
                    .stroke(Color.black.opacity(0.6), lineWidth: Palette.Stroke.border))
        } else {
            content
                .metalPlate(Palette.Metal.gunmetal, corner: Palette.Radius.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: Palette.Radius.xs)
                        .stroke(Color.black.opacity(0.55), lineWidth: Palette.Stroke.border))
        }
    }
}

// MARK: - タブ行

/// `a 作業 / b 構造 / c 壁打ち`。
/// キー文字を添えるのは 5a の索引装飾——1文字で飛べることが目で分かる。
/// 文脈計器は会話ヘッダへ移した（計器は見ているセッションの側に集める）
struct TabBar: View {
    let cockpit: Cockpit
    @Binding var mode: CockpitMode
    /// 壁打ちに未保存があるとタブを止める（既存の規律をそのまま持ってくる）
    let locked: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Palette.Space.s4) {
            // 門はこのタブの中（行・紙・明るいパネル）に居るので、警報もここに出す。
            // レールの `G` に付けていた頃は、警報と門が画面の別々の場所にあった
            tab(.work, key: "a", slug: "sagyou", stopped: cockpit.gates.count)
            tab(.structure, key: "b", slug: "kouzou")
            tab(.memory, key: "c", slug: "kabeuchi")
            Spacer(minLength: Palette.Space.s3)
        }
        .padding(.horizontal, Palette.Space.s4)
        .padding(.top, Palette.Space.small)
    }

    private func tab(_ target: CockpitMode, key: String, slug: String,
                     stopped: Int = 0) -> some View {
        let active = mode == target
        return Button { if !locked { mode = target } } label: {
            VStack(spacing: Palette.Space.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Palette.Space.s2) {
                    Text(key)
                        .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                        .foregroundStyle(active ? Palette.accentText : Palette.inkTertiary)
                    Text(target.title)
                        .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                        .tracking(Palette.Tracking.wider)
                        .foregroundStyle(active ? Palette.ink : Palette.inkTertiary)
                    Text(slug)
                        .font(.system(size: Palette.FontSize.label, design: .monospaced))
                        .foregroundStyle(Palette.inkTertiary)
                    if stopped > 0 { stopBadge(stopped) }
                }
                // 選択中の下線は**行の下**に引く。重ねると字を貫いて取り消し線に見える
                Rectangle()
                    .fill(active ? Palette.rule : Color.clear)
                    .frame(height: Palette.Stroke.rule)
            }
            // ローマ字のスラグは折り返さない。折り返すとタブの高さが揃わず、下線の位置がずれる
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .opacity(locked && !active ? 0.4 : 1)
    }

    /// 止まっている門の件数。**画面で明滅する赤はこれ1つ**
    private func stopBadge(_ count: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 0.7)) { timeline in
            let on = Int(timeline.date.timeIntervalSince1970 / 0.7) % 2 == 0
            HStack(spacing: 3) {
                Circle().fill(Palette.dotRed).frame(width: 6, height: 6)
                Text("停止\(count)")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.accentText)
                    // スラグと同じく折り返させない。折り返すと件数だけ下に落ちてタブの下線に掛かる
                    .fixedSize(horizontal: true, vertical: false)
            }
            .opacity(on ? 1 : 0.35)
        }
        .help("門で止まっている指示が \(count) 件。この画面の右のパネルで答える")
    }
}

// MARK: - 進行表の帯

/// 最上段の1行。**沈めた面**に載せて「動かない掲示」であることを出す。
/// 畳み方は `Cockpit.progressStrip` が持つ（SwiftUI 抜きで検査できる側）
struct ProgressStripBar: View {
    let cockpit: Cockpit
    let onOpenTasks: () -> Void

    var body: some View {
        // 帯そのものは切り詰めるが、**右端の鍵は切らない**。
        // 全体を `.clipped()` していた頃は、タスクの文が長いと「⇧⌘T タスク一覧」が
        // 幕の外へ押し出され、見えないのに押せる（当たり判定は切られない）状態になっていた
        HStack(spacing: Palette.Space.s2) {
            titles.frame(maxWidth: .infinity, alignment: .leading).clipped()
            openKey
        }
        .padding(.horizontal, Palette.Space.s4)
        .padding(.vertical, Palette.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.32))
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair) }
    }

    private var titles: some View {
        let strip = Cockpit.progressStrip(cockpit.allTasks(session: cockpit.selectedSession))
        return HStack(spacing: Palette.Space.s2) {
            Text("進行表")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .tracking(Palette.Tracking.wider)
                .foregroundStyle(Palette.inkTertiary)

            if !strip.foldedNumbers.isEmpty {
                Text(strip.foldedNumbers)
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .tracking(Palette.Tracking.wide)
                    .foregroundStyle(Palette.inkDisabled)
                    .lineLimit(1)
            }

            if !strip.recent.isEmpty {
                Text(strip.recent.map { "\($0.number) ✓\($0.subject)" }.joined(separator: " "))
                    .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }

            if let current = strip.current {
                HStack(alignment: .firstTextBaseline, spacing: Palette.Space.tiny) {
                    Text("▶\(current.number)").foregroundStyle(Palette.accentText)
                    Text(current.activeForm.isEmpty ? current.subject : current.activeForm)
                        .foregroundStyle(Palette.ink)
                }
                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                .lineLimit(1)
            }

            if !strip.upcoming.isEmpty {
                Text(strip.upcoming.map { "\($0.number) \($0.subject)" }.joined(separator: " · "))
                    .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Palette.Space.s2)
        }
    }

    private var openKey: some View {
        Button(action: onOpenTasks) {
            HStack(spacing: Palette.Space.tiny) {
                Text("⇧⌘T")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .padding(.horizontal, Palette.Space.s1)
                    .padding(.vertical, 1)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .metalPlate(Palette.Metal.gunmetal, corner: Palette.Radius.xs)
                Text("タスク一覧")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .help("タスク一覧の表示・非表示（⇧⌘T）")
        .fixedSize()
    }
}

// MARK: - 門のパネル

/// 止まった指示に答える口。**画面で唯一の明るい面**。
///
/// 暗い地の中に明るい金属板が1枚だけ立つので、「いま人間の番はここ」が一目で分かる。
/// 明るい面を2枚に増やすと、この指し示す力がそのまま半分になる。
///
/// キャンバス側に置いたのは、レールの上に立つ紙と同じ高さに並ぶため——
/// **どの行が止まったのか**が線で繋がる。答える口は1つだけで、
/// 許可・書換・却下がここで完結する（サイドバーにもカードを出すと口が2つに割れる）。
struct GatePanel: View {
    let request: Gate.Request
    /// 答えを書けなかった時。**黙って消さない**（司令塔は待ったまま）
    let failed: Bool
    let onAnswer: (Gate.Verdict, String) -> Void
    let onClose: () -> Void

    @State private var rewriting = false
    @State private var revised = ""

    static let width: CGFloat = 288

    var body: some View {
        VStack(alignment: .leading, spacing: Palette.Space.s2) {
            header
            paperRow
            if failed {
                Text("答えを書けなかった。司令塔は待ったままなので、置き場を直してもう一度")
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rewriting { rewriteControls } else { choices }
        }
        .padding(14)
        .frame(width: Self.width)
        .background {
            // スピン仕上げの明るい板。金属は面＋工具目＋艶の3層で作る
            ZStack {
                Palette.Metal.silver
                Texture.spun.resizable().opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.sm))
        }
        .overlay(RoundedRectangle(cornerRadius: Palette.Radius.sm)
            .stroke(Palette.Metal.bevelDarkOnSilver, lineWidth: Palette.Stroke.border))
        .overlay(alignment: .topLeading) { screw }
        .overlay(alignment: .topTrailing) { screw }
        .overlay(alignment: .bottomLeading) { screw }
        .overlay(alignment: .bottomTrailing) { screw }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        .onAppear { revised = CockpitLayout.plainLine(request.instruction) }
        .onChange(of: request.id) {
            rewriting = false
            revised = CockpitLayout.plainLine(request.instruction)
        }
    }

    /// 四隅のネジ。板が筐体に留まっていることを出す小さな印
    private var screw: some View {
        Circle()
            .fill(Palette.Metal.silver)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
            .overlay(Rectangle().fill(Color.black.opacity(0.55))
                .frame(width: 5, height: 1).rotationEffect(.degrees(35)))
            .frame(width: 8, height: 8)
            .padding(5)
    }

    private var header: some View {
        HStack(spacing: Palette.Space.s2) {
            // 赤い点。**一画面に1つ**、面としては使わない
            TimelineView(.periodic(from: .now, by: 0.7)) { timeline in
                let on = Int(timeline.date.timeIntervalSince1970 / 0.7) % 2 == 0
                Circle().fill(Palette.dotRed).frame(width: 9, height: 9).opacity(on ? 1 : 0.3)
            }
            Text("門 — 止まった指示").etched(Palette.FontSize.label, light: true)
            Spacer(minLength: Palette.Space.s1)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text("待機 " + CockpitCanvas.waited(request.waited(now: timeline.date)))
                    .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                    .foregroundStyle(Palette.paperInkDim)
            }
            Button(action: onClose) {
                Text("✕")
                    .font(.system(size: Palette.FontSize.body, design: .monospaced))
                    .foregroundStyle(Palette.paperInkDim)
            }
            .buttonStyle(.plain)
        }
    }

    private var paperRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // レールの上に立っている紙と同じ印。パネルと紙が同じものだと分かる
            VStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(Palette.paperInkDim.opacity(1 - Double(i) * 0.18))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: [1.0, 0.9, 0.7, 0.5][i], anchor: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(width: 28, height: 40)
            .background(Rectangle().fill(Palette.paper))
            .overlay(Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(request.to.isEmpty ? request.call : request.to)
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .foregroundStyle(Palette.paperInkDim)
                Text(CockpitLayout.plainLine(request.instruction))
                    .font(.system(size: Palette.FontSize.body))
                    .lineSpacing(1)
                    .lineLimit(4)
                    .foregroundStyle(Palette.paperInk)
                if !request.risk.isEmpty {
                    Text(request.risk)
                        .font(.system(size: Palette.FontSize.label, design: .monospaced))
                        .foregroundStyle(request.risk.lowercased() == "high"
                                         ? Palette.danger : Palette.paperInkDim)
                }
            }
        }
    }

    /// 3択。**色が付くのは「許可」だけ**——押すと物事が前へ進むボタンにだけ赤を載せる
    private var choices: some View {
        HStack(spacing: Palette.Space.tiny) {
            // ⌘Return はサイドバーの「送る」が持っている。門が出ている間は両方が画面にあるので、
            // 同じ鍵にすると**門に答えたつもりで割り込みが飛ぶ**。門側は ⇧⌘G に逃がす
            Button("許可") { onAnswer(.allow, "") }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                // 既定の青はシステムの色で、DS の「赤ひとつ」の規律の外にある
                .tint(Palette.accent)
            Button("書換") { rewriting = true }.buttonStyle(.bordered)
            Button("却下") { onAnswer(.deny, "") }.buttonStyle(.bordered)
        }
        .font(.system(size: Palette.FontSize.body, design: .monospaced))
    }

    /// 書き換えはこの場で編む。別の欄を開くと、答える口がまた2つに割れる
    private var rewriteControls: some View {
        VStack(spacing: Palette.Space.s2) {
            TextEditor(text: $revised)
                .font(.system(size: Palette.FontSize.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 64)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Palette.Radius.xs)
                    .fill(Color.white.opacity(0.75)))
                .overlay(RoundedRectangle(cornerRadius: Palette.Radius.xs)
                    .stroke(Color.black.opacity(0.35), lineWidth: Palette.Stroke.hair))
            HStack(spacing: Palette.Space.tiny) {
                Button("書き換えて発行") { onAnswer(.revise, revised) }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .disabled(revised.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("戻る") { rewriting = false }.buttonStyle(.bordered)
            }
            .font(.system(size: Palette.FontSize.body, design: .monospaced))
        }
    }
}

// MARK: - ステータスバー

/// 28pt。**刻印だけ**。ここに置くのは「いま何段か」「門が止まっているか」の2つで、
/// どちらも目を上げずに確かめたいもの
struct StatusBar: View {
    let cockpit: Cockpit

    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: Palette.Space.s3) {
            Text(cockpit.gateLevel.title)
                .etched(Palette.FontSize.label)
            Text(gateText)
                .etched(Palette.FontSize.label)
                .foregroundStyle(cockpit.gates.isEmpty ? Palette.inkTertiary : Palette.accentText)
            Spacer(minLength: Palette.Space.s2)
            Text(tail)
                .etched(Palette.FontSize.label)
                .opacity(0.6)
        }
        .lineLimit(1)
        .padding(.horizontal, Palette.Space.s3)
        .frame(height: Self.height)
        .metalPlate(Palette.Metal.black)
    }

    /// `門 01 停止中` / `門 00`。番号を0詰めにするのは索引装飾の作法
    private var gateText: String {
        let n = cockpit.gates.count
        return n == 0 ? "門 00" : String(format: "門 %02d 停止中", n)
    }

    private var tail: String {
        guard let id = cockpit.selectedSession else { return "AT22" }
        return String(id.prefix(8)).uppercased()
    }
}
