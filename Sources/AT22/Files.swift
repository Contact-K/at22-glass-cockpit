import SwiftUI

// MARK: - FILES の状態

/// 1つのワークスペースのファイルの木と、手で直すために開いた1本。
///
/// **AT22 がソースを書くのは、人が ⌘S を押した時だけ。** 開いた時の中身を覚えておき、
/// 保存する前に読み直して違っていたら上書きせず、読み直すか上書きかを人に返す（壁打ちの編集欄と同じ流儀）
@MainActor @Observable
final class FilesModel {
    private(set) var root: String?
    private(set) var files: [String] = []
    var open: Set<String> = []
    var path: String?
    var line = 1
    var text = ""
    private(set) var loaded = ""
    /// 開いてから外で書き換えられた（保存の時に訊く）
    private(set) var external = false
    var conflict = false
    var flash: String?
    var failure: String?
    var query = ""
    private(set) var hits: [(path: String, line: Int, text: String)] = []

    var dirty: Bool { text != loaded }
    /// 木の右の git の印（`M` / `??`）。読み直すたびに `git status` から
    private(set) var marks: [String: String] = [:]

    nonisolated static func marks(_ root: String) -> [String: String] {
        let out = (try? Worktree.git(["status", "--porcelain", "-uall"], in: root)) ?? ""
        var marks: [String: String] = [:]
        for line in out.split(separator: "\n") where line.count > 3 {
            let code = String(line.prefix(2)), path = String(line.dropFirst(3))
            marks[path.components(separatedBy: " -> ").last ?? path] = code == "??" ? "??" : "M"
        }
        return marks
    }

    /// 木を読み直す（`.gitignore` を尊重する: 追跡しているもの＋無視されていない追跡外）
    func load(root: String?) async {
        guard root != self.root || files.isEmpty else { return }
        self.root = root
        guard let root else { files = []; return }
        let listed = await Task.detached {
            ((try? Worktree.git(["ls-files", "--cached", "--others", "--exclude-standard"], in: root)) ?? "")
                .split(separator: "\n").map(String.init).sorted()
        }.value
        guard self.root == root else { return }
        files = listed
        marks = await Task.detached { Self.marks(root) }.value
        if open.isEmpty { open = Set(listed.compactMap { $0.split(separator: "/").first.map(String.init) }.prefix(3)) }
    }

    /// `--shot` 用（ImageRenderer は task を待たない）
    func loadNow(root: String, open file: String?) {
        self.root = root
        files = ((try? Worktree.git(["ls-files", "--cached", "--others", "--exclude-standard"], in: root)) ?? "")
            .split(separator: "\n").map(String.init).sorted()
        open = Set(files.compactMap { $0.split(separator: "/").first.map(String.init) })
        marks = Self.marks(root)
        if let file { show(file, line: 1) }
    }

    func show(_ relative: String, line: Int) {
        guard let root else { return }
        if relative != path {
            guard !dirty else { flash = "未保存の変更があります。保存するか戻してから"; return }
            path = relative
            let disk = Self.read(root, relative)
            text = disk ?? ""
            loaded = text
            external = false
            conflict = false
            failure = disk == nil ? "読めないファイル（バイナリか、消えた）" : nil
        }
        self.line = max(1, line)
        for dir in Self.parents(relative) { open.insert(dir) }
    }

    /// 2秒おきに見る。外で変わっていて、こちらが書きかけでなければ黙って読み直す
    func watch() {
        guard let root, let path, let disk = Self.read(root, path), disk != loaded else { return }
        if dirty { external = true } else { text = disk; loaded = disk }
    }

