import SwiftUI
import CoreGraphics

// MARK: - 遷移のドット

/// 遷移の相。idle → cover → hold → reveal → idle（v10 の `go()` と同じ並び）
enum WipePhase: Equatable { case idle, cover, hold, reveal }

/// DotWipe。押した所から波紋の順にドットが育って画面を覆い、離れた順に縮んで次を見せる。
/// 波紋の先頭からピンク → 白 → 青。24fps のコマ送り
struct DotWipeLayer: View {
    let phase: WipePhase
    let start: Date
    let origin: CGPoint
    var coverMs = 380.0
    var revealMs = 380.0
    var pitch: CGFloat = 18

    var body: some View {
        SumiClock(fps: 24, running: phase == .cover || phase == .reveal) { now in
            Canvas { ctx, size in
                let dur = phase == .cover ? coverMs : revealMs
                let q = min(1, floor(now.timeIntervalSince(start) * 1000 / (1000 / 24)) * (1000 / 24) / dur)
                let p: Double
                switch phase {
                case .idle: p = 0
                case .cover: p = q
                case .hold: p = 1
                case .reveal: p = 1 - q
                }
                if p >= 1 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.blue)); return }
                guard p > 0 else { return }
                let cover = phase == .cover
                let cols = Int((size.width / pitch).rounded(.up)), rows = Int((size.height / pitch).rounded(.up))
                let ox = origin.x, oy = origin.y
                let maxD = [hypot(ox, oy), hypot(size.width - ox, oy), hypot(ox, size.height - oy),
                            hypot(size.width - ox, size.height - oy)].max() ?? 1
                var pink = Path(), white = Path(), blue = Path()
                let P2 = p * 1.35
                for j in 0..<rows {
                    for i in 0..<cols {
                        let d = Double(hypot((CGFloat(i) + 0.5) * pitch - ox, (CGFloat(j) + 0.5) * pitch - oy) / maxD)
                        let f = P2 - (cover ? d : 1 - d)
                        let s = max(0, min(1, f / 0.35))
                        guard s > 0 else { continue }
                        let sz = (CGFloat(s) * pitch).rounded(.up), inset = ((pitch - sz) / 2).rounded(.down)
                        let r = CGRect(x: CGFloat(i) * pitch + inset, y: CGFloat(j) * pitch + inset, width: sz, height: sz)
                        if f < 0.1 { pink.addRect(r) } else if f < 0.2 { white.addRect(r) } else { blue.addRect(r) }
                    }
                }
                ctx.fill(blue, with: .color(Palette.blue))
                ctx.fill(white, with: .color(Palette.white))
                ctx.fill(pink, with: .color(Palette.pink))
            }
        }
        .allowsHitTesting(phase != .idle)
    }
}

/// 遷移の大見出し。`01 // ━━ FROM WORK` / 矢印＋ 132pt の題 / 和名と説明。
/// 字は1つずつ下から現れ（150ms・steps(3)）、`out` で上へ抜ける
struct WipeTitle: View {
    let to: CockpitMode
    let from: CockpitMode
    let start: Date
    let outStart: Date?

    nonisolated static func words(_ mode: CockpitMode) -> (no: String, en: String, jp: String, desc: String) {
        switch mode {
        case .work: ("01", "WORK", "作業", "会話と門")
        case .structure: ("02", "STRUCTURE", "構造", "ファイルの関係")
        case .memory: ("03", "SPARRING", "壁打ち", "引き継ぎと記憶")
        }
    }

