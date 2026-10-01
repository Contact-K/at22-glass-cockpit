import SwiftUI

// MARK: - 遷移（DotWipe ＋ 大見出し）

/// 画面の切り替え1回ぶん。`cover → hold → reveal → idle` は**始めた時刻からの経過だけで決まる**ので、
/// 状態を持つのはこの値1つ（`components/DotWipe.js` と v10 の `go()`）
struct Wipe: Equatable {
    let from: CockpitMode
    let to: CockpitMode
    let origin: CGPoint
    let started: Date

    // v10: C = 380, H = 1100, R = 380（ms）
    static let cover = 0.38
    static let hold = 1.1
    static let reveal = 0.38
    /// ここで画面を差し替える
    static var swapAt: Double { cover }
    /// ここで大見出しが引っ込み始める（`C + H - 240`）
    static var outAt: Double { cover + hold - 0.24 }
    static var total: Double { cover + hold + reveal }
}

/// ドットが波紋の順に育って画面を覆い、離れた順に縮んで次を見せる。
/// 波紋の先頭からピンク → 白 → 青の三色。24fps のコマ送り
struct DotWipeLayer: View {
    let wipe: Wipe?

    var body: some View {
        Ticker(fps: 24, paused: wipe == nil) { now in
            if let wipe {
                let e = now.timeIntervalSince(wipe.started)
                ZStack {
                    Canvas { ctx, size in Self.draw(&ctx, size: size, wipe: wipe, elapsed: e) }
                    WipeTitle(wipe: wipe, elapsed: e)
                }
            }
        }
        .allowsHitTesting(wipe != nil)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, wipe: Wipe, elapsed e: Double) {
        let frame = 1.0 / 24
        let covering = e < Wipe.cover + Wipe.hold
        let p: Double
        if e < Wipe.cover { p = min(1, floor(e / frame) * frame / Wipe.cover) }
        else if covering { p = 1 }
        else { p = 1 - min(1, floor((e - Wipe.cover - Wipe.hold) / frame) * frame / Wipe.reveal) }
        guard p > 0 else { return }
        if p >= 1 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.blue))
            return
        }
        let pc: CGFloat = 18, ox = wipe.origin.x, oy = wipe.origin.y
        let cols = Int(ceil(size.width / pc)), rows = Int(ceil(size.height / pc))
        let maxD = max(hypot(ox, oy), hypot(size.width - ox, oy),
                       hypot(ox, size.height - oy), hypot(size.width - ox, size.height - oy))
        let p2 = p * 1.35
        for j in 0..<rows {
            for i in 0..<cols {
                let d = Double(hypot((CGFloat(i) + 0.5) * pc - ox, (CGFloat(j) + 0.5) * pc - oy) / maxD)
                let f = p2 - (covering ? d : 1 - d)
                let s = max(0, min(1, f / 0.35))
                guard s > 0 else { continue }
                let sz = ceil(CGFloat(s) * pc), inset = floor((pc - sz) / 2)
                let color = f < 0.1 ? Palette.pink : f < 0.2 ? Palette.white : Palette.blue
                ctx.fill(Path(CGRect(x: CGFloat(i) * pc + inset, y: CGFloat(j) * pc + inset, width: sz, height: sz)),
                         with: .color(color))
            }
        }
    }
}

/// 覆っている間に出る大見出し。`01 // ━━ FROM WORK` / 矢印＋`STRUCTURE` / 和文と説明。
/// 1文字ずつ下から迫り上がり（`wl-up`）、引っ込む時は下から消える（`wl-out`）
private struct WipeTitle: View {
    let wipe: Wipe
    let elapsed: Double

    private static let words: [CockpitMode: (no: String, en: String, jp: String, desc: String)] = [
        .work: ("01", "WORK", "作業", "会話と門"),
        .structure: ("02", "STRUCTURE", "構造", "ファイルの関係"),
        .memory: ("03", "SPARRING", "壁打ち", "引き継ぎと記憶"),
    ]

