import SwiftUI
import AppKit

// MARK: - 見え方を1枚に焼く

/// 画面を開かずに筐体を PNG へ出す。`AT22 --shot <path> [幅 高さ]`。
///
/// **これは検査であって機能ではない。** 引き継ぎ 2026-08-04 §1 が
/// 「見え方を継続的に確かめる手段がまだ無い／同じ失敗が繰り返されている」と書いていた穴を埋める。
/// この筐体で多い壊れ方——半透明を二重に掛けて線が消える、暗い地の上で沈む、
/// 余白の取り違えで区画が重なる——は、どれも組んだ結果を見ないと分からない。
///
/// 動き（墨のローダー・鶴・墨流し・遷移）は時刻で見た目が変わるので、
/// **焼いた瞬間の1コマ**しか写らない。動きそのものはここでは確かめられない。
enum Snapshot {

    /// `AT22 --shot <path> [幅 高さ] [--mode work|structure|memory] [--transcript <jsonl>] [--gate]`。
    ///
    /// **時刻を固定して焼く。** ImageRenderer は TimelineView / ScrollView / TextField の中身を組まないので、
    /// 根に `shotTime` を渡すと、動く部品は全部その1コマを直接組み、会話ログは素の VStack に、
    /// 入力欄は置き字に替わる（`SumiClock` と `Talk.log` を参照）。墨流しは初回の 40 歩を進めた絵になる
    @MainActor
    static func write(to path: String, size: CGSize, mode: CockpitMode = .work,
                      transcript: String? = nil, gate: Bool = false) {
        Palette.registerFonts()
        let cockpit = Cockpit()
        if let transcript { feed(cockpit, from: transcript) }
        if gate { stopOneGate(cockpit) }

        let renderer = ImageRenderer(content:
            CockpitView(cockpit: cockpit, shotTime: Date(), mode: mode)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light))
        // Retina で焼く。1px の罫は等倍だと潰れて「あるのか無いのか」が読めない
        renderer.scale = 2
        emit(renderer, to: path, label: "\(Int(size.width))×\(Int(size.height)) \(mode.rawValue)")
    }

    @MainActor
    private static func emit(_ renderer: ImageRenderer<some View>, to path: String, label: String) {
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("AT22: 焼けなかった\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("AT22: \(path) に \(label) で焼いた")
        } catch {
            FileHandle.standardError.write(Data("AT22: 書けなかった — \(error)\n".utf8))
            exit(1)
        }
    }

    /// 門を1つ立てた状態にする。**門は実際に止まっている時にしか出ない**ので、
    /// 門のカード・上帯の門の札・ACTIONS の WAIT 行の見え方はこれが無いと確かめられない
    @MainActor
    private static func stopOneGate(_ cockpit: Cockpit) {
        let issuer = cockpit.snapshot(now: Date(), mode: .work).chips.first?.id ?? ""
        cockpit.loadGatesForProbe([
            Gate.Request(id: "/probe/gate/g1.md", call: "probe", by: issuer,
                         to: "凡例の検査", risk: "high",
                         issued: Date(timeIntervalSinceNow: -12),
                         instruction: "W6 を起こす：p0-selfcheck に凡例の検査を足す")
        ])
        print("AT22: 門を1つ立てた（\(cockpit.gates.count)件）")
    }

    /// transcript を1行ずつ流し込む。壊れた行は `parse` が空を返すので黙って飛ばす
    @MainActor
    private static func feed(_ cockpit: Cockpit, from path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("AT22: transcript を読めない — \(path)\n".utf8))
            return
        }
        let session = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".jsonl", with: "")
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            cockpit.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: session))
        }
        cockpit.selectedSession = session
        // 記憶DBと門は毎秒の周回が拾うもので、流し込みだけでは空のまま。
        // ここを通さないと壁打ちが「3見出しだけ」に焼けて、実機の見え方を代弁しない。
        //
        // **`housekeeping()` ごと呼んではいけない。** あれは `autoHideIdleAgents` を含むので、
        // 過去の transcript を流し込むとエージェントが軒並み「古い」と判定されて全部畳まれ、
        // 帯が空になる。構造の走査は `Task.detached` なので、どのみち焼く前に返ってこない
        cockpit.refreshMemory()
        cockpit.refreshGates()
        print("AT22: \(path) を流し込んだ")
    }
}