    var body: some View {
        SumiClock(fps: 30) { now in
            let w = Self.words(to)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text("\(w.no) //").font(Palette.mono(12)).tracking(12 * 0.16)
                        .foregroundStyle(Palette.pink).opacity(fade(now, 0))
                    Rectangle().fill(Palette.white).frame(width: 180, height: 4)
                        .scaleEffect(x: blade(now), y: 1, anchor: outStart == nil ? .leading : .trailing)
                    Text("FROM \(Self.words(from).en)").font(Palette.mono(12)).tracking(12 * 0.16)
                        .foregroundStyle(Palette.OnBlue.fg3).opacity(fade(now, 420))
                }
                HStack(alignment: .center, spacing: 22) {
                    arrow.frame(width: 96, height: 96)
                        .mask(alignment: outStart == nil ? .leading : .trailing) {
                            Rectangle().frame(width: 96 * clip(now, 120, inside: true))
                        }
                    HStack(spacing: 0) {
                        ForEach(Array(w.en.enumerated()), id: \.offset) { i, ch in
                            letter(String(ch), progress: clip(now, 160 + Double(i) * 45, inside: true))
                        }
                    }
                }
                HStack(spacing: 12) {
                    letter(w.jp, progress: clip(now, 160 + Double(w.en.count) * 45 + 60, inside: true), jp: true)
                    Text(w.desc).font(Palette.mono(11)).tracking(11 * 0.14)
                        .foregroundStyle(Palette.OnBlue.fg2)
                        .opacity(fade(now, 160 + Double(w.en.count) * 45 + 160))
                }
                .padding(.leading, 66)
            }
            .foregroundStyle(Palette.white)
        }
        .allowsHitTesting(false)
    }

    /// 字の現れ方。入りは下から、抜けは下から削れて上へ消える
    private func letter(_ s: String, progress: Double, jp: Bool = false) -> some View {
        Text(s)
            .font(jp ? Palette.bodyJP(22) : Palette.display(132))
            .fixedSize()
            .mask(alignment: outStart == nil ? .bottom : .top) {
                GeometryReader { g in
                    Rectangle().frame(height: g.size.height * progress)
                        .frame(maxHeight: .infinity, alignment: outStart == nil ? .bottom : .top)
                }
            }
    }

    /// 入りの進み（0→1）か、抜けの残り（1→0）
    private func clip(_ now: Date, _ delay: Double, inside: Bool) -> Double {
        if let outStart {
            return 1 - steps((now.timeIntervalSince(outStart) * 1000 - delay / 4) / 150, 3)
        }
        return steps((now.timeIntervalSince(start) * 1000 - 240 - delay) / 150, 3)
    }
    private func fade(_ now: Date, _ delay: Double) -> Double { clip(now, delay, inside: false) }
    private func blade(_ now: Date) -> Double {
        if let outStart { return 1 - steps(now.timeIntervalSince(outStart) * 1000 / 120, 4) }
        return steps((now.timeIntervalSince(start) * 1000 - 240) / 120, 4)
    }

    private var arrow: some View {
        ZStack(alignment: .trailing) {
            Rectangle().fill(Palette.white).frame(height: 6).padding(.trailing, 30)
            ArrowHead().fill(Palette.white).frame(width: 44, height: 52)
        }
    }
}

/// 矢じり（v10 の `polygon(0 0,14px 0,44px 26px,14px 52px,0 52px,30px 26px)`）
struct ArrowHead: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 44, sy = r.height / 52
        var p = Path()
        p.addLines([(0, 0), (14, 0), (44, 26), (14, 52), (0, 52), (30, 26)].map {
            CGPoint(x: r.minX + $0.0 * sx, y: r.minY + $0.1 * sy)
        })
        p.closeSubpath()
        return p
    }
}

// MARK: - 決定のドット

/// 1回ぶんの飛行。押したもの（from）がドット格子に崩れ、5コマで to へ渡り、着地後に育って面になる
struct Flight: Identifiable {
    let id = UUID()
    let from: CGRect
    let to: CGRect
    let start: Date
    var duration = 1.7
    var ink: Color = Palette.blue
}

/// 決定のドットを描く層。飛行中だけピンク、着地で左から青（`runDots` の 24fps コマ送り）
struct FlightLayer: View {
    let flights: [Flight]

