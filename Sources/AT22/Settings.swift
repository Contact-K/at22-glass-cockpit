import SwiftUI

// MARK: - 10 SETTINGS

/// 新しいワークスペースの既定と、表示・片付け。CLI の場所とログインは従来どおり ⌘, の窓
struct SettingsScreen: View {
    static let levelKey = "defaultLevel"
    static let agentKey = "defaultAgent"

    let cockpit: Cockpit
    let width: CGFloat
    /// 窓の高さ。900 未満では行の上下を詰めて、最後の行まで下帯の上に収める
    var height: CGFloat = 900
    let onLink: () -> Void

    @AppStorage(levelKey) private var level = Gate.defaultLevel.rawValue
    @AppStorage(agentKey) private var agent = "claude|opus"
    @AppStorage("showThinking") private var showThinking = false
    @State private var note: String?
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionMark(number: "10", title: "SETTINGS", jp: "設定")
                Text("Defaults.").font(.display(44))
            }
            .padding(.bottom, 18)
            row("01", "Approval", "承認の段 · 新しいワークスペースの既定") {
                HStack(spacing: 0) {
                    ForEach(Array([Gate.Level.each, .normal, .auto, .unattended].enumerated()), id: \.offset) { i, l in
                        let on = level == l.rawValue
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(l.title.prefix { $0 != " " }).uppercased()).font(.mono(11)).tracking(0.9)
                            Text(String(l.title.drop { $0 != " " }.dropFirst())).font(.bodyJP(13))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
                        .background(on ? Palette.Light.fg : .clear)
                        .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Palette.Light.fg).frame(width: 1) } }
                        .contentShape(Rectangle())
                        .onTapGesture { level = l.rawValue }
                        .help(NewWorkspaceSheet.levelNote[l] ?? "")
                    }
                }
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
            }
            row("02", "Agent", "既定のエージェント") {
                Group {
                    if frozen != nil {
                        Text(agentLabel).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Menu {
                            ForEach(Backend.allCases, id: \.self) { b in
                                ForEach(NewWorkspaceSheet.models(b), id: \.self) { m in
                                    Button(label(b, m)) { agent = b.rawValue + "|" + m }
                                }
                            }
                        } label: {
                            Text(agentLabel).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                .font(.mono(13))
                .padding(.horizontal, 10).frame(height: 38)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
            }
            row("03", "Worktrees", "置き場") {
                // ponytail: 置き場は各リポジトリの中で固定。外に出したい要望が出たら Worktree.location に根を渡す
                Text("<リポジトリ>/" + Worktree.directory + "/<名前>  ·  枝は " + Worktree.branch(for: "<名前>"))
                    .font(.mono(13)).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 10).frame(height: 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
            }
            row("04", "Display", "表示と片付け") {
                HStack(spacing: 8) {
                    Button(showThinking ? "■ 思考を見せる" : "□ 思考を見せる") { showThinking.toggle() }
                        .buttonStyle(SumiButtonStyle(primary: showThinking, size: 11))
                    Button("止まったエージェントを畳む") {
                        cockpit.clearIdleAgents(now: Date())
                        flash("止まったエージェントを畳みました")
                    }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    Button("全部まっさらに") {
                        cockpit.clear()
                        flash("ここから先だけを数えます")
                    }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    if let note { Text(note).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
                }
            }
            row("05", "Link", "連携とログイン") {
                HStack(spacing: 12) {
                    Button("⌘, で開く", action: onLink).buttonStyle(SumiButtonStyle(primary: false, size: 11))
                    Text("CLI の場所・ログイン・起こすかどうか。AT22 は鍵を預からない")
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2)
                }
            }
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
    }

    private var agentLabel: String {
        let parts = agent.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let b = Backend(rawValue: parts.first ?? "") else { return agent }
        return label(b, parts.count > 1 ? parts[1] : "")
    }

    private func label(_ b: Backend, _ m: String) -> String { b.title + " " + (m.isEmpty ? "既定" : m) }

    private func row<C: View>(_ n: String, _ en: String, _ jp: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(n).font(.mono(11)).tracking(1.1).foregroundStyle(Palette.pink)
                Text(en).font(.display(24))
                Text(jp).font(.brush(13))
            }
            content()
        }
        .padding(.vertical, height < 900 ? 9 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
    }

    private func flash(_ text: String) {
        note = text
        Task { try? await Task.sleep(for: .seconds(2.4)); if note == text { note = nil } }
    }
}

/// SETTINGS の右列。操作の鍵の一覧
struct KeysPanel: View {
    let height: CGFloat

    static let keys = [("M", "メニュー"), ("←  →", "メニューの階層を上る · 入る"), ("⌘0", "管制塔 ⇄ 会話"),
                       ("⌘J", "ワークスペースへ飛ぶ"), ("⌘1–6", "待ちの順に飛ぶ"), ("⌃`", "端末を引き出す · しまう"),
                       ("⌘P", "ファイルを開く"), ("⌘S", "開いたファイルを保存"), ("ESC", "閉じる · 戻る")]

    var body: some View {
        SumiPanel(number: "10", title: "KEYS", jp: "操作", foot: nil) {
            ForEach(Self.keys, id: \.0) { k, d in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(k).font(.mono(12)).frame(width: 84, alignment: .leading)
                    Text(d).font(.bodyJP(13))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            }
        }
        .frame(width: 352, height: height - 136)
    }
}