    func save(force: Bool = false) {
        guard let root, let path, dirty else { return }
        let disk = Self.read(root, path)
        if !force, disk != loaded { conflict = true; external = true; return }
        let url = URL(fileURLWithPath: root).appendingPathComponent(path)
        // 置き場の外には書かない（`..` で抜けない）
        guard url.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: root).standardizedFileURL.path + "/") else {
            failure = "置き場の外には書かない"
            return
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            loaded = text
            external = false
            conflict = false
            flash = force ? "上書きしました" : "保存しました"
            marks = Self.marks(root)
        } catch {
            failure = "保存できなかった: \(error.localizedDescription)"
        }
    }

    func reload() {
        guard let root, let path else { return }
        text = Self.read(root, path) ?? text
        loaded = text
        external = false
        conflict = false
        flash = "読み直しました"
    }

    func search() async {
        guard let root, query.count >= 2 else { hits = []; return }
        let q = query
        let out = await Task.detached {
            (try? Worktree.git(["grep", "-n", "-I", "--no-color", "-F", "-e", q], in: root)) ?? ""
        }.value
        guard q == query else { return }
        hits = out.split(separator: "\n").prefix(100).compactMap { row in
            let f = row.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, let n = Int(f[1]) else { return nil }
            return (f[0], n, f[2].trimmingCharacters(in: .whitespaces))
        }
    }

    static func read(_ root: String, _ relative: String) -> String? {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: url), !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parents(_ relative: String) -> [String] {
        let parts = relative.split(separator: "/").dropLast()
        return parts.indices.map { parts[...$0].joined(separator: "/") }
    }
}

// MARK: - 02 FILES（構造とファイル）

/// 手で介入する時のパーキングブレーキ。1ファイルを開いて直して ⌘S。ハイライト・タブ・自動保存は無い
struct FilesScreen: View {
    let model: FilesModel
    let width: CGFloat
    let height: CGFloat

    @State private var finding: String?
    @State private var selection: TextSelection?
    @Environment(\.frozenTime) private var frozen

