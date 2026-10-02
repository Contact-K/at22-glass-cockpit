import SwiftUI
import AppKit
import CoreText

// MARK: - Sumi v10 のトークン

/// SUMI_ デザインシステムの値。`docs/design/sumi-v10/tokens/*.css` をそのまま写してある。
///
/// 規律（`docs/design/sumi-v10/README.md`）:
/// - 色は**青 × 白**の2色。深紺は第3の面。差し色は**ピンク1色だけ**、面積は常に小さく
/// - 角丸は**すべて 0**、影は**なし**。区切りは 1px 罫線と明度差
/// - 動きは 100–200ms、`steps(3)` 等のコマ送り。バウンス・ぼかし・透過は使わない
///   （モーダルの幕 `rgba(8,8,92,.8)` だけが例外）
///
/// `Cockpit` など p0 が食うファイルからは参照しないこと（あちらは SwiftUI 抜き）
enum Palette {

    // 基本の3色＋差し色
    static let blue = Color(hex: 0x1212EE)
    static let navy = Color(hex: 0x08085C)
    static let pink = Color(hex: 0xFF3DCC)
    static let white = Color.white
    /// 下層メニューの面。`DEPTH = ['#1212EE', '#0C0CA0', '#08085C']`
    static let depth = [blue, Color(hex: 0x0C0CA0), navy]
    /// モーダルの幕。**透過はここだけ**
    static let scrim = navy.opacity(0.8)
    /// 行のホバー（`#E8E8FF`）
    static let hover = Color(hex: 0xE8E8FF)
    /// CTX の空き升（`#E0E0FF`）
    static let ctxEmpty = Color(hex: 0xE0E0FF)

    /// 白地・青インク。**アプリのメイン領域**（`data-surface="light"`）
    enum Light {
        static let bg = Color.white
        static let bg2 = Color(hex: 0xF5F5FF)
        static let bg3 = Color(hex: 0xECECFF)
        static let fg = Color(hex: 0x1212EE)
        static let fg2 = Color(hex: 0x4A4AE0)
        static let fg3 = Color(hex: 0x8E8EEA)
        static let line = Color(hex: 0xC9C9FF)
        static let success = Color(hex: 0x0C8F55)
        static let warning = Color(hex: 0xA8720F)
        static let danger = Color(hex: 0xD12E2E)
    }

    /// 青地・白インク。帯とパネル（`data-surface="blue"`）
    enum Blue {
        static let bg = Color(hex: 0x1212EE)
        static let bg2 = Color(hex: 0x1E1EF4)
        static let bg3 = Color(hex: 0x2C2CFF)
        static let fg = Color.white
        static let fg2 = Color(hex: 0xD9D9FF)
        static let fg3 = Color(hex: 0xA3A3FF)
        static let line = Color.white.opacity(0.38)
        /// 深紺の fg3。下帯の破線・沈んだ数字（`#7C7CE0`）
        static let dim = Color(hex: 0x7C7CE0)
        static let success = Color(hex: 0x8CFFBE)
        static let warning = Color(hex: 0xFFD46B)
        static let danger = Color(hex: 0xFF7B7B)
    }

    /// 余白 4–96（`--space-1` … `--space-9`）
    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
        static let s6: CGFloat = 32
        static let s7: CGFloat = 48
        static let s8: CGFloat = 64
        static let s9: CGFloat = 96
    }

    /// 角丸。**全部 0**。`RoundedRectangle` を使わず `Rectangle` で済ませる印として置いておく
    static let radius: CGFloat = 0

    /// 字送り。CSS の em はその場の字の大きさに掛けるので、関数にしてある
    static func caps(_ size: CGFloat) -> CGFloat { size * 0.14 }

    /// 動きの長さ（`--dur-fast` / `--dur-normal`）
    static let fast: Double = 0.1
    static let normal: Double = 0.2
}

