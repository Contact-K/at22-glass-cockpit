import SwiftUI

// MARK: - REVIEW と GIT の状態

/// 1つのワークスペースの差分・ステージ・コミット・送出・PR。REVIEW と GIT が同じものを見る。
/// git は全部裏で叩き、押した時だけ書く（ステージ・記帳・送出・PR）
@MainActor @Observable
final class ReviewModel {
    /// 指摘。エージェントには1通にまとめて送る
    struct Note: Identifiable, Equatable {
        enum State { case queued, sent }
        let id = UUID()
        let file: String
        let line: Int?
        let code: String
        var text: String
        var state: State = .queued
    }

    enum HunkState { case unstaged, staged, committed }

    private(set) var path: String?
    private(set) var base = "HEAD"
    private(set) var files: [Worktree.DiffFile] = []
    private(set) var unstagedKeys: [String: Worktree.Hunk] = [:]
    private(set) var stagedKeys: [String: Worktree.Hunk] = [:]
    private(set) var stagedNew: Set<String> = []
    private(set) var commits: [Worktree.Commit] = []
    private(set) var ahead = 0
    private(set) var behind = 0
    private(set) var upstream: String?
    private(set) var pullRequest: Worktree.PullRequest?
    private(set) var loading = false
    var failure: String?
    var notes: [Note] = []
    var seen: Set<String> = []
    var selected = 0
    var pushing = false
    /// 送り終わった直後。遠くの自分の枝の行を青く光らせる
    var fresh = false

    func load(_ cockpit: Cockpit, path: String?) async {
        if path != self.path { notes = []; seen = []; selected = 0; pullRequest = nil }
        self.path = path
        guard let path else { files = []; return }
        let base = cockpit.reviewBase(of: path)
        self.base = base
        loading = true
        let result = await cockpit.review(path)
        let state = await Task.detached { try? Worktree.stagingState(path) }.value
        let commits = await Task.detached { Worktree.log(path, base: base) }.value
        let counts = await Task.detached { Worktree.aheadBehind(path, base: base) }.value
        guard self.path == path else { return }
        switch result {
        case let .success(files): self.files = files; failure = nil
        case let .failure(error): failure = error.message
        }
        unstagedKeys = Dictionary((state?.unstaged ?? []).flatMap { f in f.hunks.map { (f.path + "\n" + Worktree.hunkKey($0), $0) } },
                                  uniquingKeysWith: { a, _ in a })
        stagedKeys = Dictionary((state?.staged ?? []).flatMap { f in f.hunks.map { (f.path + "\n" + Worktree.hunkKey($0), $0) } },
                                uniquingKeysWith: { a, _ in a })
        stagedNew = Set((state?.staged ?? []).filter(\.isNew).map(\.path))
        self.commits = commits
        (ahead, behind, upstream) = counts
        loading = false
    }

    /// `--shot --review` 用。同じ読み方を主スレッドでその場で済ませる（ImageRenderer は task を待たない）
    func loadNow(_ cockpit: Cockpit, path: String) {
        self.path = path
        base = cockpit.reviewBase(of: path)
        files = (try? Worktree.review(path, base: base)) ?? []
        let state = try? Worktree.stagingState(path)
        unstagedKeys = Dictionary((state?.unstaged ?? []).flatMap { f in f.hunks.map { (f.path + "\n" + Worktree.hunkKey($0), $0) } },
                                  uniquingKeysWith: { a, _ in a })
        stagedKeys = Dictionary((state?.staged ?? []).flatMap { f in f.hunks.map { (f.path + "\n" + Worktree.hunkKey($0), $0) } },
                                uniquingKeysWith: { a, _ in a })
        stagedNew = Set((state?.staged ?? []).filter(\.isNew).map(\.path))
        commits = Worktree.log(path, base: base)
        (ahead, behind, upstream) = Worktree.aheadBehind(path, base: base)
    }

    func refreshPullRequest(_ path: String) async {
        let json = await Task.detached { () -> String? in
            guard let gh = Launcher.locate(override: nil, command: "gh") else { return nil }
            return try? Worktree.run(gh.executable.path, ["pr", "view", "--json", "number,state,url,statusCheckRollup"],
                                     in: path, path: gh.path)
        }.value
        pullRequest = json.flatMap(Worktree.parsePullRequest)
    }

