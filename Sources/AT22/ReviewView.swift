import SwiftUI

// MARK: - レビュー

/// 選んでいるセッションのワークスペースの差分を読み、行にコメントを付けてエージェントへ返す。
/// 返したら直してもらい、良ければその場でコミット・push・PR まで。
///
/// 差分の基準は `Cockpit.reviewBase`——AT22 が作ったワークスペースは作った時のコミット（そこからの全部）、
/// それ以外は HEAD（まだコミットしていない分だけ）。**インデックスには触らない**（読むだけ）
struct ReviewView: View {
    let cockpit: Cockpit
    /// 画像焼きの時だけ渡す。実機の git を叩かない
    var preloaded: [Worktree.DiffFile]? = nil
    var preloadedComments: [Cockpit.ReviewComment] = []
    /// 画像焼きの時だけ偽。ImageRenderer は ScrollView の中身を組まない
    var scrolls = true

    @State private var files: [Worktree.DiffFile] = []
    @State private var loading = false
    @State private var problem: String?
    @State private var selectedFile: String?
    @State private var comments: [Cockpit.ReviewComment] = []
    @State private var drafting: String?        // コメントを書いている行の ID
    @State private var draft = ""
    @State private var hovered: String?
    @State private var commitMessage = ""
    @State private var result: String?
    @State private var shipping = false

    private var session: String? { cockpit.selectedSession }
    private var path: String? { preloaded != nil ? "/preview" : session.flatMap(cockpit.workspacePath(of:)) }
    private var shown: Worktree.DiffFile? { files.first { $0.path == selectedFile } ?? files.first }

    var body: some View {
        Group {
            if let path {
                VStack(spacing: 0) {
                    header(path)
                    Divider()
                    if let problem {
                        Text(problem).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CockpitCanvas.error).padding(12)
                    }
                    HStack(spacing: 0) {
                        fileList.frame(width: 230)
                        Rectangle().fill(Palette.border).frame(width: Palette.Stroke.hair)
                        diffPane
                    }
                    Divider()
                    footer(path)
                }
            } else {
                Text("このセッションのワークスペースが分からない（リポジトリの外か、一覧をまだ読んでいない）")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.field)
        .task(id: path) {
            if let preloaded { files = preloaded; comments = preloadedComments; return }
            await reload()
        }
    }

    // MARK: 上

