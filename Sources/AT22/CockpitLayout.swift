import Foundation
import CoreGraphics

/// 画面の座標をここで全部決める。描画から切り離してあるので、
/// SwiftUI 抜きでセルフチェックから同じ計算を叩ける。
struct CockpitLayout {

    struct ChipBox {
        let chip: AgentChip
        let role: String         // 幅に合わせて省略済み
        let trailing: String     // モデル名と労働量
        let doing: String        // 今していること / してきたことの内訳
        let rect: CGRect
        /// ビームの出口（チップ右側の状態ランプ）
        var dot: CGPoint
    }

    struct CellBox {
        let cell: FileCell
        let display: String      // 幅に合わせて省略済み
        let badge: String
        let rect: CGRect
        /// 表示中で最も書かれたごく一部。虹を掛ける対象
        let huge: Bool
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
    static let cellHeight: CGFloat = 30
    static let cellGapX: CGFloat = 10
    static let cellGapY: CGFloat = 6
    static let cellPad: CGFloat = 9
    static let cardPad: CGFloat = 10
    static let cardTitle: CGFloat = 24
    static let cardGap: CGFloat = 14
    static let cardBottomPad: CGFloat = 12
    static let cardMinWidth: CGFloat = 220
    static let cardMaxWidth: CGFloat = 400
    static let legendHeight: CGFloat = 54

    private(set) var chips: [ChipBox] = []
    private(set) var cards: [CardBox] = []
    private(set) var busY: CGFloat = 0
    private(set) var contentHeight: CGFloat = 0
    private var cellRects: [String: CGRect] = [:]
    private var cardRects: [String: CGRect] = [:]      // ファイルパス -> それが載っているカード
    private var chipRects: [String: CGRect] = [:]      // エージェントID -> チップ

    func rect(forFile path: String) -> CGRect? { cellRects[path] }
    /// 点の上にあるファイル。セルは重ならないので当たるのは高々1つ
    func file(at point: CGPoint) -> String? { cellRects.first { $0.value.contains(point) }?.key }
    func cardRect(forFile path: String) -> CGRect? { cardRects[path] }
    func chipRect(forAgent id: String) -> CGRect? { chipRects[id] }

    // MARK: 文字幅と省略