    func state(_ file: Worktree.DiffFile, _ hunk: Worktree.Hunk) -> HunkState {
        if file.untracked { return stagedNew.contains(file.path) ? .staged : .unstaged }
        let key = file.path + "\n" + Worktree.hunkKey(hunk)
        if stagedKeys[key] != nil { return .staged }
        if unstagedKeys[key] != nil { return .unstaged }
        return .committed
    }

    var stagedCount: Int {
        files.reduce(0) { n, f in n + f.hunks.filter { state(f, $0) == .staged }.count }
    }

    /// ステージする／外す。外す時は索引側のハンク、入れる時は作業側のハンクを当てる
    func toggle(_ cockpit: Cockpit, file: Worktree.DiffFile, hunk: Worktree.Hunk) async {
        guard let path else { return }
        let current = state(file, hunk)
        guard current != .committed else { return }
        let key = file.path + "\n" + Worktree.hunkKey(hunk)
        let on = current == .unstaged
        let applied = file.untracked ? nil : (on ? unstagedKeys[key] : stagedKeys[key])
        let name = file.path, untracked = file.untracked
        let error = await Task.detached { () -> String? in
            do { try Worktree.stage(path, file: name, hunk: untracked ? nil : applied, on: on); return nil }
            catch { return "\(error)" }
        }.value
        failure = error
        await load(cockpit, path: path)
    }

    /// 一括ステージ。`only` を渡すとそのファイルだけ、無ければ変わったファイル全部
    func stageAll(_ cockpit: Cockpit, on: Bool, only: Worktree.DiffFile? = nil) async {
        guard let path else { return }
        let names = (only.map { [$0] } ?? files).map(\.path)
        let error = await Task.detached { () -> String? in
            do { try Worktree.stageAll(path, files: names, on: on); return nil } catch { return "\(error)" }
        }.value
        failure = error
        await load(cockpit, path: path)
    }

    /// ステージできる（まだ記帳していない）ハンクの数と、そのうちステージ済みの数
    func stageCounts(_ only: Worktree.DiffFile? = nil) -> (open: Int, staged: Int) {
        let list = only.map { [$0] } ?? files
        let states = list.flatMap { f in f.hunks.map { state(f, $0) } }.filter { $0 != .committed }
        return (states.count, states.filter { $0 == .staged }.count)
    }

    func commit(_ cockpit: Cockpit, message: String) async -> String? {
        guard let path else { return nil }
        let result = await Task.detached { () -> String in
            do { return try Worktree.commitStaged(path, message: message) } catch { return "記帳できない: \(error)" }
        }.value
        await load(cockpit, path: path)
        return result
    }
}

// MARK: - 07 REVIEW

/// 差分を読み、行に指摘を書いて溜め、1通にしてエージェントへ送る。ハンクごとにステージ（記帳と送出は GIT で）
struct ReviewScreen: View {
    let cockpit: Cockpit
    let model: ReviewModel
    let workspace: String?
    let session: String?
    let width: CGFloat
    let height: CGFloat
    let onOpen: (String, Int) -> Void
    let onGit: () -> Void

