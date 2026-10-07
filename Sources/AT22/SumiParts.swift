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
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        // ponytail: `done` も繰り返す（本人の指示。1回きりだと見落とした）。済みの行が数十を越えて重ければ、見えている分だけ回す
        // 済みの行やタイルに数が並ぶ done は半分のコマで回す
        Ticker(fps: status == "done" ? 12 : 24) { now in
            // 焼く時は周期の真ん中（絵がいちばん立っている所）を写す
            let t = frozen != nil ? (Self.period[status] ?? 2.6) * 0.5 : now.timeIntervalSince(start)
            Canvas { ctx, _ in
                Self.draw(&ctx, status: status, t: t, pitch: pitch, ink: color, accent: accent)
            }
        }
        .frame(width: 10 * pitch, height: 10 * pitch)
        .onChange(of: status) { start = Date() }
    }

    /// `done` は描き終えた絵をこの秒数だけ見せてから、また描き始める
    nonisolated static let doneHold = 1.2

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
        // done は描き切って少し止まり、また頭から（1周 = 描く時間 + 止まる時間）
        var p = once ? cl(fr(tq / (period + doneHold)) * (period + doneHold) / period) : fr(tq / period)

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
    /// 見上げる（送り終えた時。v11 の look "u"）。向きは lookRight のまま、目と嘴が上へずれる
    var lookUp = false
    var pose: Pose? = nil
    /// 処理中の状態名。入っている間は畳んで InkLoader になる
    var busy: String? = nil
    var color: Color = Palette.Light.fg
    var accent: Color = Palette.pink

    /// 脚を畳み始めた／伸ばし始める時刻。脚は 70ms ごとに 1/4 ずつ畳む／伸ばす（伸ばす時刻は先のことがある）
    @State private var changedAt = Date.distantPast
    /// InkLoader が頭から回り始めた時刻と、最後の状態名。戻る時はその1周を描き切ってから脚を伸ばす
    @State private var loaderFrom = Date.distantPast
    @State private var lastBusy = "think"
    /// 待機の振り付けの時計。脚を伸ばし始めた所から数え直す（元の Mascot も戻るたびに頭から）
    @State private var start = Date()
    @Environment(\.frozenTime) private var frozen
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // 24fps。12 では 0.12 秒のまばたきが抜け、ついばみの点（8Hz）が不揃いになった（元は描画のたびに描く）
        Ticker(fps: 24) { now in
            let fold = legs(now)
            if fold <= 0 {
                InkLoader(status: busy ?? lastBusy, pitch: pitch, color: color, accent: accent)
                    .offset(x: -pitch, y: -pitch)
                    .frame(width: 8 * pitch, height: 8 * pitch, alignment: .topLeading)
            } else {
                Canvas { ctx, _ in
                    let t = frozen != nil ? 0.5 : max(0, now.timeIntervalSince(start))
                    Self.drawCrane(&ctx, t: t, pitch: pitch, scale: displayScale, legs: fold, lookRight: lookRight,
                                   lookUp: lookUp, pose: pose, ink: color, accent: accent)
                }
                .frame(width: 8 * pitch, height: 8 * pitch)
            }
        }
        .frame(width: 8 * pitch, height: 8 * pitch)
        .onChange(of: busy) { old, new in turn(from: old, to: new, now: Date()) }
    }

    /// 処理中に入る・状態が替わる・抜ける。抜ける時は InkLoader の今の1周の終わりまで待つ（最長 3.4 秒。元の `onLoop` と同じ）
    private func turn(from old: String?, to new: String?, now: Date) {
        if let new {
            lastBusy = new
            if old == nil {
                changedAt = now
                loaderFrom = now.addingTimeInterval(0.28)      // 4 段畳み終えた所から回る
            } else if now >= loaderFrom {
                loaderFrom = now                                // InkLoader は状態が替わると頭から
            }
            return
        }
        var extend = now
        if now >= loaderFrom {
            let period = (InkLoader.period[lastBusy] ?? 2.6) + (lastBusy == "done" ? InkLoader.doneHold : 0)
            let loopEnd = loaderFrom.addingTimeInterval(ceil(now.timeIntervalSince(loaderFrom) / period) * period)
            extend = min(loopEnd, now.addingTimeInterval(3.4))
        }
        changedAt = extend
        start = extend
    }

    /// 脚の伸び 0…1。伸ばし始めが先の間は 0（InkLoader のまま）
    private func legs(_ now: Date) -> Double {
        let steps = floor(now.timeIntervalSince(changedAt) / 0.07) * 0.25
        return busy != nil ? max(0, 1 - steps) : max(0, min(1, steps))
    }

    // swiftlint:disable:next function_body_length
    /// 升は**画面の実ピクセル**で丸める（元の Mascot も devicePixelRatio 倍の canvas に描いて縮める）。
    /// ポイントで丸めると pitch 9 の 1/4 升（2.25pt）が 2pt に潰れて、尾と脚の形が崩れる
    nonisolated static func drawCrane(_ ctx: inout GraphicsContext, t: Double, pitch: CGFloat, scale: CGFloat = 2,
                                      legs a: Double, lookRight: Bool, lookUp: Bool = false, pose: Pose?,
                                      ink: Color, accent: Color) {
        let k = max(1, min(3, scale))
        ctx.scaleBy(x: 1 / k, y: 1 / k)
        let p = max(2, (pitch * k).rounded()), s = 8 * p, h = p / 2, q = p / 4
        // 見上げる時は元の look "u"（lx 0・ly -1）。向き（dir）は前の左右のまま
        let dir: CGFloat = lookRight ? 1 : -1, lx: CGFloat = lookUp ? 0 : dir, ly: CGFloat = lookUp ? -1 : 0
        let A = CGFloat(a)

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

        // 普段は止まっていて、ときどきだけ動く（本人の指示 2026-10-07。元の Mascot は 7.5 秒の決まった周期で回していた）。
        // 時刻を枠に切り、枠ごとの擬似乱数で「動くか・何をするか」を決める。同じ t なら同じ絵（--shot も毎コマも揺れない）
        func roll(_ k: Double, _ salt: Double) -> Double {
            let v = sin(k * 12.9898 + salt * 78.233) * 43758.5453
            return v - floor(v)
        }
        // まばたき: 0.5 秒の枠のうち 8%（平均 6 秒に1回）
        let bk = floor(t / 0.5)
        var blink = roll(bk, 3.1) < 0.08 && t - bk * 0.5 < 0.12
        if a < 0.5 { blink = true }
        // 仕草: 1.8 秒の枠のうち 22%（平均 8 秒に1回）、枠の頭 1.4 秒だけ。片脚・啄む・羽繕いのどれか
        let slot = 1.8, sk = floor(t / slot), into = t - sk * slot
        enum Act { case idle, one, peck, preen }
        let acts: [Act] = [.one, .peck, .preen]
        let act: Act = pose.map { $0 == .one ? .one : .idle }
            ?? (into < 1.4 && roll(sk, 1.7) < 0.22 ? acts[min(2, Int(roll(sk, 5.3) * 3))] : .idle)
        let pd = act == .peck && Int(floor(into * 4)) % 3 != 2
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

// MARK: - 選択のポップオーバー

/// アプリの書体で描く選択肢の板。macOS 標準の Menu は中の文字に独自の書体を当てられず、
/// システムのゴシックで出てしまうので、選ぶ口はこれで揃える
struct SumiPicker<Label: View>: View {
    struct Item: Identifiable {
        let id: String
        let text: String
        let on: Bool
    }
    struct Section: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    let sections: [Section]
    /// (セクション名, 選んだ id)
    let onPick: (String, String) -> Void
    @ViewBuilder let label: () -> Label

    @State private var open = false
    @State private var hover: String?

    var body: some View {
        Button { open.toggle() } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.title).font(.mono(9)).tracking(1.3).foregroundStyle(Palette.Light.fg2)
                            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                        ForEach(section.items) { item in
                            let key = section.title + "/" + item.id
                            HStack(spacing: 10) {
                                Text(item.on ? "■" : "□").font(.mono(11))
                                Text(item.text).font(.mono(12)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .foregroundStyle(hover == key ? Palette.Light.bg : Palette.Light.fg)
                            .background(hover == key ? Palette.Light.fg : .clear)
                            .contentShape(Rectangle())
                            .onHover { hover = $0 ? key : (hover == key ? nil : hover) }
                            .onTapGesture { onPick(section.title, item.id); open = false }
                        }
                    }
                }
                .padding(.bottom, 8)
                .frame(minWidth: 240, alignment: .leading)
                .background(Palette.Light.bg)
            }
    }
}

