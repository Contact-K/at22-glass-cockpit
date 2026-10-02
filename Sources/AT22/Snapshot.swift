import SwiftUI
import AppKit

// MARK: - 見え方を1枚に焼く

/// 画面を開かずに PNG へ出す。`AT22 --shot <path> [幅 高さ] [--mode work|structure|memory]`。
///
/// **これは検査であって機能ではない。** 組んだ結果を見ないと分からない壊れ方——
/// 区画の重なり、字の溢れ、色の取り違え——を、窓を開く前に1枚で確かめる。
///
/// `ImageRenderer` は `TimelineView` / `ScrollView` / `TextField` の中身を組まない。
/// なので `CockpitView(shot:)` に**固定の時刻**を渡し、時計を回す部品は全部その1コマで描き、
/// 会話のログは素の VStack に、入力欄は文字だけに差し替えて焼く。
/// 動き（墨流し・ドット・InkLoader）は1コマしか写らない
enum Snapshot {

    @MainActor
    static func write(to path: String, size: CGSize, mode: CockpitMode = .work,
                      transcript: String? = nil, gate: Bool = false, approval: Bool = false) {
        let cockpit = Cockpit()
        // 空のまま焼くとセッションの選び口しか写らない。実 transcript を1本流し込むと、
        // ACTIONS の行・会話・門まで入った本物の1コマになる
        if let transcript { feed(cockpit, from: transcript) }
        if gate { stopOneGate(cockpit) }
        // 道具の承認の見え方。実機の can_use_tool の形そのまま（実行されるのは書き換えた方）
        if approval {
            cockpit.loadApprovalsForProbe([Approval(
                id: "probe", session: cockpit.selectedSession ?? "probe", tool: "Bash",
                detail: "Create file at /tmp/at22-spike-file",
                input: #"{"command":"touch /tmp/at22-spike-file","description":"Create file at /tmp/at22-spike-file"}"#,
                at: Date(timeIntervalSinceNow: -8))])
        }

        let renderer = ImageRenderer(content:
            CockpitView(cockpit: cockpit, shot: Date(), shotMode: mode)
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
    /// 門のカードと上帯の札の見え方はこれが無いと確かめられない
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
        // ここを通さないと壁打ちが空に焼けて、実機の見え方を代弁しない。
        //
        // **`housekeeping()` ごと呼んではいけない。** あれは `autoHideIdleAgents` を含むので、
        // 過去の transcript を流し込むとエージェントが軒並み「古い」と判定されて全部畳まれ、
        // ACTIONS が空になる。構造の走査は `Task.detached` なので、どのみち焼く前に返ってこない
        cockpit.refreshMemory()
        cockpit.refreshGates()
        print("AT22: \(path) を流し込んだ")
    }
}