    @State private var editing: String?
    @State private var draft = ""
    @State private var flash: String?
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let files = model.files
        let open = model.notes.filter { $0.state == .queued }.count
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                SectionMark(number: "07", title: "REVIEW", jp: "差分")
                Text(workspace == nil ? "Pick a worktree."
                     : "\(files.count) files, " + (open > 0 ? "\(open) note\(open > 1 ? "s" : "") open." : "nothing open."))
                    .font(.display(44)).lineLimit(1)
            }
            .offset(y: 0)
            if let flash {
                Text(flash).font(.bodyJP(12)).foregroundStyle(Palette.Light.bg)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(Palette.Light.fg)
                    .offset(y: 98)
            }
            diffBox
                .frame(width: width, height: max(200, height - 214 - 110))
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                .offset(y: 130)
            stagedBar
                .frame(width: width, height: 48)
                .offset(y: max(200, height - 214 - 110) + 130 + 12)
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
        .task(id: workspace) { await model.load(cockpit, path: workspace) }
    }

    @ViewBuilder
    private var diffBox: some View {
        if workspace == nil {
            Text("管制塔で worktree を選ぶと、基点からの差分がここに出ます。").font(.bodyJP(14)).padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let failure = model.failure, model.files.isEmpty {
            Text(failure).font(.mono(12)).foregroundStyle(Palette.Light.danger).padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if model.files.isEmpty {
            Text(model.loading ? "差分を読んでいます" : "基点（\(String(model.base.prefix(8)))）から変わったファイルはありません。")
                .font(.bodyJP(14)).padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let file = model.files[min(model.selected, model.files.count - 1)]
            VStack(spacing: 0) {
                fileHead(file)
                LiveScroll {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in hunkView(file, hunk) }
                        if file.isBinary { Text("バイナリなので差分は出せません").font(.bodyJP(13)).padding(12) }
                        Text("行を押すと指摘 · ハンクごとにステージ").font(.mono(9)).tracking(1.1)
                            .foregroundStyle(Palette.Light.fg3).padding(12)
                    }
                }
            }
        }
    }

    private func fileHead(_ file: Worktree.DiffFile) -> some View {
        let seen = model.seen.contains(file.path)
        return HStack(spacing: 10) {
            Text(file.path).font(.mono(12)).lineLimit(1).truncationMode(.head)
            if file.untracked { Text("?? NEW").font(.mono(9)).padding(.horizontal, 5).padding(.vertical, 2).overlay(Rectangle().stroke(lineWidth: 1)) }
            Text("+\(file.added) −\(file.removed)").font(.mono(11)).foregroundStyle(Palette.Light.fg2)
            Spacer(minLength: 0)
            let counts = model.stageCounts(file)
            if counts.open > 0 {
                let all = counts.staged == counts.open
                pill(all ? "■ ファイルを外す" : "□ ファイルを STAGE", filled: all) {
                    Task { await model.stageAll(cockpit, on: !all, only: file) }
                }
            }
            pill(seen ? "✓ 見た" : "□ 見た", filled: seen) {
                if seen { model.seen.remove(file.path) } else { model.seen.insert(file.path) }
            }
            pill("↗", filled: false) { onOpen(file.path, 1) }
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(height: 38)
        .background(Palette.Light.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 2) }
    }

    private func hunkView(_ file: Worktree.DiffFile, _ hunk: Worktree.Hunk) -> some View {
        let state = model.state(file, hunk)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(hunk.header).font(.mono(11)).lineLimit(1).foregroundStyle(Palette.Light.fg2)
                Spacer(minLength: 0)
                switch state {
                case .committed:
                    Text("記帳済み").font(.mono(10)).tracking(1)
                case .staged:
                    pill("■ STAGED · 外す", filled: true) { Task { await model.toggle(cockpit, file: file, hunk: hunk) } }
                case .unstaged:
                    pill("□ STAGE ハンク", filled: false) { Task { await model.toggle(cockpit, file: file, hunk: hunk) } }
                }
            }
            .padding(.leading, 10).padding(.trailing, 8)
            .frame(height: 32)
            .background(Palette.Light.bg2)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { i, line in
                let key = file.path + "#" + hunk.header + "#\(i)"
                let ln = line.new ?? line.old
                let here = model.notes.filter { $0.file == file.path && $0.line == ln }
                DiffRow(kind: line.kind == .add ? "+" : line.kind == .remove ? "-" : " ",
                        old: line.old, new: line.new, text: line.text, commented: !here.isEmpty, dim: state == .committed)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = key; draft = "" }
                ForEach(here) { note in noteBox(note) }
                if editing == key { noteEditor(file: file.path, line: ln, code: line.text) }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
    }

    private func noteBox(_ note: ReviewModel.Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text("YOU").font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2).padding(.top, 3)
                Text(note.text).font(.bodyJP(13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            HStack(spacing: 8) {
                Text(note.state == .queued ? "送る前 · 溜めています" : "送信済").font(.mono(9)).tracking(1.1)
                    .foregroundStyle(Palette.Light.fg2)
                Spacer(minLength: 0)
                if note.state == .queued {
                    Button("取り下げ") { model.notes.removeAll { $0.id == note.id } }.buttonStyle(.plain).font(.mono(10))
                } else {
                    InkLoader(status: "write", pitch: 1.4)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.Light.bg2)
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        }
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
        .padding(EdgeInsets(top: 4, leading: 108, bottom: 8, trailing: 10))
    }

    private func noteEditor(file: String, line: Int?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $draft).font(.bodyJP(13)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 64)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                .onExitCommand { editing = nil }
            HStack(spacing: 8) {
                Button("溜める") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { model.notes.append(.init(file: file, line: line, code: code, text: text)) }
                    editing = nil
                }
                .buttonStyle(SumiButtonStyle(primary: true, size: 10))
                .keyboardShortcut(.return, modifiers: .command)
                Button("やめる") { editing = nil }.buttonStyle(SumiButtonStyle(primary: false, size: 10))
            }
        }
        .padding(EdgeInsets(top: 4, leading: 108, bottom: 8, trailing: 10))
    }

    private var stagedBar: some View {
        let n = model.stagedCount
        return HStack(spacing: 10) {
            Text("STAGED").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
            Text("\(n)").font(.display(26))
            Text(n > 0 ? "ハンクを選びました。記帳と送出は GIT で。" : "差分のハンクを STAGE すると、GIT で記帳できます。")
                .font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
            Spacer(minLength: 0)
            let counts = model.stageCounts()
            if counts.open > 0 {
                let all = counts.staged == counts.open
                pill(all ? "すべて外す" : "すべて STAGE", filled: false) {
                    Task { await model.stageAll(cockpit, on: !all) }
                }
                .help(all ? "ステージを全部外す" : "変わったファイルを全部ステージする")
            }
            Button(action: onGit) {
                Text("08 GIT ▸").font(.mono(11)).tracking(0.9)
                    .foregroundStyle(n > 0 ? Palette.Light.bg : Palette.Light.fg)
                    .padding(.horizontal, 20).frame(maxHeight: .infinity)
                    .background(n > 0 ? Palette.Light.fg : .clear)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.Light.fg).frame(width: 2) }
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 14)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
    }

    private func pill(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.mono(10)).tracking(1)
                .foregroundStyle(filled ? Palette.Light.bg : Palette.Light.fg)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(filled ? Palette.Light.fg : .clear)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/// REVIEW の右列。上＝変わったファイル（見た・ステージ数・指摘数）とコミット、下＝指摘（1通にして送る）