// MARK: - モデルとエフォート

/// 入力欄の左の「モデル · エフォート ▾」。押すと板が開き、上でモデル（最新の別名・固定の版）、下でエフォートを
/// スライダーで選ぶ（会話・壁打ちの入力欄と新規の既定で共通。Orca と同じく一覧は CLI から取る）。
/// 選び直しは次に送った時から効く（`Cockpit.setModel` / `setEffort` が接続を畳み、--resume で繋ぎ直す）
struct ModelPicker: View {
    let backend: Backend
    let models: [AgentCatalog.Model]
    /// いまのモデル（空なら CLI の既定）・エフォート（空なら既定）
    let model: String
    let effort: String
    let onModel: (String) -> Void
    let onEffort: (String) -> Void
    /// 新しい会話の時だけ: 選べるプロバイダと、選んだ時。会話が始まった後はプロバイダを変えられない
    var backends: [Backend] = []
    var onBackend: ((Backend) -> Void)? = nil
    @Environment(\.frozenTime) private var frozen
    @State private var open = false
    @State private var openEffort = false

    /// 札を2つ: [モデル ▾] [エフォート ▾]。押すとそれぞれの板
    var body: some View {
        let current = models.first { $0.matches(model) }
        let name = current?.label ?? Self.short(model)
        let levels = AgentCatalog.efforts(for: model, in: models)
        let shown = effort.isEmpty ? AgentCatalog.defaultEffort(backend) : effort
        HStack(spacing: 4) {
            chip((backend == .claude && onBackend == nil ? "" : backend.title + " · ") + name + " ▾", open: $open,
                 help: "モデル（次に送った時から）") { board }
            if !levels.isEmpty {
                chip(shown + " ▾", open: $openEffort, help: "エフォート（考える深さ）") {
                    EffortSlider(levels: levels, value: effort, fallback: AgentCatalog.defaultEffort(backend), onChange: onEffort)
                        .padding(14).frame(width: 300).background(Palette.Light.bg)
                }
                // 上げるほど派手に（high で縁が回り、xhigh で滲み、max で火の粉）
                .modifier(EffortAura(rank: levels.count > 1
                    ? Double(levels.firstIndex(of: shown) ?? 0) / Double(levels.count - 1) : 0))
            }
        }
        .fixedSize()
    }