    /// 等幅フォント前提の見積もり。全角は2文字分として数える。
    /// ponytail: SF Mono の実測から 1文字 ≒ 0.6em。ずれたらこの係数だけ直す
    static func textWidth(_ s: String, size: CGFloat = font) -> CGFloat {
        var units: CGFloat = 0
        for u in s.unicodeScalars { units += u.value < 0x2E80 ? 1 : 2 }
        return units * size * 0.6
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

    /// チップ右肩。モデル名と労働量（ツール呼び出し回数）。
    /// 並び順が労働量なので、その数字が見えないと並びの理由が分からない
    static func chipTrailing(_ chip: AgentChip) -> String {
        var parts: [String] = []
        if !chip.model.isEmpty { parts.append(chip.model) }
        if chip.work > 0 { parts.append("\(chip.work)") }
        return parts.joined(separator: " ")
    }

    // MARK: 書き込み量

    static let tickSize: CGFloat = 3
    static let tickGap: CGFloat = 2
    static let tickColumn: CGFloat = 10      // ティック欄の幅（0本でも空けて名前の位置を揃える）
    static let maxTicks = 3

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

    /// セル右肩の数字。参照回数だけを出す。
    /// 書き込み量は数字ではなくティック・掃引・波・虹で表す（読み取りには対応する見た目が無い）。
    /// 行数の内訳はセルをクリックした先で出す
    static func badge(_ cell: FileCell) -> String {
        cell.reads > 0 ? "R\(cell.reads)" : ""
    }

    // MARK: 組み立て

    /// 「特大」は絶対量ではなく表示中の上位2%。絶対値で決めると
    /// 大きく書いた日は画面じゅうが特大になって目印にならない
    static func hugeThreshold(_ snapshot: CockpitSnapshot) -> Int {
        let volumes = snapshot.cards.flatMap(\.files)
            .map { $0.added + $0.removed }
            .filter { $0 >= 100 }              // 最低でも T3 の量は要る
            .sorted(by: >)
        guard !volumes.isEmpty else { return .max }
        let count = max(1, Int((Double(volumes.count) * 0.02).rounded(.up)))
        return volumes[min(count, volumes.count) - 1]
    }

    static func compute(_ snapshot: CockpitSnapshot, width: CGFloat) -> CockpitLayout {
        var layout = CockpitLayout()
        let available = max(320, width) - margin * 2
        let huge = hugeThreshold(snapshot)

        // 上段：エージェントのチップ。階層ごとに行を変えて、深いほど右へ下げる
        var y = margin
        var previousDepth: Int?
        var x = margin
        for chip in snapshot.chips {
            let indent = margin + CGFloat(chip.depth) * chipIndent
            if previousDepth != chip.depth {
                if previousDepth != nil { y += chipHeight + chipGap }
                x = indent
                previousDepth = chip.depth
            }

            let trailing = chipTrailing(chip)
            let trailingWidth = trailing.isEmpty ? 0 : textWidth(trailing, size: badgeFont) + 8
            let roleLimit = chipMaxWidth - chipPad * 2 - 18 - trailingWidth
            let role = truncateMiddle(chip.role, toWidth: roleLimit)
            let doingLimit = chipMaxWidth - chipPad * 2 - 18
            let doing = truncateMiddle(chip.doing, toWidth: doingLimit, size: badgeFont)

            let topLine = textWidth(role) + trailingWidth
            let w = min(chipMaxWidth,
                        chipPad * 2 + 18 + max(topLine, textWidth(doing, size: badgeFont)))

            if x > indent, x + w > margin + available {
                y += chipHeight + chipGap
                x = indent
            }
            let rect = CGRect(x: x, y: y, width: w, height: chipHeight)
            layout.chips.append(ChipBox(chip: chip, role: role, trailing: trailing, doing: doing,
                                        rect: rect,
                                        dot: CGPoint(x: rect.maxX - chipPad, y: rect.minY + 15)))
            layout.chipRects[chip.id] = rect
            x += w + chipGap
        }
        let chipsBottom = snapshot.chips.isEmpty ? margin : y + chipHeight
        layout.busY = chipsBottom + busGap

        // 下段：ディレクトリのカードを折り返しながら並べる
        var cardX = margin
        var cardY = layout.busY + cardTopGap
        var rowTallest: CGFloat = 0

        for card in snapshot.cards {
            let natural = card.files.map { naturalCellWidth($0) }.max() ?? cardMinWidth
            let cardWidth = min(max(natural + cardPad * 2, cardMinWidth), min(cardMaxWidth, available))
            let inner = cardWidth - cardPad * 2
            let half = (inner - cellGapX) / 2

            // セルは全幅か半幅にしか置かない。名前は入る幅まで縮める（＝カードを突き抜けない）
            var rows: [[(FileCell, CGFloat)]] = []
            var row: [(FileCell, CGFloat)] = []
            var rowUsed: CGFloat = 0
            for file in card.files {
                let w = naturalCellWidth(file) <= half ? half : inner
                if !row.isEmpty, rowUsed + cellGapX + w > inner + 0.5 {
                    rows.append(row)
                    row = []
                    rowUsed = 0
                }
                rowUsed += (row.isEmpty ? 0 : cellGapX) + w
                row.append((file, w))
            }
            if !row.isEmpty { rows.append(row) }

            let cardHeight = cardTitle + CGFloat(rows.count) * cellHeight
                           + CGFloat(max(0, rows.count - 1)) * cellGapY + cardPad + cardBottomPad

            if cardX > margin, cardX + cardWidth > margin + available {
                cardX = margin
                cardY += rowTallest + cardGap
                rowTallest = 0
            }

            var boxes: [CellBox] = []
            var cellY = cardY + cardPad + cardTitle
            for row in rows {
                var cellX = cardX + cardPad
                for (file, w) in row {
                    let rect = CGRect(x: cellX, y: cellY, width: w, height: cellHeight)
                    let badgeText = badge(file)
                    let badgeWidth = badgeText.isEmpty ? 0 : textWidth(badgeText, size: badgeFont) + 8
                    let nameLimit = w - cellPad * 2 - tickColumn - badgeWidth
                    boxes.append(CellBox(cell: file,
                                         display: truncateMiddle(file.name, toWidth: nameLimit),
                                         badge: badgeText,
                                         rect: rect,
                                         huge: file.added + file.removed >= huge))
                    layout.cellRects[file.id] = rect
                    layout.cardRects[file.id] = CGRect(x: cardX, y: cardY,
                                                       width: cardWidth, height: cardHeight)
                    cellX += w + cellGapX
                }
                cellY += cellHeight + cellGapY
            }

            layout.cards.append(CardBox(title: truncateHead(card.dir, toWidth: inner),
                                        rect: CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight),
                                        cells: boxes))
            cardX += cardWidth + cardGap
            rowTallest = max(rowTallest, cardHeight)
        }

        layout.contentHeight = cardY + rowTallest + margin + legendHeight
        return layout
    }