    private func header(_ path: String) -> some View {
        HStack(spacing: Palette.Space.s2) {
            Text("レビュー")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text("基点 " + String(cockpit.reviewBase(of: path).prefix(8)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CockpitCanvas.dim)
            Spacer()
            let added = files.reduce(0) { $0 + $1.added }, removed = files.reduce(0) { $0 + $1.removed }
            Text("\(files.count) ファイル  +\(added) −\(removed)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(CockpitCanvas.dim)
            Button(loading ? "読んでいる…" : "再読込") { Task { await reload() } }
                .font(.system(size: 11, design: .monospaced))
                .disabled(loading || preloaded != nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: 左

    @ViewBuilder
    private var fileList: some View {
        let list = VStack(alignment: .leading, spacing: 0) {
            if files.isEmpty && !loading {
                Text("差分は無い").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim).padding(12)
            }
            ForEach(files) { file in
                Button { selectedFile = file.path } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((file.path as NSString).lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text("+\(file.added)").foregroundStyle(Palette.success)
                            Text("−\(file.removed)").foregroundStyle(Palette.danger)
                            if file.untracked { Text("追跡外") }
                            else if file.isNew { Text("新規") }
                            if file.isDeleted { Text("削除") }
                            if file.isBinary { Text("バイナリ") }
                            let count = comments.filter { $0.file == file.path }.count
                            if count > 0 { Text("✎\(count)").foregroundStyle(Palette.warning) }
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(shown?.path == file.path ? CockpitCanvas.agentOn.opacity(0.12) : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        if scrolls { ScrollView { list } } else { VStack(spacing: 0) { list; Spacer(minLength: 0) } }
    }

    // MARK: 右

    @ViewBuilder
    private var diffPane: some View {
        let body = VStack(alignment: .leading, spacing: 0) {
            if let file = shown {
                Text(file.path)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                if file.isBinary {
                    Text("バイナリなので中身は出さない").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim).padding(.horizontal, 12)
                }
                ForEach(Array(file.hunks.enumerated()), id: \.offset) { index, hunk in
                    Text(hunk.header)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.ink.opacity(0.04))
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { offset, line in
                        lineRow(file: file.path, line: line, id: "\(file.path)#\(index)#\(offset)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if scrolls { ScrollView([.vertical]) { body } } else { VStack(spacing: 0) { body; Spacer(minLength: 0) } }
    }

    private func lineRow(file: String, line: Worktree.DiffLine, id: String) -> some View {
        let number = line.new ?? line.old
        let mine = comments.filter { $0.file == file && $0.line == number && $0.code == line.text }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(line.old.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
                Text(line.new.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
                Text(line.kind == .add ? " +" : line.kind == .remove ? " −" : "  ")
                    .foregroundStyle(line.kind == .add ? Palette.success : line.kind == .remove ? Palette.danger : CockpitCanvas.dim)
                Text(" " + line.text)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                // 行に乗ったら「＋」。押すとこの行にコメントを書く
                if hovered == id || drafting == id {
                    Button { drafting = id; draft = "" } label: {
                        Image(systemName: "plus.bubble").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(CockpitCanvas.dim)
            .padding(.vertical, 1)
            .background(line.kind == .add ? Palette.success.opacity(0.10)
                        : line.kind == .remove ? Palette.danger.opacity(0.10) : .clear)
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }

            ForEach(mine) { comment in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.bubble").foregroundStyle(Palette.warning)
                    Text(comment.text).foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    Button("消す") { comments.removeAll { $0.id == comment.id } }.buttonStyle(.plain)
                        .foregroundStyle(CockpitCanvas.dim)
                }
                .font(.system(size: 11))
                .padding(.leading, 80)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .background(Palette.warning.opacity(0.10))
            }

            if drafting == id {
                HStack(spacing: 6) {
                    TextField("この行へのコメント", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addComment(file: file, number: number, code: line.text) }
                    Button("追加") { addComment(file: file, number: number, code: line.text) }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("やめる") { drafting = nil }
                }
                .font(.system(size: 11))
                .padding(.leading, 80)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: 下

    private func footer(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("コメント \(comments.count) 件")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(comments.isEmpty ? CockpitCanvas.dim : Palette.warning)
                Button("エージェントに送る") { sendComments() }
                    .disabled(comments.isEmpty || session == nil)
                    .help("コメントをまとめて1通にし、このセッションのエージェントに送る")
                Spacer()
                TextField("コミットのメッセージ", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Button("コミット") { ship { await cockpit.commit(path, message: commitMessage) } }
                    .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || shipping)
                Button("push") { ship { await cockpit.push(path) } }.disabled(shipping)
                Button("PR を作る") { ship { await cockpit.createPullRequest(path) } }.disabled(shipping)
            }
            .font(.system(size: 11))
            if let result {
                Text(result)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: 操作

    private func reload() async {
        guard let path, preloaded == nil else { return }
        loading = true
        switch await cockpit.review(path) {
        case let .success(found): files = found; problem = nil
        case let .failure(error): problem = error.message
        }
        loading = false
    }

    private func addComment(file: String, number: Int?, code: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        comments.append(Cockpit.ReviewComment(file: file, line: number, code: code, text: text))
        drafting = nil
        draft = ""
    }

    private func sendComments() {
        guard let session else { return }
        if cockpit.send(Cockpit.reviewMessage(comments), to: session) {
            result = "コメント \(comments.count) 件をエージェントに送った"
            comments.removeAll()
        } else {
            result = cockpit.launchError ?? "送れなかった"
        }
    }

    /// 出荷は1つずつ。終わったら差分を読み直す（コミットすれば作業中の分が消える）
    private func ship(_ action: @escaping () async -> String) {
        shipping = true
        Task {
            result = await action()
            shipping = false
            await reload()
        }
    }
}
