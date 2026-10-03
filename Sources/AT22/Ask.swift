import SwiftUI

// MARK: - 訊かれた時の窓

/// エージェントが人に訊いている時の窓。**質問**（AskUserQuestion）は選択肢で答え、**計画**（ExitPlanMode）は進めるかを決め、
/// それ以外の**道具の承認**は許可か却下。答えは承認と同じ口（`Cockpit.answer`）で返す——
/// 質問の答えは道具の入力に `answers` を足して許可する（`updatedInput` は書き換えた方が使われる・実測）
struct AskWindow: View {
    let cockpit: Cockpit
    let approval: Approval

    @State private var picks: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]
    @State private var failed = false

    static let questionTool = "AskUserQuestion"
    static let planTool = "ExitPlanMode"

    /// 窓で訊くもの（会話画面の門のカードには出さない）
    static func isWindowed(_ approval: Approval) -> Bool { [questionTool, planTool].contains(approval.tool) }

    struct Question {
        let text: String
        let header: String
        let options: [(label: String, note: String)]
        let multi: Bool
    }

    /// AskUserQuestion の入力から問いを起こす。壊れていたら空
    static func questions(_ input: String) -> [Question] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any],
              let list = object["questions"] as? [[String: Any]] else { return [] }
        return list.compactMap { q in
            guard let text = q["question"] as? String else { return nil }
            let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> (String, String)? in
                guard let label = o["label"] as? String else { return nil }
                return (label, o["description"] as? String ?? "")
            }
            return Question(text: text, header: q["header"] as? String ?? "", options: options,
                            multi: q["multiSelect"] as? Bool ?? false)
        }
    }

    /// 答えを足した入力（JSON）
    static func answered(_ input: String, _ answers: [String: String]) -> String? {
        guard var object = try? JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any] else { return nil }
        object["answers"] = answers
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(kindLabel).font(.mono(11)).tracking(1.1).foregroundStyle(Palette.pink)
                    Text(cockpit.title(for: approval.session) ?? String(approval.session.prefix(8)))
                        .font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                    Spacer()
                    Text(approval.at, style: .relative).font(.mono(10)).foregroundStyle(Palette.Light.fg3)
                }
                ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 460)
                if failed {
                    Text("答えを返せませんでした（接続が切れているかもしれません）").font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                }
                buttons
            }
            .padding(22)
            .frame(width: 620)
            .foregroundStyle(Palette.Light.fg)
            .background(Palette.Light.bg)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
        }
    }

    private var kindLabel: String {
        switch approval.tool {
        case Self.questionTool: "// 訊いています"
        case Self.planTool: "// 計画を見てください"
        default: "// 許可を求めています · " + approval.tool
        }
    }

    @ViewBuilder
    private var content: some View {
        switch approval.tool {
        case Self.questionTool:
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(Self.questions(approval.input).enumerated()), id: \.offset) { _, q in question(q) }
            }
        case Self.planTool:
            let plan = ((try? JSONSerialization.jsonObject(with: Data(approval.input.utf8))) as? [String: Any])?["plan"] as? String
            Text(TalkScreen.formatted(plan ?? approval.detail))
                .font(.bodyJP(14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text(approval.detail).font(.bodyJP(15)).fixedSize(horizontal: false, vertical: true)
                Text(String(approval.input.prefix(1200))).font(.mono(11)).foregroundStyle(Palette.Light.fg2)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
            }
        }
    }

    private func question(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !q.header.isEmpty { Text(q.header.uppercased()).font(.mono(10)).tracking(1.1).foregroundStyle(Palette.Light.fg2) }
            Text(q.text).font(.bodyJP(16)).fixedSize(horizontal: false, vertical: true)
            ForEach(q.options, id: \.label) { o in
                let on = picks[q.text]?.contains(o.label) == true
                Button { pick(q, o.label) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(on ? "■" : "□").font(.mono(12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.label).font(.bodyJP(14))
                            if !o.note.isEmpty { Text(o.note).font(.bodyJP(11)).opacity(0.75).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
                    .background(on ? Palette.Light.fg : .clear)
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            TextField("その他（書けばこちらを答えにする）", text: Binding(get: { other[q.text] ?? "" }, set: { other[q.text] = $0 }))
                .textFieldStyle(.plain).font(.bodyJP(13))
                .padding(.horizontal, 10).frame(height: 30)
                .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
        }
    }

    private func pick(_ q: Question, _ label: String) {
        var set = picks[q.text] ?? []
        if q.multi {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = set.contains(label) ? [] : [label]
        }
        picks[q.text] = set
    }

    /// 問いごとの答え。「その他」に書いてあればそちら
    private var answers: [String: String] {
        var out: [String: String] = [:]
        for q in Self.questions(approval.input) {
            let typed = (other[q.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = q.options.map(\.label).filter { picks[q.text]?.contains($0) == true }
            let value = typed.isEmpty ? chosen.joined(separator: ", ") : typed
            if !value.isEmpty { out[q.text] = value }
        }
        return out
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            switch approval.tool {
            case Self.questionTool:
                let ready = answers.count == Self.questions(approval.input).count
                Button("答える ↵") { send(allow: true, input: Self.answered(approval.input, answers)) }
                    .buttonStyle(SumiButtonStyle(primary: true)).disabled(!ready)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("答えない") { send(allow: false, input: nil) }.buttonStyle(SumiButtonStyle(primary: false))
            case Self.planTool:
                Button("この計画で進める ↵") { send(allow: true, input: nil) }
                    .buttonStyle(SumiButtonStyle(primary: true)).keyboardShortcut(.return, modifiers: .command)
                Button("まだ（計画を続ける）") { send(allow: false, input: nil) }.buttonStyle(SumiButtonStyle(primary: false))
            default:
                Button("許可 ↵") { send(allow: true, input: nil) }
                    .buttonStyle(SumiButtonStyle(primary: true)).keyboardShortcut(.return, modifiers: .command)
                Button("却下") { send(allow: false, input: nil) }.buttonStyle(SumiButtonStyle(primary: false))
            }
            Spacer()
        }
    }

    private func send(allow: Bool, input: String?) {
        failed = !cockpit.answer(approval, allow: allow, input: input)
    }
}
