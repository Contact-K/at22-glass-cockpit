import SwiftUI

// MARK: - 時刻（--shot で止める）

private struct FrozenTimeKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

private struct MotionPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `--shot` が焼く1コマの時刻。**入っている間は TimelineView を作らない**——
    /// `ImageRenderer` は TimelineView の中身を組まないので、時刻を外から渡して1枚で描く
    var frozenTime: Date? {
        get { self[FrozenTimeKey.self] }
        set { self[FrozenTimeKey.self] = newValue }
    }

    /// 画面が見えていない時（窓が隠れた・メニューが面を覆いきった）。**立っている間は全部の時計が止まる**
    var motionPaused: Bool {
        get { self[MotionPausedKey.self] }
        set { self[MotionPausedKey.self] = newValue }
    }
}

/// コマ送りの時計。動く部品はみなこれを通す。
/// `paused` の間は TimelineView が止まるので、隠れている部品は CPU を食わない
struct Ticker<Content: View>: View {
    let fps: Double
    let paused: Bool
    let content: (Date) -> Content
    @Environment(\.frozenTime) private var frozen
    @Environment(\.motionPaused) private var motionPaused

    init(fps: Double, paused: Bool = false, @ViewBuilder content: @escaping (Date) -> Content) {
        self.fps = fps
        self.paused = paused
        self.content = content
    }

    var body: some View {
        if let frozen {
            content(frozen)
        } else {
            TimelineView(.animation(minimumInterval: 1 / fps, paused: paused || motionPaused)) { timeline in
                content(timeline.date)
            }
        }
    }
}

/// CSS の `steps(n, jump-start)` ＋ `animation-fill-mode: both`。
/// 0…1 を返す。`delay` 前は 0、終わった後は 1
func stepped(_ elapsed: Double, delay: Double, duration: Double, steps: Int) -> Double {
    let x = (elapsed - delay) / duration
    if x < 0 { return 0 }
    if x >= 1 { return 1 }
    return min(1, (floor(x * Double(steps)) + 1) / Double(steps))
}

/// JS の `Math.round`（.5 は +∞ 側へ）。負の数で Swift の `rounded()` と食い違うので分けてある
@inline(__always) func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

// MARK: - 節番号

/// `01 // TALK 会話`。番号だけピンク、和文は青柳衡山T（小さな和文ラベルはここだけ）
struct SectionMark: View {
    let number: String
    let title: String
    let jp: String
    var size: CGFloat = 11
    var ink: Color = Palette.Light.fg2
    var jpInk: Color = Palette.Light.fg

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(number).foregroundStyle(Palette.pink)
            Text("// " + title).foregroundStyle(ink)
            Text(jp).font(.brush(14)).tracking(0).foregroundStyle(jpInk)
        }
        .font(.mono(size))
        .tracking(Palette.caps(size))
    }
}

// MARK: - 飾り（RegMark / Barcode / Starburst / Ruler / WaveLines）

/// 見当の印。1px の線だけ
struct RegMark: View {
    enum Kind { case cross, target, star }
    let kind: Kind
    var size: CGFloat = 12
    var color: Color = .white

    var body: some View {
        Canvas { ctx, _ in
            let c = size / 2
            var p = Path()
            p.move(to: CGPoint(x: c, y: 0)); p.addLine(to: CGPoint(x: c, y: size))
            p.move(to: CGPoint(x: 0, y: c)); p.addLine(to: CGPoint(x: size, y: c))
            switch kind {
            case .cross: break
            case .target:
                p.addEllipse(in: CGRect(x: c - c * 0.55, y: c - c * 0.55, width: c * 1.1, height: c * 1.1))
            case .star:
                p.move(to: CGPoint(x: c * 0.3, y: c * 0.3)); p.addLine(to: CGPoint(x: size - c * 0.3, y: size - c * 0.3))
                p.move(to: CGPoint(x: size - c * 0.3, y: c * 0.3)); p.addLine(to: CGPoint(x: c * 0.3, y: size - c * 0.3))
            }
            ctx.stroke(p, with: .color(color), lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

/// 値から決まる縞。同じ値なら必ず同じ縞になる
struct Barcode: View {
    let value: String
    var width: CGFloat = 96
    var height: CGFloat = 20
    var color: Color = .white

    var body: some View {
        Canvas { ctx, _ in
            var s: UInt32 = 0
            for ch in value.unicodeScalars { s = s &* 31 &+ ch.value }
            var x: CGFloat = 0
            while x < width {
                s = s &* 1_103_515_245 &+ 12_345
                let w = CGFloat(1 + (s >> 16) % 3)
                let gap = CGFloat(1 + (s >> 8) % 2)
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: height)), with: .color(color))
                x += w + gap
            }
        }
        .frame(width: width, height: height)
    }
}

/// 尖った星。`spin` は 12 秒で1周（12fps のコマ送り）
struct Starburst: View {
    var size: CGFloat = 20
    var points = 4
    var inner: CGFloat = 0.18
    var color: Color = Palette.pink
    var fill = true
    var spin = false

