import SwiftUI

// MARK: - モデルの言葉

/// モデルが書いた言葉を読み、こちらからも差し込む窓。
///
/// これまで AT22 は `tool_use` しか見ていなかったので、**モデルが何を言っているかは
/// 一画面も出ていなかった**（実測1セッションで text 256件・thinking 297件）。
/// キャンバスが「何をしたか」を出すのに対し、ここは「何を考えて何を言ったか」を出す。
///
/// 送る側は **AT22 が起こしたセッションにだけ**通る。人が端末で開いているセッションへ
/// `--resume` で割り込むと同じ transcript を2プロセスが書くので、そちらは塞いである
struct MessageWindow: View {
    static let windowID = "messages"

    let cockpit: Cockpit

    /// 思考は発言より多い（実測 297 > 256）が**本文は残っていない**ので、
    /// 出るのは「いつ考えたか」だけ。既定では畳み、流れを追いたい時だけ出す
    @AppStorage("showThinking") private var showThinking = false
    @State private var draft = ""
    @State private var failed = false

    private var messages: [Message] {
        let session = cockpit.selectedSession
        return cockpit.messages.filter {
            (session == nil || $0.session == session) && (showThinking || !$0.thinking)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if messages.isEmpty {
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
                        // 初期位置は末尾に。デフォルトは冒頭なので macOS 14+ の defaultScrollAnchor で揃える
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                bubble(message).id(message.id)
                            }
                            // 思考中の表示。動いている時だけ出す
                            if cockpit.isWorking(cockpit.selectedSession) {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    HStack(spacing: 4) {
                                        Text("思考中")
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(CockpitCanvas.agentOn)
                                        Text("●")
                                            .font(.system(size: 6, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(CockpitCanvas.agentOn)
                                            .opacity(0.3 + 0.4 * abs(sin(Date().timeIntervalSince(context.date) * .pi)))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                }
                                .id(Int.max)  // 末尾スクロール対象に含める
                            }
                        }
                        .padding(12)
                    }
                    .defaultScrollAnchor(.bottom)
                    // showThinking 切り替えで一覧の中身が変わるので末尾に寄る。
                    // messages.last?.id が同じままだと .onChange が発火しないので別に必要
                    .onChange(of: messages.count) { _, _ in
                        guard let last = messages.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    // 新しいものが下に積まれるので、来たら追う
                    .onChange(of: messages.last?.id) { _, last in
                        guard let last else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    // 思考中の状態が変わったら末尾に寄る
                    .onChange(of: cockpit.isWorking(cockpit.selectedSession)) { _, working in
                        guard working else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Int.max, anchor: .bottom) }
                    }
                }
            }

            Divider()
            composer
        }
        .background(CockpitCanvas.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(cockpit.selectedSession.map { String($0.prefix(8)) } ?? "すべて")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text("\(messages.count)件")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CockpitCanvas.dim)
            Spacer(minLength: 6)
            Toggle("思考も出す", isOn: $showThinking)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func bubble(_ message: Message) -> some View {
        let isHuman = message.speaker == .human
        let bgColor = isHuman
            ? CockpitCanvas.agentOn.opacity(0.12)
            : (message.thinking ? CockpitCanvas.rule.opacity(0.08) : CockpitCanvas.paper)
        let labelColor = message.thinking ? CockpitCanvas.rule : (isHuman ? CockpitCanvas.agentOn : CockpitCanvas.agentOn)
        let label = message.thinking ? "思考" : (isHuman ? "あなた" : "発言")

        // 吹き出しが中身の幅に合わせて縮み、外側で左右に振り分ける。
        // 内側の Text に maxWidth:.infinity を付けないことで、VStack が内容幅で決定する
        return HStack(spacing: 0) {
            if isHuman { Spacer(minLength: 0) }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3)
                            .fill(labelColor.opacity(0.20)))
                    Text(message.at.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                    if !isHuman && message.agent != message.session {
                        Text(String(message.agent.prefix(8)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(CockpitCanvas.dim)
                    }
                }
                // 思考の本文は transcript に残らない（実測で458件すべて空、`signature` だけ）。
                // 空欄を出すより「考えた」という事実だけを出す方が、読む人を騙さない
                Text(message.text.isEmpty ? "（本文は残っていない。考えた時刻だけ分かる）" : message.text)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .foregroundStyle(message.thinking || message.text.isEmpty
                                     ? CockpitCanvas.dim : CockpitCanvas.label)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(bgColor))
            .frame(maxWidth: 600)  // 吹き出しの最大幅。長文でも読みやすいように（窓幅の約80%を想定）

            if !isHuman { Spacer(minLength: 0) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if failed {
                Text(cockpit.launchError ?? "送れなかった")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.calledBy)
            } else if !cockpit.canSend(to: cockpit.selectedSession) {
                Text("送れるのは AT22 が起こしたセッションだけ")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
            }
            HStack(spacing: 8) {
                TextField("割り込む", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1...5)
                Button("送る") { send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || !cockpit.canSend(to: cockpit.selectedSession))
                Button("停止") { interrupt() }
                    .disabled(!cockpit.canSend(to: cockpit.selectedSession)
                              || !cockpit.isWorking(cockpit.selectedSession))
                    .help("進行中のターンだけ止める。セッションは終わらない")
            }
        }
        .padding(12)
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
        // 進行中のターンを止める。失敗時は send() と同じ経路で error を出す
        if !cockpit.interrupt(cockpit.selectedSession) {
            failed = true
        }
    }
}
