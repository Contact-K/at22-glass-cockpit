import Foundation

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

// MARK: - コード構造

/// プロジェクトのソースを読んで、ファイル同士の依存を出す。
///
/// import では辺が張れない。Swift の単一モジュールにはファイル間の import が無く、
/// `import Foundation` しか出てこないのでグラフが空になる（madge/pydeps 系を採らなかった理由）。
/// 代わりに「**どのファイルが宣言した名前を、どのファイルが使っているか**」で張る。
/// 単一モジュールでも、TypeScript でも Python でも同じ規則で効く。
enum Structure {

    /// 走査する拡張子。ここに無いものは読まない
    static let sourceExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "py", "go", "rs",
        "rb", "java", "kt", "kts", "c", "h", "cpp", "hpp", "cc", "m", "mm", "cs", "php",
    ]

    /// ソースではないが、ソースについて書かれているもの。
    /// 構想ノートや計画書がどのファイルの話をしているかは、コードからは絶対に出てこない情報
    static let noteExtensions: Set<String> = ["md", "markdown", "txt"]

    /// 中身が生成物・依存物のディレクトリ。ここを読むと辺がライブラリで埋まる
    static let skipDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "vendor", "Pods", "Carthage",
        "DerivedData", "dist", "build", "out", "target", "coverage",
        ".venv", "venv", "__pycache__", ".next", ".nuxt", ".cache", ".tox", "Migrations",
    ]

    /// 宣言を拾うキーワード。言語をまたいで同じ形をしている
    private static let declarationKeywords: Set<String> = [
        "class", "struct", "enum", "protocol", "actor", "typealias",
        "interface", "trait", "record", "object",
    ]

    /// `type` は TypeScript の型別名（`type Foo = …`）にだけ効かせる。
    /// 他の言語では `obj["type"] as? String` のようにただの語として頻出し、
    /// 直後の `String` が「そのファイルが宣言した型」になって全ファイルに誤った辺が張られる
    private static let typeAliasExtensions: Set<String> = ["ts", "tsx", "js", "jsx", "mjs"]

    // 走査の上限。監視対象が青天井にならないように切る
    static let maxFiles = 3000
    static let maxFileBytes = 512_000
    static let maxTotalBytes = 32_000_000
    /// 短すぎる名前はジェネリクス（`T` / `U`）や略語と衝突するので拾わない
    static let minSymbolLength = 3

    /// 1ファイルが「何をするやつか」。構造画面の2行目に出す。
    /// LLM を呼ばないので、書けるのはソース自身から取れることだけ
    struct FileNote: Sendable {
        /// 人が書いた役割。実測でこれが取れるのは Swift 264本中の約半分
        var memo = ""
        /// 宣言している型。出現順。memo が無いファイルはこれが代わりになる（100%取れる）
        var declared: [String] = []
        /// 他のファイルが実際に使っている名前。「外に何を供給しているか」
        var exported: [String] = []
        var lines = 0

        /// セルの2行目に出す1行。人の言葉があればそれ、無ければ何が住んでいるか。
        /// ponytail: 実測で 364本中20本（5%）はどちらも空になる。`extension` しか持たない
        /// `Color+Hex.swift` や設定ファイルで、どれも名前自体が役割を語っている。
        /// 埋めるには型宣言とは別の走査がもう1本要るので、空欄のままにしてある
        var headline: String {
            if !memo.isEmpty { return memo }
            guard let first = declared.first else { return "" }
            return declared.count > 1 ? "\(first) +\(declared.count - 1)型" : first
        }
    }

    struct Graph: Sendable {
        /// 辺が無いファイルも構造画面に残すため、走査結果そのものを持つ
        var files: Set<String> = []
        /// ファイル -> そのファイルの役割
        var notes: [String: FileNote] = [:]
        /// ファイル -> そのファイルが名前を借りている先
        var dependsOn: [String: Set<String>] = [:]
        /// 逆引き。「これを直すとどこに響くか」
        var usedBy: [String: Set<String>] = [:]
        /// ソース -> そのファイルに言及しているノート（構想ノート・計画書・README）。
        /// 「この実装がどの企画から来たか」はコードの中には書かれていない
        var notedBy: [String: Set<String>] = [:]
        /// 逆引き。ノート -> そのノートが話題にしているソース
        var mentions: [String: Set<String>] = [:]
        /// 走査したファイル数と、張れた辺の数。空だった時に理由を出すため
        var scanned = 0
        var edges = 0

        var isEmpty: Bool { dependsOn.isEmpty }

        /// ホバーしたファイルと関係のあるファイル。呼んでいる先と呼ばれている元の両方。
        /// 片方向にすると「これを使っている側」が沈んだまま見えなくなる
        func related(to path: String) -> Set<String> {
            (dependsOn[path] ?? []).union(usedBy[path] ?? [])
        }
    }

    // MARK: 走査

    /// プロジェクトの根をまとめて走査する。パスは絶対なので複数プロジェクトを混ぜても衝突しない。
    /// メインアクタから外して呼ぶこと（数千ファイルを読む）
    nonisolated static func scan(roots: [URL]) -> Graph {
        var contents: [String: String] = [:]
        var budget = maxTotalBytes

        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { continue }

            for case let url as URL in walker {
                guard contents.count < maxFiles, budget > 0 else { break }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true {
                    if skipDirectories.contains(url.lastPathComponent) { walker.skipDescendants() }
                    continue
                }
                let ext = url.pathExtension.lowercased()
                guard sourceExtensions.contains(ext) || noteExtensions.contains(ext),
                      let size = values?.fileSize, size <= maxFileBytes,
                      let text = try? String(contentsOf: url, encoding: .utf8)
                else { continue }
                budget -= size
                contents[url.standardizedFileURL.path] = text
            }
        }

        return build(contents)
    }

    /// 読み込み済みの中身から辺を張る。走査と分けてあるので検査から直接叩ける
    nonisolated static func build(_ contents: [String: String]) -> Graph {
        // ノートはソースの依存グラフには入れない。混ぜると「README が全ファイルを呼んでいる」
        // ことになって指揮系統が読めなくなる。言及だけを別の軸として拾う
        var sources: [String: String] = [:]
        var notes: [String: String] = [:]
        for (path, text) in contents {
            let ext = (path as NSString).pathExtension.lowercased()
            if noteExtensions.contains(ext) { notes[path] = text } else { sources[path] = text }
        }
        let contents = sources

        // 1. 誰が何を宣言したか。2ファイル以上が同じ名前を宣言していたら、
        //    どちらを指すか決められないので捨てる（当てずっぽうの辺を張らない）
        var owner: [String: String] = [:]
        var ambiguous: Set<String> = []
        for (path, text) in contents {
            for name in declarations(in: text, ext: (path as NSString).pathExtension) {
                if let existing = owner[name], existing != path { ambiguous.insert(name) }
                owner[name] = path
            }
        }
        for name in ambiguous { owner[name] = nil }

        // 2. 各ファイルに出てくる語を引く。1ファイル1パスで済む
        // 一覧にはノートも並べる（企画書や README もプロジェクトの一部）。
        // ただし依存グラフには入れない。混ぜると「README が全ファイルを呼んでいる」ことになる
        var graph = Graph(files: Set(contents.keys).union(notes.keys), scanned: contents.count)
        var exported: [String: Set<String>] = [:]
        for (path, text) in contents {
            var targets: Set<String> = []
            for word in identifiers(in: text) {
                guard let target = owner[word], target != path else { continue }
                targets.insert(target)
                // どのファイルと繋がったかだけでなく、どの名前で繋がったかも残す。
                // 「外に何を供給しているファイルか」＝そのファイルの役割そのもの
                exported[target, default: []].insert(word)
            }
            guard !targets.isEmpty else { continue }
            graph.dependsOn[path] = targets
            graph.edges += targets.count
            for target in targets { graph.usedBy[target, default: []].insert(path) }
        }

        // 3. ノートがどのソースの話をしているか。ファイル名そのものか、宣言している型名で拾う
        for (notePath, text) in notes {
            let words = Set(self.words(in: text))
            for (source, _) in contents {
                let file = (source as NSString).lastPathComponent
                let stem = (file as NSString).deletingPathExtension
                let named = text.contains(file) || words.contains(stem)
                let byType = !named && (owner.contains { $0.value == source && words.contains($0.key) })
                if named || byType {
                    graph.notedBy[source, default: []].insert(notePath)
                    graph.mentions[notePath, default: []].insert(source)
                }
            }
        }

        // ノートにも見出しと行数を付ける。記憶の画面はここが本文になる
        for (path, text) in notes {
            graph.notes[path] = FileNote(memo: noteHeadline(text),
                                         lines: text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
        }

        // 4. 「何をするやつか」。辺が無いファイルにも必ず1行付ける
        for (path, text) in contents {
            let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            // ファイル名と同じ型があればそれが主役。出現順のままだと、たまたま先頭にある
            // 小さな enum が見出しになる（`Cockpit.swift` が `CockpitMode` を名乗る）
            var declared = declarations(in: text, ext: (path as NSString).pathExtension)
            if let i = declared.firstIndex(of: stem), i != 0 {
                declared.insert(declared.remove(at: i), at: 0)
            }
            graph.notes[path] = FileNote(
                memo: memo(in: text, stem: stem),
                declared: declared,
                exported: (exported[path] ?? []).sorted(),
                lines: text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
        }
        return graph
    }

    /// ノートの1行要約。優先順は **frontmatter の description → 最初の本文 → 見出し**。
    ///
    /// 見出しを最優先にすると、ほとんどのノートが「# ファイル名」か「# Concept」のような
    /// 節の名前を名乗って、どれも同じ顔になる（実測で41本中の大半がそうだった）。
    /// 記憶ファイルは frontmatter の `description:` がまさに1行要約なので、あれば一番強い
    nonisolated static func noteHeadline(_ text: String) -> String {
        var inFrontMatter = false
        var seenFirstLine = false
        var heading = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmed
            if line == "---" {
                if !seenFirstLine { inFrontMatter = true; seenFirstLine = true; continue }
                if inFrontMatter { inFrontMatter = false; continue }
            }
            seenFirstLine = true

            if inFrontMatter {
                guard line.lowercased().hasPrefix("description:") else { continue }
                let value = line.dropFirst("description:".count).trimmed
                if !value.isEmpty { return value }
                continue
            }
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if heading.isEmpty {
                    let title = line.drop { $0 == "#" }.trimmed
                    if !title.isEmpty { heading = title }
                }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("|") { continue }   // コード塊と表は要約にならない
            let body = line.drop { $0 == "-" || $0 == "*" || $0 == ">" || $0 == " " }.trimmed
            if body.count >= 6 { return body }
        }
        return heading
    }

    // MARK: 役割

    /// 人が書いた「このファイルは何か」。取れなければ空。
    ///
    /// 拾い方を2つに絞ってある。緩めると別のものを掴む——実測で、前方一致まで許すと
    /// `Cockpit.swift` が `CockpitMode` の説明を、`Transcript.swift` が `TranscriptEvent` の説明を
    /// 「ファイルの役割」として出してしまう。どちらもファイル全体の話ではない。
    /// ponytail: 取れるのは実測で約半分。残りは declared が埋めるので、無理に精度を追わない
    nonisolated static func memo(in text: String, stem: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // 1. ファイル名と完全に同じ名前の型に付いた doc コメント。そのファイルの主役の説明
        for (i, line) in lines.enumerated() {
            guard let name = declaredName(line), name == stem else { continue }
            var buffer: [String] = []
            var j = i - 1
            while j >= 0, lines[j].trimmed.hasPrefix("///") {
                buffer.insert(String(lines[j].trimmed.dropFirst(3)).trimmed, at: 0)
                j -= 1
            }
            let joined = clean(buffer, stem: stem)
            if !joined.isEmpty { return joined }
            break
        }

        // 2. import の直後に置かれた本物のファイルヘッダ。
        //    `// MARK:` が挟まったら、その先のコメントは節の中身の説明なので取らない
        var header: [String] = []
        for line in lines.prefix(30) {
            let s = line.trimmed
            if s.isEmpty { if header.isEmpty { continue } else { break } }
            if s.hasPrefix("import") || s.hasPrefix("@") { continue }
            guard s.hasPrefix("//") else { break }
            let body = s.drop { $0 == "/" }.trimmed
            if body.hasPrefix("MARK") { return "" }
            header.append(body)
        }
        return clean(header, stem: stem)
    }

    /// Xcode が自動で入れるヘッダ（ファイル名・プロジェクト名・Created by）は役割を語らないので落とす
    private static let boilerplate = ["created by", "copyright", "all rights", "licensed under",
                                      "swift-tools-version", "http://", "https://"]

    private nonisolated static func clean(_ lines: [String], stem: String) -> String {
        let kept = lines.filter { line in
            let lower = line.lowercased()
            guard !line.isEmpty, line.contains(where: { $0.isLetter }) else { return false }
            if boilerplate.contains(where: { lower.hasPrefix($0) }) { return false }
            // Xcode の自動ヘッダはファイル名とプロジェクト名が1行ずつ並ぶ。
            // 「Created by」だけ落としても、この2行が残ると説明のふりをして通ってしまう
            if lower == stem.lowercased() || lower.hasPrefix(stem.lowercased() + ".") { return false }
            // 空白を含まない ASCII だけの1語＝プロジェクト名やファイル名。説明は必ずこれより長い
            // （日本語の説明は空白が無くても ASCII 外の文字を含むので残る）
            let single = !line.contains(" ") && line.unicodeScalars.allSatisfy { $0.isASCII }
            return !single
        }
        let joined = kept.joined(separator: " ")
        // 断片を弾くための下限。長くしすぎない——「台帳。全部ここを通る」は10文字で
        // 立派な説明なのに、12文字を境にすると日本語の説明が丸ごと落ちる。
        // 定型行はファイル名一致と ASCII1語の規則が既に落としているので、ここは短くていい
        return joined.count >= 6 ? joined : ""
    }

    /// `final class Foo` / `enum Foo` の Foo。修飾子は読み飛ばす
    private nonisolated static func declaredName(_ line: String) -> String? {
        var words = line.trimmed.split(separator: " ").map(String.init)
        while let head = words.first, ["public", "private", "internal", "fileprivate",
                                       "final", "open", "indirect"].contains(head) || head.hasPrefix("@") {
            words.removeFirst()
        }
        guard let keyword = words.first,
              ["class", "struct", "enum", "protocol", "actor"].contains(keyword),
              words.count > 1 else { return nil }
        return String(words[1].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
    }

    // MARK: 字句

    /// `struct Foo` / `class Foo` / `interface Foo` の Foo。
    /// 大文字始まりだけを拾う。`func` や `def` まで入れるとメソッド名が全部入り、
    /// `update` のようなありふれた名前で無関係なファイルが繋がる
    /// 出現順で返す。先頭がそのファイルの主役になるので、Set にすると順序が失われる
    nonisolated static func declarations(in text: String, ext: String) -> [String] {
        var keywords = declarationKeywords
        if typeAliasExtensions.contains(ext.lowercased()) { keywords.insert("type") }

        var found: [String] = []
        var seen: Set<String> = []
        var previous = ""
        for word in words(in: text) {
            if keywords.contains(previous), isTypeName(word), seen.insert(word).inserted {
                found.append(word)
            }
            previous = word
        }
        return found
    }

    /// 参照されうる語だけに絞る。宣言側と同じ条件にしておかないと引けない
    nonisolated static func identifiers(in text: String) -> Set<String> {
        Set(words(in: text).filter(isTypeName))
    }

    nonisolated static func isTypeName(_ word: String) -> Bool {
        word.count >= minSymbolLength && (word.first?.isUppercase ?? false)
    }

    /// 識別子として成立する部分だけを切り出す。
    /// ponytail: コメントと文字列リテラルも一緒に拾う。除くには言語ごとの字句解析が要り、
    /// 「コメントで型名に言及しているファイル」を辺に含める害より高くつく
    nonisolated static func words(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) || ch == "_" {
                current.unicodeScalars.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
