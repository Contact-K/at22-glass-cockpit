import Foundation
import CoreGraphics

/// 画面の座標をここで全部決める。描画から切り離してあるので、
/// SwiftUI 抜きでセルフチェックから同じ計算を叩ける。
struct CockpitLayout {

    /// エージェント1体ぶん。**深さ0は箱、それ以外は行**。
    ///
    /// 以前は深さを横軸にして箱を列に並べていたが、指示の紙（62×88）が通る道を作るための
    /// 都合であって、読む側の都合ではなかった。紙を 28×40 の印に縮めたことで道が要らなくなり、
    /// 縦1本の点線レールに行を吊る形にできる（読む順が上から下の1方向になる）
    struct ChipBox {
        let chip: AgentChip
        let role: String         // 幅に合わせて省略済み
        let trailing: String     // モデル名と労働量
        let doing: String        // 今していること / してきたことの内訳
        let rect: CGRect
        let summary: Bool        // 「他N体」は状態ランプも押した先も持たない
        /// 状態ランプ（行なら右端、箱なら右上）
        var dot: CGPoint
        /// 司令塔の箱か。偽なら点線レールに吊る行
        var isRoot = false
        /// 行頭の短縮ID。司令塔は `C0`、子は `W1` から順に振る
        var shortID = ""
        /// 右端のバッジ。実行中 / 終了 / 待機
        var badge = ""
        /// 門で止まっている行。押すと門が開く（`chip.id` が門のパス）
        var gate = false
    }

    struct CellBox {
        let cell: FileCell
        let display: String      // 幅に合わせて省略済み
        /// 記憶モードだけ。1行要約と来歴（どちらも幅に合わせて省略済み）
        let note: String
        let trace: String
        /// 右端に出す参照回数の点の数
        let readTicks: Int
        let rect: CGRect
        /// 表示中で最も書かれたごく一部。虹を掛ける対象
        let huge: Bool
        let category: FileCategory
        /// いま触っているエージェント（`W5 書込中`）。**ビームを外した代わりの手掛かり**——
        /// エージェント帯の行が「このファイルを編集中」と言い、こちらが「W5 が」と返す
        var tag = ""
    }

    struct CardBox {
        let title: String        // 幅に合わせて省略済み
        let rect: CGRect
        let cells: [CellBox]
    }

    // MARK: 寸法（at22_canvas_recommended_detail.html の比率に合わせてある）

    static let margin: CGFloat = 20
    static let font: CGFloat = 12.5
    static let badgeFont: CGFloat = 11
    /// 2行ぶん。上が役割＋モデル＋労働量、下が「今していること」
    static let chipHeight: CGFloat = 46
    static let chipGap: CGFloat = 8
    static let chipPad: CGFloat = 12
    static let chipMaxWidth: CGFloat = 260
    static let chipIndent: CGFloat = 26      // 階層1つぶんの下げ幅
    static let busGap: CGFloat = 14          // チップ下端から区切り線まで
    static let cardTopGap: CGFloat = 26      // 区切り線からカード上端まで

    // MARK: エージェントの帯（司令塔の箱＋点線レール＋行）

    /// 章見出し「03 エージェント N」のぶん
    static let agentHeader: CGFloat = 26
    /// 司令塔の箱。深さ0のエージェントだけがこの幅を持つ
    static let rootCardWidth: CGFloat = 236
    /// 縦の点線レールの x（`margin` からの寄せ幅）。箱の下端から降りる
    static let railOffset: CGFloat = 100
    /// 行の左端（`margin` からの寄せ幅）。レールから 56pt の横枝でここへ繋ぐ
    static let rowOffset: CGFloat = 156
    static let rowHeight: CGFloat = 36
    static let rowGap: CGFloat = 4
    /// 箱の下端からレールが降り始めるまで
    static let railTopGap: CGFloat = 8
    /// 行頭の短縮ID（`W5`）の欄
    static let rowIDColumn: CGFloat = 30
    /// 行の名前の欄。ここを超える分は「いま何をしているか」に回す
    static let rowNameColumn: CGFloat = 150
    /// 右端のバッジの欄
    static let rowBadgeColumn: CGFloat = 52

    /// 止まった指示の印。**紙は 62×88 から 28×40 に縮めた**——
    /// 中身は行の meta と門のパネルが持つので、ここは「そこで止まっている」ことだけを指す
    static let gatePaper = CGSize(width: 28, height: 40)
    /// 紙をレールの右横に置く寄せ幅
    static let gatePaperInset: CGFloat = 12
    /// 作業と構造でセルの寸法は変えない。解説は一覧に出さず解説画面に置いたので、
    /// 2行ぶんの高さは要らなくなった（モードを切り替えても並びが飛ばない）
    static let cellHeight: CGFloat = 30
    /// 記憶モードだけ3行ぶん。ノートは名前だけでは何なのか分からないので、
    /// 1行要約と来歴を同じセルに載せる（そこが読ませたい本体）
    static let noteCellHeight: CGFloat = 58
    /// 字下げ1段ぶん。チップの階層（26）より狭くし、3つの範囲を軽く見分ける
    static let memoryIndent: CGFloat = 18
    static func cellHeight(_ mode: CockpitMode) -> CGFloat {
        mode == .memory ? noteCellHeight : cellHeight
    }
    static let cellGapX: CGFloat = 10
    static let cellGapY: CGFloat = 6
    static let cellPad: CGFloat = 9
    static let cardPad: CGFloat = 10
    static let cardTitle: CGFloat = 24
    static let cardGap: CGFloat = 14
    static let cardBottomPad: CGFloat = 12
    static let cardMinWidth: CGFloat = 220
    static let cardMaxWidth: CGFloat = 400
    /// 下端に空ける余白。凡例が章見出しの右へ移ったので、2段ぶん（76）は要らなくなった
    static let legendHeight: CGFloat = 24

