import SwiftUI

// MARK: - 時刻（--shot で止める）

private struct FrozenTimeKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// `--shot` が焼く1コマの時刻。**入っている間は TimelineView を作らない**——
    /// `ImageRenderer` は TimelineView の中身を組まないので、時刻を外から渡して1枚で描く
    var frozenTime: Date? {
        get { self[FrozenTimeKey.self] }
        set { self[FrozenTimeKey.self] = newValue }
    }
}

/// コマ送りの時計。動く部品はみなこれを通す。
/// `paused` の間は TimelineView が止まるので、隠れている部品は CPU を食わない
struct Ticker<Content: View>: View {
    let fps: Double
    let paused: Bool
    let content: (Date) -> Content
    @Environment(\.frozenTime) private var frozen

    init(fps: Double, paused: Bool = false, @ViewBuilder content: @escaping (Date) -> Content) {
        self.fps = fps
        self.paused = paused
        self.content = content
    }

    var body: some View {
        if let frozen {
            content(frozen)
        } else {
            TimelineView(.animation(minimumInterval: 1 / fps, paused: paused)) { timeline in
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