    private func chip<B: View>(_ text: String, open: Binding<Bool>, help: String, @ViewBuilder board: @escaping () -> B) -> some View {
        let label = Text(text).font(.mono(11)).tracking(0.6).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Rectangle().strokeBorder(Palette.Light.line, lineWidth: 1))
            .foregroundStyle(Palette.Light.fg)
        return Group {
            if frozen != nil {
                label
            } else {
                Button { open.wrappedValue.toggle() } label: { label.contentShape(Rectangle()) }
                    .buttonStyle(.plain).help(help)
                    .popover(isPresented: open, arrowEdge: .bottom) { board() }
            }
        }
    }

    /// モデルの板（エフォートは隣の札）
    private var board: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBackend, backends.count > 1 {
                Text("PROVIDER プロバイダ").font(.mono(9)).tracking(1.3).foregroundStyle(Palette.Light.fg2)
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                // 折り返す並び（プロバイダは10前後）
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(backends, id: \.self) { b in
                        Button { onBackend(b) } label: {
                            Text(b.title).font(.mono(11)).lineLimit(1)
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                                .foregroundStyle(b == backend ? Palette.Light.bg : Palette.Light.fg)
                                .background(b == backend ? Palette.Light.fg : .clear)
                                .overlay(Rectangle().strokeBorder(Palette.Light.fg, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                Rectangle().fill(Palette.Light.line).frame(height: 1).padding(.top, 10)
            }
            Text("\(backend.title.uppercased()) // MODEL モデル").font(.mono(9)).tracking(1.3).foregroundStyle(Palette.Light.fg2)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            if onBackend == nil {
                Text("プロバイダは会話ごとに決まる。変えるなら ＋ 新しい会話").font(.bodyJP(10)).foregroundStyle(Palette.Light.fg3)
                    .padding(.horizontal, 14).padding(.bottom, 4)
            }
            ForEach([false, true], id: \.self) { pinned in
                let rows = models.filter { $0.pinned == pinned }
                if !rows.isEmpty {
                    Text(pinned ? "固定の版" : "最新（別名）").font(.bodyJP(10)).foregroundStyle(Palette.Light.fg3)
                        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
                    ForEach(rows) { m in row(m) }
                }
            }
            Color.clear.frame(height: 10)
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: 320, alignment: .leading)
        .background(Palette.Light.bg)
    }

    private func row(_ m: AgentCatalog.Model) -> some View {
        let on = m.matches(model)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(on ? "■" : "□").font(.mono(11))
            VStack(alignment: .leading, spacing: 2) {
                Text(m.label).font(.mono(12))
                if !m.detail.isEmpty { Text(m.detail).font(.bodyJP(10)).foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg2) }
            }
            Spacer(minLength: 0)
            if m.pinned { Text(m.id).font(.mono(9)).foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg3) }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .foregroundStyle(on ? Palette.Light.bg : Palette.Light.fg)
        .background(on ? Palette.Light.fg : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onModel(m.id) }
    }

    /// `claude-opus-5-5-20260901` → `opus-5-5`。空は既定
    static func short(_ model: String) -> String {
        guard !model.isEmpty else { return "default" }
        var m = model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model
        if let r = m.range(of: #"-\d{8}$"#, options: .regularExpression) { m.removeSubrange(r) }
        return m.replacingOccurrences(of: "[1m]", with: "")
    }
}