struct ReviewPanels: View {
    let cockpit: Cockpit
    let model: ReviewModel
    let session: String?
    let height: CGFloat
    let onSent: () -> Void

    var body: some View {
        let lower = max(260, height - 406)
        VStack(spacing: 14) {
            SumiPanel(number: "07", title: "CHANGES", jp: "変わったファイル",
                      right: "見た \(model.seen.count) / \(model.files.count)",
                      foot: "基点 \(String(model.base.prefix(8))) · +\(model.files.reduce(0) { $0 + $1.added }) −\(model.files.reduce(0) { $0 + $1.removed })") {
                ForEach(Array(model.files.enumerated()), id: \.offset) { i, f in
                    let on = i == model.selected
                    let staged = f.hunks.filter { model.state(f, $0) == .staged }.count
                    let notes = model.notes.filter { $0.file == f.path }.count
                    HStack(spacing: 8) {
                        Text(model.seen.contains(f.path) ? "✓" : "□").font(.mono(11)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text((f.path as NSString).lastPathComponent + (f.untracked ? "  ??" : "")).font(.mono(12)).lineLimit(1)
                            HStack(spacing: 10) {
                                Text("STAGE \(staged)/\(f.hunks.count)")
                                if notes > 0 { Text("指摘 \(notes)") }
                            }
                            .font(.mono(9)).opacity(0.75)
                        }
                        Spacer(minLength: 0)
                        Text("+\(f.added) −\(f.removed)").font(.mono(10))
                    }
                    .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 14))
                    .foregroundStyle(on ? Palette.white : Palette.blue)
                    .background(on ? Palette.blue : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                    .contentShape(Rectangle())
                    .onTapGesture { model.selected = i }
                }
                Text("COMMITS · 基点から \(model.commits.count)").font(.mono(9)).tracking(1.3)
                    .foregroundStyle(Palette.Light.fg2).padding(EdgeInsets(top: 10, leading: 14, bottom: 4, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(model.commits.enumerated()), id: \.offset) { i, c in
                    CommitRow(commit: c, unsent: i < model.ahead)
                }
            }
            .frame(height: lower - 76 - 14)
            SumiPanel(number: "07", title: "NOTES", jp: "指摘",
                      right: "送る \(model.notes.filter { $0.state == .queued }.count)") {
                ForEach(model.notes) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Text(note.state == .queued ? "▸" : "…").font(.mono(11)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.text).font(.bodyJP(12)).lineLimit(2)
                            Text((note.file as NSString).lastPathComponent + (note.line.map { ":\($0)" } ?? ""))
                                .font(.mono(9)).opacity(0.75)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                }
                if model.notes.isEmpty {
                    Text("指摘はありません。差分の行を押すと書けます。").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            } footer: {
                let queued = model.notes.filter { $0.state == .queued }
                HStack(spacing: 8) {
                    Text(model.notes.contains { $0.state == .sent } ? "エージェントが直しています" : "指摘は 1 通にまとめて送ります")
                    Spacer(minLength: 0)
                    Button("\(queued.count) 件を送る ▸") { send(queued) }
                        .buttonStyle(.plain)
                        .foregroundStyle(queued.isEmpty ? Palette.Light.fg3 : Palette.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(queued.isEmpty ? .clear : Palette.blue)
                        .overlay(Rectangle().strokeBorder(queued.isEmpty ? Palette.Light.line : Palette.blue, lineWidth: 1))
                        .disabled(queued.isEmpty || session == nil || !cockpit.canSend(to: session))
                }
            }
            .frame(height: height - 60 - lower)
        }
        .frame(width: 352)
    }

    private func send(_ queued: [ReviewModel.Note]) {
        guard let session, !queued.isEmpty else { return }
        let message = Cockpit.reviewMessage(queued.map {
            Cockpit.ReviewComment(file: $0.file, line: $0.line, code: $0.code, text: $0.text)
        })
        guard cockpit.send(message, to: session) else { return }
        for note in queued { if let i = model.notes.firstIndex(of: note) { model.notes[i].state = .sent } }
        onSent()
    }
}

/// 基点からのコミット1行。送っていないものは左にピンクの点
struct CommitRow: View {
    let commit: Worktree.Commit
    let unsent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 5) {
                Rectangle().fill(unsent ? Palette.pink : .clear).frame(width: 6, height: 6)
                Text(commit.hash).font(.mono(11))
            }
            .frame(width: 74, alignment: .leading)
            Text(commit.subject).font(.bodyJP(12)).lineLimit(1)
            Spacer(minLength: 0)
            Text(commit.when).font(.mono(10)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }
}