    private(set) var chips: [ChipBox] = []
    private(set) var cards: [CardBox] = []
    private(set) var busY: CGFloat = 0
    private(set) var contentHeight: CGFloat = 0
    /// 縦の点線レール。司令塔の箱の下端から最後の行まで
    private(set) var railX: CGFloat = 0
    private(set) var railTop: CGFloat = 0
    private(set) var railBottom: CGFloat = 0
    private var cellRects: [String: CGRect] = [:]
    private var cardRects: [String: CGRect] = [:]      // ファイルパス -> それが載っているカード
    private var chipRects: [String: CGRect] = [:]      // エージェントID -> チップ
    /// 門のパス -> 押せる範囲（紙と行を合わせたもの）
    private var gateRects: [String: CGRect] = [:]
    /// 門のパス -> 紙そのもの（描くのはこちら）
    private var gatePapers: [String: CGRect] = [:]

    func rect(forFile path: String) -> CGRect? { cellRects[path] }
    /// 点の上にあるファイル。セルは重ならないので当たるのは高々1つ
    func file(at point: CGPoint) -> String? { cellRects.first { $0.value.contains(point) }?.key }
    func chip(at point: CGPoint) -> String? { chipRects.first { $0.value.contains(point) }?.key }
    func cardRect(forFile path: String) -> CGRect? { cardRects[path] }
    func chipRect(forAgent id: String) -> CGRect? { chipRects[id] }
    func rect(forGate id: String) -> CGRect? { gateRects[id] }
    /// 点の上にある門。紙はチップの通り道に立つので、当たり判定はチップより先に見る
    func gate(at point: CGPoint) -> String? { gateRects.first { $0.value.contains(point) }?.key }
    /// 描画側が引く一覧。順序は問わない（重ならないよう置いてある）
    var gates: [(id: String, rect: CGRect)] { gatePapers.map { (id: $0.key, rect: $0.value) } }
    func paper(forGate id: String) -> CGRect? { gatePapers[id] }

    /// 行の3つの文字（名前・モデルと割合・いま何をしているか）を行幅に収める。
    /// 広ければ今まで通り meta に余りを全部回す。入りきらない時は
    /// いま何をしているか → モデルと割合 の順に落とし、名前は削ってでも残す（誰なのかが最後の手掛かり）
    static func fitRow(role: String, trailing: String, meta: String,
                       rowWidth: CGFloat) -> (role: String, trailing: String, doing: String) {
        let text = rowWidth - rowIDColumn - rowBadgeColumn - 10      // 名前の頭からバッジの手前まで
        let trailingWidth = textWidth(trailing, size: badgeFont)
        let keep = trailing.isEmpty || text >= 60 + trailingWidth + 10
        let reserved = keep && !trailing.isEmpty ? trailingWidth + 10 : 0
        let metaLimit = rowWidth - rowIDColumn - rowNameColumn - rowBadgeColumn - reserved - 30
        return (truncateMiddle(role, toWidth: max(0, min(rowNameColumn - 8, text - reserved))),
                keep ? trailing : "",
                metaLimit >= 40 ? truncateMiddle(meta, toWidth: metaLimit, size: badgeFont) : "")
    }

    /// 状態のバッジ。**終了・待機は無彩色、実行中だけが色を持つ**
    static func chipBadge(_ chip: AgentChip) -> String {
        chip.done ? "終了" : (chip.busy ? "実行中" : "待機")
    }

    /// 行の「いま何をしているか」。
    ///
    /// **いま触っているファイルがあれば、必ずそれを出す。** ビーム（エージェントとファイルを
    /// 結ぶ線）を外したので、どのエージェントがどのファイルを触っているかを語るのは
    /// この1行とセル側のタグだけになった。触っていない時だけ、それまでの内訳
    /// （編集166 読取136 検索67）に落とす——ファイル軸に載らない作業はそこにしか出ない
    static func rowMeta(_ chip: AgentChip) -> String {
        if let target = chip.target, let kind = chip.kind {
            let name = (target as NSString).lastPathComponent
            return name + (kind == .write ? " を編集中" : " を読取中")
        }
        return plainLine(chip.doing)
    }
    // MARK: エゴビュー

    /// 1ファイルの解説画面。左＝ファイルの一覧、中央＝そのファイルが何か、右＝関係。
    /// 曲線で結ぶ案から読み物へ寄せた（at22 解説画面モック）。線は目で追えないが、
    /// 「呼んでいる／呼ばれている／関連ノート」を分けて並べれば一目で数と顔ぶれが分かる
    struct EgoView {
        enum Marker { case none, calling, calledBy, note }
        struct Row {
            let path: String        // 押した時の飛び先。空なら押せない
            let label: String
            let rect: CGRect
            let indent: CGFloat
            let marker: Marker
            let selected: Bool
        }
        struct Stat {
            let title: [String]     // 2行に折り返す
            let value: String
            let rect: CGRect
        }
        struct Group {
            let title: String
            let point: CGPoint
        }
        var panels: [CGRect] = []       // 中央のハブ
        var relations: [Row] = []
        var groups: [Group] = []
        var breadcrumb: [String] = []
        var name = ""
        var memo: [String] = []
        var stats: [Stat] = []
        var namePoint = CGPoint.zero
        var memoTop: CGFloat = 0
        /// 中央のファイルと右の行を結ぶ矢印。向きが色と一緒に意味を持つ
        var links: [Link] = []