/// エフォートのスライダー。段はモデルが対応するものだけ（左が軽く、右が深い）。つまみを動かすか目盛りを押す。
/// 空（既定）の間は、既定の段の位置につまみを薄く出す
struct EffortSlider: View {
    let levels: [String]
    let value: String
    let fallback: String
    let onChange: (String) -> Void

    var body: some View {
        let shown = levels.firstIndex(of: value) ?? levels.firstIndex(of: fallback) ?? (levels.count - 1) / 2
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let step = levels.count > 1 ? (geo.size.width - 12) / CGFloat(levels.count - 1) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.Light.line).frame(height: 2).padding(.horizontal, 6)
                    Rectangle().fill(Palette.Light.fg).frame(width: step * CGFloat(shown), height: 2).padding(.leading, 6)
                    ForEach(levels.indices, id: \.self) { i in
                        Rectangle().fill(i <= shown ? Palette.Light.fg : Palette.Light.line)
                            .frame(width: 2, height: 8).offset(x: 5 + step * CGFloat(i))
                    }
                    Rectangle().fill(value.isEmpty ? Palette.Light.fg3 : Palette.Light.fg)
                        .frame(width: 12, height: 18).offset(x: step * CGFloat(shown))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    guard step > 0 else { return }
                    let i = max(0, min(levels.count - 1, Int(((g.location.x - 6) / step).rounded())))
                    if levels[i] != value { onChange(levels[i]) }
                })
            }
            .frame(height: 20)
            HStack(spacing: 0) {
                ForEach(levels.indices, id: \.self) { i in
                    Text(levels[i]).font(.mono(9)).tracking(0.6)
                        .foregroundStyle(i == shown ? Palette.Light.fg : Palette.Light.fg3)
                        .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : i == levels.count - 1 ? .trailing : .center)
                        .onTapGesture { onChange(levels[i]) }
                }
            }
            Text(value.isEmpty ? "既定（\(fallback)）· 動かすと指定" : "指定: \(value)")
                .font(.bodyJP(10)).foregroundStyle(Palette.Light.fg2)
        }
    }
}

/// 入力欄の「／ SKILL」。そのエージェントから見えるスキルを出し、選ぶと呼び名（`/名前` か `$名前`）を差し込む
struct SkillPicker: View {
    let backend: Backend
    let skills: [Skills.Skill]
    let onPick: (String) -> Void
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let list = Skills.visible(skills, to: backend)
        if frozen == nil, !list.isEmpty {
            SumiPicker(sections: Dictionary(grouping: list, by: \.source.label).sorted { $0.key < $1.key }.map { label, items in
                .init(title: label, items: items.map { .init(id: Skills.invocation($0, for: backend), text: $0.name
                    + ($0.plugin.isEmpty ? "" : " · " + $0.plugin), on: false) })
            }, onPick: { _, id in onPick(id + " ") }) {
                Text("／").font(.mono(12)).foregroundStyle(Palette.Light.fg2).padding(.horizontal, 6)
            }
            .help("スキルを呼ぶ（\(list.count) 本）")
        }
    }
}

