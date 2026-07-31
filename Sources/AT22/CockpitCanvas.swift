import SwiftUI

// MARK: - 画面

struct CockpitView: View {
    let cockpit: Cockpit

    var body: some View {
        VStack(spacing: 0) {
            sessionTabs
            Divider()
            canvas
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("クリア") { cockpit.clear() }
                    .help("実装の区切りで、溜まった終了済みエージェントとファイルの集計を落とす")
            }
        }
        .task {
            while !Task.isCancelled {
                cockpit.housekeeping()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// セッションごとにタブ。同じ画面に複数セッションが混ざると
    /// 司令塔チップが見分けられなくなるので、既定でここを切り替えて使う
    private var sessionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                tab(title: "すべて", session: nil, busy: false)
                ForEach(cockpit.liveSessions) { s in
                    tab(title: s.name, session: s.id, busy: s.busy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
        .background(CockpitCanvas.background)
    }

    private func tab(title: String, session: String?, busy: Bool) -> some View {
        let selected = cockpit.selectedSession == session
        return Button {
            cockpit.selectedSession = session
        } label: {
            HStack(spacing: 5) {
                if session != nil {
                    Circle()
                        .fill(busy ? CockpitCanvas.live : CockpitCanvas.rule)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(selected ? CockpitCanvas.label : CockpitCanvas.dim)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? CockpitCanvas.agentOn : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var canvas: some View {
        GeometryReader { geo in
            ScrollView {
                // 動いている時だけ 30fps。止まったら 3fps に落とす。
                // ponytail: 常時30fps以上だと、何も起きていない間も全ファイル名を
                // 毎フレーム組み直して常時20%以上CPUを食う
                TimelineView(.periodic(from: .now, by: cockpit.isBusy ? 1.0 / 30.0 : 1.0 / 3.0)) { timeline in
                    let snapshot = cockpit.snapshot(now: timeline.date)
                    let layout = CockpitLayout.compute(snapshot, width: geo.size.width)
                    Canvas { context, size in
                        CockpitCanvas.draw(&context, size: size, layout: layout,
                                           snapshot: snapshot, now: timeline.date)
                    }
                    .frame(width: geo.size.width,
                           height: max(geo.size.height, layout.contentHeight))
                }
            }
            .background(CockpitCanvas.background)
        }
    }
}

// MARK: - 描画

/// 上段＝エージェントのチップ、下段＝ディレクトリごとのファイルカード。
/// チップから今触っているファイルへビームが伸びる（実線＝書き込み / 破線＝読み取り）。
/// 色と寸法は at22_canvas_recommended_detail.html に合わせてある。
enum CockpitCanvas {

    static let background = Color(nsColor: .controlBackgroundColor)
    static let label = Color(nsColor: .labelColor)
    static let dim = Color(nsColor: .secondaryLabelColor)
    static let rule = Color(red: 0.706, green: 0.698, blue: 0.663)      // #B4B2A9
    static let live = Color(red: 0.114, green: 0.620, blue: 0.459)      // #1D9E75
    static let liveDeep = Color(red: 0.059, green: 0.431, blue: 0.337)  // #0F6E56
    static let flag = Color(red: 0.937, green: 0.624, blue: 0.153)      // #EF9F27
    static let flagBeam = Color(red: 0.729, green: 0.459, blue: 0.090)  // #BA7517
    static let flagDeep = Color(red: 0.521, green: 0.310, blue: 0.043)  // #854F0B
    static let agentOn = Color(red: 0.482, green: 0.471, blue: 0.816)   // チップの稼働枠

    /// 書かれた瞬間の光の帯。明るい箱では暗い帯、暗い箱では明るい帯になるよう、
    /// 明度を反転させる `labelColor` に乗せる（白固定だと明るい背景で消える）
    static let sweepInk = Color(nsColor: .labelColor)
    static let sweepDuration: TimeInterval = 0.6

    /// 特大の書き込みに掛ける虹。琥珀と朱はフラグ色と衝突するので抜いた5色
    static let rainbow: [(r: Double, g: Double, b: Double)] = [
        (0.325, 0.290, 0.718),   // #534AB7
        (0.094, 0.373, 0.647),   // #185FA5
        (0.059, 0.431, 0.337),   // #0F6E56
        (0.231, 0.427, 0.067),   // #3B6D11
        (0.600, 0.208, 0.337),   // #993556
    ]
    static let rainbowPeriod: TimeInterval = 2.6
    static let rainbowStagger: TimeInterval = 0.2
    static let wavePeriod: TimeInterval = 1.6
    static let waveStagger: TimeInterval = 0.07

    /// 文字ごとの見せ方。量と状態を明度チャンネルを使わずに分ける
    enum NameStyle {
        case plain
        case wave        // 書き込み中：不透明度が文字の上を走る
        case rainbow     // 特大：色が文字の上を循環する
    }

    /// 文字を1つずつ描く。等幅なので送り幅は文字幅の計算そのまま
    private static func drawName(_ ctx: inout GraphicsContext, _ text: String,
                                 at origin: CGPoint, base: Color,
                                 style: NameStyle, now: Date) {
        guard style != .plain else {
            ctx.draw(ctx.resolve(Text(text)
                .font(.system(size: CockpitLayout.font, design: .monospaced))
                .foregroundStyle(base)), at: origin, anchor: .leading)
            return
        }

        var x = origin.x
        for (i, character) in text.enumerated() {
            let piece = String(character)
            let advance = CockpitLayout.textWidth(piece)
            let color: Color
            switch style {
            case .plain:
                color = base
            case .wave:
                // 0…25% で明るくなり、55% で戻る。以降は暗いまま待つ
                let phase = cycle(now, period: wavePeriod, delay: Double(i) * waveStagger)
                let opacity: Double
                if phase < 0.25 { opacity = 0.45 + 0.55 * (phase / 0.25) }
                else if phase < 0.55 { opacity = 1.0 - 0.55 * ((phase - 0.25) / 0.30) }
                else { opacity = 0.45 }
                color = base.opacity(opacity)
            case .rainbow:
                let phase = cycle(now, period: rainbowPeriod, delay: -Double(i) * rainbowStagger)
                color = rainbowColor(phase)
            }
            ctx.draw(ctx.resolve(Text(piece)
                .font(.system(size: CockpitLayout.font, weight: style == .rainbow ? .medium : .regular,
                              design: .monospaced))
                .foregroundStyle(color)),
                     at: CGPoint(x: x, y: origin.y), anchor: .leading)
            x += advance
        }
    }

    private static func cycle(_ now: Date, period: TimeInterval, delay: TimeInterval) -> Double {
        let t = (now.timeIntervalSince1970 + delay).truncatingRemainder(dividingBy: period)
        return (t < 0 ? t + period : t) / period
    }

    private static func rainbowColor(_ phase: Double) -> Color {
        let scaled = phase * Double(rainbow.count)
        let index = Int(scaled) % rainbow.count
        let next = (index + 1) % rainbow.count
        let f = scaled - Double(Int(scaled))
        let a = rainbow[index], b = rainbow[next]
        return Color(red: a.r + (b.r - a.r) * f,
                     green: a.g + (b.g - a.g) * f,
                     blue: a.b + (b.b - a.b) * f)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, layout: CockpitLayout,
                     snapshot: CockpitSnapshot, now: Date) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

        guard !snapshot.chips.isEmpty || !snapshot.cards.isEmpty else {
            drawEmpty(&ctx, size: size)
            return
        }

        // チップ帯の下の区切り線
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: CockpitLayout.margin, y: layout.busY))
            p.addLine(to: CGPoint(x: size.width - CockpitLayout.margin, y: layout.busY))
        }, with: .color(rule), lineWidth: 0.8)

        let states = Dictionary(snapshot.cards.flatMap(\.files).map { ($0.id, $0.state) },
                                uniquingKeysWith: { a, _ in a })

        // ビームはカードの下に敷く。間のカードに隠れて跨いで見えるので、
        // 行き先が下の方でも上のカードと重なって読めなくならない
        drawBeams(&ctx, layout: layout, states: states, now: now)
        for card in layout.cards { drawCard(&ctx, card: card, now: now) }
        // 行き先のカードに入ってからの最後のひと伸びだけは前に出す
        drawBeamEntries(&ctx, layout: layout, states: states)

        drawAgentTree(&ctx, layout: layout, now: now)
        for chip in layout.chips { drawChip(&ctx, box: chip, now: now) }
        drawLegend(&ctx, size: size, layout: layout, flagCount: snapshot.flagCount)
    }

    // MARK: エージェントのチップ

    /// 親エージェントから子エージェントへの指示。子が動いている間は破線が流れ、
    /// 終われば静かな線に戻る。オーケストレーターの指揮系統がそのまま出る
    private static func drawAgentTree(_ ctx: inout GraphicsContext, layout: CockpitLayout, now: Date) {
        for box in layout.chips {
            guard let parent = box.chip.parent,
                  let from = layout.chipRect(forAgent: parent),
                  from.maxY <= box.rect.minY else { continue }

            let points = CockpitLayout.orderPoints(from: from, to: box.rect)
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }

            guard box.chip.busy else {
                ctx.stroke(path, with: .color(rule), lineWidth: 0.9)
                continue
            }
            ctx.stroke(path, with: .color(agentOn),
                       style: StrokeStyle(lineWidth: 1.4, lineJoin: .round, dash: [5, 4],
                                          dashPhase: -now.timeIntervalSince1970 * 14))
            let period = 2.2
            let t = now.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
            let dot = CockpitLayout.pointOnPolyline(points, t)
            let r = 3.0
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)),
                     with: .color(agentOn))
        }
    }

    private static func drawChip(_ ctx: inout GraphicsContext, box: CockpitLayout.ChipBox, now: Date) {
        let shape = Path(roundedRect: box.rect, cornerRadius: 4)
        let on = box.chip.busy
        let done = box.chip.done
        // 終了したエージェントは消さずにグレーで残す。何体が何をやったかが振り返れる
        let fade = done ? 0.45 : 1.0

        ctx.fill(shape, with: .color(background))
        ctx.fill(shape, with: .color(on ? agentOn.opacity(0.10) : rule.opacity(done ? 0.08 : 0.14)))
        ctx.stroke(shape, with: .color(on ? agentOn : rule.opacity(fade)), lineWidth: on ? 1.4 : 0.9)

        let topY = box.rect.minY + 15
        let text = Text(box.role)
            .font(.system(size: CockpitLayout.font, design: .monospaced))
            .foregroundStyle((on ? label : dim).opacity(fade))
        ctx.draw(ctx.resolve(text),
                 at: CGPoint(x: box.rect.minX + CockpitLayout.chipPad, y: topY),
                 anchor: .leading)

        if !box.trailing.isEmpty {
            let trailing = Text(box.trailing)
                .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
                .foregroundStyle(dim.opacity(fade))
            ctx.draw(ctx.resolve(trailing),
                     at: CGPoint(x: box.dot.x - 10, y: topY),
                     anchor: .trailing)
        }

        // 2行目。線が引けない作業（検索・ビルド）はここでしか見えない
        if !box.doing.isEmpty {
            let doing = Text(box.doing)
                .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
                .foregroundStyle((on ? live : dim).opacity(fade))
            ctx.draw(ctx.resolve(doing),
                     at: CGPoint(x: box.rect.minX + CockpitLayout.chipPad, y: box.rect.maxY - 13),
                     anchor: .leading)
        }

        // 状態ランプ。稼働中は脈を打つ
        let alpha = on ? 0.55 + 0.45 * (0.5 + 0.5 * sin(now.timeIntervalSince1970 * 4)) : 1
        let r = 4.0
        ctx.fill(Path(ellipseIn: CGRect(x: box.dot.x - r, y: box.dot.y - r, width: r * 2, height: r * 2)),
                 with: .color(on ? live.opacity(alpha) : rule.opacity(fade)))
    }

    // MARK: ファイルのカード

    private static func drawCard(_ ctx: inout GraphicsContext, card: CockpitLayout.CardBox, now: Date) {
        let shape = Path(roundedRect: card.rect, cornerRadius: 4)
        // 背景で塗ってからでないと、下に敷いたビームがカードの中を素通りして見える
        ctx.fill(shape, with: .color(background))
        ctx.stroke(shape, with: .color(rule), lineWidth: 0.8)

        let title = Text(card.title)
            .font(.system(size: CockpitLayout.font, design: .monospaced))
            .foregroundStyle(dim)
        ctx.draw(ctx.resolve(title),
                 at: CGPoint(x: card.rect.minX + CockpitLayout.cardPad,
                             y: card.rect.minY + CockpitLayout.cardPad + 6),
                 anchor: .leading)

        for box in card.cells { drawCell(&ctx, box: box, now: now) }
    }

    private static func drawCell(_ ctx: inout GraphicsContext, box: CockpitLayout.CellBox, now: Date) {
        let shape = Path(roundedRect: box.rect, cornerRadius: 3)
        // 進行中は脈打たせる。止まっているものは静止させて、放置した画面が完全に静止するようにする
        let pulse = 0.6 + 0.4 * (0.5 + 0.5 * sin(now.timeIntervalSince1970 * 5))

        switch box.cell.state {
        case .writing:
            ctx.fill(shape, with: .color(live.opacity(0.16 + 0.14 * pulse)))
            ctx.stroke(shape, with: .color(live.opacity(pulse)), lineWidth: 1.3)
        case .reading:
            ctx.fill(shape, with: .color(rule.opacity(0.14)))
            // 読み取り中はセルの外側にリングを出す（HTML の state.ts と同じ表現）
            let ring = box.rect.insetBy(dx: -4, dy: -4)
            ctx.stroke(Path(roundedRect: ring, cornerRadius: 5),
                       with: .color(liveDeep.opacity(pulse)), lineWidth: 1.5)
        case .flagged:
            ctx.fill(shape, with: .color(flag.opacity(0.30)))
            ctx.stroke(shape, with: .color(flagBeam.opacity(0.8)), lineWidth: 1.1)
        case .idle:
            ctx.fill(shape, with: .color(rule.opacity(0.20)))
        }

        let ink: Color = box.cell.state == .idle ? dim : label

        // 左端の縦ティックで書き込み量。固定寸法なのでファイル名の長さに左右されない
        let ticks = CockpitLayout.writeTicks(box.cell.added + box.cell.removed)
        if ticks > 0 {
            let size = CockpitLayout.tickSize, gap = CockpitLayout.tickGap
            let total = CGFloat(ticks) * size + CGFloat(ticks - 1) * gap
            var tickY = box.rect.midY - total / 2
            let tickX = box.rect.minX + CockpitLayout.cellPad
            for _ in 0..<ticks {
                ctx.fill(Path(roundedRect: CGRect(x: tickX, y: tickY, width: size, height: size),
                              cornerRadius: 1),
                         with: .color(box.cell.state == .flagged ? flagDeep : ink))
                tickY += size + gap
            }
        }

        let nameX = box.rect.minX + CockpitLayout.cellPad + CockpitLayout.tickColumn
        let namePoint = CGPoint(x: nameX, y: box.rect.midY)
        // 掃引のマスクと幅の計測に、飾り無しの実体を1つ用意しておく
        let resolved = ctx.resolve(Text(box.display)
            .font(.system(size: CockpitLayout.font, design: .monospaced))
            .foregroundStyle(ink))

        // 特大は虹、書き込み中は波。どちらでもなければ普通に1回で描く
        let style: NameStyle = box.huge ? .rainbow : (box.cell.state == .writing ? .wave : .plain)
        drawName(&ctx, box.display, at: namePoint, base: ink, style: style, now: now)

        // 書かれた瞬間だけ、名前の上を光の帯が1回流れる（発火通知）。
        // 所要時間は固定なので、名前が長くても短くても同じ速さで通る
        if let wrote = box.cell.lastWriteAt {
            let age = now.timeIntervalSince(wrote)
            if age >= 0, age < Self.sweepDuration {
                let extent = resolved.measure(in: CGSize(width: 500, height: 40))
                let progress = age / Self.sweepDuration
                ctx.drawLayer { layer in
                    layer.clipToLayer { mask in
                        mask.draw(resolved, at: namePoint, anchor: .leading)
                    }
                    // 右から左へ抜ける
                    let span = extent.width + 90
                    let x = nameX + extent.width + 45 - span * progress
                    let band = CGRect(x: x - 22, y: box.rect.minY, width: 44, height: box.rect.height)
                    layer.fill(Path(band), with: .linearGradient(
                        Gradient(colors: [.clear, sweepInk, .clear]),
                        startPoint: CGPoint(x: band.minX, y: 0),
                        endPoint: CGPoint(x: band.maxX, y: 0)))
                }
            }
        }

        guard !box.badge.isEmpty else { return }
        let badge = Text(box.badge)
            .font(.system(size: CockpitLayout.badgeFont, design: .monospaced))
            .foregroundStyle(box.cell.state == .flagged ? flagDeep : dim)
        ctx.draw(ctx.resolve(badge),
                 at: CGPoint(x: box.rect.maxX - CockpitLayout.cellPad, y: box.rect.midY),
                 anchor: .trailing)
    }

    // MARK: ビーム

    /// チップ → いま触っているファイル。直角に曲げて、エージェントごとに通り道の高さをずらす。
    /// 色は行き先の状態に合わせる（フラグ付きへ伸びる線は琥珀）
    private static func drawBeams(_ ctx: inout GraphicsContext, layout: CockpitLayout,
                                  states: [String: FileState], now: Date) {
        for (i, box) in layout.chips.enumerated() {
            guard let target = box.chip.target,
                  let cell = layout.rect(forFile: target),
                  let kind = box.chip.kind else { continue }

            let corridor = layout.busY + 6 + CGFloat(i) * 5
            let points = CockpitLayout.beamPoints(from: box.dot, to: cell,
                                                  corridor: corridor, kind: kind)
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }

            let flagged = states[target] == .flagged
            // 読み書きはどちらも実線。違いは向きで表す（読み取りはファイルから流れてくる）
            ctx.stroke(path, with: .color(flagged ? flagBeam : live),
                       style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

            // 走る点が向きを見せる。カードの下を通るので跨いでいる間は自然に隠れる
            let period = 2.2
            let t = now.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
            let dot = CockpitLayout.pointOnPolyline(points, t)
            let r = 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)),
                     with: .color(flagged ? flagDeep : liveDeep))
        }
    }

    /// 行き先のカードの上端から目的のセルまで。ここだけカードより前に描かないと、
    /// カードの背景で最後のひと伸びごと消えてしまう
    private static func drawBeamEntries(_ ctx: inout GraphicsContext, layout: CockpitLayout,
                                        states: [String: FileState]) {
        for box in layout.chips {
            guard let target = box.chip.target,
                  let cell = layout.rect(forFile: target),
                  let card = layout.cardRect(forFile: target) else { continue }
            var path = Path()
            path.move(to: CGPoint(x: cell.midX, y: card.minY))
            path.addLine(to: CGPoint(x: cell.midX, y: cell.minY - 5))
            ctx.stroke(path, with: .color(states[target] == .flagged ? flagBeam : live), lineWidth: 1.6)
        }
    }

    // MARK: 凡例

    private static func drawLegend(_ ctx: inout GraphicsContext, size: CGSize,
                                   layout: CockpitLayout, flagCount: Int) {
        let y = layout.contentHeight - CockpitLayout.legendHeight / 2
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: CockpitLayout.margin, y: y - 18))
            p.addLine(to: CGPoint(x: size.width - CockpitLayout.margin, y: y - 18))
        }, with: .color(rule), lineWidth: 0.8)

        var x = CockpitLayout.margin
        func item(_ text: String, swatch: (inout GraphicsContext, CGRect) -> Void) {
            let box = CGRect(x: x, y: y - 7, width: 20, height: 14)
            swatch(&ctx, box)
            x += 27
            ctx.draw(ctx.resolve(Text(text)
                .font(.system(size: CockpitLayout.font, design: .monospaced))
                .foregroundStyle(dim)), at: CGPoint(x: x, y: y), anchor: .leading)
            x += CockpitLayout.textWidth(text) + 24
        }

        item("書き込み（実線 →ファイル）") { c, r in
            c.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(live))
        }
        item("読み取り（実線 ファイル→）") { c, r in
            c.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(live), lineWidth: 1.5)
        }
        item("指示（破線 エージェント間）") { c, r in
            c.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(agentOn),
                     style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        item("フラグ付き \(flagCount)") { c, r in
            c.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(flag))
        }
        item("アイドル") { c, r in
            c.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(rule.opacity(0.55)))
        }
    }

    private static func drawEmpty(_ ctx: inout GraphicsContext, size: CGSize) {
        let text = Text("動きを待っています\nClaude Code がファイルを読み書きするとここに出ます")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(dim)
        ctx.draw(ctx.resolve(text), at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }
}
