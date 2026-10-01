import SwiftUI

// MARK: - 時計

// `@Entry` は使わない。マクロの実装は Xcode 側にしか無く、Command Line Tools だけでは展開できない
private struct SumiFixedTimeKey: EnvironmentKey { static let defaultValue: Date? = nil }
private struct SumiPausedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// `--shot` が渡す固定時刻。立っている間は TimelineView を使わずこの1コマだけ組む
    /// （ImageRenderer は TimelineView の中身を組まない）
    var sumiFixedTime: Date? {
        get { self[SumiFixedTimeKey.self] }
        set { self[SumiFixedTimeKey.self] = newValue }
    }
    /// 窓が隠れている間は動きを止める。墨流しもローダーも回し続けない
    var sumiPaused: Bool {
        get { self[SumiPausedKey.self] }
        set { self[SumiPausedKey.self] = newValue }
    }
}

/// コマ送りの時計。動くものは全部これを通す——止める・固定する口が1か所で済む
struct SumiClock<Content: View>: View {
    var fps: Double
    var running: Bool = true
    @ViewBuilder var content: (Date) -> Content

    @Environment(\.sumiFixedTime) private var fixed
    @Environment(\.sumiPaused) private var paused

    var body: some View {
        if let fixed {
            content(fixed)
        } else {
            TimelineView(.animation(minimumInterval: 1 / fps, paused: paused || !running)) { timeline in
                content(timeline.date)
            }
        }
    }
}

/// CSS の `steps(n, jump-start)`。t は 0…1、返りは 1/n 刻み（始まった瞬間に1段目へ跳ぶ）
func steps(_ t: Double, _ n: Int) -> Double {
    if t <= 0 { return 0 }
    if t >= 1 { return 1 }
    return (t * Double(n)).rounded(.up) / Double(n)
}

// MARK: - 斜め板

/// 斜め板・矢羽。v10 の `clip-path` と `skewX(18deg)` をまとめて1つの形にしたもの。
///
/// - `tip`: 右端の尖り（0 なら四角）
/// - `notch`: 左端の切り欠き（上帯の門の札の `10px 50%`）
/// - `skew`: 横の傾き（度）。`anchor` は傾きの原点の高さ（0=上、0.5=中央、1=下）
struct Plate: Shape {
    var tip: CGFloat = 0
    var notch: CGFloat = 0
    var leftTip: CGFloat = 0
    var skew: CGFloat = 0
    var anchor: CGFloat = 0.5

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var pts: [CGPoint] = [
            CGPoint(x: leftTip, y: 0), CGPoint(x: w - tip, y: 0), CGPoint(x: w, y: h / 2),
            CGPoint(x: w - tip, y: h), CGPoint(x: leftTip, y: h),
        ]
        if leftTip > 0 { pts.append(CGPoint(x: 0, y: h / 2)) }
        if notch > 0 { pts.append(CGPoint(x: notch, y: h / 2)) }
        let k = tan(skew * .pi / 180), oy = h * anchor
        var p = Path()
        p.addLines(pts.map { CGPoint(x: r.minX + $0.x + ($0.y - oy) * k, y: r.minY + $0.y) })
        p.closeSubpath()
        return p
    }
}

// MARK: - 飾り

/// 見当（トンボ）。`cross` `target` `star` の3つだけ v10 が使う
struct RegMark: View {
    var kind = "cross"
    var size: CGFloat = 12
    var color: Color = Palette.white