        struct Link {
            let from: CGPoint       // 出どころ
            let to: CGPoint         // 矢の先
            let marker: Marker
        }

        /// 点の上にあるファイル。左右の一覧から飛べる
        func file(at point: CGPoint) -> String? {
            relations.first { !$0.path.isEmpty && $0.rect.contains(point) }?.path
        }

        /// 押しても閉じない場所。中央のハブ・数値タイル・解説の本文は
        /// 「読ませるために置いてある」ので、触っただけで画面が消えると使えない
        func holdsFocus(at point: CGPoint) -> Bool {
            if panels.contains(where: { $0.contains(point) }) { return true }
            if stats.contains(where: { $0.rect.contains(point) }) { return true }
            // 解説の本文。行の高さぶんを帯として見る
            guard !memo.isEmpty, let stat = stats.first else { return false }
            let body = CGRect(x: stat.rect.minX, y: memoTop - 14,
                              width: stat.rect.width * 3, height: CGFloat(memo.count) * 21 + 14)
            return body.contains(point)
        }
    }

    /// 中央と右の間だけ広く取る。矢印を通す隙間で、16px だと向きが読めない
    static let egoLinkGap: CGFloat = 64
    static let egoRowHeight: CGFloat = 26
    static let egoMarker: CGFloat = 11
    static let egoMaxSide = 8          // 1グループに並べる上限
    static let egoStatHeight: CGFloat = 92

    static func ego(path: String, graph: Structure.Graph,
                    lastEdit: Int?, size: CGSize) -> EgoView {
        var view = EgoView()
        let top = margin + 34                       // 見出しのぶん
        let centerWidth = max(300, min(430, size.width * 0.34))
        let sideWidth = max(150, (size.width - centerWidth - margin * 2 - egoLinkGap * 2) / 2)
        let centerX = (size.width - centerWidth) / 2

        // 左＝呼ばれている元とノート（向こうから来るもの）、右＝呼んでいる先
        func column(_ groups: [(String, Set<String>, EgoView.Marker, Bool)],
                    x: CGFloat) -> [CGFloat] {
            var y = top
            var anchors: [CGFloat] = []
            for (title, paths, marker, strip) in groups {
                view.groups.append(EgoView.Group(title: "\(title) \(paths.count)",
                                                 point: CGPoint(x: x, y: y + 8)))
                y += 26
                let sorted = paths.sorted {
                    ($0 as NSString).lastPathComponent < ($1 as NSString).lastPathComponent
                }
                for p in sorted.prefix(egoMaxSide) {
                    var label = (p as NSString).lastPathComponent
                    if strip { label = (label as NSString).deletingPathExtension }
                    let rect = CGRect(x: x, y: y, width: sideWidth, height: egoRowHeight)
                    view.relations.append(EgoView.Row(
                        path: p,
                        label: truncateMiddle(label, toWidth: sideWidth - 30, size: badgeFont),
                        rect: rect, indent: 20, marker: marker, selected: false))
                    anchors.append(rect.midY)
                    y += egoRowHeight + 2
                }
                if paths.count > egoMaxSide {
                    view.relations.append(EgoView.Row(
                        path: "", label: "他 \(paths.count - egoMaxSide) 件",
                        rect: CGRect(x: x, y: y, width: sideWidth, height: egoRowHeight),
                        indent: 20, marker: .none, selected: false))
                    y += egoRowHeight + 2
                }
                y += 12
            }
            return anchors
        }

        let insCount = view.relations.count
        let insAnchors = column([("呼ばれている", graph.usedBy[path] ?? [], .calledBy, true),
                                 ("関連ノート", graph.notedBy[path] ?? [], .note, false)],
                                x: margin)
        let insRows = Array(view.relations[insCount...])
        let outsStart = view.relations.count
        let outAnchors = column([("呼んでいる", graph.dependsOn[path] ?? [], .calling, true)],
                                x: size.width - margin - sideWidth)
        let outRows = Array(view.relations[outsStart...])

        // MARK: 中央（そのファイル）
        let note = graph.notes[path]
        let hubWidth = min(centerWidth, 320)
        let hubX = (size.width - hubWidth) / 2
        let hub = CGRect(x: hubX, y: top + 18, width: hubWidth, height: 52)
        view.panels = [hub]
        view.breadcrumb = wrap(Cockpit.shortDirName((path as NSString).deletingLastPathComponent,
                                                    strippingPrefix: "") + "/",
                               toWidth: centerWidth, size: badgeFont, maxLines: 2)
        view.name = truncateMiddle((path as NSString).lastPathComponent, toWidth: hubWidth - 24, size: 17)
        view.namePoint = CGPoint(x: hub.midX, y: hub.midY)

        // 余白＝ハブの下。ここに解説と数値を入れる
        view.memoTop = hub.maxY + 34
        view.memo = wrap(note?.headline ?? "", toWidth: centerWidth, size: 14, maxLines: 10)

        let statWidth = (centerWidth - 16) / 3
        let statY = view.memoTop + CGFloat(view.memo.count) * 21 + 22
        let values = [
            (["定義され", "た型"], "\(note?.declared.count ?? 0)"),
            (["被参照"], "\(graph.usedBy[path]?.count ?? 0)"),
            (["直近の", "編集"], lastEdit.map { "+\($0)" } ?? "—"),
        ]
        for (i, v) in values.enumerated() {
            view.stats.append(EgoView.Stat(
                title: v.0, value: v.1,
                rect: CGRect(x: centerX + CGFloat(i) * (statWidth + 8), y: statY,
                             width: statWidth, height: egoStatHeight)))
        }

        // MARK: 矢印。向きは呼び出しの向きそのもの
        func fan(_ count: Int) -> [CGFloat] {
            guard count > 1 else { return [hub.midY] }
            return (0..<count).map { hub.minY + hub.height * CGFloat($0 + 1) / CGFloat(count + 1) }
        }
        let insHub = fan(insAnchors.count)
        for (i, row) in insRows.enumerated() where !row.path.isEmpty {
            view.links.append(EgoView.Link(from: CGPoint(x: row.rect.maxX + 6, y: row.rect.midY),
                                           to: CGPoint(x: hub.minX - 5, y: insHub[min(i, insHub.count - 1)]),
                                           marker: row.marker))
        }
        let outHub = fan(outAnchors.count)
        for (i, row) in outRows.enumerated() where !row.path.isEmpty {
            view.links.append(EgoView.Link(from: CGPoint(x: hub.maxX + 5, y: outHub[min(i, outHub.count - 1)]),
                                           to: CGPoint(x: row.rect.minX - 6, y: row.rect.midY),
                                           marker: row.marker))
        }
        return view
    }