    /// 行送り。行番号と本文を同じ書体・同じ行間の Text にして揃え、帯と送り先の位置だけこの値で数える
    static let spacing: CGFloat = 6
    static let lineHeight: CGFloat = {
        let font = SumiFonts.mono.flatMap { NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 13) }
            ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        return ceil(font.ascender - font.descender + font.leading) + spacing
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                SectionMark(number: "02", title: "FILES", jp: "構造とファイル")
                Text(model.path.map { ($0 as NSString).lastPathComponent } ?? "Pick a file.")
                    .font(.display(44)).lineLimit(1).truncationMode(.middle)
            }
            editor
                .frame(width: width, height: max(240, height - 184 - 60))
                .offset(y: 100)
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, alignment: .topLeading)
        .task(id: model.path) {
            guard frozen == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.watch()
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(model.path ?? "—").font(.mono(11)).lineLimit(1).truncationMode(.head)
                if model.dirty {
                    HStack(spacing: 6) { Rectangle().fill(Palette.Light.fg).frame(width: 8, height: 8); Text("未保存") }
                        .font(.mono(9)).tracking(1.1)
                }
                Spacer(minLength: 0)
                if let flash = model.flash { Text(flash).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
                Button("⌘F") { finding = finding == nil ? "" : nil }
                    .buttonStyle(SumiButtonStyle(primary: false, size: 10))
                    .keyboardShortcut("f", modifiers: .command)
                Button("⌘S 保存") { model.save() }
                    .buttonStyle(SumiButtonStyle(primary: true, size: 10))
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.dirty)
            }
            .padding(.leading, 12).padding(.trailing, 6)
            .frame(height: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }

            if model.external && !model.conflict {
                HStack(spacing: 10) {
                    Blink()
                    Text("外で書き換えられています。保存するときに訊きます。").font(.bodyJP(13))
                    Spacer(minLength: 0)
                    Button("いま読み直す") { model.reload() }.buttonStyle(.plain).font(.mono(10)).underline()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().stroke(Palette.Light.fg, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(height: 1)
                }
            }
            if model.conflict {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { Blink(); Text("CONFLICT // 上書きしませんでした").font(.mono(10)).tracking(1.2) }
                    Text("開いてから、このファイルは外で書き換えられています。どちらにしますか。").font(.bodyJP(14))
                    HStack(spacing: 8) {
                        Button("読み直す（自分の変更を捨てる）") { model.reload() }
                            .buttonStyle(SumiButtonStyle(primary: true, ink: Palette.white, paper: Palette.blue))
                        Button("上書きする") { model.save(force: true) }
                            .buttonStyle(SumiButtonStyle(primary: false, ink: Palette.white, paper: Palette.blue))
                        Button("やめる") { model.conflict = false }.buttonStyle(.plain).font(.mono(11))
                    }
                }
                .foregroundStyle(Palette.white)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.Light.fg)
            }
            if let failure = model.failure {
                Text(failure).font(.bodyJP(12)).foregroundStyle(Palette.Light.danger)
                    .padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let query = finding { findBar(query) }

            body(text: model.text)

            HStack(spacing: 14) {
                Text("\(lineCount) 行")
                Text("UTF-8 · LF")
                Spacer(minLength: 0)
                Text("ハイライト・自動保存なし · 手で直す時だけ")
            }
            .font(.mono(9)).tracking(1.1).foregroundStyle(Palette.Light.fg2)
            .padding(.horizontal, 12).frame(height: 26)
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
        }
        .background(Palette.Light.bg)
        .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 2))
    }

    private var lineCount: Int { model.text.split(separator: "\n", omittingEmptySubsequences: false).count }

    /// 行番号の列と本文を1つのスクロールに載せる（本文の欄は高さを行数ぶん取って、自分ではスクロールしない）
    @ViewBuilder
    private func body(text: String) -> some View {
        if model.path == nil {
            Text("木から選ぶか、⌘P で開く。REVIEW の行や 04 ACTIONS の行からもその行で開けます。")
                .font(.bodyJP(14)).padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollViewReader { proxy in
                LiveScroll {
                    ZStack(alignment: .topLeading) {
                        if model.line > 1 {
                            Rectangle().fill(Palette.hover)
                                .frame(height: Self.lineHeight)
                                .offset(y: 10 + CGFloat(model.line - 1) * Self.lineHeight)
                        }
                        // 送り先の目印（見えない）
                        VStack(spacing: 0) {
                            ForEach(1...max(1, lineCount), id: \.self) { n in Color.clear.frame(height: Self.lineHeight).id(n) }
                        }
                        .padding(.top, 10)
                        HStack(alignment: .top, spacing: 0) {
                            Text((1...max(1, lineCount)).map(String.init).joined(separator: "\n"))
                            .font(.mono(13)).lineSpacing(Self.spacing).multilineTextAlignment(.trailing)
                            .foregroundStyle(Palette.Light.fg3)
                            .padding(.vertical, 10).padding(.trailing, 10)
                            .frame(width: 52, alignment: .trailing)
                            .overlay(alignment: .trailing) { Rectangle().fill(Palette.Light.line).frame(width: 1) }
                            Group {
                                if frozen != nil {
                                    Text(text).frame(maxWidth: .infinity, alignment: .topLeading)
                                } else {
                                    TextEditor(text: Binding(get: { model.text }, set: { model.text = $0 }),
                                               selection: $selection)
                                        .scrollDisabled(true)
                                        .scrollContentBackground(.hidden)
                                }
                            }
                            .font(.mono(13))
                            .lineSpacing(Self.spacing)
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .frame(height: CGFloat(lineCount) * Self.lineHeight + 40, alignment: .topLeading)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(max(1, model.line - 6), anchor: .top) }
                .onChange(of: model.line) { proxy.scrollTo(max(1, model.line - 6), anchor: .top) }
            }
        }
    }

    private func findBar(_ query: String) -> some View {
        let hits = query.isEmpty ? 0 : model.text.components(separatedBy: query).count - 1
        return HStack(spacing: 8) {
            Text("FIND").font(.mono(10)).tracking(1).foregroundStyle(Palette.Light.fg2)
            TextField("", text: Binding(get: { finding ?? "" }, set: { finding = $0 }))
                .textFieldStyle(.plain).font(.mono(12))
                .padding(.horizontal, 8).frame(width: 240, height: 28)
                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                .onSubmit(next)
                .onExitCommand { finding = nil }
            Text(query.isEmpty ? "" : "\(hits) 件").font(.mono(10))
            Button("次 ↵", action: next).buttonStyle(.plain).font(.mono(10))
            Spacer(minLength: 0)
            Button("[×]") { finding = nil }.buttonStyle(.plain).font(.mono(10))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 1) }
    }

    /// 次の一致を選び、その行まで送る
    private func next() {
        guard let query = finding, !query.isEmpty else { return }
        let text = model.text
        let start: String.Index = {
            if case let .selection(range)? = selection?.indices { return range.upperBound }
            return text.startIndex
        }()
        guard let found = text.range(of: query, range: start..<text.endIndex) ?? text.range(of: query) else { return }
        selection = TextSelection(range: found)
        model.line = text[..<found.lowerBound].filter { $0 == "\n" }.count + 1
    }
}