// MARK: - エフォートの効果

/// エフォートを上げるほど派手に。段は相対（そのモデルの選べる幅の中の位置 0…1）:
/// - 0.5（claude の high）: 墨の縁が回り、桃色に滲み、四角い火の粉が舞う
/// - 0.75（xhigh）: 縁が太く速くなり、地に墨が流れ、青と桃の二重の滲み、火の粉が倍
/// - 1（max）: さらに四角い波紋が外へ広がり、火の粉が尾を引き、札が息をする
/// 動きを減らす設定の時は止める
struct EffortAura: ViewModifier {
    let rank: Double
    @Environment(\.accessibilityReduceMotion) private var still

    func body(content: Content) -> some View {
        if rank < 0.5 {
            content
        } else {
            // Ticker を通す: 窓が隠れた・メニューが覆った時（motionPaused）にも止まる
            Ticker(fps: 24, paused: still) { now in
                let t = now.timeIntervalSinceReferenceDate
                let tier = rank >= 0.99 ? 3 : rank >= 0.75 ? 2 : 1
                let speed = [0, 120.0, 220, 360][tier]
                content
                    // 地に流れる墨（xhigh から）
                    .background {
                        if tier >= 2 {
                            LinearGradient(colors: [Palette.pink.opacity(0), Palette.pink.opacity(tier == 3 ? 0.55 : 0.3),
                                                    Palette.blue.opacity(tier == 3 ? 0.45 : 0.25), Palette.pink.opacity(0)],
                                           startPoint: UnitPoint(x: -1 + (t * 0.8).truncatingRemainder(dividingBy: 3), y: 0),
                                           endPoint: UnitPoint(x: (t * 0.8).truncatingRemainder(dividingBy: 3), y: 1))
                        }
                    }
                    // 回る縁
                    .overlay {
                        Rectangle().strokeBorder(
                            AngularGradient(colors: [Palette.blue, Palette.pink, .white, Palette.pink, Palette.blue],
                                            center: .center, angle: .degrees(t * speed)),
                            lineWidth: [0, 1.75, 3, 4][tier])
                    }
                    .scaleEffect(tier == 3 ? 1 + 0.05 * sin(t * 5) : 1)
                    // 滲み（桃、xhigh から青も重ねる）
                    .shadow(color: Palette.pink.opacity(0.5 + 0.3 * sin(t * 3)), radius: [0, 7, 12, 18][tier])
                    .shadow(color: Palette.blue.opacity(tier >= 2 ? 0.45 + 0.3 * cos(t * 2.3) : 0), radius: tier >= 2 ? 10 : 0)
                    // 波紋（max）
                    .overlay {
                        if tier == 3 {
                            ForEach(0..<3, id: \.self) { i in
                                let p = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                                Rectangle().stroke(i % 2 == 0 ? Palette.pink : Palette.blue, lineWidth: 2 * (1 - p))
                                    .scaleEffect(1 + p * 1.6)
                                    .opacity(1 - p)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    // 火の粉
                    .overlay {
                        Canvas { ctx, size in
                            let count = [0, 10, 20, 34][tier]
                            for i in 0..<count {
                                let trail = tier == 3 ? 4 : 1
                                for k in 0..<trail {
                                    let phase = (t - Double(k) * 0.035) * (1.2 + Double(tier) * 0.5) + Double(i) * 0.63
                                    let reach = Double(tier) * 4 + Double(i % 4) * 3
                                    let x = size.width / 2 + cos(phase) * (size.width / 2 + reach)
                                    let y = size.height / 2 + sin(phase * 1.3) * (size.height / 2 + reach * 0.8)
                                    let s = (2.0 + Double(i % 2) + (tier == 3 ? 1 : 0)) * (1 - Double(k) * 0.2)
                                    let color: Color = i % 5 == 0 ? .white : i % 3 == 0 ? Palette.blue : Palette.pink
                                    ctx.fill(Path(CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)),
                                             with: .color(color.opacity(1 - Double(k) * 0.22)))
                                }
                            }
                        }
                        .padding(-28)
                        .allowsHitTesting(false)
                    }
            }
        }
    }
}