    /// 解説は省略せず折り返す。ここだけは「何をするやつか」が本文なので削らない
    static func wrap(_ text: String, toWidth limit: CGFloat, size: CGFloat, maxLines: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines: [String] = []
        var current = ""
        for ch in text {
            if textWidth(current + String(ch), size: size) > limit, !current.isEmpty {
                lines.append(current)
                if lines.count == maxLines { return lines }
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: 文字幅と省略

    /// 等幅フォント前提の見積もり。**較正の摘みはこの2つだけ**——
    /// `NSFont.monospacedSystemFont`（SwiftUI の `.system(design: .monospaced)` の実体）を
    /// 実測した値で、10 / 11 / 12.5pt のどこでも同じ比率だった。
    ///
    /// 以前は「ASCII = 0.6em、全角 = その2文字分」で数えていた。どちらも外れていて、
    /// **ASCII は 3% 足りず長い名前がセルの枠を突き抜け、全角は 30% 多く日本語名が早く省略された**。
    /// フォントを変えたらここを測り直す（`(s as NSString).size(withAttributes:)` で出る）
    static let advanceNarrow: CGFloat = 0.6182
    static let advanceWide: CGFloat = 0.9234

    static func textWidth(_ s: String, size: CGFloat = font) -> CGFloat {
        var units: CGFloat = 0
        for u in s.unicodeScalars { units += u.value < 0x2E80 ? advanceNarrow : advanceWide }
        return units * size
    }

    /// ファイル名は中央を省略する。頭（識別）と末尾（拡張子）の両方が要るため
    static func truncateMiddle(_ s: String, toWidth limit: CGFloat, size: CGFloat = font) -> String {
        guard textWidth(s, size: size) > limit else { return s }
        let chars = Array(s)
        let ellipsis = textWidth("…", size: size)
        var head = 0, tail = 0
        var used = ellipsis
        // 頭を少し多めに残す
        while head + tail < chars.count {
            let takeHead = head <= tail
            let index = takeHead ? head : chars.count - 1 - tail
            let w = textWidth(String(chars[index]), size: size)
            if used + w > limit { break }
            used += w
            if takeHead { head += 1 } else { tail += 1 }
        }
        guard head + tail < chars.count else { return s }
        guard head > 0 || tail > 0 else { return "…" }
        return String(chars.prefix(head)) + "…" + String(chars.suffix(tail))
    }

    /// ディレクトリ名は末尾（深い方）が効くので頭を落とす
    static func truncateHead(_ s: String, toWidth limit: CGFloat, size: CGFloat = font) -> String {
        guard textWidth(s, size: size) > limit else { return s }
        let chars = Array(s)
        var tail = 0
        var used = textWidth("…", size: size)
        while tail < chars.count {
            let w = textWidth(String(chars[chars.count - 1 - tail]), size: size)
            if used + w > limit { break }
            used += w
            tail += 1
        }
        return tail == 0 ? "…" : "…" + String(chars.suffix(tail))
    }

    /// チップ右肩。モデル名と労働量（ツール呼び出し回数）と割合。
    /// 並び順が労働量なので、その数字が見えないと並びの理由が分からない
    static func chipTrailing(_ chip: AgentChip) -> String {
        var parts: [String] = []
        if !chip.model.isEmpty { parts.append(chip.model) }
        if chip.work > 0 { parts.append("\(chip.work)") }
        // 割合が 1% 以上の時だけ追加。全体が 0 の時に「0%」が並ぶのを避けるため。
        // このレイアウト構造は p0-selfcheck.swift の検査対象なので、ここに割合ロジックを置いた
        if chip.share >= 0.01 {
            let percentage = Int((chip.share * 100).rounded(.toNearestOrAwayFromZero))
            parts.append("\(percentage)%")
        }
        return parts.joined(separator: " ")
    }

    // MARK: 書き込み量

    static let tickSize: CGFloat = 3
    static let tickGap: CGFloat = 2
    static let tickColumn: CGFloat = 10      // ティック欄の幅（0本でも空けて名前の位置を揃える）
    /// カテゴリの刻印（実・検・ノ・設・資・中黒）を置く欄の幅。
    /// `textWidth` の見積もりでは全角1文字 = 2単位 × 9pt × 0.6 = 10.8pt。
    /// ティック欄との間を 3pt 取って 14。カテゴリは全ファイルに必ず付くので
    /// 空になることはないが、幅は固定にして名前の左端を揃える。
    /// **ここを変えたら `nameLimit` / `subLimit` / `naturalCellWidth` の3つが連動する**
    static let markColumn: CGFloat = 14
    static let maxTicks = 3
    /// 参照の点が縦に収まる上限。6個で 6*3 + 5*2 = 28 ≒ cellHeight(30)。
    /// しきい値の設定側も同じ数で頭打ちにしてあるので、通常ここには当たらない
    static let maxReadTicks = 6

    // MARK: 止まった指示の印

    /// 紙に載る行。28×40 に文字は入らないので**罫の本数だけ**を返す。
    /// 指示の本文は行の meta と門のパネルが持つ（同じ文を2箇所で読ませない）
    static func gatePaperLines(_ text: String) -> Int {
        let words = plainLine(text).count
        return min(4, max(2, words / 12))
    }

    /// 1行に押し込む用に Markdown の記号と改行を潰す。
    /// codex に渡すプロンプトは md なので、生のままだと `##` や `**` が
    /// チップの2行目と線を流れる指示に混ざって読めない
    static func plainLine(_ raw: String) -> String {
        var out = ""
        var atLineStart = true
        for ch in raw {
            if ch == "\n" || ch == "\r" || ch == "\t" {
                if !out.isEmpty, out.last != " " { out.append(" ") }
                atLineStart = true
                continue
            }
            // 行頭の見出し・箇条書き・引用の印だけ落とす（文中の記号は残す）
            if atLineStart, ch == "#" || ch == ">" || ch == "-" || ch == "*" || ch == " " { continue }
            atLineStart = false
            if ch == "`" || ch == "*" || ch == "_" { continue }
            out.append(ch)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 書き込み量の段階。**点 → 下線 → 虹** の順に足していく。
    /// 下線を単独で量に使うと「ファイル名が長いほど大きく見える」ので一度却下したが、
    /// 量そのものは固定寸法の点が持っているので、下線は重ねる印として使える
    enum WriteTier {
        case none
        case small      // 点1
        case medium     // 点2 ＋ 細下線
        case large      // 点3 ＋ 太下線
        case huge       // 点3 ＋ 二重下線 ＋ 虹

        var underline: (thickness: CGFloat, double: Bool)? {
            switch self {
            case .none, .small: nil
            case .medium:       (1, false)
            case .large:        (2.5, false)
            case .huge:         (1.2, true)
            }
        }
        var rainbow: Bool { self == .huge }
    }

    static func writeTier(_ lines: Int, huge: Bool) -> WriteTier {
        if huge, lines > 0 { return .huge }
        switch lines {
        case ..<1:     return .none
        case 1..<10:   return .small
        case 10..<100: return .medium
        default:       return .large
        }
    }

    /// 書き込み量を数えられる本数にする。
    /// 下線の長さで表すとファイル名の長さが量として紛れ込むので、固定寸法のティックにする
    static func writeTicks(_ lines: Int) -> Int {
        switch lines {
        case ..<1:   return 0
        case 1..<10: return 1      // T1 通常
        case 10..<100: return 2    // T2 大
        default:     return 3      // T3 特大
        }
    }

    /// 右端の参照回数。フラグのしきい値まで埋まり、埋まりきると橙が立つ。
    /// 数字にすると名前と幅を取り合ううえ、「あと何回でフラグか」が読めない。
    /// 正確な回数はセルをクリックした先で出す
    static func readTicks(_ reads: Int, threshold: Int) -> Int {
        min(reads, max(1, threshold), maxReadTicks)
    }

    // MARK: 組み立て

    /// 「特大」は絶対量ではなく表示中の上位2%。絶対値で決めると
    /// 大きく書いた日は画面じゅうが特大になって目印にならない
    // MARK: 層の振り分け

    /// 描く層。**1フレームの費用の半分は文字の組版**で、`GraphicsContext.resolve` は
    /// キャッシュではなく毎回 CoreText で組み直す（実機のスタックサンプルで確認）。
    /// 動かないものを低い頻度の層に落とすと、その組み直しがそのまま減る。
    ///
    /// - `still`: 動いていないセル・チップと、カード枠・進行表・凡例。**文字のほぼ全部がここ**
    /// - `live` : 動いているセル・チップ・ビーム・流れる紙だけ。実測で毎フレーム数個
    /// - `both` : 1枚で全部（エゴビューと ImageRenderer 用）
    enum Layer { case still, live, both }

    /// 書かれた瞬間に名前の上を流れる光の帯の長さ
    static let sweepDuration: TimeInterval = 0.6

    /// 止まっている層の刻み。この幅に丸めた時刻が変わった時だけ描き直す。
    /// 遅い方の描画頻度（3fps）と揃えて「止まっている時は今までと同じ」にする
    static let steadyStep: TimeInterval = 1.0 / 3.0

    static func steadyDate(_ now: Date) -> Date {
        Date(timeIntervalSince1970:
                (now.timeIntervalSince1970 / steadyStep).rounded(.down) * steadyStep)
    }

    /// このセルが時間で見た目を変えるか。動くものは `live` だけ、動かないものは `still` だけが描く。
    ///
    /// 掃引だけは「書かれてから `sweepDuration`」という時間の窓なので、判定に渡す時刻は
    /// **両方の層で同じ `steady`（遅い方の刻み）**にする。層ごとに違う時刻で判定すると、
    /// 窓の境目で同じセルが両方に入る／どちらにも入らない瞬間ができる
    static func moves(_ box: CellBox, steady: Date) -> Bool {
        if box.cell.state == .writing || box.cell.state == .reading { return true }
        if box.huge { return true }                 // 虹は止まらないので常に動く側
        if let wrote = box.cell.lastWriteAt {
            let age = steady.timeIntervalSince(wrote)
            if age >= 0, age < sweepDuration { return true }
        }
        return false
    }

    /// このチップが時間で見た目を変えるか。稼働中はランプが脈打ち、指示の紙が線を流れる。
    /// `busy` はスナップショット由来で、両方の層が同じスナップショットを見るのでずれない
    static func moves(_ box: ChipBox) -> Bool { box.chip.busy }

    /// この層がこの要素を描くか
    static func draws(_ layer: Layer, moving: Bool) -> Bool {
        switch layer {
        case .both:  true
        case .live:  moving
        case .still: !moving
        }
    }

    static func hugeThreshold(_ snapshot: CockpitSnapshot) -> Int {
        let volumes = snapshot.cards.flatMap(\.files)
            .map { $0.added + $0.removed }
            .filter { $0 >= 100 }              // 最低でも T3 の量は要る
            .sorted(by: >)
        guard !volumes.isEmpty else { return .max }
        let count = max(1, Int((Double(volumes.count) * 0.02).rounded(.up)))
        let threshold = volumes[min(count, volumes.count) - 1]

        // 上位2%を「値」で切るので、境目に同点が並ぶとその分だけ増える。少しなら構わないが、
        // 同じ量のファイルが揃うと境目の値が最大値と一致し、**画面じゅうが特大**になる。
        // 虹は常時アニメーションなので、描画も道連れで重くなる。
        // 塊が画面の1割を超えたら特大は無しにする——何もかもが特大では目印にならない
        let tied = volumes.prefix { $0 >= threshold }.count
        let allowed = max(count, Int((Double(volumes.count) * 0.1).rounded(.up)))
        return tied > allowed ? .max : threshold
    }

    static func compute(_ snapshot: CockpitSnapshot, width: CGFloat) -> CockpitLayout {
        var layout = CockpitLayout()
        let available = max(320, width) - margin * 2
        let huge = hugeThreshold(snapshot)

        var y = margin

        // 上段：エージェントの帯。**司令塔は箱、子は縦1本の点線レールに吊る行**。
        //
        // 以前は深さを横軸にして箱を列に並べていた。指示の紙（62×88）が通る道を
        // 列の間に作るためで、読む都合ではなかった。紙を 28×40 の印に縮めて
        // 「そこで止まっている」ことだけを指させたので道が要らなくなり、
        // 読む順が上から下の1方向に揃う形に組み直した
        let chipsTop = y + (snapshot.chips.isEmpty && snapshot.gates.isEmpty ? 0 : agentHeader)
        var placed = snapshot.chips.map { (chip: $0, hit: true) }
        if snapshot.hiddenChips > 0 {
            placed.append((AgentChip(id: "", role: "他 \(snapshot.hiddenChips) 体", model: "",
                                     depth: snapshot.chips.last?.depth ?? 0, parent: nil,
                                     work: 0, doing: "", done: true, busy: false,
                                     target: nil, kind: nil, lastAt: .distantPast,
                                     instruction: "", counts: [], spent: 0, share: 0), false))
        }

        let railX = margin + railOffset
        // 狭い時（会話欄を出したまま窓を最小にすると盤面は320前後）は字下げを詰め、行を盤面の内側に収める。
        // 以前は行幅に下限160を付けていたので、行が盤面の外へはみ出し、名前・モデル・バッジが重なっていた
        let rowIndent = available - rowOffset >= 360 ? rowOffset : railOffset + 20
        let rowLeft = margin + rowIndent
        let rowWidth = max(0, available - rowIndent)

        // 司令塔の箱。深さ0が複数居ることもある（セッションを跨いで見ている時）ので積む
        var top = chipsTop
        for (chip, hit) in placed where chip.depth == 0 {
            let rect = CGRect(x: margin, y: top, width: min(rootCardWidth, available), height: chipHeight)
            let trailing = chipTrailing(chip)
            let inner = rect.width - chipPad * 2
            layout.chips.append(ChipBox(
                chip: chip,
                role: truncateMiddle(chip.role, toWidth: inner - textWidth(trailing, size: badgeFont) - 30),
                trailing: trailing,
                doing: truncateMiddle(plainLine(chip.doing), toWidth: inner - 40, size: badgeFont),
                rect: rect, summary: !hit,
                dot: CGPoint(x: rect.maxX - chipPad, y: rect.minY + 15),
                isRoot: true, shortID: "C0",
                badge: chipBadge(chip)))
            if hit { layout.chipRects[chip.id] = rect }
            top = rect.maxY + chipGap
        }
        let railTop = top - chipGap + railTopGap

        // 子は行。番号は上から W1、W2 …（起動順に並んでいる）
        var rowY = max(railTop + railTopGap, chipsTop)
        var worker = 0
        for (chip, hit) in placed where chip.depth > 0 {
            worker += 1
            let rect = CGRect(x: rowLeft, y: rowY, width: rowWidth, height: rowHeight)
            let fit = fitRow(role: chip.role, trailing: chipTrailing(chip), meta: rowMeta(chip), rowWidth: rowWidth)
            layout.chips.append(ChipBox(
                chip: chip,
                role: fit.role,
                trailing: fit.trailing,
                doing: fit.doing,
                rect: rect, summary: !hit,
                dot: CGPoint(x: rect.maxX - rowBadgeColumn - 12, y: rect.midY),
                isRoot: false, shortID: hit ? "W\(worker)" : "",
                badge: chipBadge(chip)))
            if hit { layout.chipRects[chip.id] = rect }
            rowY = rect.maxY + rowGap
        }

        // 答え待ちの門。**行としても出す**——紙だけだと「何が止まったのか」が読めない。
        // 起こそうとしている相手はまだエージェントとして存在しないので、ここで行を建てる。
        // 紙と行のどちらを押しても門が開く（`gateRects` に両方を登録する）
        for gate in snapshot.gates {
            let rect = CGRect(x: rowLeft, y: rowY, width: rowWidth, height: rowHeight)
            let stopped = AgentChip(id: gate.id, role: gate.to, model: "", depth: 1, parent: gate.by,
                                    work: 0, doing: "門で停止中 — 右の欄で応答", done: false, busy: false,
                                    target: nil, kind: nil, lastAt: gate.issued,
                                    instruction: gate.instruction, counts: [], spent: 0, share: 0)
            let stoppedFit = fitRow(role: gate.to, trailing: "", meta: plainLine(gate.instruction), rowWidth: rowWidth)
            layout.chips.append(ChipBox(
                chip: stopped,
                role: stoppedFit.role,
                trailing: "",
                doing: stoppedFit.doing,
                rect: rect, summary: false,
                dot: CGPoint(x: rect.maxX - rowBadgeColumn - 12, y: rect.midY),
                isRoot: false, shortID: "G", badge: "待機", gate: true))

            // 紙はレールの右横、行の高さの真ん中に立てる
            let paper = CGRect(x: railX + gatePaperInset,
                               y: rect.midY - gatePaper.height / 2,
                               width: gatePaper.width, height: gatePaper.height)
            layout.gateRects[gate.id] = paper.union(rect)
            layout.gatePapers[gate.id] = paper
            rowY = rect.maxY + rowGap
        }

        layout.railX = railX
        layout.railTop = railTop
        layout.railBottom = rowY - rowGap

        // ファイル側に打つ「誰が触っているか」の札。**行の meta と対になる**——
        // 行が「Target.swift を編集中」と言い、セルが「W5 書込中」と返す。
        // ビームを外したので、この2つが揃わないと誰が何を触っているか辿れない
        var touching: [String: String] = [:]
        for box in layout.chips where !box.shortID.isEmpty && !box.gate {
            guard let target = box.chip.target, let kind = box.chip.kind else { continue }
            touching[target] = "\(box.shortID) \(kind == .write ? "書込中" : "読取中")"
        }

        // チップが1つも無ければ帯の高さを取らない（構造モードはここを通る）
        let bandBottom = max(top - chipGap, rowY - rowGap)
        y = placed.isEmpty && snapshot.gates.isEmpty ? chipsTop : bandBottom
        let chipsBottom = y
        layout.busY = snapshot.mode == .structure ? y : chipsBottom + busGap

        // 壁打ちモードは記憶DBだけを1列で出す。材料は落とした
        if snapshot.mode == .memory {
            var top = y + agentHeader
            for card in snapshot.cards {
                let box = placeCard(card, x: margin, y: top, width: available,
                                    huge: huge, snapshot: snapshot, layout: &layout)
                top = box.maxY + cardGap
            }
            layout.contentHeight = top + margin + legendHeight
            return layout
        }

        // 下段：ディレクトリのカードを**段組み**で積む。
        // 章見出し（04 ファイル N ／ 03 構造）と凡例の1行ぶんを空けてから並べる。
        // 凡例は画面の下端ではなく**この見出しの右**に出す（5a）——
        // 下端に置くと、縦に長い一覧では凡例を見るのにスクロールが要る
        let cardsTop = (snapshot.mode == .structure ? y : layout.busY + cardTopGap) + agentHeader

        // 列の数と幅を先に決める。**幅を揃えるのが要点。**
        // 以前はカード幅をファイル名の実寸から決め、行フローで折り返していた。
        // 折り返しのたびに `cardY += rowTallest` するので、その行のいちばん高いカードに
        // 行の全員が引きずられ、短いカードの下が丸ごと空く（盤面の縦半分が空白だった）。
        // 列ごとに y を持てばその穴が消える。
        // 列数は「幅が cardMaxWidth を超えない最小の数」——1440pt でちょうど4列（モックと同じ）
        let columnCount = max(1, Int(((available + cardGap) / (cardMaxWidth + cardGap)).rounded(.up)))
        let columnWidth = (available - cardGap * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        var columnY = [CGFloat](repeating: cardsTop, count: columnCount)

        for card in snapshot.cards {
            // いま最も低い列へ積む。同じ高さなら左から（並びが幅で飛ばない）
            let column = columnY.indices.min { (columnY[$0], $0) < (columnY[$1], $1) } ?? 0
            let cardX = margin + CGFloat(column) * (columnWidth + cardGap)
            let cardY = columnY[column]
            let cardWidth = columnWidth
            let inner = cardWidth - cardPad * 2
            let half = (inner - cellGapX) / 2

            // セルは全幅か半幅にしか置かない。名前は入る幅まで縮める（＝カードを突き抜けない）
            var rows: [[(FileCell, CGFloat)]] = []
            var row: [(FileCell, CGFloat)] = []
            var rowUsed: CGFloat = 0
            for file in card.files {
                // 記憶モードは1行要約と来歴が入るので、半幅に落とさず必ず全幅で使う
                let w = snapshot.mode == .memory ? inner
                      : (naturalCellWidth(file) <= half ? half : inner)
                if !row.isEmpty, rowUsed + cellGapX + w > inner + 0.5 {
                    rows.append(row)
                    row = []
                    rowUsed = 0
                }
                rowUsed += (row.isEmpty ? 0 : cellGapX) + w
                row.append((file, w))
            }
            if !row.isEmpty { rows.append(row) }

            let rowHeight = cellHeight(snapshot.mode)
            let cardHeight = cardTitle + CGFloat(rows.count) * rowHeight
                           + CGFloat(max(0, rows.count - 1)) * cellGapY + cardPad + cardBottomPad

            var boxes: [CellBox] = []
            var cellY = cardY + cardPad + cardTitle
            for row in rows {
                var cellX = cardX + cardPad
                for (file, w) in row {
                    let rect = CGRect(x: cellX, y: cellY, width: w, height: rowHeight)
                    // 札が出ている間は名前の欄がその幅だけ狭まる。狭めないと札が名前の上に乗る
                    let tag = touching[file.id] ?? ""
                    let tagWidth = tag.isEmpty ? 0 : textWidth(tag, size: badgeFont) + 8
                    let nameLimit = w - cellPad * 2 - markColumn - tickColumn * 2 - tagWidth
                    let subLimit = w - cellPad * 2 - markColumn - tickColumn
                    boxes.append(CellBox(cell: file,
                                         display: truncateMiddle(file.name, toWidth: nameLimit),
                                         note: truncateMiddle(file.note, toWidth: subLimit, size: badgeFont),
                                         trace: truncateMiddle(file.trace, toWidth: subLimit, size: 10),
                                         readTicks: readTicks(file.reads, threshold: snapshot.readThreshold),
                                         rect: rect,
                                         huge: file.added + file.removed >= huge,
                                         category: FileCategory.classify(path: file.id),
                                         tag: tag))
                    layout.cellRects[file.id] = rect
                    layout.cardRects[file.id] = CGRect(x: cardX, y: cardY,
                                                       width: cardWidth, height: cardHeight)
                    cellX += w + cellGapX
                }
                cellY += rowHeight + cellGapY
            }

            layout.cards.append(CardBox(title: truncateHead(card.dir, toWidth: inner),
                                        rect: CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight),
                                        cells: boxes))
            columnY[column] = cardY + cardHeight + cardGap
        }

        // いちばん深い列の底。最後に足した `cardGap` は下端の余白と二重になるので引く
        let bottom = (columnY.max() ?? cardsTop) - (snapshot.cards.isEmpty ? 0 : cardGap)
        layout.contentHeight = bottom + margin + legendHeight
        return layout
    }

    /// カード1枚を決まった場所・決まった幅で置く。壁打ちモードの1列で使う。
    /// 折り返しの流し込みとは置き方が違うだけで、中の組み立ては同じ
    private static func placeCard(_ card: DirCard, x: CGFloat, y: CGFloat, width: CGFloat,
                                  huge: Int, snapshot: CockpitSnapshot,
                                  layout: inout CockpitLayout) -> CGRect {
        let inner = width - cardPad * 2
        let rowHeight = cellHeight(snapshot.mode)
        let height = cardTitle + CGFloat(card.files.count) * rowHeight
                   + CGFloat(max(0, card.files.count - 1)) * cellGapY + cardPad + cardBottomPad
        let rect = CGRect(x: x, y: y, width: width, height: height)

        var boxes: [CellBox] = []
        var cellY = y + cardPad + cardTitle
        for file in card.files {
            // 字下げ。Obsidian のアウトラインと同じで、深さぶん右へ寄せて幅を詰める
            // 120pt は3行を判別できる下限。深さが壊れていてもカードの右へ出さない
            let shift = min(CGFloat(file.indent) * memoryIndent, max(0, inner - 120))
            let width = inner - shift
            let cell = CGRect(x: x + cardPad + shift, y: cellY, width: width, height: rowHeight)
            let nameLimit = width - cellPad * 2 - markColumn - tickColumn * 2
            let subLimit = width - cellPad * 2 - markColumn - tickColumn
            boxes.append(CellBox(cell: file,
                                 display: truncateMiddle(file.name, toWidth: nameLimit),
                                 note: truncateMiddle(file.note, toWidth: subLimit, size: badgeFont),
                                 trace: truncateMiddle(file.trace, toWidth: subLimit, size: 10),
                                 readTicks: readTicks(file.reads, threshold: snapshot.readThreshold),
                                 rect: cell,
                                 huge: file.added + file.removed >= huge,
                                 category: FileCategory.classify(path: file.id)))
            layout.cellRects[file.id] = cell
            layout.cardRects[file.id] = rect
            cellY += rowHeight + cellGapY
        }
        layout.cards.append(CardBox(title: truncateHead(card.dir, toWidth: inner),
                                    rect: rect, cells: boxes))
        return rect
    }

    /// レールから行へ伸びる横枝の y。行の高さの真ん中に入る
    static func branchY(_ row: CGRect) -> CGFloat { row.midY }

    /// 省略しなければ必要な幅。カード幅と全幅/半幅の判定にだけ使う。
    /// 左右のティック欄は固定寸法なので、参照回数が増えても幅は動かない
    private static func naturalCellWidth(_ cell: FileCell) -> CGFloat {
        cellPad * 2 + markColumn + tickColumn * 2 + textWidth(cell.name)
    }
}