    /// チップとファイルを結ぶ折れ線。書き込みはエージェントからファイルへ、
    /// 読み取りはファイルからエージェントへ（データが流れてくる向き）
    static func beamPoints(from dot: CGPoint, to cell: CGRect,
                           corridor: CGFloat, kind: TouchKind) -> [CGPoint] {
        let points = [dot,
                      CGPoint(x: dot.x, y: corridor),
                      CGPoint(x: cell.midX, y: corridor),
                      CGPoint(x: cell.midX, y: cell.minY - 5)]
        return kind == .write ? points : points.reversed()
    }

    /// ビームが横に走る通り道の高さ。区切り線とカード上端の間に必ず収める。
    /// 4本までは 5px 間隔、それより増えたら詰める（はみ出すとカードの背景に隠れて線ごと消える）
    static func beamCorridor(busY: CGFloat, lane: Int, lanes: Int) -> CGFloat {
        let band = cardTopGap - 6                       // 区切り線とカード上端それぞれの余白ぶん
        let step = min(5, band / CGFloat(max(1, lanes)))
        return busY + 6 + CGFloat(lane) * step
    }

    /// 親エージェントから子エージェントへの折れ線。指示が流れる向き
    static func orderPoints(from parent: CGRect, to child: CGRect) -> [CGPoint] {
        let x = parent.minX + 10
        return [CGPoint(x: x, y: parent.maxY),
                CGPoint(x: x, y: child.midY),
                CGPoint(x: child.minX, y: child.midY)]
    }

    /// 折れ線の上を 0…1 で進んだ位置。ビームを走る点に使う
    static func pointOnPolyline(_ points: [CGPoint], _ t: Double) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        var segments: [CGFloat] = []
        var total: CGFloat = 0
        for i in 1..<points.count {
            let d = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            segments.append(d)
            total += d
        }
        guard total > 0 else { return points[0] }

        var remaining = CGFloat(min(max(t, 0), 1)) * total
        for (i, length) in segments.enumerated() {
            if remaining <= length {
                let f = length == 0 ? 0 : remaining / length
                return CGPoint(x: points[i].x + (points[i + 1].x - points[i].x) * f,
                               y: points[i].y + (points[i + 1].y - points[i].y) * f)
            }
            remaining -= length
        }
        return points[points.count - 1]
    }

    /// 省略しなければ必要な幅。カード幅と全幅/半幅の判定にだけ使う
    private static func naturalCellWidth(_ cell: FileCell) -> CGFloat {
        let badgeText = badge(cell)
        let badgeWidth = badgeText.isEmpty ? 0 : textWidth(badgeText, size: badgeFont) + 8
        return cellPad * 2 + tickColumn + textWidth(cell.name) + badgeWidth
    }
}
