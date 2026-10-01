import SwiftUI
import AppKit
import CoreText

// MARK: - Sumi のトークン

/// Sumi v10 の色・余白・書体。**青 #1212EE × 白 の2色**、深紺は第3の面、差し色はピンク1色だけ。
///
/// 規律（`docs/design/sumi-v10/README.md`）:
/// - 角丸はすべて 0、影は無し。区切りは 1px の罫と明度差。強調は実線、従属は破線
/// - 英語が主・日本語が従。見出しは Fraunces、和文は DotGothic16。青柳衡山T は節番号の横の 14px だけ
/// - ラベルと数値は Departure Mono の大文字＋字送り .14em
enum Palette {

    // 基本の3色と差し色
    static let blue = Color(hex: 0x1212EE)
    static let navy = Color(hex: 0x08085C)
    static let pink = Color(hex: 0xFF3DCC)
    static let white = Color.white

    /// 白地（`data-surface="light"`）のスコープ。アプリの主な面
    enum Light {
        static let fg = Color(hex: 0x1212EE)
        static let fg2 = Color(hex: 0x4A4AE0)
        static let fg3 = Color(hex: 0x8E8EEA)
        static let line = Color(hex: 0xC9C9FF)
        static let bg2 = Color(hex: 0xF5F5FF)
        static let bg3 = Color(hex: 0xECECFF)
        /// 行のホバー（v10 の `#E8E8FF`）
        static let hover = Color(hex: 0xE8E8FF)
        /// CTX の空き升（v10 の `#E0E0FF`）
        static let empty = Color(hex: 0xE0E0FF)
        static let accentHover = Color(hex: 0x3030FF)
    }

    /// 青地（`data-surface="blue"`）のスコープ。上下の帯とメニュー
    enum OnBlue {
        static let fg2 = Color(hex: 0xD9D9FF)
        static let fg3 = Color(hex: 0xA3A3FF)
        /// 罫。半透明なので、上から `.opacity` を重ねない（二重に薄まる）
        static let line = Color.white.opacity(0.38)
        /// 下層・沈んだ字（v10 の `#7C7CE0`）
        static let deep = Color(hex: 0x7C7CE0)
    }

    /// メニューの深さごとの面の色。下層ほど深くなる
    static let depth: [Color] = [Color(hex: 0x1212EE), Color(hex: 0x0C0CA0), Color(hex: 0x08085C)]

    /// 状態の色（白地）。**面積は常に小さく**
    static let success = Color(hex: 0x0C8F55)
    static let warning = Color(hex: 0xA8720F)
    static let danger = Color(hex: 0xD12E2E)

    /// モーダルの幕。透過はここだけ（`rgba(8,8,92,.8)`）
    static let veil = Color(hex: 0x08085C).opacity(0.8)

    /// 余白。4–96 の固定段
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

    /// 18°。斜め板・矢羽・メニューの線はすべてこの角度
    static let slant: CGFloat = tan(18 * .pi / 180)

    // MARK: 書体

    /// 書体ごとの在り処。登録後に引けた名前を使い、引けなければ代わりに落とす
    @MainActor private static var resolved: [String: String] = [:]

    /// Departure Mono。ラベル・数値（字送りは呼び出し側の `.tracking`）
    @MainActor static func mono(_ size: CGFloat) -> Font {
        custom(["Departure Mono", "DepartureMono-Regular"], size: size)
            ?? .system(size: size, design: .monospaced)
    }

    /// Fraunces。英語の大見出し
    @MainActor static func display(_ size: CGFloat) -> Font {
        custom(["Fraunces", "Fraunces-Regular"], size: size)
            ?? .system(size: size, design: .serif)
    }

    /// 青柳衡山T。節番号の横の小さな和文ラベルだけ。無い間は游明朝へ落ちる
    @MainActor static func brush(_ size: CGFloat) -> Font {
        custom(["AoyagiKouzanT", "Aoyagi Kouzan T", "AoyagiKouzanFontT", "YuMincho", "Hiragino Mincho ProN"],
               size: size) ?? .system(size: size, design: .serif)
    }

    /// DotGothic16。和文の本文
    @MainActor static func bodyJP(_ size: CGFloat) -> Font {
        custom(["DotGothic16", "DotGothic16-Regular"], size: size)
            ?? .system(size: size)
    }

    @MainActor private static func custom(_ names: [String], size: CGFloat) -> Font? {
        let key = names[0]
        if resolved[key] == nil {
            resolved[key] = names.first { NSFont(name: $0, size: 12) != nil } ?? ""
        }
        guard let name = resolved[key], !name.isEmpty else { return nil }
        return .custom(name, fixedSize: size)
    }

    /// 起動時に `Resources/Fonts` の書体をこのプロセスへ登録する。
    ///
    /// 探す順: .app の `Contents/Resources/Fonts`（package.sh がコピーする）→
    /// このファイルから辿ったリポジトリの `Resources/Fonts`（`swift run` 用）。
    /// SwiftPM の `resources:` は使わない——手組みの .app と署名が面倒になる。
    /// 無いファイルは黙って飛ばす（青柳は人が後から置く）。引けない書体は `custom` が代わりに落とす
    @MainActor static func registerFonts(filePath: String = #filePath) {
        let fromBundle = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        let fromSource = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Fonts")
        let manager = FileManager.default
        guard let dir = [fromBundle, fromSource].compactMap({ $0 })
            .first(where: { manager.fileExists(atPath: $0.path) }) else { return }
        let files = (try? manager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where ["otf", "ttf"].contains(url.pathExtension.lowercased()) {
            // 二重登録（swift run を繰り返した時など）のエラーは無視してよい
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        resolved = [:]
    }
}

extension Color {
    /// `0x1212EE` の形で書く。トークン表と同じ見た目で並べるため
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension View {
    /// ラベルの型: Departure Mono ＋ 字送り（既定 .14em）。大文字は呼び出し側で書く
    @MainActor func caps(_ size: CGFloat, tracking: CGFloat = 0.14) -> some View {
        font(Palette.mono(size)).tracking(size * tracking)
    }
}