/// v11 の右列の白い板（left 1064 · w 352）。見出し `NN // TITLE 和名` ＋ 右の小さな字、中身、下の一行
struct SumiPanel<Content: View, Footer: View>: View {
    let number: String
    let title: String
    let jp: String
    var right: String = ""
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(number: String, title: String, jp: String, right: String = "", foot: String?,
         @ViewBuilder content: @escaping () -> Content) where Footer == AnyView {
        self.number = number; self.title = title; self.jp = jp; self.right = right
        self.content = content
        self.footer = { AnyView(foot.map { Text($0) }) }
    }

    init(number: String, title: String, jp: String, right: String = "",
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.number = number; self.title = title; self.jp = jp; self.right = right
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 0) { Text(number).foregroundStyle(Palette.pink); Text("// " + title) }
                    .font(.mono(10)).tracking(Palette.caps(10))
                Text(jp).font(.brush(14))
                Spacer(minLength: 0)
                Text(right).font(.mono(10)).tracking(0.4).foregroundStyle(Palette.Light.fg2).lineLimit(1)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
            LiveScroll { VStack(spacing: 0) { content() } }
            footer()
                .font(.mono(10)).tracking(0.8).foregroundStyle(Palette.Light.fg2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 7, leading: 14, bottom: 9, trailing: 14))
                .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        }
        .foregroundStyle(Palette.Light.fg)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
    }
}

// MARK: - 08 GIT

/// 記帳 → 送出 → 依頼 の3段。ステージは REVIEW、ここは送り出すだけ。どれも押した時だけ git を叩く
struct GitScreen: View {
    let cockpit: Cockpit
    let model: ReviewModel
    let workspace: String?
    let branch: String?
    let width: CGFloat
    let height: CGFloat
    let onReview: () -> Void
    /// 成功の合図を出す場所（reportRect の鍵）
    let onBurst: (String) -> Void
    /// 決定のドットを飛ばす（reportRect の鍵から鍵へ、色）
    let onFly: (String, String, Color) -> Void
    let onPushing: (Bool) -> Void

