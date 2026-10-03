import SwiftUI

// MARK: - 遷移（DotWipe ＋ 大見出し）

/// 画面の切り替え1回ぶん。`cover → hold → reveal → idle` は**始めた時刻からの経過だけで決まる**ので、
/// 状態を持つのはこの値1つ（`components/DotWipe.js` と v10 の `go()`）
struct Wipe: Equatable {
    /// 元のタブの英名（`FROM TALK`）
    let from: String
    let to: V11Tab
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

    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, wipe: Wipe, elapsed e: Double) {
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
        let ox = wipe.origin.x, oy = wipe.origin.y
        let maxD = max(hypot(ox, oy), hypot(size.width - ox, oy),
                       hypot(ox, size.height - oy), hypot(size.width - ox, size.height - oy))
        dots(&ctx, size: size, p: p, covering: covering, pc: 18) { x, y in Double(hypot(x - ox, y - oy) / maxD) }
    }

    /// 波紋の順（`distance` が 0…1、小さいほど先）にドットが育って覆い、離れた順に縮む。先頭からピンク → 白 → 青
    /// - Parameter mid: 先頭から2色目。全面の DotWipe は白、管制塔の波紋と引き出しは淡い青（v11 の l3 `#A3A3FF`）
    nonisolated static func dots(_ ctx: inout GraphicsContext, size: CGSize, p: Double, covering: Bool, pc: CGFloat,
                                 mid: Color = Palette.white, distance: (CGFloat, CGFloat) -> Double) {
        let cols = Int(ceil(size.width / pc)), rows = Int(ceil(size.height / pc))
        let p2 = p * 1.35
        for j in 0..<rows {
            for i in 0..<cols {
                let d = distance((CGFloat(i) + 0.5) * pc, (CGFloat(j) + 0.5) * pc)
                let f = p2 - (covering ? d : 1 - d)
                let s = max(0, min(1, f / 0.35))
                guard s > 0 else { continue }
                let sz = ceil(CGFloat(s) * pc), inset = floor((pc - sz) / 2)
                let color = f < 0.1 ? Palette.pink : f < 0.2 ? mid : Palette.blue
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

    var body: some View {
        let to = wipe.to
        let letters = Array(to.en)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(to.no + " //").foregroundStyle(Palette.pink).opacity(fade(0))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.white).frame(height: 4)
                        .scaleEffect(x: blade(), anchor: out ? .trailing : .leading)
                }
                .frame(width: 180, height: 4)
                Text("FROM " + wipe.from).foregroundStyle(Palette.Blue.fg3).opacity(fade(420))
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

// MARK: - 墨流し

/// Stam の Stable Fluids（半ラグランジュの移流＋ヤコビ反復の射影）に渦の閉じ込めを足した、
/// 静かな水槽に落とした水彩の墨（`components/Suminagashi.js` の写し）。
///
/// 重い墨（青）は沈み、差し色（ピンク）は浮く。濃さを 紙 → 墨 → 濃い墨 の3段に写す。
/// 30Hz の固定刻みで進め、窓が隠れている間は呼ばれないので止まる。
///
/// ponytail: CPU の配列で 96 格子。重ければ Metal へ
///
/// 隔離は付けない（画面の body からしか触らないので、1つの隔離の中に留まる）。
/// 付けると deinit から升を解放できなくなる
final class InkTank {
    let n: Int          // 横の升
    let m: Int          // 縦の升
    private let s: Int, size: Int
    private var u, v, u0, v0, d1, d2, d0, p, div, curl, grain: UnsafeMutablePointer<Float>
    private var pixels: [UInt8]

    // v10 の値: res 96 / spread 0.08 / drop-every 7、ほかは部品の既定
    private let speed: Float = 0.35, dissolve: Float = 0.9993, spread: Float = 0.08
    private let sink: Float = 0.05, viscosity: Float = 0.997, strength: Float = 1
    private let curlStrength: Float = 0.18, brush: Float = 0.045, dropEvery: Double = 7

    /// v11 は青い面の上に紺の墨（`ink=#08085C accent=#FF3DCC bg=#1212EE`）
    private let ink: (Float, Float, Float)
    private let accent: (Float, Float, Float)
    private let paper: (Float, Float, Float)

    private var lastStep: Date?
    private var acc: Double = 0
    private var dropClock: Double = 0
    private var phase: Float = 0
    private var ax: Float = 0.5, ay: Float = 0.5
    private var hover: (Float, Float)?
    private var pending: [(due: Date, x: Float, y: Float, r: Float, accent: Bool, amount: Float)] = []
    private(set) var image: CGImage?

    /// v10 の格子は 96。**`swift run`（デバッグビルド）だけ 48 に落とす**——
    /// 実測（Linux・同じコード）で 96 格子の1コマが release 2.5ms に対し debug 56ms、
    /// 初回の温め（40 コマ）が debug だと 2 秒かかって最初の描画が止まる
    #if DEBUG
    static let defaultRes = 48
    static let warmup = 10
    #else
    static let defaultRes = 96
    static let warmup = 40
    #endif

    init(width: CGFloat = 540, height: CGFloat = 800, res: Int = InkTank.defaultRes,
         ink: UInt32 = 0x08085C, accent: UInt32 = 0xFF3DCC, paper: UInt32 = 0x1212EE) {
        func rgb(_ h: UInt32) -> (Float, Float, Float) {
            (Float((h >> 16) & 0xFF), Float((h >> 8) & 0xFF), Float(h & 0xFF))
        }
        self.ink = rgb(ink)
        self.accent = rgb(accent)
        self.paper = rgb(paper)
        let rows = max(8, Int(jsRound(Double(CGFloat(res) * height / width))))
        let count = (res + 2) * (rows + 2)
        n = res
        m = rows
        s = res + 2
        size = count
        func alloc() -> UnsafeMutablePointer<Float> { .allocate(capacity: count) }
        u = alloc(); v = alloc(); u0 = alloc(); v0 = alloc(); d1 = alloc(); d2 = alloc()
        d0 = alloc(); p = alloc(); div = alloc(); curl = alloc(); grain = alloc()
        pixels = [UInt8](repeating: 255, count: res * rows * 4)
        for buf in [u, v, u0, v0, d1, d2, d0, p, div, curl] { buf.initialize(repeating: 0, count: size) }
        for k in 0..<size { grain[k] = Float.random(in: -0.03...0.03) }

        // 種: 差し色は高く浮かべ、墨は低く沈める
        for _ in 0..<3 { drop(x: .random(in: 0.15...0.9), y: .random(in: 0.15...0.4), r: .random(in: 0.18...0.26), accent: true, amount: 0.7) }
        for _ in 0..<4 { drop(x: .random(in: 0.1...0.9), y: .random(in: 0.6...0.9), r: .random(in: 0.2...0.3), accent: false, amount: 0.9) }
        for _ in 0..<Self.warmup { step() }
        paint()
    }

    deinit {
        for buf in [u, v, u0, v0, d1, d2, d0, p, div, curl, grain] { buf.deallocate() }
    }

    @inline(__always) private func ix(_ i: Int, _ j: Int) -> Int { i + s * j }

    /// 進める。**呼ばれた分しか進まない**——隠れている間に溜めた時間は捨てる（追いつこうとしない）
    func frame(at now: Date) -> CGImage? {
        for item in pending where item.due <= now {
            drop(x: item.x, y: item.y, r: item.r, accent: item.accent, amount: item.amount)
        }
        pending.removeAll { $0.due <= now }
        let tick = 1.0 / 30
        let elapsed = lastStep.map { now.timeIntervalSince($0) } ?? tick
        lastStep = now
        acc = min(acc + max(0, elapsed), tick * 1.5)
        if acc >= tick {
            acc -= tick
            step()
            paint()
        }
        return image
    }

    /// 1行ぶんの墨を垂らす。10滴を 90ms おきに、少しずつ下へずらして落とす（v10 の `drip`）
    func drip(x: Float, y: Float, accent: Bool, amount: Float, after delay: Double, now: Date = Date()) {
        for i in 0..<10 {
            pending.append((now.addingTimeInterval(delay + Double(i) * 0.09),
                            x + .random(in: -0.005...0.005), y + Float(i) * 0.0025,
                            0.03 + Float(i) * 0.002, accent, amount * 0.09))
        }
    }

    /// ホバーでそっと掻き回す（墨は足さない）
    func hover(x: Float, y: Float) {
        if let last = hover { stir(x: x, y: y, px: last.0, py: last.1, accent: false, amount: 0) }
        hover = (x, y)
    }

    func endHover() { hover = nil }

    /// 1滴。柔らかいガウスの雲と、外へのかすかな押し
    func drop(x: Float, y: Float, r: Float, accent: Bool, amount: Float) {
        let gi = Int(jsRound(Double(x) * Double(n))), gj = Int(jsRound(Double(y) * Double(m)))
        let rr = max(2, Int(jsRound(Double(r) * Double(min(n, m)))))
        let e = Int(ceil(Double(rr) * 1.4))
        for a in -e...e {
            for b in -e...e {
                let i = gi + a, j = gj + b
                guard i >= 1, i <= n, j >= 1, j <= m else { continue }
                let dist = Float(hypot(Double(a), Double(b))), q = dist / Float(rr)
                let k = ix(i, j)
                if q < 1.4 {
                    let w = amount * exp(-q * q * 2.2)
                    if accent { d2[k] = min(1.4, d2[k] + w) } else { d1[k] = min(1.4, d1[k] + w) }
                }
                if q < 1.6, dist > 0.5 {
                    let imp = 0.012 * strength * exp(-(q - 0.9) * (q - 0.9) * 3)
                    u[k] += imp * Float(a) / dist
                    v[k] += imp * Float(b) / dist
                }
            }
        }
    }

    private func stir(x: Float, y: Float, px: Float, py: Float, accent: Bool, amount: Float) {
        let gi = max(1, min(n, Int(jsRound(Double(x * Float(n)))))), gj = max(1, min(m, Int(jsRound(Double(y * Float(m))))))
        let rb = max(3, Int(jsRound(Double(Float(n) * brush)))), sg = Float(rb * rb) * 0.35
        let dx = max(-0.12, min(0.12, (x - px) * strength * 4)), dy = max(-0.12, min(0.12, (y - py) * strength * 4))
        for a in -rb...rb {
            for b in -rb...rb {
                let i = gi + a, j = gj + b
                guard i >= 1, i <= n, j >= 1, j <= m else { continue }
                let w = exp(-Float(a * a + b * b) / sg), k = ix(i, j)
                u[k] += dx * w
                v[k] += dy * w
                guard amount > 0 else { continue }
                if accent { d2[k] = min(1.4, d2[k] + amount * w) } else { d1[k] = min(1.4, d1[k] + amount * w) }
            }
        }
    }

    private func bnd(_ x: UnsafeMutablePointer<Float>) {
        for i in 1...n { x[ix(i, 0)] = x[ix(i, 1)]; x[ix(i, m + 1)] = x[ix(i, m)] }
        for j in 1...m { x[ix(0, j)] = x[ix(1, j)]; x[ix(n + 1, j)] = x[ix(n, j)] }
    }

    private func project() {
        let fn = Float(n)
        for j in 1...m {
            for i in 1...n {
                div[ix(i, j)] = -0.5 * (u[ix(i + 1, j)] - u[ix(i - 1, j)] + v[ix(i, j + 1)] - v[ix(i, j - 1)]) / fn
                p[ix(i, j)] = 0
            }
        }
        for _ in 0..<14 {
            for j in 1...m {
                for i in 1...n {
                    p[ix(i, j)] = (div[ix(i, j)] + p[ix(i - 1, j)] + p[ix(i + 1, j)] + p[ix(i, j - 1)] + p[ix(i, j + 1)]) / 4
                }
            }
            bnd(p)
        }
        for j in 1...m {
            for i in 1...n {
                u[ix(i, j)] -= 0.5 * fn * (p[ix(i + 1, j)] - p[ix(i - 1, j)])
                v[ix(i, j)] -= 0.5 * fn * (p[ix(i, j + 1)] - p[ix(i, j - 1)])
            }
        }
        bnd(u); bnd(v)
    }

    private func vorticity(_ eps: Float) {
        for j in 1...m {
            for i in 1...n {
                curl[ix(i, j)] = 0.5 * (v[ix(i + 1, j)] - v[ix(i - 1, j)] - (u[ix(i, j + 1)] - u[ix(i, j - 1)]))
            }
        }
        for j in 2..<m {
            for i in 2..<n {
                let gx = 0.5 * (abs(curl[ix(i + 1, j)]) - abs(curl[ix(i - 1, j)]))
                let gy = 0.5 * (abs(curl[ix(i, j + 1)]) - abs(curl[ix(i, j - 1)]))
                let len = (gx * gx + gy * gy).squareRoot() + 1e-5, c = curl[ix(i, j)]
                u[ix(i, j)] += eps * (gy / len) * c
                v[ix(i, j)] -= eps * (gx / len) * c
            }
        }
    }

    private func advect(_ d: UnsafeMutablePointer<Float>, _ src: UnsafeMutablePointer<Float>, _ dt: Float, _ decay: Float) {
        let fn = Float(n)
        for j in 1...m {
            for i in 1...n {
                let x = max(0.5, min(fn + 0.5, Float(i) - dt * fn * u[ix(i, j)]))
                let y = max(0.5, min(Float(m) + 0.5, Float(j) - dt * fn * v[ix(i, j)]))
                let i0 = Int(x), j0 = Int(y), i1 = i0 + 1, j1 = j0 + 1
                let s1 = x - Float(i0), s0 = 1 - s1, t1 = y - Float(j0), t0 = 1 - t1
                d[ix(i, j)] = decay * (s0 * (t0 * src[ix(i0, j0)] + t1 * src[ix(i0, j1)])
                                     + s1 * (t0 * src[ix(i1, j0)] + t1 * src[ix(i1, j1)]))
            }
        }
        bnd(d)
    }

    private func diffuse(_ d: UnsafeMutablePointer<Float>, _ k: Float) {
        guard k > 0 else { return }
        for j in 1...m {
            for i in 1...n {
                let q = ix(i, j)
                d[q] += k * ((d[q - 1] + d[q + 1] + d[q - s] + d[q + s]) * 0.25 - d[q])
            }
        }
        bnd(d)
    }

    private func step() {
        let dt = 0.5 * speed
        // 自動: ゆっくりした対流と、ときどきの1滴
        phase += 0.0015
        let nx = 0.5 + 0.34 * sin(phase * 1.3) + 0.08 * sin(phase * 4.1)
        let ny = 0.5 + 0.3 * cos(phase * 0.9) + 0.08 * cos(phase * 3.3)
        stir(x: nx, y: ny, px: ax, py: ay, accent: false, amount: 0)
        ax = nx; ay = ny
        dropClock += 1.0 / 30
        if dropClock > dropEvery {
            dropClock = 0
            let pink = Double.random(in: 0..<1) < 0.4
            drop(x: .random(in: 0.1...0.9), y: pink ? .random(in: 0.1...0.4) : .random(in: 0.5...0.9),
                 r: .random(in: 0.12...0.22), accent: pink, amount: 0.6)
        }
        vorticity(curlStrength)
        // 墨は水より重くて沈み、差し色は軽くて浮く
        for j in 1...m {
            for i in 1...n {
                let q = ix(i, j), a = d1[q], b = d2[q]
                v[q] += sink * dt * (a * a - 0.5 * b * b) * 0.0015
            }
        }
        diffuse(u, 0.2); diffuse(v, 0.2)
        u0.update(from: u, count: size); v0.update(from: v, count: size)
        advect(u, u0, dt, viscosity); advect(v, v0, dt, viscosity)
        project()
        d0.update(from: d1, count: size); advect(d1, d0, dt, dissolve); diffuse(d1, spread)
        d0.update(from: d2, count: size); advect(d2, d0, dt, dissolve); diffuse(d2, spread)
    }

    /// 濃さ → 色。紙 → 墨 → 濃い墨（3段）と 紙 → 差し色 → くすんだ差し色 を、墨の割合で混ぜる
    private func paint() {
        let inkDeep = (ink.0 * 0.38, ink.1 * 0.38, ink.2 * 0.38)
        let accentDeep = (accent.0 * 0.55 + ink.0 * 0.25, accent.1 * 0.55 + ink.1 * 0.25, accent.2 * 0.55 + ink.2 * 0.25)
        func mix(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        for j in 1...m {
            for i in 1...n {
                let q = ix(i, j), a = max(0, d1[q]), b = max(0, d2[q])
                let tot = (a + b) * (1 + grain[q])
                let t = 1 - exp(-1.5 * tot)
                let tt = t < 0.2 ? 0 : (t - 0.2) / 0.8
                let share: Float = tot > 0 ? a / (a + b) : 0
                let inkC: (Float, Float, Float), accC: (Float, Float, Float)
                if tt < 0.55 {
                    let k = tt / 0.55
                    inkC = mix(paper, ink, k); accC = mix(paper, accent, min(1, k * 0.85))
                } else {
                    let k = (tt - 0.55) / 0.45
                    inkC = mix(ink, inkDeep, k); accC = mix(accent, accentDeep, k)
                }
                let c = mix(accC, inkC, share)
                let o = ((j - 1) * n + (i - 1)) * 4
                pixels[o] = UInt8(max(0, min(255, c.0)))
                pixels[o + 1] = UInt8(max(0, min(255, c.1)))
                pixels[o + 2] = UInt8(max(0, min(255, c.2)))
                pixels[o + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return }
        image = CGImage(width: n, height: m, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// 右の面の墨流し。30Hz、`paused` の間は進まない
struct Suminagashi: View {
    let tank: InkTank
    var paused = false

    var body: some View {
        GeometryReader { geo in
            Ticker(fps: 30, paused: paused) { now in
                if let image = tank.frame(at: now) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geo.size.width + 4, height: geo.size.height + 4)
                        .offset(x: -2, y: -2)
                        // 部品の `soft 0.8`（= 升 0.8 個ぶんのぼかし）。縁が透けないよう opaque で掛ける
                        .blur(radius: 0.8 * geo.size.width / CGFloat(tank.n), opaque: true)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    tank.hover(x: Float(point.x / max(1, geo.size.width)), y: Float(point.y / max(1, geo.size.height)))
                case .ended:
                    tank.endHover()
                }
            }
        }
        .clipped()
    }
}

// MARK: - 管制塔 ⇄ 会話の右側の波紋（V11TabRipple）

/// 3通り。どれも「<」形のドットで、毎コマいまの白い面の辺の右側で切り抜く（白い面の下に描く）。24fps
/// - 会話へ: 左（管制塔の白い三角の先）から右へ、まだ白い面が来ていない青い所を全部覆い、右端から抜ける。
///   v11 の V11TabRipple は「<」の窓だけだが、本人の指示（2026-10-03）で滑っていく途中の青い所まで広げた
/// - 管制塔へ: 右端から左へ、画面の左端まで（退いた所は退いた時点で覆い済み）
/// - 横: メニューでタブを替えた時。白い面は動かず、右の「<」の窓だけを右端から左へ覆って右列を差し替える
struct TabRipple: Equatable {
    enum Kind { case toChat, toTower, side }
    let kind: Kind
    let started: Date
    var back: Bool { kind == .toTower }
}

struct TabRippleLayer: View {
    let ripple: TabRipple?
    /// いまの白い面の開き（0 管制塔 … 1 会話）。戻りの切り抜きに使う
    let p: Double

    var body: some View {
        Ticker(fps: 24, paused: ripple == nil) { now in
            if let ripple {
                Canvas { ctx, size in
                    Self.draw(&ctx, size: size, ripple: ripple, sheet: p, n: Int(now.timeIntervalSince(ripple.started) * 24))
                }
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, ripple: TabRipple, sheet q: Double, n: Int) {
        let (c, h, r) = ripple.back ? (12, 3, 9) : (8, 6, 9)
        guard n <= c + h + r else { return }
        let p: Double, covering: Bool
        if n < c { p = Double(n + 1) / Double(c); covering = true }
        else if n < c + h { p = 1; covering = true }
        else { p = max(0, 1 - Double(n - c - h + 1) / Double(r)); covering = false }
        let w = size.width, ht = size.height, apex = w - 540, cy = ht / 2, xc = w - 394, half = (ht - 100) / 2
        // 切り抜き: いまの白い面の辺（BlueSheet と同じ XC・XT）。横は面が動かないので「<」の窓
        let k = CGFloat(ripple.kind == .side ? 1 : q)
        let edgeC = xc * k, edgeT = 146 + (apex - 146) * k
        var window = Path()
        window.addLines([CGPoint(x: edgeC, y: 56), CGPoint(x: w, y: 56), CGPoint(x: w, y: ht - 44),
                         CGPoint(x: edgeC, y: ht - 44), CGPoint(x: edgeT, y: cy)])
        window.closeSubpath()
        ctx.clip(to: window)
        DotWipeLayer.dots(&ctx, size: size, p: p, covering: covering, pc: 16, mid: Palette.Blue.fg3) { x, y in
            let kl = x - 0.37 * abs(y - cy)
            // 横は右端から「<」の先へ（←）。本人の指示（2026-10-03）。モックは先から右へ
            if ripple.kind == .side { return Double(max(0, min(1, (w - kl) / (w - apex)))) }
            if ripple.kind == .toChat { return Double(max(0, min(1, (kl - 146) / (w - 146)))) }
            // 白い面が退く速さに合わせ、左ほど遅く覆う（V11TabRipple の戻り）
            let wt = max(0, 1 - abs(y - cy) / half)
            let qs = max(0, min(1, (x - 146 * wt) / (xc - 292 * wt)))
            let u = cbrt(1 - qs)
            let d = max(0, min(1, (w - kl) / (w + 150)))
            return Double(min(d, max(0, 1.35 * u - 0.35)))
        }
    }
}

// MARK: - 成功の合図（V11Burst）

/// 送出や PR が通った所から、8px のピンクのドットが同心に育って消える。16コマ
struct Burst: Identifiable {
    let id = UUID()
    let center: CGPoint
    let started = Date()
}

struct BurstLayer: View {
    let bursts: [Burst]

    var body: some View {
        Ticker(fps: 24, paused: bursts.isEmpty) { now in
            Canvas { ctx, _ in
                for b in bursts { Self.draw(&ctx, burst: b, n: Int(now.timeIntervalSince(b.started) * 24)) }
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func draw(_ ctx: inout GraphicsContext, burst: Burst, n: Int) {
        guard n <= 16 else { return }
        let rad: CGFloat = 170, cx = burst.center.x, cy = burst.center.y
        var y = floor((cy - rad) / 8) * 8
        while y < cy + rad {
            var x = floor((cx - rad) / 8) * 8
            while x < cx + rad {
                let d = Double(hypot(x + 4 - cx, y + 4 - cy) / rad)
                let f = Double(n) / 16 * 1.5 - d
                if d <= 1, f > 0, f <= 0.6 {
                    let s = f < 0.3 ? f / 0.3 : 1 - (f - 0.3) / 0.3
                    let sz = max(1, (s * 8).rounded())
                    ctx.fill(Path(CGRect(x: x + 4 - sz / 2, y: y + 4 - sz / 2, width: sz, height: sz)),
                             with: .color(f < 0.12 ? Palette.white : Palette.pink))
                }
                x += 8
            }
            y += 8
        }
    }
}
