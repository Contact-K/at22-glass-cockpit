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
/// 動いている層（ビーム・脈打つランプ・虹）は時刻で見た目が変わるので、
/// **焼いた瞬間の1コマ**しか写らない。動きそのものはここでは確かめられない。
enum Snapshot {

    @MainActor
    static func write(to path: String, size: CGSize, transcript: String? = nil, gate: Bool = false,
                      approval: Bool = false) {
        let cockpit = Cockpit()
        // 空のまま焼くと外枠しか写らない。実 transcript を1本流し込むと、
        // エージェントの行・ファイルの格子・門まで入った本物の1コマになる
        if let transcript { feed(cockpit, from: transcript) }
        if gate { stopOneGate(cockpit) }
        // 承認の板の見え方。実機の can_use_tool の形そのまま（実行されるのは書き換えた方）
        if approval {
            cockpit.loadApprovalsForProbe([Approval(
                id: "probe", session: cockpit.selectedSession ?? "probe", tool: "Bash",
                detail: "Create file at /tmp/at22-spike-file",
                input: #"{"command":"touch /tmp/at22-spike-file","description":"Create file at /tmp/at22-spike-file"}"#,
                at: Date(timeIntervalSinceNow: -8))])
        }

        let renderer = ImageRenderer(content:
            CockpitView(cockpit: cockpit)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark))
        // Retina で焼く。1px の縁と工具目は等倍だと潰れて「あるのか無いのか」が読めない
        renderer.scale = 2
        emit(renderer, to: path, label: "\(Int(size.width))×\(Int(size.height))")
    }

    /// ワークスペースの木を焼く。`AT22 --shot <path> --workspaces`。
    /// 状態の印（あなた待ち・作業中・失敗・待機）・作成中・作成失敗・Grok の行を1枚に並べる
    @MainActor
    static func writeWorkspaces(to path: String, height: CGFloat) {
        let cockpit = Cockpit()
        let repo = "/Users/you/AT22_Glass_Cockpit"
        let wt = repo + "/.claude/worktrees/"
        cockpit.loadWorkspacesForProbe(
            projects: [repo],
            worktrees: [repo: [
                Worktree.Entry(path: repo, head: "e0fba49", branch: "dev", isMain: true),
                Worktree.Entry(path: wt + "login-screen", head: "e0fba49", branch: "at22/login-screen", isMain: false),
                Worktree.Entry(path: wt + "api-rate-limit-with-a-very-long-name", head: "e0fba49",
                               branch: "at22/api-rate-limit-with-a-very-long-name", isMain: false),
            ]],
            pending: [wt + "search": .init(repo: repo, name: "search", error: nil),
                      wt + "broken": .init(repo: repo, name: "broken", error: "基点 feature/x が見つからない")],
            failed: ["s-failed"],
            backends: ["s-grok": .grok])
        cockpit.liveSessions = [
            LiveSession(id: "s-main", name: "main", cwd: repo, busy: false),
            LiveSession(id: "s-ask", name: "ask", cwd: wt + "login-screen", busy: false, waiting: "承認待ち"),
            LiveSession(id: "s-work", name: "work", cwd: wt + "login-screen/src", busy: true),
            LiveSession(id: "s-failed", name: "failed", cwd: wt + "api-rate-limit-with-a-very-long-name", busy: false),
            LiveSession(id: "s-grok", name: "grok", cwd: wt + "api-rate-limit-with-a-very-long-name", busy: true),
        ]
        cockpit.selectedSession = "s-work"
        let renderer = ImageRenderer(content:
            WorkspaceSidebar(cockpit: cockpit, onOpen: {}, scrolls: false)
                .frame(height: height)
                .environment(\.colorScheme, .dark))
        renderer.scale = 2
        emit(renderer, to: path, label: "\(Int(WorkspaceSidebar.width))×\(Int(height)) ワークスペース")
    }

    /// 盤面だけを焼く。`AT22 --shot <path> --board [--mode work|structure|memory]`。
    ///
    /// `CockpitView` ごと焼くと**盤面が写らない**——`TimelineView` と `ScrollView` は
    /// `ImageRenderer` の中で中身を組まない。ここは同じ `CockpitCanvas.draw` を
    /// 時刻を固定して直接呼ぶので、行・格子・門・凡例がそのまま出る。
    /// 代わりに外枠は写らないので、外枠は `--shot` の方で見る
    @MainActor
    static func writeBoard(to path: String, size: CGSize, mode: CockpitMode, transcript: String?,
                           gate: Bool = false) {
        let cockpit = Cockpit()
        if let transcript { feed(cockpit, from: transcript) }
        // 門の紙は行の間に立つので、行と重ならないかは盤面側でしか確かめられない
        if gate { stopOneGate(cockpit) }

        let now = Date()
        let snapshot = cockpit.snapshot(now: now, mode: mode)
        let layout = CockpitLayout.compute(snapshot, width: size.width)
        let height = max(size.height, layout.contentHeight)

        let renderer = ImageRenderer(content:
            Canvas { context, canvasSize in
                CockpitCanvas.draw(&context, size: canvasSize, layout: layout,
                                   snapshot: snapshot, now: now, mode: mode,
                                   structure: cockpit.structure, hovered: nil,
                                   layer: .both, steady: now)
            }
            .frame(width: size.width, height: height)
            .background(Palette.field)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        emit(renderer, to: path, label: "\(Int(size.width))×\(Int(height)) 盤面(\(mode.rawValue))")
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
    /// 明るいパネルの見え方（暗い地の上で1枚だけ浮いているか）はこれが無いと確かめられない
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
