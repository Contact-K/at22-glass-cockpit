import SwiftUI
import CoreGraphics

// MARK: - 金属の肌

/// デザインシステムが画像で持っている3つの質感を、Swift 側で1回だけ描いて焼く。
///
/// DS の素材（`assets/hairline-tile.png` / `spun-disc.png` / `noise-field-white.svg`）は
/// 取り込めなかったので、**同じ作り方を直接書いている**。作り方はどれも DS の注記通り:
///
/// - ヘアライン … 1px の工具目を敷き詰める。**引き伸ばさずに並べる**——
///   伸ばすと筋が部品の大きさに比例して太り、走査線に見える
/// - スピン … 同心の工具目**と**中心から放射する幅広のスペキュラ楔の2つ。
///   同心だけだと年輪に、放射だけだと艶が死ぬ。両方要る
/// - 網点 … 雲をしきい値に通して粒に落とす。**灯りではなく印刷**として出す
///
/// 乱数は固定の種から作る。毎回違う模様になると、止まっている層の描き直し判定
/// （`StillLayer.==`）が効いていても肌だけがちらつく。
///
/// ponytail: 焼く大きさはここの3つの数だけ。粗い／細かいと感じたら動かす。
/// 素材の画像が手に入ったら、`Image(nsImage:)` に差し替えれば呼び出し側は変わらない
enum Texture {

    /// 敷き詰める単位。DS の素材は 640px だが、筋は 1px なので 256 でも継ぎ目は出ない
    static let hairlineTile = 256
    /// スピン円板を焼く大きさ。門のパネル（288pt）を @2x で覆う
    static let spunSize = 576
    /// 網点の雲を焼く大きさ
    static let noiseSize = 512

    // MARK: 焼いたもの（初回に1回だけ作る）

    static let hairline = Image(decorative: makeHairline(), scale: 2)
    static let spun = Image(decorative: makeSpun(), scale: 2)
    static let noiseField = Image(decorative: makeNoiseField(), scale: 2)

    // MARK: 種を固定した乱数