    @State private var message = ""
    @State private var note: String?
    @State private var prTitle = ""
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let staged = stagedHunks
        let pushed = model.ahead == 0 && model.upstream != nil
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                SectionMark(number: "08", title: "GIT", jp: "記帳と送出")
                Text("\(staged.count) staged, " + (pushed ? "all pushed." : "↑\(model.ahead) to push."))
                    .font(.display(44)).lineLimit(1)
            }
            if let note {
                Text(note).font(.bodyJP(12)).foregroundStyle(Palette.Light.bg).lineLimit(2)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(Palette.Light.fg).offset(y: 98)
            }
            step("01", "Commit", "記帳", state: staged.isEmpty ? (model.ahead > 0 ? "done" : "now") : "now") {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("BRANCH 枝").font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2)
                        Text(branch ?? "切り離し").font(.mono(12))
                        Text("← " + String(model.base.prefix(8))).font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                        Spacer(minLength: 0)
                        Text("先行 \(model.ahead) · 遅れ \(model.behind)").font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                    }
                    .padding(.horizontal, 14).frame(height: 36)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                    LiveScroll {
                        VStack(spacing: 0) {
                            if staged.isEmpty {
                                HStack(spacing: 12) {
                                    Text("ステージしたハンクはありません。差分を読んで選ぶのは 07 REVIEW です。").font(.bodyJP(14))
                                    Spacer(minLength: 0)
                                    Button("07 REVIEW ▸", action: onReview).buttonStyle(SumiButtonStyle(primary: false, size: 10))
                                }
                                .padding(14)
                            }
                            ForEach(Array(staged.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text((item.file.path as NSString).lastPathComponent).font(.mono(12)).lineLimit(1)
                                        Text(item.hunk.header).font(.mono(10)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Button("外す") { Task { await model.toggle(cockpit, file: item.file, hunk: item.hunk) } }
                                        .buttonStyle(SumiButtonStyle(primary: false, size: 10))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                            }
                        }
                    }
                    HStack(spacing: 0) {
                        Group {
                            if frozen != nil {
                                Text(message.isEmpty ? (staged.isEmpty ? "先に REVIEW でステージ" : "記帳の文") : message)
                                    .foregroundStyle(Palette.Light.fg3)
                            } else {
                                TextField(staged.isEmpty ? "先に REVIEW でステージ" : "記帳の文 · \(staged.count) ハンクが入ります",
                                          text: $message)
                                    .textFieldStyle(.plain)
                                    .onSubmit(commit)
                            }
                        }
                        .font(.bodyJP(15)).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: commit) {
                            Text("記帳 ↵").font(.mono(11)).tracking(0.9)
                                .foregroundStyle(canCommit(staged) ? Palette.Light.bg : Palette.Light.fg3)
                                .padding(.horizontal, 20).frame(maxHeight: .infinity)
                                .background(canCommit(staged) ? Palette.Light.fg : .clear)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!canCommit(staged))
                        .reportRect("commitBtn")
                    }
                    .frame(height: 48)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 2) }
                }
            }
            .frame(height: commitH).offset(y: 130)
            step("02", "Push", "送出", state: pushed ? "done" : model.ahead > 0 ? (staged.isEmpty ? "now" : "wait") : "wait") {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(branch ?? "HEAD") → \(model.upstream ?? "origin/" + (branch ?? "HEAD"))").font(.mono(12)).lineLimit(1)
                        HStack(spacing: 6) {
                            if !pushed && model.ahead > 0 { Rectangle().fill(Palette.pink).frame(width: 6, height: 6) }
                            Text(pushed ? "送り済み · 遠くと同じ" : model.ahead > 0 ? "未送出 \(model.ahead) 件" : "送るものはありません")
                        }
                        .font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                    }
                    Spacer(minLength: 0)
                    Button(action: push) {
                        HStack(spacing: 8) {
                            if model.pushing { Blink(size: 6) }
                            Text(model.pushing ? "PUSHING ↑\(model.ahead)" : pushed ? "PUSHED ✓" : "PUSH ↑\(model.ahead)")
                        }
                        .font(.mono(11)).tracking(0.9)
                        .foregroundStyle(pushed ? Palette.white : canPush(staged) ? Palette.Light.bg : Palette.Light.fg3)
                        .padding(.horizontal, 20).frame(height: 40)
                        .background(pushed ? Palette.pink : canPush(staged) ? Palette.Light.fg : .clear)
                        .overlay(Rectangle().strokeBorder(pushed ? Palette.pink : canPush(staged) ? Palette.Light.fg : Palette.Light.line, lineWidth: 1))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!canPush(staged))
                    .reportRect("pushBtn")
                }
                .padding(.horizontal, 14).frame(maxHeight: .infinity)
            }
            .frame(height: pushH).offset(y: 130 + commitH + 12)
            step("03", "Pull request", "依頼", state: model.pullRequest != nil ? "done" : pushed ? "now" : "wait") {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if let pr = model.pullRequest {
                            Text("#\(pr.number) " + pr.state).frame(maxWidth: .infinity, alignment: .leading)
                        } else if frozen != nil {
                            Text(prTitle.isEmpty ? (pushed ? model.commits.first?.subject ?? "" : "送出の後に書けます") : prTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField(pushed ? (model.commits.first?.subject ?? "") : "送出の後に書けます", text: $prTitle)
                                .textFieldStyle(.plain).disabled(!pushed)
                        }
                    }
                    .font(.bodyJP(14)).padding(.horizontal, 10).frame(height: 36)
                    .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                    .opacity(pushed ? 1 : 0.5)
                    HStack(spacing: 12) {
                        Text("\(String(model.base.prefix(8))) ← \(branch ?? "HEAD") · \(model.commits.count) 記帳")
                            .font(.mono(10)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                        Spacer(minLength: 0)
                        if let pr = model.pullRequest { CIMark(pr: pr) }
                        Button(model.pullRequest == nil ? "PR を作る" : "PR を開く ↗", action: pullRequest)
                            .buttonStyle(SumiButtonStyle(primary: pushed, size: 11))
                            .disabled(!pushed && model.pullRequest == nil)
                            .reportRect("prBtn")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .frame(height: prH).offset(y: 130 + commitH + 12 + pushH + 12)
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
        .task(id: workspace) {
            await model.load(cockpit, path: workspace)
            if let workspace { await model.refreshPullRequest(workspace) }
        }
    }

    /// 3段の高さ。900 の窓で 300 / 140 / 162（v11 の 214〜514・526〜666・678〜840）。
    /// 低い窓では先に 02・03 を詰め（中身は1行ずつ）、残りを 01 に回して 3 段とも下帯の上に収める
    private var tight: Bool { height < 900 }
    private var pushH: CGFloat { tight ? 112 : 140 }
    private var prH: CGFloat { tight ? 146 : 162 }
    private var commitH: CGFloat { max(190, height - 84 - 130 - 60 - 12 - pushH - 12 - prH) }

    private struct Item {
        let file: Worktree.DiffFile
        let hunk: Worktree.Hunk
    }

    private var stagedHunks: [Item] {
        model.files.flatMap { f in f.hunks.filter { model.state(f, $0) == .staged }.map { Item(file: f, hunk: $0) } }
    }

    private func canCommit(_ staged: [Item]) -> Bool {
        !staged.isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func canPush(_ staged: [Item]) -> Bool {
        !model.pushing && model.ahead > 0 && staged.isEmpty && branch != nil
    }

    private func step<C: View>(_ n: String, _ en: String, _ jp: String, state: String,
                               @ViewBuilder content: () -> C) -> some View {
        let on = state == "now"
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(n).font(.mono(11)).tracking(1.1).foregroundStyle(Palette.pink)
                Text(en).font(.display(24))
                Text(jp).font(.brush(13))
                Spacer(minLength: 0)
                Text(state == "done" ? "✓ 済み" : on ? "いまここ" : "前の段の後").font(.mono(9)).tracking(1.1)
                    .foregroundStyle(Palette.Light.fg2)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(on ? Palette.Light.fg : Palette.Light.line).frame(height: 1) }
            content().frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: width)
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(on ? Palette.Light.fg : Palette.Light.line, lineWidth: on ? 2 : 1))
        .opacity(state == "wait" ? 0.55 : 1)
    }

    private func commit() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCommit(stagedHunks) else { return }
        // 数では比べない。基点が HEAD の時の log は 12 件で切るので、記帳しても数が変わらない
        let before = model.commits.first?.hash
        Task {
            let result = await model.commit(cockpit, message: text)
            message = ""
            // 記帳できたら、ボタンから新しいコミットの行へドットを渡す
            if model.commits.first?.hash != before {
                try? await Task.sleep(for: .milliseconds(40))
                onFly("commitBtn", "commit:0", Palette.blue)
            }
            flash(result.map { Cockpit.plainLine($0) } ?? "記帳しました")
        }
    }

    /// v11 の push: ボタン → 先頭のコミット（ピンク）、1.1 秒後に未送出のコミットから順に遠くの枝へ、
    /// 送り終わったら遠くの行が青く光ってピンクの波紋。git が速く終わっても動きは 2.8 秒見せる
    private func push() {
        guard let workspace, canPush(stagedHunks) else { return }
        let ahead = model.ahead, started = Date()
        model.pushing = true
        onPushing(true)
        onFly("pushBtn", "commit:0", Palette.pink)
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            for i in 0..<min(ahead, 6) {
                onFly("commit:\(i)", "remote:cur", Palette.pink)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        Task {
            let result = await cockpit.push(workspace)
            let rest = 2.8 - Date().timeIntervalSince(started)
            if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
            await model.load(cockpit, path: workspace)
            model.pushing = false
            onPushing(false)
            if model.ahead == 0 {
                model.fresh = true
                onBurst("remote:cur")
                Task { try? await Task.sleep(for: .seconds(1.8)); model.fresh = false }
            }
            flash(Cockpit.plainLine(result))
        }
    }

    private func pullRequest() {
        guard let workspace else { return }
        if let pr = model.pullRequest, let url = URL(string: pr.url) { NSWorkspace.shared.open(url); return }
        Task {
            let result = await cockpit.createPullRequest(workspace)
            await model.refreshPullRequest(workspace)
            if model.pullRequest != nil { onBurst("prBtn") }
            flash(Cockpit.plainLine(result))
        }
    }

    private func flash(_ text: String) {
        note = text
        Task { try? await Task.sleep(for: .seconds(2.4)); if note == text { note = nil } }
    }
}