    var body: some View {
        Canvas { ctx, _ in
            let s = size, c = s / 2
            var p = Path()
            p.move(to: CGPoint(x: c, y: 0)); p.addLine(to: CGPoint(x: c, y: s))
            p.move(to: CGPoint(x: 0, y: c)); p.addLine(to: CGPoint(x: s, y: c))
            if kind == "star" {
                p.move(to: CGPoint(x: c * 0.3, y: c * 0.3)); p.addLine(to: CGPoint(x: s - c * 0.3, y: s - c * 0.3))
                p.move(to: CGPoint(x: s - c * 0.3, y: c * 0.3)); p.addLine(to: CGPoint(x: c * 0.3, y: s - c * 0.3))
            }
            if kind == "target" {
                p.addEllipse(in: CGRect(x: c - c * 0.55, y: c - c * 0.55, width: c * 1.1, height: c * 1.1))
            }
            ctx.stroke(p, with: .color(color), lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

/// 値から決まる縞。同じ値なら毎回同じ縞（v10 の線形合同法をそのまま写した）
struct Barcode: View {
    var value: String
    var width: CGFloat = 96
    var height: CGFloat = 20
    var color: Color = Palette.white

    var body: some View {
        Canvas { ctx, _ in
            var s: UInt32 = 0
            for ch in value.unicodeScalars { s = s &* 31 &+ UInt32(truncatingIfNeeded: ch.value) }
            var x: CGFloat = 0
            var p = Path()
            while x < width {
                s = s &* 1_103_515_245 &+ 12_345
                let w = CGFloat(1 + (s >> 16) % 3), gap = CGFloat(1 + (s >> 8) % 2)
                p.addRect(CGRect(x: x, y: 0, width: w, height: height))
                x += w + gap
            }
            ctx.fill(p, with: .color(color))
        }
        .frame(width: width, height: height)
    }
}

/// 星形。`spin` の時だけ 12 秒で1周する
struct Starburst: View {
    var size: CGFloat = 20
    var points = 4
    var inner: CGFloat = 0.18
    var color: Color = Palette.pink
    var fill = true
    var spin = false

    var body: some View {
        if spin {
            SumiClock(fps: 24) { now in
                star.rotationEffect(.degrees(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) * 30))
            }
            .frame(width: size, height: size)
        } else {
            star.frame(width: size, height: size)
        }
    }

    private var star: some View {
        Canvas { ctx, _ in
            let c = size / 2, R = c - 1, r = R * inner, n = points * 2
            var p = Path()
            for i in 0..<n {
                let a = Double(i) / Double(n) * .pi * 2 - .pi / 2
                let rad = i % 2 == 1 ? r : R
                let pt = CGPoint(x: c + cos(a) * rad, y: c + sin(a) * rad)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            if fill { ctx.fill(p, with: .color(color)) }
            ctx.stroke(p, with: .color(color), lineWidth: 1)
        }
    }
}

/// 目盛り。細目は半分の高さ、`major` 本ごとに全高
struct Ruler: View {
    var length: CGFloat
    var step: CGFloat = 6
    var major = 7
    var thickness: CGFloat = 5
    var color: Color = Color.white.opacity(0.45)

    var body: some View {
        Canvas { ctx, _ in
            var p = Path()
            var i = 0
            var x: CGFloat = 0
            while x < length {
                let full = i % major == 0
                p.addRect(CGRect(x: x, y: full ? 0 : thickness / 2, width: 1, height: full ? thickness : thickness / 2))
                x += step; i += 1
            }
            ctx.fill(p, with: .color(color.opacity(0.9)))
        }
        .frame(width: length, height: thickness)
    }
}

/// 波線。`animate` の間だけ位相が流れる
struct WaveLines: View {
    var width: CGFloat = 120
    var height: CGFloat = 24
    var lines = 4
    var amp: CGFloat = 4
    var freq: CGFloat = 2
    var color: Color = Palette.white
    var animate = false

    var body: some View {
        // ponytail: v10 は常に流しているが、何も動いていない時まで 24fps で回さない
        SumiClock(fps: 24, running: animate) { now in
            Canvas { ctx, _ in
                let phase = animate ? now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600) / 0.6 : 0
                for i in 0..<lines {
                    let y0 = (CGFloat(i) + 0.5) * (height / CGFloat(lines))
                    var p = Path()
                    for k in 0...48 {
                        let u = CGFloat(k) / 48
                        let y = y0 + sin(u * .pi * 2 * freq + phase + CGFloat(i) * 0.35) * amp
                        if k == 0 { p.move(to: CGPoint(x: u * width, y: y)) } else { p.addLine(to: CGPoint(x: u * width, y: y)) }
                    }
                    ctx.stroke(p, with: .color(color), lineWidth: 1)
                }
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - ボタン

/// 直角の塊。押下は `translate(1px,1px)`、ホバーは面の色だけ変える
struct SumiButton: View {
    enum Variant { case primary, secondary }
    let title: String
    var variant = Variant.primary
    var disabled = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Palette.mono(11)).tracking(11 * 0.08)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(foreground)
                .background(background)
                .overlay(Rectangle().stroke(variant == .primary ? Palette.blue : Palette.Light.fg, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressNudge())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hover = $0 }
    }

    private var foreground: Color {
        switch variant {
        case .primary: Palette.white
        case .secondary: hover && !disabled ? Palette.white : Palette.Light.fg
        }
    }
    private var background: Color {
        switch variant {
        case .primary: hover && !disabled ? Palette.Light.accentHover : Palette.blue
        case .secondary: hover && !disabled ? Palette.Light.fg : .clear
        }
    }
}

/// 押している間だけ右下へ 1pt ずらす。v10 のボタンの押下はこれだけ
struct PressNudge: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

// MARK: - 墨のローダー

/// 4×4 の墨の四角が状態の絵に崩れて戻る。v10 の `InkLoader`（10×10 格子・24fps のコマ送り）を写した。
/// 使う状態: write search think reply transfer wait reread handoff build upload duplicate error overload done idle
struct InkLoader: View {
    let status: String
    var pitch: CGFloat = 2
    var color: Color = Palette.blue
    var accent: Color = Palette.pink

    @State private var start = Date()

    var body: some View {
        SumiClock(fps: 24) { now in
            Canvas { ctx, _ in
                let cells = Ink.frame(status: status, elapsed: now.timeIntervalSince(start))
                var ink = Path(), pop = Path()
                for (i, v) in cells.enumerated() where v != 0 {
                    let r = CGRect(x: CGFloat(i % 10) * pitch, y: CGFloat(i / 10) * pitch, width: pitch, height: pitch)
                    if v == 2 { pop.addRect(r) } else { ink.addRect(r) }
                }
                ctx.fill(ink, with: .color(color))
                ctx.fill(pop, with: .color(accent))
            }
        }
        .frame(width: pitch * 10, height: pitch * 10)
        .id(status)        // 状態が変わったら四角から描き直す
    }
}

/// ローダーの絵。10×10 の升に 0=空 / 1=墨 / 2=ピンク を返す。
/// v10 の `components/InkLoader.js` の MOTIF と SDF の混ぜ方をそのまま写してある
enum Ink {
    static let period: [String: Double] = [
        "think": 2.6, "search": 2.8, "write": 2.8, "reply": 2.8, "transfer": 3.2, "download": 2.6,
        "upload": 2.6, "delete": 2.6, "connect": 2.8, "error": 2.4, "wait": 3.6, "idle": 6.4,
        "handoff": 3.6, "reread": 3.6, "duplicate": 3.6, "done": 2.2, "build": 3.0, "overload": 2.6,
    ]
    static let alias = ["compile": "build", "test": "build", "get": "download", "doze": "idle"]
    static let G = 10

    static func fr(_ v: Double) -> Double { v - floor(v) }
    static func cl(_ t: Double) -> Double { max(0, min(1, t)) }
    static func ss(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    /// JS の Math.round（.5 は常に上へ）
    static func jr(_ v: Double) -> Int { Int(floor(v + 0.5)) }

    static func frame(status raw: String, elapsed: Double, fps: Double = 24) -> [UInt8] {
        let st = alias[raw] ?? raw
        let T = period[st] ?? 2.6
        let tq = floor(max(0, elapsed) * fps) / fps
        let once = st == "done", nomorph = st == "idle"
        var p: Double
        if once {
            p = cl(tq / T)
            if p >= 1 { return drawMask(motif(st, 0) ?? [], w: 0) }
        } else {
            p = fr(tq / T)
        }
        let w: Double = nomorph ? 1 : p < 0.1 ? 0 : p < 0.22 ? ss((p - 0.1) / 0.12) : p < 0.8 ? 1
            : p < 0.92 ? 1 - ss((p - 0.8) / 0.12) : 0
        let q = nomorph ? p : cl((p - 0.1) / 0.82)
        if let m = motif(st, q) { return drawMask(m, w: w) }
        // 思考だけは絵を持たず、2つの墨玉が分かれて回る
        let sp = sin(.pi * q), a = .pi * q * 2 + .pi / 4, D = 2.1 * sp, r = 2.3 / 2.0.squareRoot() * (1 - 0.12 * sp)
        return drawBlobs([(D * cos(a), D * sin(a), r, false), (-D * cos(a), -D * sin(a), r, true)], w: w)
    }

    private static let m = 4.5, H = 2.0
    private static func sq(_ x: Int, _ y: Int) -> Double {
        (max(abs(Double(x) - m), abs(Double(y) - m)) - H) / (H + 0.5)
    }

    static func drawMask(_ M: [UInt8], w: Double) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 100)
        guard M.count == 100 else { return out }
        var lit: [(Int, Int)] = [], un: [(Int, Int)] = []
        for y in 0..<10 { for x in 0..<10 { if M[y * 10 + x] != 0 { lit.append((x, y)) } else { un.append((x, y)) } } }
        for y in 0..<10 {
            for x in 0..<10 {
                let a = M[y * 10 + x]
                var v: Double
                if w >= 1 {
                    v = a != 0 ? -1 : 1
                } else {
                    var d = 1e9
                    for (X, Y) in (a != 0 ? un : lit) {
                        let e = Double((X - x) * (X - x) + (Y - y) * (Y - y))
                        if e < d { d = e }
                    }
                    d = d.squareRoot() - 0.5
                    v = (1 - w) * sq(x, y) + w * (a != 0 ? -d : d) / (H + 0.5)
                }
                if v < 0 { out[y * 10 + x] = w > 0.5 && a == 2 ? 2 : 1 }
            }
        }
        return out
    }

    static func drawBlobs(_ B: [(Double, Double, Double, Bool)], w: Double) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 100)
        for y in 0..<10 {
            for x in 0..<10 {
                let dx = Double(x) - m, dy = Double(y) - m
                var f = 0.0, best = 0.0, bi = 0
                for (i, b) in B.enumerated() {
                    let v = b.2 * b.2 / ((dx - b.0) * (dx - b.0) + (dy - b.1) * (dy - b.1) + 0.01)
                    f += v
                    if v > best { best = v; bi = i }
                }
                let v = (1 - w) * sq(x, y) + w * (1 - f.squareRoot())
                if v < 0 { out[y * 10 + x] = w > 0.5 && B[bi].3 ? 2 : 1 }
            }
        }
        return out
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func motif(_ st: String, _ q: Double) -> [UInt8]? {
        var M = [UInt8](repeating: 0, count: 100)
        func S(_ x: Int, _ y: Int, _ v: UInt8 = 1) { if x >= 0, y >= 0, x < G, y < G { M[y * G + x] = v } }
        func RC(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt8 = 1) {
            for y in y0...y1 { for x in x0...x1 { S(x, y, v) } }
        }
        func RG(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt8 = 1) {
            for x in x0...x1 { S(x, y0, v); S(x, y1, v) }
            for y in y0...y1 { S(x0, y, v); S(x1, y, v) }
        }
        func near(_ x: Int, _ y: Int, _ px: Double, _ py: Double, _ r: Double) -> Bool {
            (Double(x) - px) * (Double(x) - px) + (Double(y) - py) * (Double(y) - py) < r * r
        }
        func seg(_ x: Int, _ y: Int, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ r: Double) -> Bool {
            let vx = bx - ax, vy = by - ay
            let t = cl(((Double(x) - ax) * vx + (Double(y) - ay) * vy) / (vx * vx + vy * vy))
            return near(x, y, ax + vx * t, ay + vy * t, r)
        }
        let TAU = Double.pi * 2
        switch st {
        case "search":
            let a = q * TAU, cx = 3.6 + 1.1 * sin(a), cy = 3.6 + 0.8 * sin(2 * a)
            for y in 0..<G { for x in 0..<G {
                let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
                if abs(d - 2.05) < 0.62 || seg(x, y, cx + 1.9, cy + 1.9, cx + 4.6, cy + 4.6, 0.8) { M[y * G + x] = 1 }
            } }
            let gx = jr(cx - 0.8), gy = jr(cy - 0.8)
            if gx >= 0, gy >= 0 { S(gx, gy, 2) }
        case "write":
            let wq = cl((q - 0.06) / 0.72), tx = 1 + 7 * wq
            func wy(_ x: Double) -> Int { 7 - (jr(x) % 3 == 1 ? 1 : 0) }
            let ty = Double(wy(tx))
            if Int(floor(tx)) >= 1 { for x in 1...Int(floor(tx)) { S(x, wy(Double(x))) } }
            for y in 0..<G { for x in 0..<G where seg(x, y, tx + 1.1, ty - 1.1, tx + 4.4, ty - 4.4, 1.05) { M[y * G + x] = 1 } }
            let px = jr(tx), py = jr(ty)
            S(px, py, 2)
            if px + 1 < G, py - 1 >= 0 { S(px + 1, py - 1, 2) }
        case "reply":
            for x in 0...8 { S(x, 1); S(x, 6) }
            for y in 1...6 { S(0, y); S(8, y) }
            S(1, 7); S(2, 7); S(1, 8)
            let f = fr(cl((q - 0.06) / 0.8) * 2) * 4, n = Int(floor(f))
            let count = min(3, n + (q > 0.06 && q < 0.86 ? 1 : 0))
            if count > 0 { for i in 0..<count { let x = 2 + i * 2; S(x, 3, i == n ? 2 : 1); S(x, 4, i == n ? 2 : 1) } }
        case "transfer":
            let tq = cl((q - 0.04) / 0.8), f = tq * 4, n = min(4, Int(floor(f))), t = f - Double(n)
            let run = tq < 1, sd = run && t < 0.2, dd = run && t > 0.8
            func key(_ x0: Int, _ down: Bool) { let y0 = down ? 8 : 7; RC(x0, y0, x0 + 2, y0 + 1) }
            key(0, sd); key(7, dd)
            let done = min(4, n + (dd ? 1 : 0))
            if done > 0 { for i in 0..<done { S(1 + i * 2, 1); S(2 + i * 2, 1) } }
            if run, t >= 0.2, t <= 0.8 {
                let u = (t - 0.2) / 0.6, px = jr(1 + 7 * u), py = jr(5.5 - 4 * u * (1 - u) * 3.2)
                S(px, py, 2); S(px, py + 1, 2)
            }
        case "download", "upload":
            let up = st == "upload"
            let f = cl((q - 0.04) / 0.84) * 2, t = fr(f)
            let tip = up ? jr(5 - t * 8) : min(7, Int(floor(2 + t * 6.5)))
            let flash = up ? (t < 0.15 && q < 0.9) : (tip >= 7 && q < 0.9)
            for x in 1...8 { S(x, 9, flash ? 2 : 1) }
            for y in 7...9 { S(1, y); S(8, y) }
            func R(_ y: Int, _ x0: Int, _ x1: Int) { if y >= 0, y < (up ? 7 : G) { for x in x0...x1 { S(x, y) } } }
            let s = up ? 1 : -1
            R(tip, 4, 5); R(tip + s, 3, 6); R(tip + 2 * s, 2, 7); R(tip + 3 * s, 4, 5); R(tip + 4 * s, 4, 5)
        case "connect":
            for y in 3...5 { for x in [0, 1, 2, 7, 8, 9] { S(x, y) } }
            let e = cl(q / 0.45), n = Int(floor(e * 4.99))
            if n > 0 { for x in 3..<(3 + n) { S(x, 4) } }
            if e < 1 { S(min(6, 3 + n), 4, 2) } else {
                let u = fr((q - 0.45) / 0.25)
                S(jr(3 + u * 3.99), 4, 2)
                if q > 0.7, Int(floor(q * 16)) % 2 == 0 { S(1, 4, 2); S(8, 4, 2) }
            }
        case "wait":
            RC(3, 3, 6, 6); S(6, 2)
            let wv = (q > 0.1 && q < 0.44) || (q > 0.54 && q < 0.86)
            let pose = wv ? [0, 1, 2, 1][Int(floor(q * 28)) % 4] : 1
            let A = [[(5, 1), (4, 0)], [(6, 1), (6, 0)], [(7, 1), (8, 0)]][pose]
            S(A[0].0, A[0].1); S(A[1].0, A[1].1, wv ? 2 : 1)
        case "handoff":
            if q < 0.08 { RC(3, 3, 6, 6); break }
            if q < 0.18 { RC(2, 3, 3, 6); RC(6, 3, 7, 6); break }
            if q >= 0.66 { RG(0, 3, 2, 6); RC(7, 3, 9, 6); break }
            let k = q < 0.3 ? 0 : q < 0.62 ? Int(((q - 0.3) / 0.32 * 5).rounded(.up)) : 5
            RC(0, 3, 2, 6); RG(7, 3, 9, 6)
            if k > 0 {
                S(1, 4, 0); S(1, 5, 0)
                if k < 5 { let x = jr(2 + Double(k) * 1.2); S(x, 4, 2); S(x, 5, 2) } else { S(8, 4, 2); S(8, 5, 2) }
            }
        case "reread":
            RC(2, 1, 7, 8)
            S(7, 1, 0); S(6, 1, 0); S(7, 2, 0); S(6, 2, 2)
            let u = fr(q * 2), y = 2 + min(5, Int(floor(u * 6)))
            for x in 3...6 { S(x, y, u < 0.9 ? 2 : 1) }
        case "duplicate":
            let n = min(3, Int(floor(q * 3.6)))
            if n >= 1 { for k in stride(from: n, through: 1, by: -1) {
                RG(3 + k, 3 - k, 6 + k, 6 - k, k == n && fr(q * 3.6) < 0.35 ? 2 : 1)
            } }
            RC(3, 3, 6, 6)
        case "idle":
            if q < 0.12 || q >= 0.66 { RC(3, 3, 6, 6); break }
            if q < 0.16 { RC(3, 3, 6, 6); S(2, 6); S(7, 6); break }
            if q < 0.5 {
                RC(3, 4, 6, 6); S(2, 6); S(7, 6)
                if q > 0.22, q < 0.34 { S(5, 7) }
                if q > 0.3, q < 0.4 { S(5, 7); S(5, 8) }
                if q >= 0.4 { S(5, 9) }
                break
            }
            RC(3, 2, 6, 5)
            if q < 0.54 { S(5, 9) } else if q < 0.58 { S(5, 8, 2) } else if q < 0.62 { S(5, 7, 2); S(5, 6, 2) } else {
                M = [UInt8](repeating: 0, count: 100); RC(3, 3, 6, 6)
            }
        case "done":
            let C = [(1, 5), (2, 6), (3, 7), (4, 6), (5, 5), (6, 4), (7, 3), (8, 2)]
            let n = min(C.count, Int((cl(q / 0.5) * Double(C.count)).rounded(.up))), v: UInt8 = q > 0.65 ? 1 : 2
            if n == 0 { RC(3, 3, 6, 6) } else { for k in 0..<n { S(C[k].0, C[k].1, v); S(C[k].0, C[k].1 + 1, v) } }
        case "build":
            let u = cl((q - 0.04) / 0.8), f = u * 4, n = min(4, Int(floor(f))), t = f - Double(n)
            if n > 0 { for i in 0..<n { for x in 3...6 { S(x, 6 - i) } } }
            if n < 4 {
                let ty = Double(6 - n), k = min(1, (t * 6).rounded(.up) / 6 / 0.85), y = jr(ty * k)
                for x in 3...6 { S(x, y, k < 1 ? 2 : 1) }
            }
            let gx = jr(1 + u * 7)
            for x in 1...8 { S(x, 9, x < gx ? 1 : x == gx ? 2 : 0) }
        case "overload":
            let a = sin(.pi * cl(q / 0.92)), fn = floor(q * 31)
            for y in 0..<G { for x in 0..<G {
                let e = max(abs(Double(x) - 4.5), abs(Double(y) - 4.5)) - 1.5
                let r = fr(sin(Double(x) * 12.9898 + Double(y) * 78.233 + fn * 37.719) * 43758.5453)
                if e <= 0 { if !(a > 0.55 && r < (a - 0.55) * 0.7) { S(x, y) } }
                else if e <= 1 { if r < a * 0.85 { S(x, y, r < a * 0.3 ? 2 : 1) } }
                else if e <= 2 { if r < a * 0.35 { S(x, y) } }
                else if r < a * 0.1 { S(x, y, 2) }
            } }
            for x in 3...6 {
                let len = Int(floor(a * 4.2 * fr(sin(Double(x) * 91.37) * 4375.5)))
                if len > 0 { for y in 7..<(7 + len) where y < G { S(x, y) } }
            }
        case "error":
            let o = q < 0.15 ? 0 : q < 0.3 ? 1 : q < 0.6 ? 2 : q < 0.75 ? 1 : 0
            let sh = q > 0.3 && q < 0.6 ? [0, 1, 0, -1][Int(floor(q * 40)) % 4] : 0
            let J = [0, 1, 0, 1]
            for r in 0..<4 {
                let y = 3 + r, cut = 4 + J[r]
                for x in 3...6 {
                    let XX = (x <= cut ? x - (o + 1) / 2 : x + o / 2 + (o > 0 ? 1 : 0)) + sh
                    S(XX, y)
                }
                if o > 0 { for g in 0..<o {
                    let gx = cut + 1 - (o + 1) / 2 + g + sh
                    if gx >= 0, gx < G, M[y * G + gx] == 0 { M[y * G + gx] = 2 }
                } }
            }
        default:
            return nil          // think（墨玉）と未知の状態
        }
        return M
    }
}

// MARK: - 鶴

/// 鶴。メニューボタンであり読み込み表示でもある（左下の1羽だけ）。
/// 処理中は脚と嘴を畳んで四角になり、InkLoader に変わる。終わると 0.6 秒は四角のまま、それから脚を伸ばす。
/// v10 の `Mascot form="crane"` を写した（v10 は pose を常に渡すので、つつく・羽づくろいは出ない）
struct Mascot: View {
    var pitch: CGFloat = 9
    var lookRight = true
    /// `one` で片脚立ち（門の応答待ち）。それ以外は両脚
    var pose = "idle"
    /// 処理中の状態名。nil で鶴に戻る
    var busy: String?
    var color: Color = Palette.blue
    var accent: Color = Palette.pink

    @State private var busySince: Date?
    @State private var freeSince: Date?
    @State private var lastBusy = "think"

    /// 1段 70ms で 1/4 ずつ畳む／伸ばす
    private static let stepTime = 0.07
    private static let hold = 0.6

    var body: some View {
        SumiClock(fps: 15) { now in
            let (k, loader) = phase(now)
            if loader {
                InkLoader(status: busy ?? lastBusy, pitch: pitch, color: color, accent: accent)
                    .frame(width: pitch * 8, height: pitch * 8)
            } else {
                Canvas { ctx, _ in draw(&ctx, t: now.timeIntervalSinceReferenceDate, A: k) }
                    .frame(width: pitch * 8, height: pitch * 8)
            }
        }
        .onChange(of: busy, initial: true) { _, now in
            if let now {
                lastBusy = now
                if busySince == nil { busySince = Date(); freeSince = nil }
            } else if busySince != nil {
                busySince = nil
                freeSince = Date()
            }
        }
    }

    /// (脚の伸び 0…1, ローダーを出すか)
    private func phase(_ now: Date) -> (CGFloat, Bool) {
        if let busySince {
            let k = 1 - floor(now.timeIntervalSince(busySince) / Self.stepTime) * 0.25
            return k <= 0 ? (0, true) : (CGFloat(k), false)
        }
        if let freeSince {
            let e = now.timeIntervalSince(freeSince)
            if e < Self.hold { return (0, true) }
            return (CGFloat(min(1, floor((e - Self.hold) / Self.stepTime) * 0.25)), false)
        }
        return (1, false)
    }

    private func draw(_ ctx: inout GraphicsContext, t: Double, A: CGFloat) {
        let P = pitch, h = P / 2, q = P / 4, S = 8 * P
        let dir: CGFloat = lookRight ? 1 : -1, lx: CGFloat = lookRight ? 1 : -1
        let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.12 || A < 0.5
        let hop = 0.75 * A
        let ox = 2 * P, oy = (2 - hop) * P
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat) -> CGRect {
            CGRect(x: x.rounded(), y: y.rounded(), width: max(1, w.rounded()), height: max(1, hh.rounded()))
        }
        var ink = Path(), pop = Path()
        // 胴。目は抜き（偶奇の塗りで穴にする）
        var torso = Path(R(ox, oy, 4 * P, 4 * P))
        let e = (P * 0.6).rounded(), d = (P * 0.35).rounded()
        let ecx = dir > 0 ? [ox + 2.4 * P, ox + 3.3 * P] : [ox + 0.7 * P, ox + 1.6 * P]
        for cx in ecx {
            let eh = blink ? max(1, (q / 2).rounded()) : e
            let x = min(max(cx - e / 2 + lx * d, ox + q), ox + 4 * P - q - e)
            let y = min(max(oy + 1.3 * P - eh / 2, oy + q), oy + 2.5 * P - eh)
            torso.addRect(R(x, y, e, eh))
        }
        ctx.fill(torso, with: .color(color), style: FillStyle(eoFill: true))

        guard A > 0 else { return }
        let fl = S - q, L = (fl - (oy + 4 * P)) * A
        let lg = ox + 2 * P - q / 2 + dir * 0.6 * P, lg2 = ox + 2 * P - q / 2 - dir * 0.6 * P
        func toe(_ x: CGFloat, _ y: CGFloat) { ink.addRect(R(dir > 0 ? x : x - P * A + q, y, P * A, q)) }
        func leg(_ x: CGFloat) { ink.addRect(R(x, oy + 4 * P, q, L)); toe(x, oy + 4 * P + L - q) }
        leg(lg)
        if pose == "one" {
            let ky = oy + 4 * P + L * 0.45
            ink.addRect(R(dir > 0 ? lg2 : lg2 - h + q, oy + 4 * P, q, L * 0.45))
            ink.addRect(R(dir > 0 ? lg2 : lg2 - h + q, ky, h + q, q))
        } else {
            leg(lg2)
        }
        // 嘴（ピンクはここ1か所）
        let fr = dir > 0 ? ox + 4 * P : ox, by = oy + P + q, bw = P * A
        pop.addRect(R(dir > 0 ? fr : fr - bw, by, bw, h))
        // 尾
        let tx = dir > 0 ? ox - h * A : ox + 4 * P
        ink.addRect(R(tx, oy + 2.5 * P, h * A, P + h))
        ink.addRect(R(dir > 0 ? tx - q * A : tx + h * A, oy + 2.5 * P + h, q * A, h))
        ctx.fill(ink, with: .color(color))
        ctx.fill(pop, with: .color(accent))
    }
}