    var body: some View {
        SumiClock(fps: 24, running: !flights.isEmpty) { now in
            Canvas { ctx, _ in
                for f in flights { draw(&ctx, f, now: now) }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext, _ S: Flight, now: Date) {
        let A = S.from, B = S.to, pt: CGFloat = 8
        let cols = max(4, Int((B.width / pt).rounded())), rows = max(2, Int((B.height / pt).rounded()))
        let cw = B.width / CGFloat(cols), ch = B.height / CGFloat(rows)
        let frame = 1000.0 / 24
        let t = floor(now.timeIntervalSince(S.start) * 1000 / frame) * frame
        let dur = S.duration * 1000, k1 = dur * 0.19, k2 = dur * 0.45, fadeAt = dur * 0.83
        guard t <= dur + 200 else { return }
        var layer = ctx
        layer.opacity = t > fadeAt ? max(0, 1 - (t - fadeAt) / 260) : 1
        var seed: Int = 7
        var pink = Path(), ink = Path()
        for j in 0..<rows {
            for i in 0..<cols {
                seed = seed * 16807 % 2_147_483_647
                let jitter = Double(seed) / 2_147_483_647 * 60
                let u = (CGFloat(i) + 0.5) / CGFloat(cols), v = (CGFloat(j) + 0.5) / CGFloat(rows)
                let sx = A.minX + u * A.width, sy = A.minY + v * A.height
                let tx = B.minX + (CGFloat(i) + 0.5) * cw, ty = B.minY + (CGFloat(j) + 0.5) * ch
                let d = Double(hypot(u - 0.5, v - 0.5)) * 1.4
                let lt = t - d * 160 - jitter
                guard lt >= 0 else { continue }
                var x = sx, y = sy, rr: CGFloat = 4, landed = false
                if lt < k1 {
                    rr = 4 * CGFloat(min(1, lt / (k1 * 0.8)))
                } else if lt < k2 {
                    let k = CGFloat(((lt - k1) / (k2 - k1) * 5).rounded(.up) / 5)
                    x = sx + (tx - sx) * k; y = sy + (ty - sy) * k
                } else {
                    x = tx; y = ty
                    rr = 8 * (0.5 + 0.5 * CGFloat(min(1, (lt - k2) / 260)))
                    landed = lt > k2 + 60 + Double(u) * 220
                }
                let sz = max(1, min(rr * 2, max(cw, ch) + 1))
                let r = CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz)
                if landed { ink.addRect(r) } else { pink.addRect(r) }
            }
        }
        layer.fill(ink, with: .color(S.ink))
        layer.fill(pink, with: .color(Palette.pink))
    }
}

// MARK: - メニューの面

/// メニューの青い面。斜線（286,0 → 線は 18°）から離れる順にドットが育ち、閉じる時は逆順に縮む。
/// 開き切ったら（`settled`）時計を止めて1枚の面にする
struct MenuDots: View {
    let start: Date
    let closing: Bool
    let settled: Bool

    var body: some View {
        SumiClock(fps: 60, running: !settled || closing) { now in
            Canvas { ctx, size in
                if settled && !closing {
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.blue)); return
                }
                let t = now.timeIntervalSince(start) * 1000, G: CGFloat = 24, cosA = cos(18 * Double.pi / 180)
                var p = Path()
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        let cx = x + G / 2, cy = y + G / 2
                        let d = Double(abs(cx - (286 + cy * Palette.slant))) * cosA
                        let k = closing ? 1 - max(0, min(1, (t - 80 - (1150 - d) * 0.14) / 90))
                                        : max(0, min(1, (t - 120 - d * 0.22) / 120))
                        let sz = CGFloat((k * 4).rounded() / 4) * (G + 1)
                        if sz > 0 { p.addRect(CGRect(x: cx - sz / 2, y: cy - sz / 2, width: sz, height: sz)) }
                        x += G
                    }
                    y += G
                }
                ctx.fill(p, with: .color(Palette.blue))
            }
        }
    }
}

// MARK: - 墨流し

/// 墨流し。Stam の Stable Fluids（半ラグランジュの移流＋ヤコビ射影）に渦度の補強を足したもの。
/// v10 の `Suminagashi` を写した: 墨は沈み、ピンクは浮く。濃さは 紙 → 墨 → 深い墨 の3段に落とす。
///
/// ponytail: CPU の配列で 96 格子・30Hz。重ければ Metal へ
final class InkTank {
    let N: Int, M: Int
    private let S: Int, T: Int
    private var u, v, u0, v0, d1, d2, d0, p, div, curl, grain: [Float]
    private let I: [Float], A: [Float], B: [Float], ID: [Float], AD: [Float]
    var dropEvery: Double
    let spread: Float
    private let speed: Float = 0.35, dissolve: Float = 0.9993, sink: Float = 0.05
    private let viscosity: Float = 0.997, strength: Float = 1, curlStrength: Float = 0.18, brush: Float = 0.045
    private var ph: Float = 0, ax: Float = 0.5, ay: Float = 0.5, dropT: Double = 0
    private var lastStep: Date?
    private var warmed = false
    private var pixels: [UInt8]
    private(set) var image: CGImage?