    var body: some View {
        let to = Self.words[wipe.to] ?? Self.words[.work]!
        let from = Self.words[wipe.from] ?? Self.words[.work]!
        let letters = Array(to.en)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(to.no + " //").foregroundStyle(Palette.pink).opacity(fade(0))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.white).frame(height: 4)
                        .scaleEffect(x: blade(), anchor: out ? .trailing : .leading)
                }
                .frame(width: 180, height: 4)
                Text("FROM " + from.en).foregroundStyle(Palette.Blue.fg3).opacity(fade(420))
            }
            .font(.mono(12))
            .tracking(12 * 0.16)

            HStack(alignment: .center, spacing: 22) {
                arrow
                HStack(spacing: 0) {
                    ForEach(letters.indices, id: \.self) { i in
                        Text(String(letters[i]))
                            .font(.display(132))
                            .tracking(-1.32)
                            .clipShape(rise(160 + Double(i) * 45))
                    }
                }
            }
            HStack(spacing: 12) {
                Text(to.jp).font(.bodyJP(22)).clipShape(rise(160 + Double(letters.count) * 45 + 60))
                Text(to.desc).font(.mono(11)).tracking(Palette.caps(11))
                    .foregroundStyle(Palette.Blue.fg2)
                    .opacity(fade(160 + Double(letters.count) * 45 + 160))
            }
            .padding(.leading, 66)
        }
        .foregroundStyle(Palette.white)
        .allowsHitTesting(false)
    }

    private var out: Bool { elapsed >= Wipe.outAt }

    /// 入りは `240 + delay` ms、引きは `delay / 4` ms。どちらも 150ms・3コマ
    private func progress(_ delayMs: Double, duration: Double = 0.15, steps: Int = 3) -> Double {
        out ? stepped(elapsed - Wipe.outAt, delay: delayMs / 4000, duration: duration, steps: steps)
            : stepped(elapsed, delay: (240 + delayMs) / 1000, duration: duration, steps: steps)
    }

    private func fade(_ delayMs: Double) -> Double {
        out ? 1 - progress(delayMs) : progress(delayMs)
    }

    private func blade() -> CGFloat {
        CGFloat(out ? 1 - progress(0, duration: 0.12, steps: 4) : progress(0, duration: 0.12, steps: 4))
    }

    /// 下から迫り上がる切り抜き。CSS の polygon が −20%…120% を動くのをそのまま写す
    private func rise(_ delayMs: Double) -> Band {
        let k = CGFloat(progress(delayMs))
        return out ? Band(top: -0.2, bottom: 1.2 - 1.4 * k) : Band(top: 1.2 - 1.4 * k, bottom: 1.2)
    }

    /// 96×96 の矢印。左から現れ（`wl-arrow`）、右へ抜ける（`wl-arrowout`）
    private var arrow: some View {
        let k = CGFloat(progress(120))
        return ZStack(alignment: .trailing) {
            Rectangle().fill(Palette.white).frame(width: 66, height: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            ArrowHead().fill(Palette.white).frame(width: 44, height: 52)
        }
        .frame(width: 96, height: 96)
        .clipShape(out ? Band(left: -0.2 + 1.4 * k, right: 1.2) : Band(left: -0.2, right: -0.2 + 1.4 * k))
    }
}

/// 割合で指定する切り抜きの帯（−20%…120% をはみ出して指せる）
struct Band: Shape {
    var top: CGFloat = -0.2
    var bottom: CGFloat = 1.2
    var left: CGFloat = -0.2
    var right: CGFloat = 1.2

    nonisolated func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX + left * r.width, y: r.minY + top * r.height,
                    width: max(0, (right - left) * r.width), height: max(0, (bottom - top) * r.height)))
    }
}