    /// 線形合同法。**質は要らない**（見た目の粒しか作らない）が、
    /// 毎回同じ模様になることは要る
    private struct Seeded {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed | 1 }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
    }

    private static func context(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    // MARK: ヘアライン

    /// 1px の縦筋を敷き詰めた透明なタイル。金属の面に**乗せて**使う。
    /// 明るい筋と暗い筋を混ぜないと、単なる格子に見える
    private static func makeHairline() -> CGImage {
        let n = hairlineTile
        guard let ctx = context(n, n) else { return blank() }
        var rng = Seeded(0x4154_3232)                 // "AT22"

        for x in 0..<n {
            // 3本に1本くらいしか筋を立てない。全部立てると縞になる
            let roll = rng.next()
            guard roll > 0.62 else { continue }
            let lit = rng.next() > 0.5
            // 値幅は一枚あたり10%以内（DS）。白は 5.5%、黒は 7.5% を上限にする
            let alpha = (lit ? 0.055 : 0.075) * (0.35 + rng.next() * 0.65)
            ctx.setFillColor(red: lit ? 1 : 0, green: lit ? 1 : 0, blue: lit ? 1 : 0, alpha: alpha)
            // 筋は途中で切れる。通しで引くと定規の線になる
            var y = 0
            while y < n {
                let run = Int(rng.next() * Double(n) * 0.5) + 8
                if rng.next() > 0.25 {
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: min(run, n - y)))
                }
                y += run
            }
        }
        return ctx.makeImage() ?? blank()
    }

    // MARK: スピン仕上げ

    /// 円板。同心の工具目 ＋ 中心から放射する幅広の艶。門のパネルだけが使う
    private static func makeSpun() -> CGImage {
        let n = spunSize
        guard let ctx = context(n, n) else { return blank() }
        let c = CGPoint(x: Double(n) / 2, y: Double(n) / 2)
        let maxR = Double(n) * 0.75
        var rng = Seeded(0x5350_554E)                 // "SPUN"

        // 地。明るい面なので銀色から始める
        ctx.setFillColor(red: 0.78, green: 0.79, blue: 0.785, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))

        // 放射する艶。**これが無いと年輪にしか見えない**。楔を12枚、幅を散らして重ねる
        for i in 0..<12 {
            let angle = Double(i) / 12 * .pi * 2 + rng.next() * 0.2
            let spread = 0.10 + rng.next() * 0.16
            let lit = i % 2 == 0
            ctx.saveGState()
            ctx.beginPath()
            ctx.move(to: c)
            ctx.addArc(center: c, radius: maxR, startAngle: angle - spread,
                       endAngle: angle + spread, clockwise: false)
            ctx.closePath()
            ctx.clip()
            ctx.setFillColor(red: lit ? 1 : 0, green: lit ? 1 : 0, blue: lit ? 1 : 0,
                             alpha: lit ? 0.10 : 0.055)
            ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
            ctx.restoreGState()
        }

        // 同心の工具目。半径ごとに1本、途切れさせながら
        ctx.setLineWidth(1)
        var r = 3.0
        while r < maxR {
            let lit = rng.next() > 0.5
            ctx.setStrokeColor(red: lit ? 1 : 0, green: lit ? 1 : 0, blue: lit ? 1 : 0,
                               alpha: (lit ? 0.05 : 0.06) * (0.3 + rng.next() * 0.7))
            let start = rng.next() * .pi * 2
            let sweep = (0.5 + rng.next() * 1.4) * .pi
            ctx.beginPath()
            ctx.addArc(center: c, radius: r, startAngle: start, endAngle: start + sweep, clockwise: false)
            ctx.strokePath()
            r += 1 + rng.next() * 1.4
        }

        // 縁の陰り。これが無いと平らな円に見える
        if let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                                              CGColor(red: 0, green: 0, blue: 0, alpha: 0.16)] as CFArray,
                                     locations: [0.55, 1.0]) {
            ctx.drawRadialGradient(vignette, startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: maxR, options: [])
        }
        return ctx.makeImage() ?? blank()
    }

    // MARK: 網点の雲

    /// 大きくぼやけた雲を、しきい値で粒に落としたもの。**階調ではなく粒**。
    /// 画面の隅にごく薄く敷いて、平らな黒に空気を入れる役
    private static func makeNoiseField() -> CGImage {
        let n = noiseSize
        guard let ctx = context(n, n) else { return blank() }
        var rng = Seeded(0x4E4F_4953)                 // "NOIS"

        // 雲。大きい円をたくさん重ねて、なだらかな濃淡を作る
        var field = [Double](repeating: 0, count: n * n)
        for _ in 0..<38 {
            let cx = rng.next() * Double(n)
            let cy = rng.next() * Double(n)
            let radius = Double(n) * (0.12 + rng.next() * 0.28)
            let weight = 0.4 + rng.next() * 0.6
            let r2 = radius * radius
            let x0 = max(0, Int(cx - radius)), x1 = min(n - 1, Int(cx + radius))
            let y0 = max(0, Int(cy - radius)), y1 = min(n - 1, Int(cy + radius))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    let d2 = dx * dx + dy * dy
                    guard d2 < r2 else { continue }
                    // なだらかに落とす（1 - d²/r²）²
                    let f = 1 - d2 / r2
                    field[y * n + x] += f * f * weight
                }
            }
        }

        // しきい値で粒に落とす。**ここが「印刷であって灯りではない」の実体**
        let peak = field.max() ?? 1
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        for y in 0..<n {
            for x in 0..<n {
                let v = field[y * n + x] / max(peak, 0.0001)
                // 濃いところほど粒が立ちやすい。乱数と比べるので網点になる
                if v > 0.12, rng.next() < v * 0.5 {
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return ctx.makeImage() ?? blank()
    }

    private static func blank() -> CGImage {
        let ctx = context(1, 1)!
        return ctx.makeImage()!
    }
}