    init(res: Int, aspect: Double, ink: UInt32, accent: UInt32, bg: UInt32, dropEvery: Double = 7, spread: Float = 0.06) {
        N = res; M = max(8, Int((Double(res) * aspect).rounded()))
        S = N + 2; T = M + 2
        let zero = [Float](repeating: 0, count: S * T)
        u = zero; v = zero; u0 = zero; v0 = zero; d1 = zero; d2 = zero; d0 = zero; p = zero; div = zero; curl = zero
        grain = (0..<(S * T)).map { _ in Float.random(in: -0.03...0.03) }
        func rgb(_ h: UInt32) -> [Float] { [Float((h >> 16) & 0xFF), Float((h >> 8) & 0xFF), Float(h & 0xFF)] }
        let i = rgb(ink), a = rgb(accent)
        I = i; A = a; B = rgb(bg)
        ID = i.map { $0 * 0.38 }
        AD = (0..<3).map { a[$0] * 0.55 + i[$0] * 0.25 }
        self.dropEvery = dropEvery
        self.spread = spread
        pixels = [UInt8](repeating: 255, count: N * M * 4)
    }

    @inline(__always) private func IX(_ i: Int, _ j: Int) -> Int { i + S * j }

    private func bnd(_ x: inout [Float]) {
        for i in 1...N { x[IX(i, 0)] = x[IX(i, 1)]; x[IX(i, M + 1)] = x[IX(i, M)] }
        for j in 1...M { x[IX(0, j)] = x[IX(1, j)]; x[IX(N + 1, j)] = x[IX(N, j)] }
    }

    private func project() {
        let n = Float(N)
        for j in 1...M { for i in 1...N {
            div[IX(i, j)] = -0.5 * (u[IX(i + 1, j)] - u[IX(i - 1, j)] + v[IX(i, j + 1)] - v[IX(i, j - 1)]) / n
            p[IX(i, j)] = 0
        } }
        for _ in 0..<14 {
            for j in 1...M { for i in 1...N {
                p[IX(i, j)] = (div[IX(i, j)] + p[IX(i - 1, j)] + p[IX(i + 1, j)] + p[IX(i, j - 1)] + p[IX(i, j + 1)]) / 4
            } }
            bnd(&p)
        }
        for j in 1...M { for i in 1...N {
            u[IX(i, j)] -= 0.5 * n * (p[IX(i + 1, j)] - p[IX(i - 1, j)])
            v[IX(i, j)] -= 0.5 * n * (p[IX(i, j + 1)] - p[IX(i, j - 1)])
        } }
        bnd(&u); bnd(&v)
    }

    private func vorticity(_ eps: Float) {
        for j in 1...M { for i in 1...N {
            curl[IX(i, j)] = 0.5 * (v[IX(i + 1, j)] - v[IX(i - 1, j)] - (u[IX(i, j + 1)] - u[IX(i, j - 1)]))
        } }
        guard N > 3, M > 3 else { return }
        for j in 2..<M { for i in 2..<N {
            let gx = 0.5 * (abs(curl[IX(i + 1, j)]) - abs(curl[IX(i - 1, j)]))
            let gy = 0.5 * (abs(curl[IX(i, j + 1)]) - abs(curl[IX(i, j - 1)]))
            let len = (gx * gx + gy * gy).squareRoot() + 1e-5
            let c = curl[IX(i, j)]
            u[IX(i, j)] += eps * (gy / len) * c
            v[IX(i, j)] -= eps * (gx / len) * c
        } }
    }