/// `polygon(0 0,14px 0,44px 26px,14px 52px,0 52px,30px 26px)`
private struct ArrowHead: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        let sx = r.width / 44, sy = r.height / 52
        for (i, pt) in [(0.0, 0.0), (14, 0), (44, 26), (14, 52), (0, 52), (30, 26)].enumerated() {
            let point = CGPoint(x: r.minX + pt.0 * sx, y: r.minY + pt.1 * sy)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 決定のドット

/// 押したボタンがドットに崩れ、5コマで行き先へ渡り、着地して育って面になる。
/// 飛んでいる間だけピンク、着地で左から青へ。24fps（v10 の `runDots`）
struct DotFlight: Identifiable {
    let id = UUID()
    let start: Date
    let duration: Double
    let ink: Color
    let cell: CGFloat
    fileprivate let dots: [Dot]

    fileprivate struct Dot {
        let sx: CGFloat, sy: CGFloat, tx: CGFloat, ty: CGFloat
        let d: Double, u: Double, jitter: Double
    }

    init(from a: CGRect, to b: CGRect, start: Date = Date(), duration: Double = 1.7, ink: Color = Palette.blue) {
        self.start = start
        self.duration = duration
        self.ink = ink
        let pt: CGFloat = 8
        let cols = max(4, Int(jsRound(Double(b.width / pt)))), rows = max(2, Int(jsRound(Double(b.height / pt))))
        let cw = b.width / CGFloat(cols), ch = b.height / CGFloat(rows)
        cell = max(cw, ch)
        var seed: Int64 = 7
        func rnd() -> Double { seed = seed * 16807 % 2_147_483_647; return Double(seed) / 2_147_483_647 }
        var out: [Dot] = []
        for j in 0..<rows {
            for i in 0..<cols {
                let u = (Double(i) + 0.5) / Double(cols), v = (Double(j) + 0.5) / Double(rows)
                out.append(Dot(sx: a.minX + CGFloat(u) * a.width, sy: a.minY + CGFloat(v) * a.height,
                               tx: b.minX + (CGFloat(i) + 0.5) * cw, ty: b.minY + (CGFloat(j) + 0.5) * ch,
                               d: hypot(u - 0.5, v - 0.5) * 1.4, u: u, jitter: rnd() * 60))
            }
        }
        dots = out
    }

    /// もう描くものが無いか
    func over(at now: Date) -> Bool { now.timeIntervalSince(start) * 1000 > duration * 1000 + 200 }

    func draw(_ ctx: inout GraphicsContext, now: Date) {
        let ms = now.timeIntervalSince(start) * 1000, frame = 1000.0 / 24
        let t = floor(ms / frame) * frame, dur = duration * 1000
        let k1 = dur * 0.19, k2 = dur * 0.45, fadeAt = dur * 0.83
        guard t <= dur + 200 else { return }
        var c = ctx
        c.opacity = t > fadeAt ? max(0, 1 - (t - fadeAt) / 260) : 1
        for o in dots {
            let lt = t - o.d * 160 - o.jitter
            guard lt >= 0 else { continue }
            var x = o.tx, y = o.ty, rr: Double, color = Palette.pink
            if lt < k1 {
                x = o.sx; y = o.sy; rr = 4 * min(1, lt / (k1 * 0.8))
            } else if lt < k2 {
                let k = CGFloat(ceil((lt - k1) / (k2 - k1) * 5) / 5)
                x = o.sx + (o.tx - o.sx) * k; y = o.sy + (o.ty - o.sy) * k; rr = 4
            } else {
                rr = 8 * (0.5 + 0.5 * min(1, (lt - k2) / 260))
                if lt > k2 + 60 + o.u * 220 { color = ink }
            }
            let sz = max(1, min(CGFloat(rr) * 2, cell + 1))
            c.fill(Path(CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz)), with: .color(color))
        }
    }
}

/// 決定のドットを描く最前面の層。飛んでいる間だけ時計が回る
struct DecideLayer: View {
    let flights: [DotFlight]

    var body: some View {
        Ticker(fps: 24, paused: flights.isEmpty) { now in
            Canvas { ctx, _ in
                for flight in flights { flight.draw(&ctx, now: now) }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - メニューの面（ドットの成長）

/// 白い斜線（18°）から離れる順にドットが育って青い面になる。閉じる時は遠い方から縮む。
/// 育ちきったら時計を止めて、ただの青い面として描く（v10 の `drawMenu`）
struct MenuDots: View {
    let opened: Date
    let closing: Date?
    /// 開ききったか。持ち主が時刻を見て立てる（ここで判定すると、時計を止める合図が body に届かない）
    let settled: Bool

    static let lineX: CGFloat = 286
    static let tan18 = CGFloat(tan(18 * Double.pi / 180))

    var body: some View {
        Ticker(fps: 30, paused: settled && closing == nil) { now in
            Canvas { ctx, size in
                if closing == nil, settled || Self.isSettled(since: opened, now: now) {
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.blue))
                } else {
                    draw(&ctx, size: size, now: now)
                }
            }
        }
    }

    /// 開ききるまでの秒数。最も遠い升（≈1500pt）が育ち終わる時刻
    static let settleTime = 0.12 + 1500 * 0.22 / 1000 + 0.12

    static func isSettled(since opened: Date, now: Date) -> Bool {
        now.timeIntervalSince(opened) > settleTime
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let g: CGFloat = 24, cos18 = CGFloat(cos(18 * Double.pi / 180))
        let t = (now.timeIntervalSince(closing ?? opened)) * 1000
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let cx = x + g / 2, cy = y + g / 2
                let d = Double(abs(cx - (Self.lineX + cy * Self.tan18)) * cos18)
                let p = closing != nil
                    ? 1 - max(0, min(1, (t - 80 - (1150 - d) * 0.14) / 90))
                    : max(0, min(1, (t - 120 - d * 0.22) / 120))
                let sz = CGFloat(jsRound(p * 4) / 4) * (g + 1)
                if sz > 0 {
                    ctx.fill(Path(CGRect(x: cx - sz / 2, y: cy - sz / 2, width: sz, height: sz)),
                             with: .color(Palette.blue))
                }
                x += g
            }
            y += g
        }
    }
}