/// FILES の右列。上＝木（いま触られているものに墨、書込量の目盛り、使う→／使われる← を浮かべる）と検索、
/// 下＝開いているファイルの関係（使う・使われる・書込・読み）
struct FilesPanels: View {
    let cockpit: Cockpit
    let model: FilesModel
    let height: CGFloat
    @State private var hover: String?
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let lower = max(260, height - 406)
        VStack(spacing: 14) {
            SumiPanel(number: "02", title: "TREE", jp: "木", right: "⌘P · ⇧⌘F",
                      foot: ".gitignore で隠したものは出しません") {
                Group {
                    if frozen != nil {
                        Text(model.query.isEmpty ? "検索 · 結果は ファイル:行" : model.query)
                            .foregroundStyle(Palette.Light.fg3).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("検索 · 結果は ファイル:行", text: Binding(get: { model.query }, set: { model.query = $0 }))
                            .textFieldStyle(.plain)
                    }
                }
                    .font(.mono(12))
                    .padding(.horizontal, 8).frame(height: 30)
                    .overlay(Rectangle().strokeBorder(Palette.blue, lineWidth: 1))
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 6, trailing: 12))
                    .task(id: model.query) {
                        try? await Task.sleep(for: .milliseconds(250))
                        await model.search()
                    }
                if !model.query.isEmpty { results } else {
                    tree
                    HStack(spacing: 10) { Text("墨 = いま触られている"); Text("▮ = 書込量"); Text("→ 使う · ← 使われる") }
                        .font(.mono(9)).tracking(0.7).foregroundStyle(Palette.Light.fg2)
                        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: lower - 76 - 14)
            ties.frame(height: height - 60 - lower)
        }
        .frame(width: 352)
    }

    @ViewBuilder
    private var results: some View {
        Text("\(model.hits.count) 件 · ファイル:行").font(.mono(9)).tracking(1.2).foregroundStyle(Palette.Light.fg2)
            .padding(.horizontal, 14).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
        ForEach(Array(model.hits.enumerated()), id: \.offset) { _, hit in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text((hit.path as NSString).lastPathComponent)
                    Text(":\(hit.line)").foregroundStyle(Palette.Light.fg2)
                }
                .font(.mono(11))
                Text(hit.text).font(.mono(11)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            .contentShape(Rectangle())
            .onTapGesture { model.show(hit.path, line: hit.line) }
        }
    }

    /// ディレクトリは開閉、ファイルは押すと開く。ホバーしたファイルの使う／使われるを浮かべる
    @ViewBuilder
    private var tree: some View {
        let rows = visibleRows
        let ties = hover.map { relations(of: $0) }
        ForEach(rows, id: \.path) { row in
            if row.isDir {
                HStack(spacing: 6) {
                    // 名前の頭をファイルの行（印・墨の欄の後ろ）と揃える
                    Text(model.open.contains(row.path) ? "▾" : "▸").frame(width: 14)
                    Color.clear.frame(width: 16, height: 1)
                    Text(row.name + "/")
                    Spacer(minLength: 0)
                }
                .font(.mono(11))
                .padding(.leading, 12 + CGFloat(row.depth) * 14).padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    if model.open.contains(row.path) { model.open.remove(row.path) } else { model.open.insert(row.path) }
                }
            } else {
                fileRow(row, rel: ties.map { $0.dep.contains(row.path) ? "→" : $0.used.contains(row.path) ? "←" : "" })
            }
        }
    }

    private func fileRow(_ row: TreeRow, rel: String?) -> some View {
        let on = row.path == model.path
        let absolute = abs(row.path)
        let live = cockpit.touches.last { $0.path == absolute && $0.finished == nil }
        let weight = weightOf(absolute)
        return HStack(spacing: 6) {
            Text(rel ?? "").font(.mono(11)).frame(width: 14).foregroundStyle(on ? Palette.white : Palette.Light.fg3)
            Group {
                if let live { InkLoader(status: live.kind == .write ? "write" : "search", pitch: 1.4, color: on ? Palette.white : Palette.blue) }
                else { Color.clear }
            }
            .frame(width: 16, height: 14)
            Text(row.name + (on && model.dirty ? " ■" : "")).font(.mono(12)).fontWeight(live != nil ? .bold : .regular)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Text(model.marks[row.path] ?? "").font(.mono(9)).opacity(0.8).frame(width: 20)
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle().fill(i < weight ? (on ? Palette.white : Palette.blue) : (on ? Palette.white.opacity(0.3) : Palette.Light.line))
                        .frame(width: 4, height: 8)
                }
            }
        }
        .padding(.leading, 12 + CGFloat(row.depth) * 14).padding(.trailing, 12)
        .frame(height: 26)
        .foregroundStyle(on ? Palette.white : Palette.blue)
        .background(on ? Palette.blue : hover == row.path ? Palette.hover : .clear)
        .opacity(hover != nil && rel == "" && hover != row.path ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.show(row.path, line: 1) }
        .onHover { hover = $0 ? row.path : nil }
    }

    private var ties: some View {
        let path = model.path
        let r = path.map { relations(of: $0) } ?? (dep: [], used: [])
        let absolute = path.map(abs)
        return SumiPanel(number: "02", title: "TIES", jp: "関係", right: path.map { ($0 as NSString).lastPathComponent } ?? "",
                         foot: nil) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([("DEPENDS ON 使う", r.dep, "→"), ("USED BY 使われる", r.used, "←")], id: \.0) { title, list, arrow in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(title) · \(list.count)").font(.mono(9)).tracking(1.2).foregroundStyle(Palette.Light.fg2)
                        if list.isEmpty { Text("なし").font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
                        ForEach(list.prefix(8), id: \.self) { p in
                            HStack(spacing: 8) {
                                Text(arrow).foregroundStyle(Palette.Light.fg3)
                                Text((p as NSString).lastPathComponent)
                                Spacer(minLength: 0)
                            }
                            .font(.mono(12))
                            .contentShape(Rectangle())
                            .onTapGesture { model.show(p, line: 1) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("WRITES 書込").font(.mono(9)).tracking(1.2).foregroundStyle(Palette.Light.fg2)
                    let writes = absolute.map { cockpit.writeHistory(of: $0) } ?? []
                    if writes.isEmpty { Text("このセッションでは書かれていません").font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2) }
                    ForEach(writes.prefix(4)) { w in
                        HStack(spacing: 10) {
                            Text(w.role).lineLimit(1)
                            Text("+\(w.added) −\(w.removed)").foregroundStyle(Palette.Light.fg2)
                            Spacer(minLength: 0)
                            Text(w.at.formatted(.dateTime.hour().minute())).foregroundStyle(Palette.Light.fg2)
                        }
                        .font(.mono(11))
                    }
                    let reads = absolute.map { cockpit.readCounts(of: $0).reduce(0) { $0 + $1.count } } ?? 0
                    Text("READS ×\(reads)").font(.mono(10)).foregroundStyle(Palette.Light.fg2)
                    if let memo = absolute.flatMap({ cockpit.structure.notes[$0]?.memo }), !memo.isEmpty {
                        Text(memo).font(.bodyJP(12)).lineLimit(3)
                    }
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 値

    private struct TreeRow {
        let path: String
        let name: String
        let depth: Int
        let isDir: Bool
    }

    /// 開いているディレクトリの中だけを並べた木
    private var visibleRows: [TreeRow] {
        var rows: [TreeRow] = []
        var shownDirs = Set<String>()
        for file in model.files {
            let parts = file.split(separator: "/").map(String.init)
            var visible = true
            for depth in 0..<(parts.count - 1) {
                let dir = parts[...depth].joined(separator: "/")
                if !shownDirs.contains(dir) {
                    if visible { rows.append(TreeRow(path: dir, name: parts[depth], depth: depth, isDir: true)) }
                    shownDirs.insert(dir)
                }
                if !model.open.contains(dir) { visible = false }
            }
            if visible { rows.append(TreeRow(path: file, name: parts.last ?? file, depth: parts.count - 1, isDir: false)) }
        }
        // ponytail: 数千本の木は先頭 600 行で切る（検索か ⌘P で開く）
        return Array(rows.prefix(600))
    }

    private func abs(_ relative: String) -> String {
        guard let root = model.root else { return relative }
        return (root as NSString).appendingPathComponent(relative)
    }

    private func rel(_ absolute: String) -> String? {
        guard let root = model.root, absolute.hasPrefix(root + "/") else { return nil }
        return String(absolute.dropFirst(root.count + 1))
    }

    private func relations(of relative: String) -> (dep: [String], used: [String]) {
        let a = abs(relative)
        return ((cockpit.structure.dependsOn[a] ?? []).compactMap(rel).sorted(),
                (cockpit.structure.usedBy[a] ?? []).compactMap(rel).sorted())
    }

    private func weightOf(_ absolute: String) -> Int {
        let cells = cockpit.snapshot(now: Date(), mode: .structure).cards.flatMap(\.files)
        guard let cell = cells.first(where: { $0.id == absolute }) else { return 0 }
        return Cockpit.writeWeight(added: cell.added, removed: cell.removed)
    }
}

// MARK: - ⌘P

/// ファイル名の飛び飛びの一致（`cvsw` → `CockpitView.swift`）で9件まで。↑↓ ENTER
struct QuickOpen: View {
    let files: [String]
    let onPick: (String) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let list = Self.match(files, query)
        ZStack(alignment: .topLeading) {
            Palette.scrim.contentShape(Rectangle()).onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("⌘P // OPEN").font(.mono(10)).tracking(1.2).foregroundStyle(Palette.Light.fg2)
                    TextField("ファイル名", text: $query)
                        .textFieldStyle(.plain).font(.mono(16)).focused($focused)
                        .onSubmit { if list.indices.contains(index) { onPick(list[index]) } }
                        .onKeyPress(.downArrow) { index = min(max(0, list.count - 1), index + 1); return .handled }
                        .onKeyPress(.upArrow) { index = max(0, index - 1); return .handled }
                        .onExitCommand(perform: onClose)
                        .onChange(of: query) { index = 0 }
                }
                .padding(.horizontal, 12).frame(height: 48)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.fg).frame(height: 2) }
                ForEach(Array(list.enumerated()), id: \.offset) { i, f in
                    HStack(spacing: 10) {
                        Text((f as NSString).lastPathComponent)
                        Text((f as NSString).deletingLastPathComponent).opacity(0.65)
                        Spacer(minLength: 0)
                    }
                    .font(.mono(12))
                    .foregroundStyle(i == index ? Palette.Light.bg : Palette.Light.fg)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(i == index ? Palette.Light.fg : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(f) }
                    .onHover { if $0 { index = i } }
                }
                if list.isEmpty { Text("見つかりません").font(.bodyJP(13)).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .foregroundStyle(Palette.Light.fg)
            .frame(width: 600)
            .background(Palette.Light.bg)
            .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
            .offset(x: 420, y: 110)
        }
        .onAppear { focused = true }
    }

    nonisolated static func match(_ files: [String], _ query: String) -> [String] {
        let q = query.lowercased()
        guard !q.isEmpty else { return Array(files.prefix(9)) }
        return Array(files.filter { file in
            var rest = Substring(file.lowercased())
            for c in q {
                guard let i = rest.firstIndex(of: c) else { return false }
                rest = rest[rest.index(after: i)...]
            }
            return true
        }.sorted { ($0 as NSString).lastPathComponent.count < ($1 as NSString).lastPathComponent.count }.prefix(9))
    }
}