    /// 速度場は値で受ける。`u` 自身を移流する時に inout と読みが同じ配列に重なる（排他違反で落ちる）
    private func advect(_ d: inout [Float], _ src: [Float], _ vu: [Float], _ vv: [Float],
                        _ dt: Float, _ decay: Float) {
        let n = Float(N), m = Float(M)
        for j in 1...M { for i in 1...N {
            var x = Float(i) - dt * n * vu[IX(i, j)], y = Float(j) - dt * n * vv[IX(i, j)]
            x = max(0.5, min(n + 0.5, x)); y = max(0.5, min(m + 0.5, y))
            let i0 = Int(x), j0 = Int(y), i1 = i0 + 1, j1 = j0 + 1
            let s1 = x - Float(i0), s0 = 1 - s1, t1 = y - Float(j0), t0 = 1 - t1
            d[IX(i, j)] = decay * (s0 * (t0 * src[IX(i0, j0)] + t1 * src[IX(i0, j1)])
                                   + s1 * (t0 * src[IX(i1, j0)] + t1 * src[IX(i1, j1)]))
        } }
        bnd(&d)
    }

    private func diffuse(_ d: inout [Float], _ k: Float) {
        guard k > 0 else { return }
        for j in 1...M { for i in 1...N {
            let q = IX(i, j)
            d[q] += k * ((d[q - 1] + d[q + 1] + d[q - S] + d[q + S]) * 0.25 - d[q])
        } }
        bnd(&d)
    }

    /// 掻き混ぜる。`amt` が 0 なら流れだけ（ホバーの波紋）
    func stir(_ x: Double, _ y: Double, _ px: Double, _ py: Double, accent: Bool, amt: Float = 0.12) {
        let gi = max(1, min(N, Int((x * Double(N)).rounded()))), gj = max(1, min(M, Int((y * Double(M)).rounded())))
        let RB = max(3, Int((Float(N) * brush).rounded())), sg = Float(RB * RB) * 0.35
        let dx = max(-0.12, min(0.12, Float(x - px) * strength * 4)), dy = max(-0.12, min(0.12, Float(y - py) * strength * 4))
        for a in -RB...RB { for b in -RB...RB {
            let i = gi + a, j = gj + b
            guard i >= 1, i <= N, j >= 1, j <= M else { continue }
            let w = exp(-Float(a * a + b * b) / sg), k = IX(i, j)
            u[k] += dx * w; v[k] += dy * w
            guard amt > 0 else { continue }
            if accent { d2[k] = min(1.4, d2[k] + amt * w) } else { d1[k] = min(1.4, d1[k] + amt * w) }
        } }
    }

    /// 1滴。やわらかい雲と、外へ向かうかすかな押し
    func drop(_ x: Double, _ y: Double, radius r: Double, accent: Bool, amount: Float = 1) {
        let gi = Int((x * Double(N)).rounded()), gj = Int((y * Double(M)).rounded())
        let R = max(2, Int((r * Double(min(N, M))).rounded())), E = Int((Double(R) * 1.4).rounded(.up))
        for a in -E...E { for b in -E...E {
            let i = gi + a, j = gj + b
            guard i >= 1, i <= N, j >= 1, j <= M else { continue }
            let dist = Float(a * a + b * b).squareRoot(), q = dist / Float(R), k = IX(i, j)
            if q < 1.4 {
                let w = amount * exp(-q * q * 2.2)
                if accent { d2[k] = min(1.4, d2[k] + w) } else { d1[k] = min(1.4, d1[k] + w) }
            }
            if q < 1.6, dist > 0.5 {
                let imp = 0.012 * strength * exp(-(q - 0.9) * (q - 0.9) * 3)
                u[k] += imp * Float(a) / dist; v[k] += imp * Float(b) / dist
            }
        } }
    }

    private func step() {
        let dt = 0.5 * speed
        ph += 0.0015
        let nx = 0.5 + 0.34 * sin(ph * 1.3) + 0.08 * sin(ph * 4.1), ny = 0.5 + 0.3 * cos(ph * 0.9) + 0.08 * cos(ph * 3.3)
        stir(Double(nx), Double(ny), Double(ax), Double(ay), accent: false, amt: 0)
        ax = nx; ay = ny
        dropT += 1.0 / 30
        if dropEvery > 0, dropT > dropEvery {
            dropT = 0
            let acc = Double.random(in: 0..<1) < 0.4
            drop(.random(in: 0.1...0.9), acc ? .random(in: 0.1...0.4) : .random(in: 0.5...0.9),
                 radius: .random(in: 0.12...0.22), accent: acc, amount: 0.6)
        }
        vorticity(curlStrength)
        if sink > 0 {
            for j in 1...M { for i in 1...N {
                let q = IX(i, j), a = d1[q], b = d2[q]
                v[q] += sink * dt * (a * a - 0.5 * b * b) * 0.0015
            } }
        }
        diffuse(&u, 0.2); diffuse(&v, 0.2)
        u0 = u; v0 = v
        advect(&u, u0, u0, v0, dt, viscosity); advect(&v, v0, u0, v0, dt, viscosity)
        project()
        let cu = u, cv = v
        d0 = d1; advect(&d1, d0, cu, cv, dt, dissolve); diffuse(&d1, spread)
        d0 = d2; advect(&d2, d0, cu, cv, dt, dissolve); diffuse(&d2, spread)
    }

