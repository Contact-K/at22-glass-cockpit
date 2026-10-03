import SwiftUI
import AppKit

// MARK: - 見え方を1枚に焼く

/// 画面を開かずに PNG へ出す。`AT22 --shot <path> [幅 高さ] [--mode talk|files|spar|review|git|settings] [--tower]`。
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
    static func write(to path: String, size: CGSize, tab: V11Tab = .talk, tower: Bool = false,
                      transcript: String? = nil, gate: Bool = false, approval: Bool = false,
                      workspaces: Bool = false, menu: String? = nil, sheet: String? = nil, review: String? = nil,
                      term: Bool = false, ripple: String? = nil) {
        let cockpit = Cockpit()
        // 空のまま焼くとセッションの選び口しか写らない。実 transcript を1本流し込むと、
        // ACTIONS の行・会話・門まで入った本物の1コマになる
        if let transcript { feed(cockpit, from: transcript) }
        if gate { stopOneGate(cockpit) }
        if workspaces { stockWorkspaces(cockpit) }
        var reviewModel: ReviewModel?
        var filesModel: FilesModel?
        // 実在の worktree を1本だけ管制塔に載せ、その差分を読み込んだ状態で焼く（REVIEW / GIT の見え方）
        if let review, let repo = try? Worktree.root(of: review) {
            cockpit.loadWorkspacesForProbe(projects: [repo], worktrees: [repo: (try? Worktree.list(repo: repo)) ?? []])
            cockpit.liveSessions = [LiveSession(id: "s-review", name: "review", cwd: review, busy: false)]
            cockpit.selectedSession = "s-review"
            let model = ReviewModel()
            model.loadNow(cockpit, path: review)
            reviewModel = model
            let files = FilesModel()
            files.loadNow(root: review, open: model.files.first?.path)
            files.line = 3
            filesModel = files
        }
        // 道具の承認の見え方。実機の can_use_tool の形そのまま（実行されるのは書き換えた方）
        if approval {
            cockpit.loadApprovalsForProbe([Approval(
                id: "probe", session: cockpit.selectedSession ?? "probe", tool: "Bash",
                detail: "Create file at /tmp/at22-spike-file",
                input: #"{"command":"touch /tmp/at22-spike-file","description":"Create file at /tmp/at22-spike-file"}"#,
                at: Date(timeIntervalSinceNow: -8))])
        }

        let renderer = ImageRenderer(content:
            CockpitView(cockpit: cockpit, shot: Date(), shotTab: tab, shotTower: tower, shotMenu: menu, shotSheet: sheet, shotReview: reviewModel, shotFiles: filesModel, shotTerm: term, shotRipple: ripple)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light))
        // Retina で焼く。1px の罫は等倍だと潰れて「あるのか無いのか」が読めない
        renderer.scale = 2
        emit(renderer, to: path, label: "\(Int(size.width))×\(Int(size.height)) \(tower ? "tower" : tab.rawValue)")
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

    /// 管制塔の見本。3つのプロジェクトに、分岐・競走・作成中・失敗・あなた待ちを1つずつ置く
    /// （v11 モックの `V11_SEED` と同じ並び。実機の git と ~/.claude には触らない）
    @MainActor
    private static func stockWorkspaces(_ cockpit: Cockpit) {
        let root = "/Users/me/code"
        func entry(_ repo: String, _ name: String?, branch: String) -> Worktree.Entry {
            Worktree.Entry(path: name.map { "\(root)/\(repo)/.claude/worktrees/\($0)" } ?? "\(root)/\(repo)",
                           head: "a1b2c3d4", branch: branch, isMain: name == nil)
        }
        let layout: [(repo: String, items: [(name: String?, branch: String, base: String?, race: String?)])] = [
            ("AT22", [(nil, "dev", nil, nil), ("legend-fix", "at22/legend-fix", "dev", nil),
                      ("legend-tooltip", "at22/legend-tooltip", "at22/legend-fix", nil),
                      ("legend-check", "at22/legend-check", "at22/legend-fix", nil),
                      ("ctx-meter-claude", "at22/ctx-meter-claude", "dev", "競走 dev ctx"),
                      ("ctx-meter-grok", "at22/ctx-meter-grok", "dev", "競走 dev ctx"),
                      ("gate-card", "at22/gate-card", "dev", nil), ("review-tab", "at22/review-tab", "dev", nil),
                      ("old-spike", "at22/old-spike", "dev", nil)]),
            ("ink-sim", [(nil, "main", nil, nil), ("metal-port", "ink/metal-port", "main", nil)]),
            ("sumi-site", [(nil, "main", nil, nil), ("hero-depth", "site/hero-depth", "main", nil),
                           ("lp-v5", "site/lp-v5", "main", nil)]),
        ]
        var lists: [String: [Worktree.Entry]] = [:]
        var meta: [String: Cockpit.WorkspaceMeta] = [:]
        for (repo, items) in layout {
            let entries = items.map { entry(repo, $0.name, branch: $0.branch) }
            lists["\(root)/\(repo)"] = entries
            for (e, item) in zip(entries, items) where item.base != nil {
                meta[e.path] = .init(baseRef: item.base!, baseSHA: "a1b2c3d4", parent: item.race, createdAt: Date())
            }
        }
        let fonts = "\(root)/AT22/.claude/worktrees/fonts-bundle"
        let drawer = "\(root)/AT22/.claude/worktrees/term-drawer"
        cockpit.loadWorkspacesForProbe(
            projects: layout.map { "\(root)/\($0.repo)" }, worktrees: lists,
            pending: [fonts: .init(repo: "\(root)/AT22", name: "fonts-bundle", error: "枝 at22/fonts-bundle が既にあります"),
                      drawer: .init(repo: "\(root)/AT22", name: "term-drawer", error: nil)],
            failed: ["s-hero"], backends: ["s-grok": .grok, "s-metal2": .grok], meta: meta)
        // 各ワークスペースに1体ずつ（状態は稼働中 busy・あなた待ち waiting・それ以外は完了/待機）
        let agents: [(id: String, ws: String, busy: Bool, waiting: String?, title: String)] = [
            ("s-c0", "AT22", false, "permission prompt", "W6 を起こすか訊いています"),
            ("s-fix", "AT22/.claude/worktrees/legend-fix", true, nil, "凡例の作り直し"),
            ("s-tip", "AT22/.claude/worktrees/legend-tooltip", true, nil, "凡例の行にホバーで件数"),
            ("s-claude", "AT22/.claude/worktrees/ctx-meter-claude", true, nil, "CTX 計器を 20 目盛りに"),
            ("s-grok", "AT22/.claude/worktrees/ctx-meter-grok", true, nil, "CTX 計器を 20 目盛りに"),
            ("s-gate", "AT22/.claude/worktrees/gate-card", false, "permission prompt", "承認カードを読める形に"),
            ("s-review", "AT22/.claude/worktrees/review-tab", true, nil, "REVIEW タブを作る"),
            ("s-metal", "ink-sim/.claude/worktrees/metal-port", true, nil, "格子を Metal へ"),
            ("s-metal2", "ink-sim/.claude/worktrees/metal-port", false, "permission prompt", "格子を Metal へ"),
            ("s-hero", "sumi-site/.claude/worktrees/hero-depth", false, nil, "ヒーローの深さを 3 段に"),
        ]
        cockpit.liveSessions = agents.map {
            LiveSession(id: $0.id, name: $0.title, cwd: "\(root)/\($0.ws)", busy: $0.busy, waiting: $0.waiting)
        }
        for agent in agents { cockpit.setTitleForProbe(agent.id, agent.title) }
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