    var body: some View {
        if spin {
            Ticker(fps: 12) { now in
                star.rotationEffect(.degrees(now.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 12) / 12 * 360))
            }
        } else {
            star
        }
    }

    private var star: some View {
        Canvas { ctx, _ in
            let c = size / 2, r = c - 1, n = points * 2
            var p = Path()
            for i in 0..<n {
                let a = Double(i) / Double(n) * .pi * 2 - .pi / 2
                let rad = i % 2 == 1 ? r * inner : r
                let pt = CGPoint(x: c + cos(a) * rad, y: c + sin(a) * rad)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            if fill { ctx.fill(p, with: .color(color)) }
            ctx.stroke(p, with: .color(color), lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

/// 目盛り。細目は下半分、`major` 本ごとに全高
struct Ruler: View {
    let length: CGFloat
    var step: CGFloat = 6
    var major = 7
    var thickness: CGFloat = 5
    var color: Color = .white.opacity(0.45)

    var body: some View {
        Canvas { ctx, _ in
            var x: CGFloat = 0, i = 0
            while x <= length {
                let full = i % major == 0
                let h = full ? thickness : thickness * 0.5
                ctx.fill(Path(CGRect(x: x, y: thickness - h, width: 1, height: h)), with: .color(color))
                x += step
                i += 1
            }
        }
        .frame(width: length, height: thickness)
        .opacity(0.9)
    }
}

/// 波線。動いている時だけ 0.6 秒で 1 ラジアン進む
struct WaveLines: View {
    var width: CGFloat = 120
    var height: CGFloat = 24
    var lines = 4
    var amp: CGFloat = 4
    var freq: Double = 2
    var color: Color = .white
    var animate = false

    var body: some View {
        Ticker(fps: 24, paused: !animate) { now in
            let phase = animate ? now.timeIntervalSinceReferenceDate / 0.6 : 0
            Canvas { ctx, _ in
                for i in 0..<lines {
                    let y0 = (CGFloat(i) + 0.5) * (height / CGFloat(lines))
                    var p = Path()
                    for k in 0...48 {
                        let u = Double(k) / 48
                        let pt = CGPoint(x: u * width,
                                         y: y0 + sin(u * .pi * 2 * freq + phase + Double(i) * 0.35) * amp)
                        if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    ctx.stroke(p, with: .color(color), lineWidth: 1)
                }
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - 斜め板・矢羽

/// 尖った板。CSS の `clip-path: polygon(...)` と `skewX(18deg)` を1つにまとめた形。
///
/// - `point`: 左端を尖らせる幅（自分の発言の矢羽）
/// - `notch`: 左端を内へ切り込む幅（上帯の門の札）
/// - `head` : 右端を尖らせる幅（選んだ板）
/// - `skew` : skewX の角度（度）。`origin` は傾きの支点（0 = 上端、1 = 下端、0.5 = 中央）
struct Chevron: Shape {
    var point: CGFloat = 0
    var notch: CGFloat = 0
    var head: CGFloat = 0
    var skew: Double = 0
    var origin: CGFloat = 0.5

    nonisolated func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: point, y: 0))
        p.addLine(to: CGPoint(x: w - head, y: 0))
        if head > 0 { p.addLine(to: CGPoint(x: w, y: h / 2)) }
        p.addLine(to: CGPoint(x: w - head, y: h))
        p.addLine(to: CGPoint(x: point, y: h))
        if point > 0 { p.addLine(to: CGPoint(x: 0, y: h / 2)) }
        if notch > 0 { p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: notch, y: h / 2)); p.addLine(to: CGPoint(x: 0, y: 0)) }
        p.closeSubpath()
        guard skew != 0 else { return p.offsetBy(dx: r.minX, dy: r.minY) }
        let t = CGFloat(tan(skew * .pi / 180))
        let shear = CGAffineTransform(a: 1, b: 0, c: t, d: 1, tx: -t * h * origin, ty: 0)
        return p.applying(shear).offsetBy(dx: r.minX, dy: r.minY)
    }
}

// MARK: - ボタン

/// 直角の塊。押すと `translate(1px,1px)`。`primary` は面、`secondary` は枠
struct SumiButtonStyle: ButtonStyle {
    var primary = true
    var size: CGFloat = 11
    var ink = Palette.Light.fg
    var paper = Palette.Light.bg

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, primary: primary, size: size, ink: ink, paper: paper)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let size: CGFloat
        let ink: Color
        let paper: Color
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let filled = primary || (hover && enabled)
            configuration.label
                .font(.mono(size))
                .tracking(size * 0.08)
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(filled ? paper : ink)
                .background(filled ? (primary && hover && enabled ? Color(hex: 0x3030FF) : ink) : Color.clear)
                .overlay(Rectangle().stroke(ink, lineWidth: 1))
                .opacity(enabled ? 1 : 0.4)
                .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

// MARK: - InkLoader（墨の四角の読み込み表示）

/// 4×4 の墨の四角が状態の絵に崩れて動き、また四角に戻る。10×10 の升・24fps。
/// `components/InkLoader.js` の写し。v10 が使う状態だけを写した
/// （download / delete / connect は v10 に出てこないので写していない）
struct InkLoader: View {
    let status: String
    var pitch: CGFloat = 5
    var color: Color = Palette.Light.fg
    var accent: Color = Palette.pink

    @State private var start = Date()
    /// `done` は1回きり。描き終わったら時計を止める（PLAN の済みの行に並ぶので、回し続けると無駄に食う）
    @State private var finished = false
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        Ticker(fps: 24, paused: finished) { now in
            // 焼く時は周期の真ん中（絵がいちばん立っている所）を写す
            let t = frozen != nil ? (Self.period[status] ?? 2.6) * 0.5 : now.timeIntervalSince(start)
            Canvas { ctx, _ in
                Self.draw(&ctx, status: status, t: t, pitch: pitch, ink: color, accent: accent)
            }
        }
        .frame(width: 10 * pitch, height: 10 * pitch)
        .onChange(of: status) { start = Date(); finished = false }
        .task(id: status) {
            guard status == "done" else { return }
            try? await Task.sleep(for: .seconds((Self.period["done"] ?? 2.2) + 0.1))
            finished = true
        }
    }

    nonisolated static let period: [String: Double] = [
        "think": 2.6, "search": 2.8, "write": 2.8, "reply": 2.8, "transfer": 3.2,
        "upload": 2.6, "error": 2.4, "wait": 3.6, "idle": 6.4, "handoff": 3.6,
        "reread": 3.6, "duplicate": 3.6, "done": 2.2, "build": 3.0, "overload": 2.6,
    ]

    nonisolated static func draw(_ ctx: inout GraphicsContext, status: String, t: Double,
                     pitch: CGFloat, ink: Color, accent: Color) {
        let n = 10, m = 4.5, hh = 2.0
        let period = Self.period[status] ?? 2.6
        let tq = floor(t * 24) / 24
        let once = status == "done", nomorph = status == "idle"
        var p = once ? cl(tq / period) : fr(tq / period)

        func cell(_ x: Int, _ y: Int, _ c: Color) {
            ctx.fill(Path(CGRect(x: CGFloat(x) * pitch, y: CGFloat(y) * pitch, width: pitch, height: pitch)),
                     with: .color(c))
        }
        func sq(_ x: Int, _ y: Int) -> Double {
            (max(abs(Double(x) - m), abs(Double(y) - m)) - hh) / (hh + 0.5)
        }
        if once && p >= 1 { p = 0 }      // 1回きり。終わったら四角で止まる
        let w: Double = nomorph ? 1
            : p < 0.1 ? 0 : p < 0.22 ? ss((p - 0.1) / 0.12) : p < 0.8 ? 1
            : p < 0.92 ? 1 - ss((p - 0.8) / 0.12) : 0
        let q = nomorph ? p : cl((p - 0.1) / 0.82)

        if let mask = motif(status, q) {
            // 墨の升と空の升を、互いの距離で溶かし合わせる（SDF の混ぜ）
            var lit: [(Int, Int)] = [], un: [(Int, Int)] = []
            for y in 0..<n {
                for x in 0..<n {
                    if mask[y * n + x] != 0 { lit.append((x, y)) } else { un.append((x, y)) }
                }
            }
            for y in 0..<n {
                for x in 0..<n {
                    let a = mask[y * n + x]
                    var v: Double
                    if w >= 1 { v = a != 0 ? -1 : 1 } else if w <= 0 { v = sq(x, y) } else {
                        var d = 1e9
                        for (X, Y) in (a != 0 ? un : lit) {
                            let e = Double((X - x) * (X - x) + (Y - y) * (Y - y))
                            if e < d { d = e }
                        }
                        d = d.squareRoot() - 0.5
                        v = (1 - w) * sq(x, y) + w * (a != 0 ? -d : d) / (hh + 0.5)
                    }
                    if v < 0 { cell(x, y, w > 0.5 && a == 2 ? accent : ink) }
                }
            }
        } else {
            // think: 2つの玉が割れて回る（メタボール）
            let sp = sin(.pi * q), a = .pi * q * 2 + .pi / 4
            let dd = 2.1 * sp, r = 2.3 / 2.0.squareRoot() * (1 - 0.12 * sp)
            let balls: [(Double, Double, Double, Bool)] = [
                (dd * cos(a), dd * sin(a), r, false), (-dd * cos(a), -dd * sin(a), r, true)]
            for y in 0..<n {
                for x in 0..<n {
                    let dx = Double(x) - m, dy = Double(y) - m
                    var f = 0.0, best = 0.0, pink = false
                    for b in balls {
                        let v = b.2 * b.2 / ((dx - b.0) * (dx - b.0) + (dy - b.1) * (dy - b.1) + 0.01)
                        f += v
                        if v > best { best = v; pink = b.3 }
                    }
                    let v = (1 - w) * sq(x, y) + w * (1 - f.squareRoot())
                    if v < 0 { cell(x, y, w > 0.5 && pink ? accent : ink) }
                }
            }
        }
    }

    nonisolated private static func fr(_ v: Double) -> Double { v - floor(v) }
    nonisolated private static func cl(_ t: Double) -> Double { max(0, min(1, t)) }
    nonisolated private static func ss(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    nonisolated private static func hsh(_ x: Int, _ y: Int, _ n: Double) -> Double {
        fr(sin(Double(x) * 12.9898 + Double(y) * 78.233 + n * 37.719) * 43758.5453)
    }

    /// 10×10 の絵。0 = 空、1 = 墨、2 = ピンク。q は 0…1 の進み
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    nonisolated private static func motif(_ status: String, _ q: Double) -> [UInt8]? {
        let g = 10
        var mk = [UInt8](repeating: 0, count: g * g)
        func set(_ x: Int, _ y: Int, _ v: UInt8 = 1) {
            if x >= 0, y >= 0, x < g, y < g { mk[y * g + x] = v }
        }
        func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt8 = 1) {
            for y in y0...y1 { for x in x0...x1 { set(x, y, v) } }
        }
        func ring(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt8 = 1) {
            for x in x0...x1 { set(x, y0, v); set(x, y1, v) }
            for y in y0...y1 { set(x0, y, v); set(x1, y, v) }
        }
        func near(_ x: Double, _ y: Double, _ px: Double, _ py: Double, _ r: Double) -> Bool {
            (x - px) * (x - px) + (y - py) * (y - py) < r * r
        }
        func seg(_ x: Double, _ y: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ r: Double) -> Bool {
            let vx = bx - ax, vy = by - ay
            let t = cl(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy))
            return near(x, y, ax + vx * t, ay + vy * t, r)
        }

        switch status {
        case "search":
            let a = q * .pi * 2, cx = 3.6 + 1.1 * sin(a), cy = 3.6 + 0.8 * sin(2 * a)
            for y in 0..<g {
                for x in 0..<g {
                    let d = hypot(Double(x) - cx, Double(y) - cy)
                    if abs(d - 2.05) < 0.62 || seg(Double(x), Double(y), cx + 1.9, cy + 1.9, cx + 4.6, cy + 4.6, 0.8) { set(x, y) }
                }
            }
            set(Int(jsRound(cx - 0.8)), Int(jsRound(cy - 0.8)), 2)
        case "write":
            let wq = cl((q - 0.06) / 0.72), tx = 1 + 7 * wq
            func wy(_ x: Double) -> Int { 7 - (Int(jsRound(x)) % 3 == 1 ? 1 : 0) }
            let ty = Double(wy(tx))
            if Int(floor(tx)) >= 1 { for x in 1...Int(floor(tx)) { set(x, wy(Double(x))) } }
            for y in 0..<g {
                for x in 0..<g where seg(Double(x), Double(y), tx + 1.1, ty - 1.1, tx + 4.4, ty - 4.4, 1.05) { set(x, y) }
            }
            let px = Int(jsRound(tx)), py = Int(jsRound(ty))
            set(px, py, 2)
            set(px + 1, py - 1, 2)
        case "reply":
            for x in 0...8 { set(x, 1); set(x, 6) }
            for y in 1...6 { set(0, y); set(8, y) }
            set(1, 7); set(2, 7); set(1, 8)
            let f = fr(cl((q - 0.06) / 0.8) * 2) * 4, k = Int(floor(f))
            let shown = min(3, k + (q > 0.06 && q < 0.86 ? 1 : 0))
            if shown > 0 { for i in 0..<shown { let v: UInt8 = i == k ? 2 : 1; set(2 + i * 2, 3, v); set(2 + i * 2, 4, v) } }
        case "transfer":
            let tq = cl((q - 0.04) / 0.8), f = tq * 4, k = min(4, Int(floor(f))), t = f - Double(k)
            let run = tq < 1, sd = run && t < 0.2, dd = run && t > 0.8
            func key(_ x0: Int, _ down: Bool) { let y0 = down ? 8 : 7; rect(x0, y0, x0 + 2, y0 + 1) }
            key(0, sd); key(7, dd)
            let done = min(4, k + (dd ? 1 : 0))
            if done > 0 { for i in 0..<done { set(1 + i * 2, 1); set(2 + i * 2, 1) } }
            if run && t >= 0.2 && t <= 0.8 {
                let u = (t - 0.2) / 0.6
                let px = Int(jsRound(1 + 7 * u)), py = Int(jsRound(5.5 - 4 * u * (1 - u) * 3.2))
                set(px, py, 2); set(px, py + 1, 2)
            }
        case "upload":
            let t = fr(cl((q - 0.04) / 0.84) * 2), tip = Int(jsRound(5 - t * 8)), launch = t < 0.15 && q < 0.9
            for x in 1...8 { set(x, 9, launch ? 2 : 1) }
            for y in 7...9 { set(1, y); set(8, y) }
            func row(_ y: Int, _ x0: Int, _ x1: Int) { if y >= 0, y < 7 { for x in x0...x1 { set(x, y) } } }
            row(tip, 4, 5); row(tip + 1, 3, 6); row(tip + 2, 2, 7); row(tip + 3, 4, 5); row(tip + 4, 4, 5)
        case "wait":
            rect(3, 3, 6, 6); set(6, 2)
            let wv = (q > 0.1 && q < 0.44) || (q > 0.54 && q < 0.86)
            let pose = wv ? [0, 1, 2, 1][Int(floor(q * 28)) % 4] : 1
            let arm = [[(5, 1), (4, 0)], [(6, 1), (6, 0)], [(7, 1), (8, 0)]][pose]
            set(arm[0].0, arm[0].1); set(arm[1].0, arm[1].1, wv ? 2 : 1)
        case "handoff":
            if q < 0.08 { rect(3, 3, 6, 6); break }
            if q < 0.18 { rect(2, 3, 3, 6); rect(6, 3, 7, 6); break }
            if q >= 0.66 { ring(0, 3, 2, 6); rect(7, 3, 9, 6); break }
            let k = q < 0.3 ? 0 : q < 0.62 ? Int(ceil((q - 0.3) / 0.32 * 5)) : 5
            rect(0, 3, 2, 6); ring(7, 3, 9, 6)
            if k > 0 {
                set(1, 4, 0); set(1, 5, 0)
                let x = k < 5 ? Int(jsRound(2 + Double(k) * 1.2)) : 8
                set(x, 4, 2); set(x, 5, 2)
            }
        case "reread":
            rect(2, 1, 7, 8)
            set(7, 1, 0); set(6, 1, 0); set(7, 2, 0); set(6, 2, 2)
            let u = fr(q * 2), y = 2 + min(5, Int(floor(u * 6)))
            for x in 3...6 { set(x, y, u < 0.9 ? 2 : 1) }
        case "duplicate":
            let k = min(3, Int(floor(q * 3.6)))
            if k >= 1 { for c in stride(from: k, through: 1, by: -1) { ring(3 + c, 3 - c, 6 + c, 6 - c, c == k && fr(q * 3.6) < 0.35 ? 2 : 1) } }
            rect(3, 3, 6, 6)
        case "idle":
            if q < 0.12 || q >= 0.66 { rect(3, 3, 6, 6); break }
            if q < 0.16 { rect(3, 3, 6, 6); set(2, 6); set(7, 6); break }
            if q < 0.5 {
                rect(3, 4, 6, 6); set(2, 6); set(7, 6)
                if q > 0.22 && q < 0.34 { set(5, 7) }
                if q > 0.3 && q < 0.4 { set(5, 7); set(5, 8) }
                if q >= 0.4 { set(5, 9) }
                break
            }
            rect(3, 2, 6, 5)
            if q < 0.54 { set(5, 9) } else if q < 0.58 { set(5, 8, 2) }
            else if q < 0.62 { set(5, 7, 2); set(5, 6, 2) }
            else { mk = [UInt8](repeating: 0, count: g * g); rect(3, 3, 6, 6) }
        case "done":
            let check = [(1, 5), (2, 6), (3, 7), (4, 6), (5, 5), (6, 4), (7, 3), (8, 2)]
            let k = min(check.count, Int(ceil(cl(q / 0.5) * Double(check.count))))
            let v: UInt8 = q > 0.65 ? 1 : 2
            if k == 0 { rect(3, 3, 6, 6); break }
            for (x, y) in check.prefix(k) { set(x, y, v); set(x, y + 1, v) }
        case "build":
            let u = cl((q - 0.04) / 0.8), f = u * 4, k = min(4, Int(floor(f))), t = f - Double(k)
            if k > 0 { for i in 0..<k { for x in 3...6 { set(x, 6 - i) } } }
            if k < 4 {
                let kk = min(1, ceil(t * 6) / 6 / 0.85), y = Int(jsRound(Double(6 - k) * kk))
                for x in 3...6 { set(x, y, kk < 1 ? 2 : 1) }
            }
            let gx = Int(jsRound(1 + u * 7))
            for x in 1...8 { set(x, 9, x < gx ? 1 : x == gx ? 2 : 0) }
        case "overload":
            let a = sin(.pi * cl(q / 0.92)), fn = floor(q * 31)
            for y in 0..<g {
                for x in 0..<g {
                    let e = max(abs(Double(x) - 4.5), abs(Double(y) - 4.5)) - 1.5, r = hsh(x, y, fn)
                    if e <= 0 { if !(a > 0.55 && r < (a - 0.55) * 0.7) { set(x, y) } }
                    else if e <= 1 { if r < a * 0.85 { set(x, y, r < a * 0.3 ? 2 : 1) } }
                    else if e <= 2 { if r < a * 0.35 { set(x, y) } }
                    else if r < a * 0.1 { set(x, y, 2) }
                }
            }
            for x in 3...6 {
                let len = Int(floor(a * 4.2 * fr(sin(Double(x) * 91.37) * 4375.5)))
                if len > 0 { for y in 7..<(7 + len) { set(x, y) } }
            }
        case "error":
            let o = q < 0.15 ? 0 : q < 0.3 ? 1 : q < 0.6 ? 2 : q < 0.75 ? 1 : 0
            let sh = q > 0.3 && q < 0.6 ? [0, 1, 0, -1][Int(floor(q * 40)) % 4] : 0
            let jag = [0, 1, 0, 1], up = (o + 1) / 2, down = o / 2
            for r in 0..<4 {
                let y = 3 + r, cut = 4 + jag[r]
                for x in 3...6 { set((x <= cut ? x - up : x + down + (o > 0 ? 1 : 0)) + sh, y) }
                if o > 0 {
                    for k in 0..<o {
                        let gx = cut + 1 - up + k + sh
                        if gx >= 0, gx < g, mk[y * g + gx] == 0 { mk[y * g + gx] = 2 }
                    }
                }
            }
        default:
            return nil      // think はメタボールで描く
        }
        return mk
    }
}

// MARK: - 鶴（メニューボタン＝読み込み表示）

/// 左下の1羽。本体は InkLoader と同じ 4×4 の墨の四角（8×8 升の中央）。
/// 処理中は脚と嘴を畳んで四角に戻り、そのまま InkLoader になる（`FlowParts.js` の Mascot / crane）
struct Mascot: View {
    enum Pose { case idle, one }
    var pitch: CGFloat = 9
    var lookRight = true
    var pose: Pose? = nil
    /// 処理中の状態名。入っている間は畳んで InkLoader になる
    var busy: String? = nil
    var color: Color = Palette.Light.fg
    var accent: Color = Palette.pink

    /// busy が切り替わった時刻。脚は 70ms ごとに 1/4 ずつ畳む／伸ばす
    @State private var changedAt = Date.distantPast
    @State private var start = Date()
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        Ticker(fps: 12) { now in
            let fold = legs(now)
            if busy != nil && fold <= 0 {
                InkLoader(status: busy ?? "think", pitch: pitch, color: color, accent: accent)
                    .offset(x: -pitch, y: -pitch)
                    .frame(width: 8 * pitch, height: 8 * pitch, alignment: .topLeading)
            } else {
                Canvas { ctx, _ in
                    let t = frozen != nil ? 0.5 : now.timeIntervalSince(start)
                    Self.drawCrane(&ctx, t: t, pitch: pitch, legs: fold, lookRight: lookRight,
                                   pose: pose, ink: color, accent: accent)
                }
                .frame(width: 8 * pitch, height: 8 * pitch)
            }
        }
        .frame(width: 8 * pitch, height: 8 * pitch)
        .onChange(of: busy == nil) { changedAt = Date() }
    }

    /// 脚の伸び 0…1。ponytail: 元は InkLoader の1周を待ってから伸ばす。ここは切り替えた瞬間から伸ばす
    private func legs(_ now: Date) -> Double {
        let steps = floor(now.timeIntervalSince(changedAt) / 0.07) * 0.25
        return busy != nil ? max(0, 1 - steps) : min(1, steps)
    }

    // swiftlint:disable:next function_body_length
    nonisolated static func drawCrane(_ ctx: inout GraphicsContext, t: Double, pitch: CGFloat, legs a: Double,
                          lookRight: Bool, pose: Pose?, ink: Color, accent: Color) {
        let p = max(2, pitch.rounded()), s = 8 * p, h = p / 2, q = p / 4
        let lx: CGFloat = lookRight ? 1 : -1, ly: CGFloat = 0
        let dir = lx, A = CGFloat(a)

        func r(_ v: CGFloat) -> CGFloat { CGFloat(jsRound(Double(v))) }
        func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat, _ c: Color? = nil) {
            ctx.fill(Path(CGRect(x: r(x), y: r(y), width: max(1, r(w)), height: max(1, r(hh)))),
                     with: .color(c ?? ink))
        }
        func clear(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat) {
            var c = ctx
            c.blendMode = .clear
            c.fill(Path(CGRect(x: r(x), y: r(y), width: max(1, r(w)), height: max(1, r(hh)))), with: .color(.black))
        }

        var blink = t.truncatingRemainder(dividingBy: 3.7) < 0.12
        if a < 0.5 { blink = true }
        let t7 = t.truncatingRemainder(dividingBy: 7.5)
        enum Act { case idle, one, peck, preen }
        let act: Act = pose.map { $0 == .one ? .one : .idle }
            ?? (t7 > 3 && t7 < 4.4 ? .peck : t7 > 5.2 && t7 < 6.6 ? .preen : t7 > 1.2 && t7 < 2.6 ? .one : .idle)
        let pd = act == .peck && Int(floor((t7 - 3) * 4)) % 3 != 2
        let hop = 0.75 * A - (pd ? 0.5 * A : act == .peck ? 0.25 * A : 0)

        let ox = 2 * p, oy = (2 - hop) * p
        fill(ox, oy, 4 * p, 4 * p)

        // 目は抜くだけ（瞳は描かない）
        let e = r(p * 0.6)
        func hole(_ cx: CGFloat, _ cy: CGFloat, _ bx0: CGFloat, _ by0: CGFloat, _ bx1: CGFloat, _ by1: CGFloat, _ d: CGFloat) {
            let eh = blink ? max(1, r(q / 2)) : e
            let x = min(max(cx - e / 2 + lx * d, bx0), bx1 - e)
            let y = min(max(cy - eh / 2 + ly * d * 0.6, by0), by1 - eh)
            clear(x, y, e, eh)
        }
        let fe = act == .preen ? -dir : dir
        let eyes = fe > 0 ? [ox + 2.4 * p, ox + 3.3 * p] : [ox + 0.7 * p, ox + 1.6 * p]
        if !pd { for cx in eyes { hole(cx, oy + 1.3 * p, ox + q, oy + q, ox + 4 * p - q, oy + 2.5 * p, r(p * 0.35)) } }

        guard A > 0 else { return }
        let front = dir > 0 ? ox + 4 * p : ox
        let by = oy + p + q + ly * q
        let floorY = s - q, len = (floorY - (oy + 4 * p)) * A
        let lg = ox + 2 * p - q / 2 + dir * 0.6 * p, lg2 = ox + 2 * p - q / 2 - dir * 0.6 * p
        func toe(_ x: CGFloat, _ y: CGFloat) { fill(dir > 0 ? x : x - p * A + q, y, p * A, q) }
        func leg(_ x: CGFloat) { fill(x, oy + 4 * p, q, len); toe(x, oy + 4 * p + len - q) }

        if act == .one {
            leg(lg)
            let knee = oy + 4 * p + len * 0.45
            fill(dir > 0 ? lg2 : lg2 - h + q, oy + 4 * p, q, len * 0.45)
            fill(dir > 0 ? lg2 : lg2 - h + q, knee, h + q, q)
        } else {
            leg(lg); leg(lg2)
        }

        let bw = p * A, bh = h
        switch act {
        case .peck where pd:
            let eyh = blink ? max(1, r(q / 2)) : e
            for xx in (dir > 0 ? [ox + 2.5 * p, ox + 3.3 * p] : [ox + 0.7 * p, ox + 1.5 * p]) {
                clear(xx - e / 2, oy + 2.7 * p, e, eyh)
            }
            let bx = dir > 0 ? ox + 4 * p : ox - h
            fill(bx, oy + 3.25 * p, h, h, accent)
            fill(bx + dir * h, oy + 3.25 * p + h, h, h, accent)
            let tip = bx + dir * h
            fill(tip + dir * q, floorY - q, q, q)
            if Int(floor(t * 8)) % 2 == 1 { fill(tip + dir * (h + q), floorY - q, q, q) }
        case .preen:
            let nb: CGFloat = Int(floor(t * 6)) % 2 == 1 ? q : 0
            let bx = dir > 0 ? ox - bw * 0.6 + nb : ox + 4 * p - nb
            fill(bx, oy + 1.8 * p, bw * 0.6, bh, accent)
            clear(dir > 0 ? ox : ox + 4 * p - q, oy + 2.3 * p, q, h)
        default:
            fill(dir > 0 ? front : front - bw, by, bw, bh, accent)
        }
        // 尾
        let tx = dir > 0 ? ox - h * A : ox + 4 * p
        fill(tx, oy + 2.5 * p, h * A, p + h)
        fill(dir > 0 ? tx - q * A : tx + h * A, oy + 2.5 * p + h, q * A, h)
    }
}