    /// 時刻まで進める。30Hz 固定で、1回に進めるのは1歩まで（遅れた分は捨てる）
    func advance(to now: Date) {
        if !warmed {
            warmed = true
            for _ in 0..<3 { drop(.random(in: 0.15...0.9), .random(in: 0.15...0.4), radius: .random(in: 0.18...0.26), accent: true, amount: 0.7) }
            for _ in 0..<4 { drop(.random(in: 0.1...0.9), .random(in: 0.6...0.9), radius: .random(in: 0.2...0.3), accent: false, amount: 0.9) }
            for _ in 0..<40 { step() }
            paint()
            lastStep = now
            return
        }
        guard let last = lastStep else { lastStep = now; return }
        if now.timeIntervalSince(last) >= 1.0 / 30 {
            step(); paint()
            lastStep = now
        }
    }

    private func paint() {
        var tmpI: [Float] = [0, 0, 0], tmpA: [Float] = [0, 0, 0]
        for j in 1...M { for i in 1...N {
            let q = IX(i, j), a = max(0, d1[q]), b = max(0, d2[q]), g = 1 + grain[q]
            let tot = (a + b) * g, t = 1 - exp(-1.5 * tot)
            let tt = t < 0.2 ? 0 : (t - 0.2) / 0.8
            let fi = tot > 0 ? a / (a + b) : 0
            if tt < 0.55 {
                let s = tt / 0.55
                for k in 0..<3 { tmpI[k] = B[k] + (I[k] - B[k]) * s; tmpA[k] = B[k] + (A[k] - B[k]) * min(1, s * 0.85) }
            } else {
                let s = (tt - 0.55) / 0.45
                for k in 0..<3 { tmpI[k] = I[k] + (ID[k] - I[k]) * s; tmpA[k] = A[k] + (AD[k] - A[k]) * s }
            }
            let o = ((j - 1) * N + (i - 1)) * 4
            for k in 0..<3 { pixels[o + k] = UInt8(max(0, min(255, tmpA[k] + (tmpI[k] - tmpA[k]) * fi))) }
            pixels[o + 3] = 255
        } }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return }
        image = CGImage(width: N, height: M, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: N * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// 墨流しの面。30Hz で進め、隠れている間（`sumiPaused`）は時計ごと止まる。
/// `hover` の間はポインタの動きで水を掻く（墨は足さない）
struct Suminagashi: View {
    let tank: InkTank
    var hover = true
    var soft: CGFloat = 0.8

    @State private var lastHover: CGPoint?

    var body: some View {
        GeometryReader { geo in
            SumiClock(fps: 30) { now in
                Canvas { ctx, size in
                    tank.advance(to: now)
                    guard let image = tank.image else { return }
                    ctx.addFilter(.blur(radius: soft * size.width / CGFloat(tank.N)))
                    ctx.draw(Image(decorative: image, scale: 1),
                             in: CGRect(x: -4, y: -4, width: size.width + 8, height: size.height + 8))
                }
            }
            .background(Palette.white)
            .onContinuousHover { phase in
                guard hover else { return }
                switch phase {
                case let .active(pt):
                    if let last = lastHover {
                        tank.stir(pt.x / geo.size.width, pt.y / geo.size.height,
                                  last.x / geo.size.width, last.y / geo.size.height, accent: false, amt: 0)
                    }
                    lastHover = pt
                case .ended:
                    lastHover = nil
                }
            }
        }
    }
}