extension Color {
    /// `0x1212EE` の形で書く。CSS の値と1対1で突き合わせられるように
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - 書体

/// 書体の登録。**起動時に1回だけ** `CTFontManagerRegisterFontsForURL` で読み込む。
///
/// SwiftPM の `resources:` は使わない——手組みの .app（`package.sh`）に Bundle.module の
/// 置き場が増え、署名の対象も増える。読む場所は2つ:
/// 1. `Bundle.main` の `Resources/Fonts`（配布物。`package.sh` がコピーする）
/// 2. このソースから辿った `Resources/Fonts`（`swift run` 用）
///
/// **無い書体は黙って代わりに落とす。** 青柳衡山T は持ち主が後から手で置くので、
/// 無い間は游明朝で動く
enum SumiFonts {
    /// 実際に登録できたファミリー名。ファイル名ではなく**書体の中に書かれた名前**を採る
    /// （青柳衡山T のファミリー名は置かれるまで分からない）。
    /// ponytail: 起動時に1回だけ書き、以後は読むだけなので `nonisolated(unsafe)` で済ませる。
    /// 実行中に書体を差し替える機能を足すなら、ここを MainActor に閉じ込める
    nonisolated(unsafe) private(set) static var mono: String?
    nonisolated(unsafe) private(set) static var display: String?
    nonisolated(unsafe) private(set) static var brush: String?
    nonisolated(unsafe) private(set) static var bodyJP: String?
    nonisolated(unsafe) private static var registered = false

    @MainActor
    static func register() {
        guard !registered else { return }
        registered = true
        guard let dir = fontsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else {
            FileHandle.standardError.write(Data("AT22: Resources/Fonts が見つからない。代わりの書体で動く\n".utf8))
            return
        }
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            // 二重登録（同じ書体が既に入っている機械）は失敗で返るが、使う分には困らない
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            guard let family = descriptors.first.flatMap({
                CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String
            }) else { continue }
            // ファイル名の頭で役割を決める（軸付きの `Fraunces[SOFT,WONK,opsz,wght].ttf` も拾う）
            let name = url.lastPathComponent
            if name.hasPrefix("DepartureMono") { mono = family }
            else if name.hasPrefix("Fraunces") { display = family }
            else if name.hasPrefix("AoyagiKouzan") { brush = family }
            else if name.hasPrefix("DotGothic16") { bodyJP = family }
        }
    }

    private static func fontsDirectory() -> URL? {
        let manager = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
           manager.fileExists(atPath: bundled.path) { return bundled }
        // Sources/AT22/Palette.swift → リポジトリの根 → Resources/Fonts
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
        return manager.fileExists(atPath: source.path) ? source : nil
    }
}

extension Font {
    /// 欧文の書体に、和文の受け皿を名指しで付ける。付けないと、欧文書体に無い字（かな・漢字）は
    /// OS が選んだ書体（ヒラギノ）に落ちて、ラベルの中の和文だけ別の顔になる。
    /// CSS の `"Departure Mono","DotGothic16"` / `"Fraunces","Aoyagi Kouzan T"` と同じ並び
    private static func cascaded(_ family: String, then fallback: String?, size: CGFloat) -> Font {
        var attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family]
        if let fallback {
            attributes[kCTFontCascadeListAttribute] =
                [CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: fallback] as CFDictionary)]
        }
        return Font(CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil))
    }

    /// ラベル・数値。Departure Mono、和文は DotGothic16（無ければ等幅のシステム書体）
    static func mono(_ size: CGFloat) -> Font {
        SumiFonts.mono.map { cascaded($0, then: SumiFonts.bodyJP, size: size) }
            ?? .system(size: size, design: .monospaced)
    }

    /// 英見出し。Fraunces（無ければセリフのシステム書体）。
    /// **受け皿付き（`cascaded`）にしない**——CTFont から作った Font は `minimumScaleFactor` が
    /// 必要も無いのに字を縮める（門の Allow / Rewrite が 0.6 倍で出た）。見出しは英語だけなので困らない
    static func display(_ size: CGFloat) -> Font {
        SumiFonts.display.map { .custom($0, fixedSize: size) }
            ?? .system(size: size, design: .serif)
    }

    /// 節番号の横の小さな和文ラベル。**青柳衡山T はここだけ**。無い間は游明朝
    static func brush(_ size: CGFloat) -> Font {
        .custom(SumiFonts.brush ?? "YuMincho", fixedSize: size)
    }

    /// 和文の本文。DotGothic16（無ければヒラギノ角ゴ）
    static func bodyJP(_ size: CGFloat) -> Font {
        .custom(SumiFonts.bodyJP ?? "Hiragino Sans", fixedSize: size)
    }
}