/// PR の CI の印（✓ 通った / ✗ 落ちた / ● 走っている）
struct CIMark: View {
    let pr: Worktree.PullRequest

    var body: some View {
        HStack(spacing: 5) {
            Text("PR #\(pr.number)")
            switch pr.ci {
            case .ok: Text("✓")
            case .fail: Text("✗")
            case .running: Blink(size: 6, color: Palette.Light.fg)
            case .none: EmptyView()
            }
        }
        .font(.mono(10)).tracking(0.8)
    }
}

/// GIT の右列。上＝遠く（基点・自分の枝・ほかの枝）、下＝コミット（送っていないものにピンクの点）
struct GitPanels: View {
    let model: ReviewModel
    let branch: String?
    let branches: [String]
    let height: CGFloat

    var body: some View {
        let lower = max(260, height - 406)
        VStack(spacing: 14) {
            SumiPanel(number: "08", title: "REMOTE", jp: "遠く", right: model.upstream ?? "origin",
                      foot: model.pullRequest.map { "PR #\($0.number) · \($0.state)" } ?? "送出すると、ここの枝の先頭が進みます") {
                remoteRow("◆ 基点", String(model.base.prefix(8)), main: true, me: false)
                remoteRow(model.upstream ?? "origin/" + (branch ?? "HEAD"),
                          model.commits.dropFirst(model.ahead).first?.hash ?? "—", main: false, me: true)
                ForEach(branches.filter { $0 != branch }.prefix(5), id: \.self) { b in
                    remoteRow(b, "手元だけ", main: false, me: false).opacity(0.5)
                }
            }
            .frame(height: lower - 76 - 14)
            SumiPanel(number: "08", title: "COMMITS", jp: "記帳", right: "基点から \(model.commits.count)", foot: nil) {
                ForEach(Array(model.commits.enumerated()), id: \.offset) { i, c in
                    CommitRow(commit: c, unsent: i < model.ahead)
                        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
                        .reportRect("commit:\(i)")
                }
                if model.commits.isEmpty {
                    Text("基点からのコミットはまだない").font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: height - 60 - lower)
        }
        .frame(width: 352)
    }

    private func remoteRow(_ name: String, _ head: String, main: Bool, me: Bool) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(me && model.ahead > 0 ? Palette.pink : main ? Palette.blue : .clear)
                .frame(width: 8, height: 8)
                .overlay(Rectangle().stroke(main || me ? .clear : Palette.blue, lineWidth: 1))
            Text(name).font(.mono(12)).lineLimit(1)
            Spacer(minLength: 0)
            Text(head).font(.mono(11))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .foregroundStyle(me && model.fresh ? Palette.white : Palette.blue)
        .background(me && model.fresh ? Palette.blue : .clear)
        .animation(.easeInOut(duration: 0.3), value: model.fresh)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        .reportRect(me ? "remote:cur" : "remote-\(name)")
    }
}
