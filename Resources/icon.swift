// AT22 アイコン生成（ターゲット外）
//
// swiftc Resources/icon.swift -o /tmp/at22icon && /tmp/at22icon Resources/AT22.iconset \
//   && iconutil -c icns Resources/AT22.iconset -o Resources/AT22.icns
//
// 外部のデザイン素材に依存しないための繋ぎ。差し替えるときは AT22.icns を置き換えればいい。
// 配色は CockpitCanvas と同じ（live #1D9E75 / flag #EF9F27 / 地は #04342C）。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// アイコンは 16px まで縮む。線を増やすと潰れるので、
// 「上のチップ → 下のセルへビームが落ちて、1つが琥珀」だけに絞る
func draw(into ctx: CGContext, size s: CGFloat) {
    func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: 1)
    }
    let ground = color(0.016, 0.204, 0.173)   // #04342C
    let live   = color(0.114, 0.620, 0.459)   // #1D9E75
    let flag   = color(0.937, 0.624, 0.153)   // #EF9F27
    let pale   = color(0.624, 0.882, 0.796)   // #9FE1CB

    // 角丸の地
    let radius = s * 0.22
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg)
    ctx.setFillColor(ground)
    ctx.fillPath()

    // 上段のチップ（司令塔）
    let chip = CGRect(x: s * 0.17, y: s * 0.66, width: s * 0.40, height: s * 0.16)
    ctx.addPath(CGPath(roundedRect: chip, cornerWidth: s * 0.045, cornerHeight: s * 0.045,
                       transform: nil))
    ctx.setFillColor(pale)
    ctx.fillPath()

    // ビーム：チップから琥珀のセルへ直角に降りる。16px でも消えないよう太めに
    ctx.setStrokeColor(live)
    ctx.setLineWidth(s * 0.075)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: chip.midX, y: chip.minY))
    ctx.addLine(to: CGPoint(x: chip.midX, y: s * 0.545))
    ctx.addLine(to: CGPoint(x: s * 0.70, y: s * 0.545))
    ctx.addLine(to: CGPoint(x: s * 0.70, y: s * 0.44))
    ctx.strokePath()

    // 下段は2枚だけ。行き先が琥珀、もう1枚はアイドル
    let cellH = s * 0.16
    ctx.addPath(CGPath(roundedRect: CGRect(x: s * 0.17, y: s * 0.28, width: s * 0.66, height: cellH),
                       cornerWidth: s * 0.045, cornerHeight: s * 0.045, transform: nil))
    ctx.setFillColor(flag)
    ctx.fillPath()

    ctx.addPath(CGPath(roundedRect: CGRect(x: s * 0.17, y: s * 0.08, width: s * 0.44, height: cellH),
                       cornerWidth: s * 0.045, cornerHeight: s * 0.045, transform: nil))
    ctx.setFillColor(live.copy(alpha: 0.55)!)
    ctx.fillPath()
}

@main
struct IconGen {
    static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "Resources/AT22.iconset"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        // iconutil が要求する組み合わせ。縮小ではなく各サイズで描き直す
        let wanted: [(name: String, px: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]

        for (name, px) in wanted {
            guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { fatalError("描画コンテキストを作れない: \(name)") }
            draw(into: ctx, size: CGFloat(px))

            guard let image = ctx.makeImage() else { fatalError("画像化に失敗: \(name)") }
            let url = URL(fileURLWithPath: out).appendingPathComponent("\(name).png")
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { fatalError("書き出し先を作れない: \(url.path)") }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { fatalError("書き出しに失敗: \(url.path)") }
        }
        print("icon: \(wanted.count) 枚を \(out) に書き出した")
    }
}
