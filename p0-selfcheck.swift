// AT22 p0 セルフチェック（ターゲット外・SwiftUI 非依存）
//
// swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift Sources/AT22/CockpitLayout.swift Sources/AT22/Structure.swift Sources/AT22/Memory.swift Sources/AT22/Gate.swift Sources/AT22/Launcher.swift Sources/AT22/Backend.swift Sources/AT22/CodexLauncher.swift Sources/AT22/Snowman.swift Sources/AT22/Category.swift p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
//
// 実 transcript を1本渡すと、そのリプレイ結果も検査する:
//   /tmp/p0check ~/.claude/projects/<slug>/<sessionUUID>.jsonl

import Foundation

@main @MainActor
struct P0SelfCheck {

    static func main() async {
        parseRead()
        parseEditStart()
        parseEditFinish()
        parseWriteCreate()
        ignoreGarbage()
        normalizesPaths()
        shortensDirNames()
        foldsIntoCards()
        flagsRepeatedReference()
        statePrecedence()
        sessionFilter()
        separatesModes()
        clearsIdleAgents()
        ordersCardsMainThenSubThenNotes()
        structureStaysInsideTheSelectedProject()
        beamSurvivesFastTools()
        agentRowsHangFromTheRail()
        gateShowsAsPaperAndRow()
        writeVolumeTicks()
        writeTierStacksDotsUnderlineRainbow()
        flattensMarkdownForOneLine()
        readsMemoryDatabase()
        loadsMemoryDirectory()
        savesOnlyInsideMemory()
        memoryModeShowsProjectAndSessionLevels()
        showsTargetOfBashAndGrep()
        snowmanGrowsWithContext()
        weighsWhatEachTurnCost()
        keepsSubagentSpendOffTheSnowman()
        splitsSpendAcrossAgents()
        clearsDoNotRenormalizeShare()
        readsWhatModelSaid()
        showsWhatTheHumanSaid()
        orchestratorStaysBusyWhileThinking()
        buildsClaudeArguments()
        resumesWithoutMintingANewSession()
        remembersWhoWasCalledAndWhatFor()
        readsStdoutWithoutLying()
        interruptLineStopsWithoutKilling()
        readsPendingGates()
        gateVerdictWritesOnlyInsideMemory()
        approvalLevelDecidesWhatStops()
        stoppedOrderParksOnTheLine()
        hugeStaysRareWhenVolumesTie()
        stillAndLiveLayersSplitTheScreen()
        hugeIsRelative()
        recordsWriteMoment()
        agentHierarchy()
        asyncLaunchIsNotCompletion()
        classifiesBashWork()
        showsWhatAgentIsDoing()
        bashOnlyAgentLooksActive()
        backgroundAgentEndsOnItsOwnTurn()
        roleFallsBackToDescription()
        shortensModelNames()
        laysOutWithoutOverlap()
        longNamesStayInsideCards()
        tailsAppendsAcrossPartialLines()
        initialBudgetPrefersNewest()
        showsWriteHistoryOnDemand()
        buildsRoadmapFromTaskTools()
        roadmapSurvivesClearAndFolds()
        listsEveryTaskIncludingDone()
        readTicksFillTowardFlag()
        clicksResolveToWhatWasDrawn()
        egoViewFramesOneFile()
        cellsKeepTheSameSizeInBothModes()
        classifiesFilesByCategory()
        cellsCarryTheirCategory()
        hoverLightsRelatedFiles()
        buildsDependencyGraphFromSymbols()
        labelsAgentWhenMetaArrivesLate()
        keepsTabForEndedSession()
        buildsMcpWorkerChips()
        chipDetailsListWhatItTouched()
        mcpWorkerSurvivesLongFlight()
        foldsChipsOverTheLimit()
        rowsFitWhenNarrow()
        await listsRecentSessions()
        replayRealTranscriptIfGiven()
        print("p0: ok")
    }

    /// 会話欄を出したまま窓を最小にすると盤面は320前後になる。そこで名前・モデル・バッジが重なっていた
    static func rowsFitWhenNarrow() {
        typealias L = CockpitLayout
        // 行の中で名前が使える幅（ID の右からバッジの手前まで）に、名前とモデル表示が並んで収まること
        for width: CGFloat in [120, 160, 240, 360, 900] {
            let fit = L.fitRow(role: "claude-in-chrome", trailing: "opus-5.5 124 100%",
                               meta: "javascripttool", rowWidth: width)
            let room = width - L.rowIDColumn - L.rowBadgeColumn - 10
            let used = L.textWidth(fit.role) + (fit.trailing.isEmpty ? 0 : L.textWidth(fit.trailing, size: L.badgeFont) + 10)
            assert(used <= max(room, L.textWidth("…")), "幅\(width)で名前とモデルが重なる: \(fit)")
            // いま何をしているか は名前の欄の右から描くので、欄が無ければ出さない
            if width - L.rowIDColumn - L.rowNameColumn - L.rowBadgeColumn < 40 { assert(fit.doing.isEmpty, "幅\(width): \(fit)") }
        }
        // 広ければ今まで通り全部出す
        let wide = L.fitRow(role: "claude-in-chrome", trailing: "MCP 85", meta: "navigate", rowWidth: 900)
        assert(wide == ("claude-in-chrome", "MCP 85", "navigate"), "\(wide)")
    }

    // MARK: パーサ

    /// assistant 行は `agentActivity` と `agentAction` を必ず伴うので、触りの検査では除く
    static func touchEvents(_ line: String, session: String = "x") -> [TranscriptEvent] {
        TranscriptParser.parse(Data(line.utf8), fallbackSession: session).filter {
            switch $0 {
            case .agentActivity, .agentAction: return false
            default: return true
            }
        }
    }

    static let readLine = """
    {"type":"assistant","sessionId":"S1","timestamp":"2026-07-14T05:50:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_R","name":"Read","input":{"file_path":"/p/docs/spec.md"}}]}}
    """

    static let startLine = """
    {"type":"assistant","sessionId":"S1","timestamp":"2026-07-14T05:55:56.426Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_A","name":"Edit","input":{"file_path":"/p/TaskDetailView.swift"}}]}}
    """

    static let finishLine = """
    {"type":"user","sessionId":"S1","timestamp":"2026-07-14T05:55:56.497Z","toolUseResult":{"filePath":"/p/TaskDetailView.swift","structuredPatch":[{"oldStart":118,"oldLines":19,"newStart":118,"newLines":81,"lines":["         }","+    let a = 1","+    let b = 2","-    let c = 3"]}]},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","is_error":false}]}}
    """

    static func parseRead() {
        let events = touchEvents(readLine)
        assert(events.count == 1, "Read が1件拾えること")
        guard case let .touchStarted(id, _, _, path, kind, _) = events[0] else {
            fatalError("touchStarted ではない")
        }
        assert(id == "toolu_R")
        assert(path == "/p/docs/spec.md")
        assert(kind == .read, "Read は参照として扱う")

        // Read の結果は structuredPatch を持たないが、tool_result が来れば閉じられること
        let done = #"{"type":"user","sessionId":"S1","timestamp":"2026-07-14T05:50:01.000Z","toolUseResult":{"type":"text","file":{"filePath":"/p/docs/spec.md","numLines":40,"totalLines":212}},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_R"}]}}"#
        guard case let .touchFinished(fid, added, removed, _) =
                touchEvents(done)[0]
        else { fatalError("Read の結果が閉じられない") }
        assert(fid == "toolu_R" && added == 0 && removed == 0)
    }

    static func parseEditStart() {
        let events = touchEvents(startLine, session: "fallback")
        assert(events.count == 1)
        guard case let .touchStarted(id, session, agent, path, kind, _) = events[0] else {
            fatalError("touchStarted ではない")
        }
        assert(id == "toolu_A")
        assert(session == "S1")
        assert(agent == "S1", "agentId が無い行はセッションIDを代用する")
        assert(path == "/p/TaskDetailView.swift")
        assert(kind == .write)

        // サブエージェントの行は agentId 側が使われる
        let sub = startLine.replacingOccurrences(of: "\"type\":\"assistant\"",
                                                 with: "\"type\":\"assistant\",\"agentId\":\"a1b2\"")
        guard case let .touchStarted(_, _, subAgent, _, _, _) =
                touchEvents(sub, session: "fallback")[0]
        else { fatalError("サブエージェント行が解釈できない") }
        assert(subAgent == "a1b2")
    }

    static func parseEditFinish() {
        let events = touchEvents(finishLine, session: "fallback")
        assert(events.count == 1)
        guard case let .touchFinished(id, added, removed, _) = events[0] else {
            fatalError("touchFinished ではない")
        }
        assert(id == "toolu_A")
        assert(added == 2, "structuredPatch の + 行数 (実際: \(added))")
        assert(removed == 1, "structuredPatch の - 行数 (実際: \(removed))")
    }

    /// Write の新規作成は structuredPatch が空で本文が content にだけ入る
    static func parseWriteCreate() {
        let line = #"{"type":"user","sessionId":"S1","timestamp":"2026-07-30T00:35:12.000Z","toolUseResult":{"type":"create","filePath":"/p/New.swift","content":"a\nb\nc","structuredPatch":[]},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_W"}]}}"#
        guard case let .touchFinished(id, added, removed, _) =
                touchEvents(line)[0]
        else { fatalError("Write の作成結果が解釈できない") }
        assert(id == "toolu_W")
        assert(added == 3, "新規作成は本文の行数を編集量にする (実際: \(added))")
        assert(removed == 0)
    }

    static func ignoreGarbage() {
        assert(TranscriptParser.parse(Data("これは JSON ではない".utf8), fallbackSession: "x").isEmpty)
        assert(TranscriptParser.parse(Data("{}".utf8), fallbackSession: "x").isEmpty)
        // Bash のようにファイルを持たないツールは開始側では拾わない
        let bash = #"{"type":"assistant","sessionId":"S1","timestamp":"2026-07-14T05:55:56.000Z","message":{"content":[{"type":"tool_use","id":"toolu_B","name":"Bash","input":{"command":"ls"}}]}}"#
        assert(touchEvents(bash).isEmpty, "Bash はファイル軸には載せない")
        // toolUseResult が辞書でなくても落ちず、tool_result があれば閉じる側は出る
        let odd = #"{"type":"user","sessionId":"S1","timestamp":"2026-07-14T05:55:56.497Z","toolUseResult":"plain string","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_B"}]}}"#
        let events = touchEvents(odd)
        assert(events.count == 1)
        guard case let .touchFinished(_, a, r, _) = events[0] else { fatalError() }
        assert(a == 0 && r == 0)

        // 完了通知は人間の発言ではない。代わりにサブエージェントを閉じる（実データの形そのまま）
        let notice = #"{"type":"user","sessionId":"S1","timestamp":"2026-09-25T05:35:50.000Z","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>afb28320c3a52218f</task-id>\n<status>completed</status>\n</task-notification>"}}"#
        let noticed = TranscriptParser.parse(Data(notice.utf8), fallbackSession: "x")
        assert(noticed.count == 1, "実際: \(noticed)")
        guard case let .agentEnded(agent, _) = noticed[0] else { fatalError("\(noticed)") }
        assert(agent == "afb28320c3a52218f")
        // 人間が打った行は今まで通り発言になる
        let typed = #"{"type":"user","sessionId":"S1","timestamp":"2026-09-25T05:35:50.000Z","origin":{"kind":"human"},"message":{"role":"user","content":"push して"}}"#
        guard case .said(_, _, "push して", .human, _, _)? = TranscriptParser.parse(Data(typed.utf8), fallbackSession: "x").first
        else { fatalError("人間の発言が落ちた") }
    }

    /// 同じファイルが相対パスと絶対パスの両方で記録されると、
    /// 参照回数が分散してフラグが立たなくなる
    static func normalizesPaths() {
        assert(TranscriptParser.normalize("/a/b.swift", cwd: "/proj") == "/a/b.swift")
        assert(TranscriptParser.normalize("b.swift", cwd: "/proj") == "/proj/b.swift")
        assert(TranscriptParser.normalize("./sub/b.swift", cwd: "/proj") == "/proj/sub/b.swift")
        assert(TranscriptParser.normalize("../b.swift", cwd: "/proj/sub") == "/proj/b.swift")
        assert(TranscriptParser.normalize("/a//b.swift", cwd: nil) == "/a/b.swift")

        // 行の cwd を使って、相対で記録された行と絶対で記録された行が同じファイルに集まること
        let relative = #"{"type":"assistant","sessionId":"S1","cwd":"/proj","timestamp":"2026-07-14T05:50:00.000Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"docs/spec.md"}}]}}"#
        guard case let .touchStarted(_, _, _, path, _, _) =
                touchEvents(relative)[0]
        else { fatalError("相対パスの行が解釈できない") }
        assert(path == "/proj/docs/spec.md", "cwd で絶対化する (実際: \(path))")
    }

    static func shortensDirNames() {
        // 共通部分があれば落とす
        assert(Cockpit.shortDirName("/proj/src/state", strippingPrefix: "/proj") == "src/state")
        // 共通部分が無く階層が深ければ末尾2つだけ残す
        assert(Cockpit.shortDirName("/Users/me/.claude/jobs/abc/tmp", strippingPrefix: "")
               == "…/abc/tmp",
               "実際: \(Cockpit.shortDirName("/Users/me/.claude/jobs/abc/tmp", strippingPrefix: ""))")
        // ちょうど共通部分と一致する場合は自分の名前
        assert(Cockpit.shortDirName("/proj", strippingPrefix: "/proj") == "proj")
    }

    // MARK: 畳み込み

    static func read(_ agent: String, _ path: String, _ id: String, at: Date) -> [TranscriptEvent] {
        [.touchStarted(id: id, session: "S1", agent: agent, path: path, kind: .read, at: at),
         .touchFinished(id: id, added: 0, removed: 0, at: at.addingTimeInterval(0.1))]
    }

    /// ファイルを触らない作業（検索など）を n 回ぶん
    static func work(_ agent: String, _ n: Int, kind: WorkKind = .search,
                     at: Date, model: String = "opus-5") -> [TranscriptEvent] {
        [.agentActivity(agent: agent, session: "S1", model: model, at: at)]
        + (0..<n).map { i in
            .agentAction(id: "work-\(agent)-\(at.timeIntervalSince1970)-\(i)",
                         agent: agent, session: "S1", kind: kind, detail: "grep", at: at)
        }
    }

    static func write(_ agent: String, _ path: String, _ id: String,
                      at: Date, added: Int = 10) -> [TranscriptEvent] {
        [.touchStarted(id: id, session: "S1", agent: agent, path: path, kind: .write, at: at),
         .touchFinished(id: id, added: added, removed: 0, at: at.addingTimeInterval(0.1))]
    }

    static func foldsIntoCards() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        c.apply(read("w1", "/proj/docs/spec.md", "r1", at: t0))
        c.apply(write("w1", "/proj/src/A.swift", "e1", at: t0.addingTimeInterval(10), added: 40))
        c.apply(write("w2", "/proj/src/B.swift", "e2", at: t0.addingTimeInterval(20), added: 5))

        let snap = c.snapshot(now: t0.addingTimeInterval(30), mode: .work)
        assert(snap.cards.count == 2, "docs と src の2カード (実際: \(snap.cards.count))")
        assert(snap.cards.map(\.dir).sorted() == ["docs", "src"],
               "共通の先頭パスは落とす (実際: \(snap.cards.map(\.dir)))")
        assert(snap.chips.count == 2, "エージェント2体")

        let spec = snap.cards.first { $0.dir == "docs" }!.files[0]
        assert(spec.reads == 1 && spec.added == 0)
        let a = snap.cards.first { $0.dir == "src" }!.files.first { $0.name == "A.swift" }!
        assert(a.added == 40, "編集行数が積まれる (実際: \(a.added))")

        // 別プロジェクトの同名ディレクトリは、表示名が同じでも1枚に混ぜない
        let two = Cockpit()
        two.apply(write("w", "/projA/src/X.swift", "x1", at: t0))
        two.apply(write("w", "/projB/src/Y.swift", "y1", at: t0))
        let split = two.snapshot(now: t0.addingTimeInterval(5), mode: .work)
        assert(split.cards.count == 2, "別プロジェクトの src を混ぜない (実際: \(split.cards.count))")
        assert(Set(split.cards.map(\.id)).count == 2, "カードの鍵は絶対パス")
    }

    static func flagsRepeatedReference() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        // 実装ワーカーが仕様書を3回参照して、一度も書いていない
        for i in 0..<3 {
            c.apply(read("worker", "/proj/docs/spec.md", "r\(i)", at: t0.addingTimeInterval(Double(i) * 10)))
        }
        // 別のファイルは2回しか読んでいない
        for i in 0..<2 {
            c.apply(read("worker", "/proj/docs/plan.md", "q\(i)", at: t0.addingTimeInterval(Double(i) * 10)))
        }
        // 自分が書いているファイルは何度読んでもフラグにしない
        for i in 0..<5 {
            c.apply(read("worker", "/proj/src/A.swift", "s\(i)", at: t0.addingTimeInterval(Double(i) * 10)))
        }
        c.apply(write("worker", "/proj/src/A.swift", "w0", at: t0.addingTimeInterval(60)))

        // アルファベット順なら先に来るはずの、フラグを持たないディレクトリ
        c.apply(write("worker", "/proj/aaa/Untouched.swift", "u0", at: t0.addingTimeInterval(70)))

        let snap = c.snapshot(now: t0.addingTimeInterval(600), mode: .work)
        let byName = Dictionary(uniqueKeysWithValues: snap.cards.flatMap(\.files).map { ($0.name, $0) })

        assert(snap.cards.first?.dir == "docs",
               "フラグを持つカードを先頭に寄せる (実際: \(snap.cards.map(\.dir)))")
        assert(snap.cards.first?.files.first?.name == "spec.md",
               "カード内でもフラグ付きを先頭に寄せる")

        assert(byName["spec.md"]?.state == .flagged, "3回参照＋編集ゼロ＝フラグ")
        assert(byName["spec.md"]?.flaggedBy == "worker", "フラグの主語が入る")
        assert(byName["plan.md"]?.state == .idle, "2回ではまだ立たない")
        assert(byName["A.swift"]?.state == .idle, "書いているファイルは何度読んでも立たない")
        assert(snap.flagCount == 1, "フラグ件数 (実際: \(snap.flagCount))")

        // しきい値は外から変えられる
        c.flagReadThreshold = 2
        let loose = c.snapshot(now: t0.addingTimeInterval(600), mode: .work)
        let plan = loose.cards.flatMap(\.files).first { $0.name == "plan.md" }
        assert(plan?.state == .flagged, "しきい値を下げれば立つ")

        // 別のエージェントが1回ずつ読んだだけでは合算しない
        let split = Cockpit()
        for i in 0..<3 {
            split.apply(read("agent\(i)", "/proj/docs/spec.md", "x\(i)", at: t0))
        }
        let s = split.snapshot(now: t0.addingTimeInterval(600), mode: .work)
        assert(s.cards.flatMap(\.files)[0].state == .idle, "エージェントをまたいだ合計では立てない")
        assert(s.cards.flatMap(\.files)[0].reads == 3, "表示上の参照回数は合計でよい")
    }

    static func statePrecedence() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        // 完了していない＝進行中
        c.apply([.touchStarted(id: "r", session: "S1", agent: "a", path: "/p/X.swift", kind: .read, at: t0)])
        assert(c.snapshot(now: t0.addingTimeInterval(5), mode: .work).cards[0].files[0].state == .reading)

        c.apply([.touchStarted(id: "w", session: "S1", agent: "a", path: "/p/X.swift", kind: .write, at: t0)])
        assert(c.snapshot(now: t0.addingTimeInterval(5), mode: .work).cards[0].files[0].state == .writing,
               "書き込み中は読み取り中より強い")

        assert(c.snapshot(now: t0.addingTimeInterval(300), mode: .work).cards[0].files[0].state == .idle,
               "取り残しは進行中のまま固まらない")

        // チップは触っているファイルを指す
        let live = c.snapshot(now: t0.addingTimeInterval(5), mode: .work)
        assert(live.chips[0].busy)
        assert(live.chips[0].target == "/p/X.swift")
        assert(live.chips[0].kind == .write)
    }

    static func sessionFilter() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        c.apply([.touchStarted(id: "a", session: "S1", agent: "a", path: "/p/A.swift", kind: .write, at: t0),
                 .touchStarted(id: "b", session: "S2", agent: "b", path: "/p/B.swift", kind: .write, at: t0)])
        assert(c.snapshot(now: t0, mode: .work).cards.flatMap(\.files).count == 2)
        c.selectedSession = "S2"
        let filtered = c.snapshot(now: t0, mode: .work).cards.flatMap(\.files)
        assert(filtered.count == 1 && filtered[0].name == "B.swift", "セッション絞り込み")
    }

    static func separatesModes() {
        assert(CockpitMode.work.rawValue == "work" && CockpitMode.work.title == "作業")
        assert(CockpitMode.structure.rawValue == "structure" && CockpitMode.structure.title == "構造")
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        c.adopt(Structure.build([
            "/p/src/Touched.swift": "struct TouchedType {}",
            "/p/src/Alpha.swift": "struct AlphaType {}",
            "/p/src/Zeta.swift": "struct ZetaType {}",
        ]))
        c.apply(write("worker", "/p/src/Touched.swift", "w1", at: t0, added: 12))
        c.apply([.taskDeclared(call: "task", session: "S1", subject: "モードを分ける",
                               activeForm: "分離中", detail: "画面を分ける", at: t0),
                 .taskNumbered(call: "task", id: "1")])

        let work = c.snapshot(now: t0.addingTimeInterval(1), mode: .work)
        let workFiles = work.cards.flatMap(\.files)
        assert(workFiles.map(\.id) == ["/p/src/Touched.swift"], "作業画面に未接触ファイルが出た")
        assert(workFiles[0].touched && workFiles[0].added == 12)
        // 進行表はスナップショットではなく `allTasks` が持つ（帯は SwiftUI 側の部品）
        assert(work.chips.count == 1 && c.allTasks(session: "S1").count == 1,
               "作業画面の従来要素が欠けた")

        let structure = c.snapshot(now: t0.addingTimeInterval(1), mode: .structure)
        let structureFiles = structure.cards.flatMap(\.files)
        assert(structure.chips.isEmpty, "構造画面に作業用の帯が残った")
        assert(structureFiles.map(\.id) == [
            "/p/src/Touched.swift", "/p/src/Alpha.swift", "/p/src/Zeta.swift",
        ], "触った順と未接触のパス順が守られていない")
        let untouched = structureFiles.first { $0.id == "/p/src/Alpha.swift" }!
        assert(!untouched.touched && untouched.reads == 0 && untouched.added == 0
               && untouched.removed == 0 && untouched.state == .idle,
               "未接触セルに作業量か状態が混ざった")

        let layout = CockpitLayout.compute(structure, width: 900)
        // 構造画面はエージェントの帯を持たない。空けるのは章見出し（03 構造）と凡例の1行ぶんだけ
        assert(layout.cards[0].rect.minY == CockpitLayout.margin + CockpitLayout.agentHeader,
               "構造画面がチップ帯の高さを取っている (実際: \(layout.cards[0].rect.minY))")
        let first = layout.cards[0].cells[0]
        assert(layout.file(at: CGPoint(x: first.rect.midX, y: first.rect.midY)) == first.cell.id,
               "構造画面のセルをクリックできない")

        // 最終接触が同じでも辞書順に依存せず、パスで安定すること
        let tied = Cockpit()
        tied.adopt(Structure.build([
            "/p/TouchedB.swift": "struct TouchedB {}",
            "/p/TouchedA.swift": "struct TouchedA {}",
        ]))
        tied.apply(write("a", "/p/TouchedB.swift", "tb", at: t0))
        tied.apply(write("a", "/p/TouchedA.swift", "ta", at: t0))
        assert(tied.snapshot(now: t0.addingTimeInterval(10), mode: .structure)
            .cards.flatMap(\.files).map(\.id) == ["/p/TouchedA.swift", "/p/TouchedB.swift"],
            "同着の接触順が安定していない")

        let capped = Cockpit()
        let many = Dictionary(uniqueKeysWithValues: (0..<405).map {
            (String(format: "/p/File%03d.swift", $0), "struct Type\($0) {}")
        })
        capped.adopt(Structure.build(many))
        let cappedFiles = capped.snapshot(now: t0, mode: .structure).cards.flatMap(\.files)
        assert(cappedFiles.count == Cockpit.maxStructureFiles, "構造ファイルの上限が効いていない")
        assert(cappedFiles.first?.id == "/p/File000.swift"
               && cappedFiles.last?.id == "/p/File399.swift",
               "上限でパス順の先頭400件を残していない")

        // セッション絞りとクリアは触りだけを落とし、走査一覧は残す
        c.selectedSession = "S2"
        var filtered = c.snapshot(now: t0.addingTimeInterval(1), mode: .structure)
        assert(filtered.cards.flatMap(\.files).count == 3
               && filtered.cards.flatMap(\.files).allSatisfy { !$0.touched },
               "セッション絞りが走査一覧まで落とした")
        c.selectedSession = nil
        c.clear()
        filtered = c.snapshot(now: .now, mode: .structure)
        assert(filtered.cards.flatMap(\.files).count == 3
               && filtered.cards.flatMap(\.files).allSatisfy { !$0.touched },
               "クリアが走査一覧まで落とした")
    }

    static func clearsIdleAgents() {
        let c = Cockpit()
        let now = Date(timeIntervalSince1970: 5_500_000)
        c.selectedSession = "S1"
        func meta(_ id: String, _ role: String) -> [TranscriptEvent] {
            [.agentMeta(agent: id, session: "S1", role: role, depth: 1, parentCall: "")]
        }
        c.apply(meta("inside", "無音14秒") + meta("outside", "無音15秒")
                + meta("future", "未来") + meta("ended", "終了") + meta("glowing", "光っている"))
        c.apply([.agentActivity(agent: "inside", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(-14.9)),
                 .agentActivity(agent: "outside", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(-15.0)),
                 .agentActivity(agent: "future", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(1)),
                 .agentActivity(agent: "glowing", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(-40))])
        c.apply(write("ended", "/p/Ended.swift", "ended-write", at: now.addingTimeInterval(-30), added: 4))
        c.apply([.agentDone(agent: "ended", session: "S1", role: "", model: "haiku",
                            toolCalls: 1, at: now.addingTimeInterval(-29)),
                 // 未完了の触り。isWorking は偽でも画面では光っているので消してはいけない
                 .touchStarted(id: "unfinished", session: "S1", agent: "glowing",
                               path: "/p/Glowing.swift", kind: .write,
                               at: now.addingTimeInterval(-20))])

        c.clearIdleAgents(now: now)
        var snap = c.snapshot(now: now, mode: .work)
        assert(Set(snap.chips.map(\.id)) == ["inside", "future", "glowing"],
               "無音窓の境界か未来時刻の判定が違う (実際: \(Set(snap.chips.map(\.id))))")
        assert(snap.chips.first { $0.id == "glowing" }?.busy == true,
               "未完了の触りで光っているエージェントを消した")
        assert(snap.cards.flatMap(\.files).count == 2, "エージェントと一緒にファイルを消した")
        assert(c.writeHistory(of: "/p/Ended.swift").first?.role == "終了",
               "隠したエージェントの役割名を失った")

        // 隠した後に「別のエージェントが動いた」だけでは戻らない。
        // 集合＋即時 remove だと、古い行を1件読み直しただけで隠した分がまとめて戻っていた
        c.apply([.agentActivity(agent: "inside", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(2))])
        snap = c.snapshot(now: now.addingTimeInterval(2), mode: .work)
        assert(!snap.chips.contains { $0.id == "outside" }, "他人の活動で隠した分が戻った")

        // 隠した後に本人が動いたら戻る
        c.apply([.agentActivity(agent: "outside", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(3))])
        snap = c.snapshot(now: now.addingTimeInterval(3), mode: .work)
        assert(snap.chips.contains { $0.id == "outside" }, "再開したエージェントが戻らない")

        // 隠す前の時刻の行を後から読んでも戻らない（遡り読みで復活しない）。
        // 無音窓を越えてからでないとそもそも隠れないので、そこまで進めてから押す
        let later = now.addingTimeInterval(3 + Cockpit.activeWindow + 1)
        c.clearIdleAgents(now: later)
        assert(!c.snapshot(now: later, mode: .work).chips.contains { $0.id == "outside" },
               "無音になったのに隠れない")
        c.apply([.agentActivity(agent: "outside", session: "S1", model: "opus-5",
                                at: now.addingTimeInterval(-100))])
        assert(!c.snapshot(now: later, mode: .work).chips.contains { $0.id == "outside" },
               "古い行の読み直しで戻った")

        // 見えていないセッションのエージェントは手動では消さない
        let other = Cockpit()
        other.apply([.agentActivity(agent: "z", session: "S2", model: "opus-5",
                                    at: now.addingTimeInterval(-60))])
        other.selectedSession = "S1"
        other.clearIdleAgents(now: now)
        other.selectedSession = "S2"
        assert(other.snapshot(now: now, mode: .work).chips.map(\.id) == ["z"],
               "見えていないセッションのエージェントまで消した")

        // 放っておいても溜まらない。無音が autoHideAfter を超えたら自動で畳む
        let auto = Cockpit()
        auto.apply([.agentActivity(agent: "old", session: "S1", model: "opus-5",
                                   at: now.addingTimeInterval(-Cockpit.autoHideAfter - 5)),
                    .agentActivity(agent: "recent", session: "S1", model: "opus-5",
                                   at: now.addingTimeInterval(-5))])
        assert(auto.snapshot(now: now, mode: .work).chips.count == 2, "畳む前は2体")
        // housekeeping ではなくこちらを呼ぶ。前者は実機の ~/.claude/sessions を読み、
        // 続けて実プロジェクトを裏で走査するので、検査の結果が動かす機械に左右される
        auto.foldIdleAgents(now: now)
        let left = auto.snapshot(now: now, mode: .work).chips.map(\.id)
        assert(left == ["recent"], "自動で畳めていない (実際: \(left))")

        c.clear()
        assert(c.snapshot(now: .now, mode: .work).chips.isEmpty
               && c.snapshot(now: .now, mode: .work).cards.isEmpty, "クリアの従来動作が変わった")
    }

    /// 構造モードは走査した全ファイルを出すが、走査の根は稼働中セッション全部の cwd。
    /// 絞らないと別プロジェクトが混ざる（実測で Obsidian を開いていると40件流れ込んだ）
    static func structureStaysInsideTheSelectedProject() {
        let c = Cockpit()
        c.liveSessions = [LiveSession(id: "S1", name: "こっち", cwd: "/proj/a", busy: true),
                          LiveSession(id: "S2", name: "あっち", cwd: "/proj/b", busy: true)]
        c.adopt(Structure.build([
            "/proj/a/App.swift":  "struct App {}",
            "/proj/a/Note.md":    "App.swift のこと",
            "/proj/b/Other.swift": "struct Other {}",
        ]))
        let t0 = Date(timeIntervalSince1970: 25_000_000)
        func paths(_ session: String?) -> Set<String> {
            c.selectedSession = session
            return Set(c.snapshot(now: t0, mode: .structure).cards.flatMap(\.files).map(\.id))
        }
        assert(paths("S1") == ["/proj/a/App.swift", "/proj/a/Note.md"],
               "選んだプロジェクトの外が混ざった (実際: \(paths("S1")))")
        assert(paths("S2") == ["/proj/b/Other.swift"], "実際: \(paths("S2"))")
        assert(paths(nil).count == 3, "すべてタブでは全部出す")

        // 前方一致で隣を巻き込まない（/proj/a が /proj/ab を拾わないこと）
        c.adopt(Structure.build(["/proj/a/App.swift": "struct App {}",
                                 "/proj/ab/Near.swift": "struct Near {}"]))
        assert(paths("S1") == ["/proj/a/App.swift"], "似た名前のプロジェクトを巻き込んだ")
    }

    /// カードの並びに規則を持たせる。メイン（浅い階層のソース）→ サブ → メモ。
    /// 規則が無いと、同じプロジェクトを見ているのに毎回違う順に並んで目が迷子になる
    static func ordersCardsMainThenSubThenNotes() {
        func card(_ dir: String, _ names: [String], flagged: Bool = false) -> DirCard {
            DirCard(id: dir, dir: dir, files: names.map {
                var f = FileCell(id: dir + "/" + $0, name: $0, lastAt: Date(timeIntervalSince1970: 1))
                if flagged { f.flaggedBy = "誰か" }
                return f
            })
        }
        let main = card("/p", ["App.swift"])
        let sub = card("/p/Sources/Deep", ["Detail.swift"])
        let memo = card("/p/docs", ["README.md", "note.md"])
        let flag = card("/p/Other", ["Spec.swift"], flagged: true)

        assert(Cockpit.cardRank(main) < Cockpit.cardRank(sub), "浅い方が先に来ない")
        assert(Cockpit.cardRank(sub) < Cockpit.cardRank(memo), "メモがソースより先に来た")
        assert(Cockpit.cardRank(flag) < Cockpit.cardRank(main), "フラグ付きが先頭に来ない")
        // メモだけのカードは、どれだけ浅くても最後
        assert(Cockpit.cardRank(card("/", ["a.md"])) > Cockpit.cardRank(sub),
               "浅いメモがソースより先に来た")
        // ソースが1つでも混ざればメモ扱いにしない
        assert(Cockpit.cardRank(card("/p/mix", ["a.md", "b.swift"])) < Cockpit.cardRank(memo))

        // 規則は両モードに掛かる。構造モードだけ別の並びだと、
        // 切り替えたときに同じプロジェクトが違う顔で出る
        let c = Cockpit()
        c.adopt(Structure.build([
            "/p/App.swift":            "struct App {}",
            "/p/Sources/Deep/D.swift": "struct D {}",
            "/p/docs/README.md":       "App.swift のこと",
        ]))
        let t0 = Date(timeIntervalSince1970: 26_000_000)
        c.apply(write("a", "/p/Sources/Deep/D.swift", "w1", at: t0))
        for mode in [CockpitMode.work, .structure] {
            let ranks = c.snapshot(now: t0.addingTimeInterval(1), mode: mode)
                .cards.map { Cockpit.cardRank($0) }
            assert(ranks == ranks.sorted(), "\(mode.title)モードで並びの規則が効いていない: \(ranks)")
        }
        let structure = c.snapshot(now: t0.addingTimeInterval(1), mode: .structure).cards
        assert(structure.last.map(Cockpit.cardRank) == 30, "メモが最後に来ていない")
    }

    /// チップはプロジェクト名ではなく役割＋モデルを出し、親子で階層化する
    static func agentHierarchy() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 10_000_000)

        // 司令塔（メインセッション）がサブエージェントを2体起こす
        c.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0),
                 .agentSpawn(call: "toolu_T1", by: "S1", session: "S1", type: "Explore",
                             title: "凡例の実装箇所を探す", at: t0),
                 .agentSpawn(call: "toolu_T2", by: "S1", session: "S1", type: "general-purpose",
                             title: "", at: t0),
                 .agentMeta(agent: "sub1", session: "S1", role: "Explore", depth: 1, parentCall: "toolu_T1"),
                 .agentMeta(agent: "sub2", session: "S1", role: "general-purpose", depth: 1, parentCall: "toolu_T2"),
                 .agentActivity(agent: "sub1", session: "S1", model: "sonnet-5", at: t0),
                 .agentActivity(agent: "sub2", session: "S1", model: "haiku-4.5", at: t0)])
        c.apply(write("S1", "/p/A.swift", "e1", at: t0))
        c.apply(read("sub1", "/p/B.swift", "r1", at: t0.addingTimeInterval(1)))
        c.apply(read("sub2", "/p/C.swift", "r2", at: t0.addingTimeInterval(2)))

        let snap = c.snapshot(now: t0.addingTimeInterval(3), mode: .work)
        let byId = Dictionary(uniqueKeysWithValues: snap.chips.map { ($0.id, $0) })

        assert(byId["S1"]?.role == "司令塔", "メインセッションは階層の頂点 (実際: \(byId["S1"]?.role ?? "nil"))")
        assert(byId["S1"]?.depth == 0)
        assert(byId["S1"]?.model == "opus-5", "モデル名が出る")
        assert(byId["S1"]?.parent == nil)

        assert(byId["sub1"]?.role == "Explore", "役割名は subagent_type")
        assert(byId["sub1"]?.depth == 1)
        assert(byId["sub1"]?.model == "sonnet-5")
        assert(byId["sub1"]?.parent == "S1", "meta.json の呼び出しIDから親が解決される")
        assert(byId["sub2"]?.parent == "S1")

        // 並びは階層が上から
        assert(snap.chips.first?.depth == 0, "司令塔が先頭")
        assert(snap.chips.map(\.depth) == snap.chips.map(\.depth).sorted(), "階層順に並ぶ")

        // レイアウトでは階層が深いほど右に下がり、行も分かれる
        let layout = CockpitLayout.compute(snap, width: 1100)
        let root = layout.chips.first { $0.chip.id == "S1" }!
        let child = layout.chips.first { $0.chip.id == "sub1" }!
        assert(child.rect.minX > root.rect.minX, "子は右に下がる")
        assert(child.rect.minY > root.rect.maxY - 1, "子は下の行に来る")
        assert(layout.chipRect(forAgent: "S1") != nil, "親子線を引くためチップ矩形が取れる")

        // フラグの主語も役割名になる
        let f = Cockpit()
        f.apply([.agentMeta(agent: "sub1", session: "S1", role: "実装", depth: 1, parentCall: "toolu_T1")])
        for i in 0..<3 { f.apply(read("sub1", "/p/spec.md", "x\(i)", at: t0.addingTimeInterval(Double(i)))) }
        let flagged = f.snapshot(now: t0.addingTimeInterval(60), mode: .work).cards.flatMap(\.files)[0]
        assert(flagged.flaggedBy == "実装", "実際: \(flagged.flaggedBy ?? "nil")")
    }

    /// バックグラウンド起動の結果は `agentId` を持つが、まだ終わっていない。
    /// ここを取り違えると、起こした瞬間に全部グレーアウトして労働量が0で固まる
    static func asyncLaunchIsNotCompletion() {
        let launched = #"{"type":"user","sessionId":"S1","timestamp":"2026-07-30T11:00:00.000Z","toolUseResult":{"agentId":"sub9","isAsync":true,"status":"async_launched","resolvedModel":"claude-opus-5","description":"調査"},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_L"}]}}"#
        let events = TranscriptParser.parse(Data(launched.utf8), fallbackSession: "x")
        assert(!events.contains { if case .agentDone = $0 { return true }; return false },
               "起動しただけで終了扱いにしている")
        assert(events.contains { if case .agentActivity(let a, _, _, _) = $0 { return a == "sub9" }; return false },
               "起動したエージェントが台帳に載っていない")

        // 実際に完了した報告は終了扱いになり、労働量の確定値が入る
        let completed = #"{"type":"user","sessionId":"S1","timestamp":"2026-07-30T11:05:00.000Z","toolUseResult":{"agentId":"sub9","status":"completed","agentType":"Explore","resolvedModel":"claude-opus-5","totalToolUseCount":37},"message":{"content":[{"type":"tool_result","tool_use_id":"toolu_L"}]}}"#
        guard case let .agentDone(agent, _, role, model, calls, _) =
                TranscriptParser.parse(Data(completed.utf8), fallbackSession: "x")[0]
        else { fatalError("完了報告が agentDone にならない") }
        assert(agent == "sub9" && role == "Explore" && model == "opus-5" && calls == 37)

        // 通しで：起動→働く→完了 で、灰色になるのは最後だけ
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 11_000_000)
        c.apply([.agentActivity(agent: "sub9", session: "S1", model: "opus-5", at: t0)])
        var chip = c.snapshot(now: t0.addingTimeInterval(1), mode: .work).chips.first { $0.id == "sub9" }
        assert(chip != nil, "起動直後もチップに出る")
        assert(chip?.done == false, "起動直後は終了扱いにしない")

        c.apply(work("sub9", 12, at: t0.addingTimeInterval(10)))
        chip = c.snapshot(now: t0.addingTimeInterval(11), mode: .work).chips.first { $0.id == "sub9" }
        assert(chip?.work == 12, "進行中は観測できたぶんが労働量 (実際: \(chip?.work ?? -1))")
        assert(chip?.done == false)

        c.apply([.agentDone(agent: "sub9", session: "S1", role: "Explore", model: "opus-5",
                            toolCalls: 37, at: t0.addingTimeInterval(20))])
        chip = c.snapshot(now: t0.addingTimeInterval(21), mode: .work).chips.first { $0.id == "sub9" }
        assert(chip?.done == true, "完了で灰色になる")
        assert(chip?.work == 37, "完了後は報告された確定値 (実際: \(chip?.work ?? -1))")
    }

    /// バックグラウンド実行では親側に完了記録が残らない。
    /// サブエージェント自身の `stop_reason:"end_turn"` だけが終了の手掛かりになる
    static func backgroundAgentEndsOnItsOwnTurn() {
        // サブエージェントの行（agentId を持つ）が end_turn で終わったら終了
        let sub = #"{"type":"assistant","sessionId":"S1","agentId":"sub7","timestamp":"2026-07-30T11:00:00.000Z","message":{"model":"claude-opus-5","stop_reason":"end_turn","content":[{"type":"text","text":"できた"}]}}"#
        let events = TranscriptParser.parse(Data(sub.utf8), fallbackSession: "x")
        assert(events.contains { if case .agentEnded(let a, _) = $0 { return a == "sub7" }; return false },
               "サブエージェントの end_turn を終了として拾えていない")

        // メインセッションは毎ターン end_turn になるので、終了扱いにしてはいけない
        let main = #"{"type":"assistant","sessionId":"S1","timestamp":"2026-07-30T11:00:00.000Z","message":{"model":"claude-opus-5","stop_reason":"end_turn","content":[{"type":"text","text":"はい"}]}}"#
        assert(!TranscriptParser.parse(Data(main.utf8), fallbackSession: "S1")
                .contains { if case .agentEnded = $0 { return true }; return false },
               "メインセッションを終了扱いにしている")

        // 通しで：働く → end_turn で灰色 → 続きを頼まれたら灰色が解ける
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 12_000_000)
        c.apply(work("sub7", 5, at: t0))
        c.apply([.agentEnded(agent: "sub7", at: t0.addingTimeInterval(10))])
        var chip = c.snapshot(now: t0.addingTimeInterval(11), mode: .work).chips.first { $0.id == "sub7" }
        assert(chip?.done == true, "end_turn で灰色になる")
        assert(chip?.work == 5, "労働量は観測できたぶんが残る (実際: \(chip?.work ?? -1))")

        c.apply(work("sub7", 3, at: t0.addingTimeInterval(20)))
        chip = c.snapshot(now: t0.addingTimeInterval(21), mode: .work).chips.first { $0.id == "sub7" }
        assert(chip?.done == false, "再開したら灰色が解ける")
        assert(chip?.work == 8)
    }

    /// 実測でサブエージェントのツール呼び出しの45%はファイル軸に載らない（検索・ビルドの Bash）。
    /// 稼働をファイルの触りだけで判定すると、grep を叩き続けているエージェントが「待機」に見える
    static func bashOnlyAgentLooksActive() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 14_000_000)
        // ファイルを一切触らず、Bash だけを叩き続けるエージェント
        c.apply([.agentMeta(agent: "grepper", session: "S1", role: "Explore", depth: 1, parentCall: "toolu_G"),
                 .agentActivity(agent: "grepper", session: "S1", model: "opus-5", at: t0)]
                + work("grepper", 4, at: t0))

        var chip = c.snapshot(now: t0.addingTimeInterval(3), mode: .work).chips.first { $0.id == "grepper" }
        assert(chip != nil, "ファイルを触らないエージェントもチップに出る")
        assert(chip?.busy == true, "Bash だけでも稼働中に見えること")
        assert(chip?.target == nil, "行き先が無いのでビームは出ない（これは仕様）")
        assert(chip?.work == 4)

        // 無音が続けば待機に落ちる
        chip = c.snapshot(now: t0.addingTimeInterval(Cockpit.activeWindow + 5), mode: .work).chips.first { $0.id == "grepper" }
        assert(chip?.busy == false, "無音が続けば待機に落ちる")

        // 動き出せばまた稼働に戻る
        c.apply(work("grepper", 2, at: t0.addingTimeInterval(60)))
        chip = c.snapshot(now: t0.addingTimeInterval(62), mode: .work).chips.first { $0.id == "grepper" }
        assert(chip?.busy == true, "再び動けば稼働に戻る")
        assert(chip?.work == 6)

        // 終了したら、直後でも稼働扱いにしない
        c.apply([.agentEnded(agent: "grepper", at: t0.addingTimeInterval(61))])
        chip = c.snapshot(now: t0.addingTimeInterval(62), mode: .work).chips.first { $0.id == "grepper" }
        assert(chip?.busy == false, "終了したら脈打たせない")
        assert(chip?.done == true)
    }

    /// エージェントの帯は**司令塔の箱＋縦1本の点線レール＋行**。
    ///
    /// ビーム（チップとファイルを結ぶ折れ線）はここで検査していたが、帯とファイル帯を
    /// 1本の罫で断ち切る形にしたので線の通る道が無くなった。関係は文字で語る——
    /// 行の「いま何をしているか」とセルのタグの2つが唯一の手掛かりになったので、
    /// **その2つが同じファイルを指していること**をこちらで見る
    static func agentRowsHangFromTheRail() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 9_000_000)
        // 司令塔はセッションIDそのものがエージェントID（深さ0になる条件）
        c.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0)])
        for i in 1...3 {
            c.apply([.agentMeta(agent: "w\(i)", session: "S1", role: "Phase \(i)",
                                depth: 1, parentCall: "s\(i)"),
                     .agentSpawn(call: "s\(i)", by: "S1", session: "S1", type: "Explore",
                                 title: "Phase \(i)", at: t0),
                     .agentActivity(agent: "w\(i)", session: "S1", model: "haiku-4.5", at: t0)])
        }
        c.apply(write("w2", "/proj/src/Target.swift", "e1", at: t0.addingTimeInterval(1)))

        let snap = c.snapshot(now: t0.addingTimeInterval(2), mode: .work)
        let layout = CockpitLayout.compute(snap, width: 1100)

        let roots = layout.chips.filter(\.isRoot)
        let rows = layout.chips.filter { !$0.isRoot }
        assert(!roots.isEmpty, "司令塔の箱が出ていない")
        assert(rows.count >= 3, "行が出ていない (実際: \(rows.count))")

        // 箱は左端、行はレールより右。読む順が上から下の1方向に揃っていること
        assert(roots[0].rect.minX == CockpitLayout.margin, "箱が左端に無い")
        assert(roots[0].rect.width <= CockpitLayout.rootCardWidth, "箱が広がった")
        for row in rows {
            assert(row.rect.minX > layout.railX,
                   "行がレールより左に出た (行 \(row.rect.minX) / レール \(layout.railX))")
            assert(row.rect.height == CockpitLayout.rowHeight, "行の高さが揃っていない")
        }

        // レールは箱の下から最後の行まで通っていること
        assert(layout.railTop >= roots[0].rect.maxY, "レールが箱の中から生えている")
        assert(layout.railBottom >= rows.last!.rect.minY, "レールが最後の行まで届いていない")
        assert(layout.railX > roots[0].rect.minX && layout.railX < roots[0].rect.maxX,
               "レールが箱の真下から降りていない")

        // 行同士が重ならない（重なると当たり判定がどちらに転ぶか読めない）
        for (a, b) in zip(rows, rows.dropFirst()) {
            assert(a.rect.maxY <= b.rect.minY + 0.5, "行が重なった")
        }

        // 番号は上から W1、W2 …。飛ぶと「何体目か」が読めない
        assert(rows.prefix(3).map(\.shortID) == ["W1", "W2", "W3"],
               "行の番号が順になっていない (実際: \(rows.prefix(3).map(\.shortID)))")

        // ビームを外したので、触っているファイルは行の meta が唯一の手掛かり。
        // ここが空だと、どのエージェントが何を触っているか画面から辿れなくなる
        let worker = layout.chips.first { $0.chip.id == "w2" }
        assert(worker?.chip.target == "/proj/src/Target.swift",
               "行が触っている先を持っていない (実際: \(worker?.chip.target ?? "nil"))")
        assert(worker?.doing.contains("Target.swift") == true,
               "行にファイル名が出ていない (実際: \(worker?.doing ?? "nil"))")
        assert(worker?.doing.contains("編集") == true, "読み書きの別が出ていない")

        // 触っていない行は、それまでの内訳に落ちる（ファイル軸に載らない作業はそこにしか出ない）
        let idle = layout.chips.first { $0.chip.id == "w1" }
        assert(idle?.chip.target == nil, "この行は何も触っていない前提")
        assert(idle?.doing.contains("Target.swift") != true, "触っていない行に他人のファイルが出た")
    }

    /// 止まった門は**紙と行の両方**で出る。紙だけだと何が止まったのか読めず、
    /// 行だけだとレールのどこで止まっているのか分からない
    static func gateShowsAsPaperAndRow() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 9_100_000)
        c.apply([.agentActivity(agent: "boss", session: "S1", model: "opus-5", at: t0)])
        let snap = CockpitSnapshot(
            mode: .work,
            chips: c.snapshot(now: t0.addingTimeInterval(1), mode: .work).chips,
            cards: [], flagCount: 0, readThreshold: 3, hiddenChips: 0,
            gates: [Gate.Request(id: "/m/gate/g1.md", call: "c1", by: "boss",
                                 to: "検査ワーカー", risk: "high", issued: t0,
                                 instruction: "p0-selfcheck に凡例の検査を足す")])
        let layout = CockpitLayout.compute(snap, width: 1100)

        guard let paper = layout.paper(forGate: "/m/gate/g1.md"),
              let hit = layout.rect(forGate: "/m/gate/g1.md") else {
            fatalError("門の紙が置かれていない")
        }
        assert(paper.size == CockpitLayout.gatePaper, "紙の寸法が変わった (実際: \(paper.size))")
        // 紙はレールの右横に立つ。行の上に載ると行の字と重なる
        assert(paper.minX > layout.railX, "紙がレールの左に出た")
        assert(paper.maxX < CockpitLayout.margin + CockpitLayout.rowOffset,
               "紙が行の欄に食い込んだ")

        // 紙と行のどちらを押しても門が開く
        assert(hit.contains(CGPoint(x: paper.midX, y: paper.midY)), "紙を押しても開かない")
        let row = layout.chips.first { $0.gate }
        assert(row != nil, "止まった相手の行が出ていない")
        assert(hit.contains(CGPoint(x: row!.rect.midX, y: row!.rect.midY)), "行を押しても開かない")
        assert(row?.role.contains("検査") == true,
               "行に相手の名前が出ていない (実際: \(row?.role ?? "nil"))")
        assert(row?.badge == "待機", "止まった行のバッジが待機になっていない")

        // 帯の高さが紙を含んでいること。含まないと下のカードに紙が被る
        assert(layout.busY >= paper.maxY, "紙が帯からはみ出した")
    }

    /// Read も Edit も 0.1 秒で終わるので、開始と完了が同じ取り込みバッチで届く。
    /// 「未完了だけを進行中とみなす」設計だとビームが一度も出ない
    static func beamSurvivesFastTools() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 6_000_000)
        // 開始と完了を一度に流し込む（実際の取り込みと同じ形）
        c.apply(read("worker", "/proj/docs/spec.md", "r1", at: t0))

        let during = c.snapshot(now: t0.addingTimeInterval(1), mode: .work)
        assert(during.cards[0].files[0].state == .reading, "終わった直後も余韻で光る")
        assert(during.chips[0].busy, "チップが稼働表示になる")
        assert(during.chips[0].target == "/proj/docs/spec.md", "ビームの行き先がある")
        assert(during.chips[0].kind == .read, "破線ビームとして描かれる")

        let after = c.snapshot(now: t0.addingTimeInterval(Cockpit.afterglow + 1), mode: .work)
        assert(after.cards[0].files[0].state == .idle, "余韻が切れたら消える")
        assert(after.chips[0].target == nil, "ビームも消える")

        // 書き込みも同じ
        let w = Cockpit()
        w.apply(write("worker", "/proj/src/A.swift", "w1", at: t0))
        let wDuring = w.snapshot(now: t0.addingTimeInterval(1), mode: .work)
        assert(wDuring.cards[0].files[0].state == .writing)
        assert(wDuring.chips[0].kind == .write, "実線ビームとして描かれる")
    }

    /// 線が引けない作業（実測でツール呼び出しの45%）を、種類として拾えること
    static func classifiesBashWork() {
        func kind(_ c: String) -> WorkKind { TranscriptParser.classifyBash(c).0 }

        assert(kind("grep -n foo Sources/AT22/Cockpit.swift") == .search)
        assert(kind("find . -name '*.swift'") == .search)
        assert(kind("jq -r '.type' a.jsonl") == .search)
        assert(kind("xcodebuild -scheme X build") == .build)
        assert(kind("swift build") == .build)
        assert(kind("git diff HEAD") == .git)
        assert(kind("sleep 5") == .wait)

        // 中身を出すものは Read ツールと同じ「読取」に入れる。分けて数えると
        // 「何度も読み返している」が2つのバケツに割れて順位から消える（実測 Read 3096 / Bash 2379）
        for c in ["cat README.md", "head -50 a.swift", "tail -n 20 log.txt", "wc -l a.swift"] {
            assert(kind(c) == .read, "読取に入っていない: \(c) → \(kind(c))")
        }
        // ls は「何があるか探す」行為なので find と同じ側
        assert(kind("ls Sources/AT22") == .search)

        // 先頭の飾りは読み飛ばす（実測で Bash の80%が連結コマンド）
        assert(kind("cd /proj && grep -n foo bar.swift") == .search, "cd を読み飛ばす")
        assert(kind("rtk proxy grep -n foo bar.swift") == .search, "rtk proxy を読み飛ばす")
        assert(kind("FOO=1 git status") == .git, "環境変数の代入を読み飛ばす")
        // パイプの先ではなく先頭語で決める（`xcodebuild | grep` を検索にしない）
        assert(kind("xcodebuild build 2>&1 | grep error") == .build)
        // 表に無いコマンドは「他」で、名前だけ残す
        let (k, word, _) = TranscriptParser.classifyBash("pkill -x AT22")
        assert(k == .other && word == "pkill", "実際: \(k) \(word)")

        // 実行ファイルのフルパスでもコマンド名で判定する
        assert(kind("/usr/bin/grep -n foo bar.swift") == .search)
    }

    /// **何を相手にしたか**を出す。`検索 grep` だけだと何を探したのか分からず、
    /// 実測でツール呼び出しの45%を占めるファイル軸外の作業がほぼ無内容になる
    static func showsTargetOfBashAndGrep() {
        func target(_ c: String) -> String { TranscriptParser.classifyBash(c).2 }

        assert(target("grep -n Snowman Cockpit.swift") == "Snowman",
               "grep の相手が取れない: \(target("grep -n Snowman Cockpit.swift"))")
        // 値を取る旗は値ごと飛ばす。飛ばさないと `5` を相手として出してしまう
        assert(target("rg -C 5 orderPaper") == "orderPaper", "実際: \(target("rg -C 5 orderPaper"))")
        assert(target("find . -name '*.swift'") == "*.swift", "実際: \(target("find . -name '*.swift'"))")
        // パスは末尾だけ。フルパスはチップにも紙にも入らない
        assert(target("cat /Users/x/proj/Sources/AT22/Gate.swift") == "Gate.swift",
               "実際: \(target("cat /Users/x/proj/Sources/AT22/Gate.swift"))")
        // 末尾が `/` でも畳む。畳まないと `ls ~/.claude/projects/` がフルパスのまま40字で切れる
        assert(target("ls /Users/x/.claude/projects/") == "projects/",
               "実際: \(target("ls /Users/x/.claude/projects/"))")
        assert(target("git status") == "status", "git の下位コマンドが相手にならない")
        // 引数の無いコマンドで空文字を返し、札がツール名だけになる
        assert(target("swift build").isEmpty == false, "swift build の相手が消えた")
        assert(target("pwd").isEmpty, "引数が無いのに相手が出た")
        // 相手が取れた時だけ足す
        assert(TranscriptParser.label("grep", "Snowman") == "grep Snowman")
        assert(TranscriptParser.label("Glob", "") == "Glob", "空の相手で余分な空白が付いた")

        // ファイル軸に載らないツール。名前だけでは「Grep した」以上が分からない
        func tool(_ name: String, _ input: [String: Any]) -> String {
            TranscriptParser.toolTarget(name: name, input: input)
        }
        assert(tool("Grep", ["pattern": "orderPaper", "path": "Sources"]) == "orderPaper",
               "Grep の相手が pattern になっていない")
        assert(tool("Glob", ["pattern": "**/*.swift"]) == "**/*.swift")
        assert(tool("WebSearch", ["query": "Swift Process stdin"]) == "Swift Process stdin")
        // URL はホストだけ。全部出すと1行が丸ごと埋まる
        assert(tool("WebFetch", ["url": "https://example.com/very/long/path?q=1"]) == "example.com",
               "URL がホストに縮んでいない")
        assert(tool("Unknown", [:]).isEmpty, "取れないのに何か出した")
        // 長すぎる相手は切る
        assert(tool("WebSearch", ["query": String(repeating: "あ", count: 200)]).count == 40,
               "長い相手が切られていない")

        // 通しで：Grep の tool_use から相手入りの札が出る
        let line = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:00.000Z","sessionId":"S1",\
        "message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"t1","name":"Grep",\
        "input":{"pattern":"drawGates","path":"Sources"}}]}}
        """
        let events = TranscriptParser.parse(Data(line.utf8), fallbackSession: "S1")
        let action = events.compactMap { event -> (WorkKind, String)? in
            if case let .agentAction(_, _, _, kind, detail, _) = event { return (kind, detail) }
            return nil
        }.first
        assert(action?.1 == "Grep drawGates", "実際: \(action?.1 ?? "無し")")
        assert(action?.0 == .search, "Grep が検索に数えられていない")
    }

    /// 書き込み量は 点 → 下線 → 虹 の順に足す。点だけだと3段で頭打ちになり、
    /// 100行と1000行が同じ見え方になっていた
    static func writeTierStacksDotsUnderlineRainbow() {
        typealias Tier = CockpitLayout.WriteTier
        func tier(_ n: Int, huge: Bool = false) -> Tier { CockpitLayout.writeTier(n, huge: huge) }

        assert(tier(0) == .none, "未変更に装飾を付けた")
        assert(tier(0, huge: true) == .none, "触っていないのに虹を掛けた")
        assert(tier(1) == .small && tier(9) == .small)
        assert(tier(10) == .medium && tier(99) == .medium)
        assert(tier(100) == .large && tier(9999) == .large)
        assert(tier(120, huge: true) == .huge, "上位2%が虹にならない")

        // 段が上がるほど印が増える。下の段の印が消えてはいけない
        assert(tier(5).underline == nil, "T1 に下線が付いた（点だけの段）")
        assert(tier(50).underline?.double == false, "T2 は細い1本")
        assert(tier(500).underline?.double == false, "T3 は太い1本")
        assert(tier(500).underline!.thickness > tier(50).underline!.thickness,
               "T3 が T2 より太くない")
        assert(tier(500, huge: true).underline?.double == true, "T4 が二重下線でない")
        assert(!tier(500).rainbow && tier(500, huge: true).rainbow, "虹が最上段だけになっていない")

        // 点の本数は従来どおり。下線は「重ねる印」で、量そのものは点が持つ
        assert(CockpitLayout.writeTicks(5) == 1 && CockpitLayout.writeTicks(50) == 2
               && CockpitLayout.writeTicks(500) == 3, "点の段が変わった")
    }

    /// 記憶DB。既存の書式を読み、人間が開いたノートだけ編集する
    static func readsMemoryDatabase() {
        let full = """
        ---
        name: at22-shipped-v0-1-0
        description: v0.1.0 を公開済み
        metadata:
          node_type: memory
          type: project
          originSessionId: 7e04693d
        ---

        本文。[[claude-code-transcript-data-limits]] を見る。
        """
        let node = Memory.node(path: "/m/at22-shipped-v0-1-0.md", text: full, modified: Date())
        assert(node.name == "at22-shipped-v0-1-0", "name を拾えない")
        assert(node.summary == "v0.1.0 を公開済み", "description を拾えない")
        assert(node.kind == "project", "入れ子の metadata.type を拾えない")
        assert(node.session == "7e04693d", "originSessionId を拾えない")
        assert(!node.hasState)

        // frontmatter が無い・壊れていても落とさない（人が直接直す書式なので途中の形が普通に現れる）
        let bare = Memory.node(path: "/m/bare.md", text: "ただの本文", modified: Date())
        assert(bare.name == "bare" && bare.summary.isEmpty && bare.kind.isEmpty && bare.session == nil,
               "frontmatter 無しで壊れた")
        assert(Memory.node(path: "/m/x.md", text: "---\nname: 途中で切れる", modified: Date()).name == "途中で切れる",
               "閉じていない frontmatter で落ちた")
        // 知らない type も捨てない
        assert(Memory.node(path: "/m/y.md", text: "---\ntype: 新種\n---\n", modified: Date()).kind == "新種")

        // 前提のノートは名前で見分ける。並びの先頭に固定するため
        assert(Memory.node(path: "/m/PROJECT.md", relative: "PROJECT.md",
                           text: "本文", modified: Date()).isIndex,
               "PROJECT.md を前提として見ていない")
        assert(Memory.node(path: "/m/MEMORY.md", relative: "MEMORY.md",
                           text: "本文", modified: Date()).isIndex,
               "実物の MEMORY.md を前提として見ていない")
        assert(!Memory.node(path: "/m/other.md", relative: "other.md",
                            text: "本文", modified: Date()).isIndex)

        // 状態ブロック。引き継ぎとフルオートの復帰点
        let handoff = Memory.node(path: "/m/p.md", text: """
        本文
        ```json
        {"これは": "状態ではない"}
        ```
        ```state
        stage: implement
        loop_count: 2
        壊れた行
        ```
        続き
        """, modified: Date())
        assert(handoff.hasState, "状態ブロックを読めていない")
        assert(handoff.state.map(\.key) == ["stage", "loop_count"],
               "json を状態と取り違えたか、壊れた行で落ちた (実際: \(handoff.state.map(\.key)))")
        assert(!Memory.node(path: "/m/q.md", text: "```swift\nlet stage = 1\n```", modified: Date()).hasState,
               "別の言語の塊を状態と見た")

        // 3つの見出しを固定し、type ではなく置き場だけで実体を振り分ける
        func at(_ rel: String, _ kind: String, _ name: String,
                session: String? = nil, stage: String? = nil) -> Memory.Node {
            var t = "---\nname: \(name)\ndescription: \(name) の説明\ntype: \(kind)\n---\n本文\n"
            if let session {
                t = t.replacingOccurrences(of: "type: \(kind)\n", with: "type: \(kind)\noriginSessionId: \(session)\n")
            }
            if let stage { t += "```state\nstage: \(stage)\n```\n" }
            return Memory.node(path: "/m/" + rel, relative: rel, text: t, modified: Date())
        }
        let nodes = [
            at("sessions/each/7e04693d.md", "project", "分かったこと"),
            at("PROJECT.md", "project", "企画書"),
            at("MEMORY.md", "reference", "実物索引"),
            at("flat.md", "progress", "直下の進捗", session: "origin-session"),
            at("sessions/SHARED.md", "feedback", "共有"),
            at("sessions/other.md", "project", "共有の補足"),
            at("sessions/each/ref-session.md", "reference", "参照"),
            at("sessions/each/old.md", "feedback", "前の回", stage: "done"),
        ]
        let (rows, done) = Memory.outline(nodes)
        assert(done == 1, "完了を件数に畳んでいない (実際: \(done))")

        // 見出しは必ず出し、大前提と共有ノートを各段の先頭に固定する
        let labels = rows.map(\.label)
        assert(labels == ["プロジェクト  3", "MEMORY.md", "PROJECT.md", "flat.md",
                          "セッション全体  2", "SHARED.md", "other.md",
                          "セッションごと  2", "7e04693d", "ref-session"],
               "新しい階層と違う (実際: \(labels))")
        func depth(_ label: String) -> Int? { rows.first { $0.label == label }?.depth }
        assert(rows.first?.isFolder == true && depth("プロジェクト  3") == 0)
        assert(depth("MEMORY.md") == 1 && depth("PROJECT.md") == 1)
        assert(depth("SHARED.md") == 1, "SHARED.md が1段目に来ない")
        assert(rows.contains { $0.isFolder && $0.label == "セッション全体  2" && $0.depth == 0 },
               "セッション全体の見出しが出ていない")
        assert(rows.contains { $0.isFolder && $0.label == "セッションごと  2" && $0.depth == 0 },
               "セッションごとの見出しが出ていない")
        assert(depth("7e04693d") == 1 && depth("ref-session") == 1,
               "セッションIDが1段目に来ない")
        // 完了済みは件数だけに畳み、名前もセッション見出しも残さない
        assert(!rows.contains { $0.label == "前の回" || $0.label.hasPrefix("old") },
               "畳んだ完了が一覧に残った")
        // memory/ にあるノートは畳んだ分以外すべて並ぶ
        assert(rows.filter { !$0.isFolder }.count + done == nodes.count, "並ばなかったノートがある")
        assert(depth("flat.md") == 1,
               "type と originSessionId で直下ノートをセッションへ誤分類した")
        let emptyRows = Memory.outline([]).rows
        assert(emptyRows.count == 3
               && emptyRows.allSatisfy { $0.isFolder && $0.depth == 0 }
               && emptyRows.map(\.label) == ["プロジェクト  0", "セッション全体  0", "セッションごと  0"],
               "空でも3つの見出しを出していない")

        // 本文は frontmatter を落として渡す
        assert(Memory.body("---\nname: a\n---\n\n# 見出し\n本文\n") == "# 見出し\n本文",
               "frontmatter が本文に混ざった")
        assert(Memory.body("frontmatter 無し") == "frontmatter 無し")

        // cwd からプロジェクトのディレクトリ名を組む。始まったばかりのセッションは
        // まだ transcript を書いていないので、この経路でしか辿れない
        assert(Cockpit.projectSlug("/Users/x/Swift_PRJS/AT22_Glass_Cockpit")
               == "-Users-x-Swift-PRJS-AT22-Glass-Cockpit")
        assert(Cockpit.projectSlug("/Users/x/Swift_PRJS/str(8)_ToDo")
               == "-Users-x-Swift-PRJS-str-8--ToDo", "括弧やアンダースコアの置換が違う")
        assert(Cockpit.projectSlug("").isEmpty)
    }

    /// 実ディレクトリを走査し、壊れた UTF-8 も一覧から黙って消さない
    static func loadsMemoryDirectory() {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("at22-memory-load-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: base) }
        let project = base.appendingPathComponent("project")
        let each = project.appendingPathComponent("memory/sessions/each")
        try! manager.createDirectory(at: each, withIntermediateDirectories: true)
        try! "企画書".write(to: project.appendingPathComponent("memory/PROJECT.md"),
                          atomically: false, encoding: .utf8)
        try! Data([0xff, 0xfe]).write(to: each.appendingPathComponent("broken.md"))

        let nodes = Memory.load(projectRoot: project)
        assert(nodes.count == 2, "実走査でノートが消えた (実際: \(nodes.map(\.relative)))")
        assert(nodes.contains { $0.relative == "PROJECT.md" && $0.body == "企画書" },
               "実ディレクトリの本文か相対パスを読めない")
        assert(nodes.contains {
            $0.relative == "sessions/each/broken.md" && $0.summary == "UTF-8として読めません" && $0.lines == 0
        }, "UTF-8として読めないノートが無言で消えた")
    }

    /// 保存先を実 memory/ に錨付けし、置換・失敗時の掃除・シンボリックリンク抜けを検査する
    static func savesOnlyInsideMemory() {
        enum ReplacementFailure: Error { case injected }
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("at22-memory-save-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: base) }
        let projects = base.appendingPathComponent("projects")
        let project = projects.appendingPathComponent("project")
        let memory = project.appendingPathComponent("memory")
        try! manager.createDirectory(at: memory, withIntermediateDirectories: true)
        let session = "save-probe"
        try! Data().write(to: project.appendingPathComponent("\(session).jsonl"))
        let note = memory.appendingPathComponent("PROJECT.md")
        let original = "---\nname: 企画書\noriginSessionId: base-session\n---\n変更前"
        try! original.write(to: note, atomically: false, encoding: .utf8)

        let cockpit = Cockpit(projectsRoot: projects)
        cockpit.selectedSession = session
        cockpit.refreshMemory()
        assert(cockpit.memoryDirectory()?.standardizedFileURL == memory.standardizedFileURL,
               "保存の錨が実 memory/ を向いていない")

        let outside = base.appendingPathComponent("outside.md")
        try! "外".write(to: outside, atomically: false, encoding: .utf8)
        assert(cockpit.saveNote(path: outside.path, text: "侵入", expectedText: "外") == .failed,
               "memory/ 外へ書けた")
        assert((try? String(contentsOf: outside, encoding: .utf8)) == "外", "置き場の外を書き換えた")

        let edited = original.replacingOccurrences(of: "変更前", with: "変更後")
        assert(cockpit.saveNote(path: note.path, text: edited, expectedText: original) == .saved,
               "memory/ 内を保存できない")
        let savedText = try! String(contentsOf: note, encoding: .utf8)
        assert(savedText == edited, "置換後の内容が一致しない")
        assert(Memory.frontMatter(savedText)["originSessionId"] == "base-session",
               "本文の編集で frontmatter が消えた")

        // 編集開始後にエージェントが書いた内容を、基準版のまま無条件に踏み潰さない
        let agentEdit = edited + "\nエージェントの追記"
        try! agentEdit.write(to: note, atomically: false, encoding: .utf8)
        assert(cockpit.saveNote(path: note.path, text: edited + "\n人間の追記",
                                expectedText: edited) == .conflict,
               "基準版が変わったのに保存した")
        assert((try? String(contentsOf: note, encoding: .utf8)) == agentEdit,
               "競合時にエージェントの追記を踏み潰した")

        // 明示的な上書きだけは競合を越え、UI の選択肢が実際に働く
        let forced = edited + "\n人間が上書き"
        assert(cockpit.saveNote(path: note.path, text: forced,
                                expectedText: edited, overwrite: true) == .saved,
               "明示した上書きが働かない")

        // 置換が返したURLの内容が違えば、実在していても成功にしない
        cockpit.replaceNoteForProbe = { original, _ in
            try "読み返し不一致".write(to: original, atomically: false, encoding: .utf8)
            return original
        }
        assert(cockpit.saveNote(path: note.path, text: "保存したかった内容",
                                expectedText: forced) == .failed,
               "読み返し不一致を成功扱いした")
        cockpit.replaceNoteForProbe = nil

        // tmp の生成後に置換だけを失敗させ、catch の後始末で消えることを見る
        var temporaryWasCreated = false
        let beforeFailure = try! String(contentsOf: note, encoding: .utf8)
        cockpit.replaceNoteForProbe = { _, tmp in
            temporaryWasCreated = manager.fileExists(atPath: tmp.path)
            throw ReplacementFailure.injected
        }
        assert(cockpit.saveNote(path: note.path, text: "失敗する内容",
                                expectedText: beforeFailure) == .failed,
               "置換失敗を成功扱いした")
        cockpit.replaceNoteForProbe = nil
        assert(temporaryWasCreated, "置換失敗前に一時ファイルを生成していない")
        let leftovers = (try? manager.contentsOfDirectory(atPath: memory.path)) ?? []
        assert(!leftovers.contains { $0.hasSuffix(".tmp") }, "失敗後に一時ファイルが残った: \(leftovers)")

        let outsideDirectory = base.appendingPathComponent("linked-outside")
        try! manager.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let escaped = outsideDirectory.appendingPathComponent("escape.md")
        try! "外の原文".write(to: escaped, atomically: false, encoding: .utf8)
        let linkedProject = projects.appendingPathComponent("linked-project")
        try! manager.createDirectory(at: linkedProject, withIntermediateDirectories: true)
        let linkedSession = "linked-probe"
        try! Data().write(to: linkedProject.appendingPathComponent("\(linkedSession).jsonl"))
        try! manager.createSymbolicLink(at: linkedProject.appendingPathComponent("memory"),
                                        withDestinationURL: outsideDirectory)
        let linkedCockpit = Cockpit(projectsRoot: projects)
        linkedCockpit.selectedSession = linkedSession
        linkedCockpit.refreshMemory()
        assert(linkedCockpit.saveNote(path: linkedProject.appendingPathComponent("memory/escape.md").path,
                                      text: "侵入", expectedText: "外の原文") == .failed,
               "memory/ のシンボリックリンクから外へ書けた")
        assert((try? String(contentsOf: escaped, encoding: .utf8)) == "外の原文",
               "シンボリックリンクの先を書き換えた")
    }

    /// 壁打ちモードは記憶DBだけを1列で出し、範囲とセッションを字下げで見せる
    static func memoryModeShowsProjectAndSessionLevels() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 70_000_000)
        // 構造を持っていても材料カードは出さない
        c.adopt(Structure.build([
            "/proj/docs/idea.md":  "---\ndescription: 原案\n---\n本文\n",
            "/proj/README.md":     "# 説明\n\nこのアプリの読み方。\n",
            "/proj/App.swift":     "struct App {}",
        ]))
        c.loadMemoryForProbe([
            Memory.node(path: "/m/PROJECT.md", relative: "PROJECT.md",
                        text: "---\nname: 前提\ndescription: 計画全体の仕様\n---\n本文\n", modified: t0),
            Memory.node(path: "/m/sessions/each/abc123.md", relative: "sessions/each/abc123.md",
                        text: "---\nname: a\ndescription: 覚えたこと\ntype: reference\noriginSessionId: abc123-full\n---\n本文 [[別ノート]]\n```state\nstage: implement\n```\n",
                        modified: t0),
        ])

        let snap = c.snapshot(now: t0, mode: .memory)
        assert(snap.cards.count == 1 && snap.cards[0].id == "db:outline",
               "壁打ちモードに記憶DB以外のカードが出た")
        let db = snap.cards[0]
        assert(db.files.map(\.name) == ["プロジェクト  1", "PROJECT.md", "セッション全体  0",
                                       "セッションごと  1", "abc123"],
               "記憶DB に入るものが違う (実際: \(db.files.map(\.name)))")
        assert(db.files.map(\.indent) == [0, 1, 0, 0, 1],
               "3つの段の字下げが付いていない (実際: \(db.files.map(\.indent)))")
        assert([0, 2, 3].allSatisfy { !db.files[$0].touched }
               && [1, 4].allSatisfy { db.files[$0].touched },
               "見出しとノートの実体を区別できていない")

        // 3行目に「誰が書いたか」が出る。DB は結果なので出所が要る
        let a = db.files.first { $0.name == "abc123" }!
        assert(a.note == "覚えたこと", "1行要約が入らない")
        assert(a.trace.contains("abc123-f が書いた") && a.trace.contains("状態 implement"),
               "書いたセッションか状態が出ていない (実際: \(a.trace))")
        assert(!a.trace.contains("→") && !a.trace.contains("繋がる"),
               "リンクの繋がりを表示している (実際: \(a.trace))")

        // 字下げは描画位置と幅に効き、深くても右端を越えない
        let layout = CockpitLayout.compute(snap, width: 1100)
        assert(layout.cards.count == 1, "描画でも1列になっていない")
        let card = layout.cards[0]
        assert(card.rect.maxX <= 1100 - CockpitLayout.margin + 0.5, "カードが画面幅を超えた")
        // セルは3行ぶん
        for box in card.cells {
            assert(box.rect.height == CockpitLayout.noteCellHeight, "壁打ちのセルが3行ぶんでない")
        }

        let cells = card.cells
        assert(cells[1].rect.minX > cells[0].rect.minX
               && cells[4].rect.minX > cells[3].rect.minX,
               "字下げが描画の x に効いていない")
        assert(cells.allSatisfy { $0.rect.maxX <= cells[0].rect.maxX + 0.5 },
               "字下げた行が右端をはみ出した")

        // 狭い幅で壊れた深さが来ても、120pt の下限がカード外へ押し出さない
        var narrowSnapshot = snap
        narrowSnapshot.cards[0].files[4].indent = 20
        let narrow = CockpitLayout.compute(narrowSnapshot, width: 320).cards[0]
        assert(narrow.cells.allSatisfy { $0.rect.maxX <= narrow.rect.maxX - CockpitLayout.cardPad + 0.5 },
               "狭い幅で字下げの最小幅がカードを越えた")

        // 記憶DB が空でも成立する（まだ1本も書かれていない状態が普通にある）
        let fresh = Cockpit()
        let empty = fresh.snapshot(now: t0, mode: .memory)
        assert(empty.cards.count == 1 && empty.cards[0].files.count == 3,
               "空でもDBと3つの見出しを出していない")
    }


    /// 雪だるまは**文脈の量**で育つ。長引いたセッションで推論が鈍るのは時間ではなく量で起きる
    static func snowmanGrowsWithContext() {
        // usage の3つを足したものが文脈。実測で cache_read が本体（236,780 に対し input は 1）
        let usage: [String: Any] = ["input_tokens": 1, "cache_read_input_tokens": 236_780,
                                    "cache_creation_input_tokens": 3_659, "output_tokens": 894]
        assert(TranscriptParser.contextTokens(usage) == 240_440,
               "実際: \(TranscriptParser.contextTokens(usage))")
        // 出力は次のターンの入力になるまで文脈ではない
        assert(TranscriptParser.contextTokens(["output_tokens": 5_000]) == 0, "出力を文脈に数えた")
        assert(TranscriptParser.contextTokens([:]) == 0, "空の usage で落ちた")

        // 窓はモデル名から決められない（実測で 1M 版も `claude-opus-5` としか書かれていない）。
        // 200k を超えて動いていること自体が 1M 版の証拠になる
        assert(Snowman.window(observed: 150_000) == Snowman.smallWindow, "小さい窓に落ちない")
        assert(Snowman.window(observed: 240_440) == Snowman.largeWindow, "200k 超で 1M と見なさない")

        var r = Snowman.Reading()
        assert(r.stage == .fresh && r.growth == 0, "何も観測していないのに育っている")
        Snowman.observe(&r, tokens: 39_129)
        assert(r.stage == .fresh, "39k で警戒した")
        Snowman.observe(&r, tokens: 997_520)          // 実測の最大
        assert(r.window == Snowman.largeWindow, "窓が 1M に切り替わらない")
        assert(r.stage == .warning, "997k / 1M で警報が出ない（実際: \(r.stage)）")
        assert(r.growth > 0.99, "実際: \(r.growth)")

        // 圧縮されたら溶ける。**peak は下げない**——下げると次から小さい窓で測ってしまう
        Snowman.compact(&r, before: 999_564, after: 15_178)
        assert(r.tokens == 15_178 && r.stage == .fresh, "圧縮しても溶けない")
        assert(r.window == Snowman.largeWindow, "圧縮で窓が小さい方に戻った")
        assert(r.compactions == 1 && r.droppedTotal == 984_386, "落ちた量を数えていない")

        // 0 や負で壊れない
        Snowman.observe(&r, tokens: 0)
        assert(r.tokens == 15_178, "0 トークンで上書きした")
        assert(Snowman.growth(tokens: 100, window: 0) == 0, "窓が0で落ちた")
        assert(Snowman.growth(tokens: 2_000_000, window: 1_000_000) == 1, "1を超えた")

        // 表示。桁が変わっても読める形にする
        assert(Snowman.short(999) == "999" && Snowman.short(236_780) == "236k"
               && Snowman.short(1_000_000) == "1.0M", "短縮が崩れた")
        assert(Snowman.caption(tokens: 240_000, window: 1_000_000) == "240k / 1.0M（24%）",
               "実際: \(Snowman.caption(tokens: 240_000, window: 1_000_000))")
        // 警報には手が添えられている。警報だけ出して何をすればいいか無いと、見た人が困る
        assert(!Snowman.Stage.warning.advice.isEmpty && !Snowman.Stage.heavy.advice.isEmpty,
               "重い側に助言が無い")
        assert(Snowman.Stage.fresh.advice.isEmpty, "軽いのに助言が出た")

        // 通しで：transcript の行から Cockpit の読みまで届く
        let c = Cockpit()
        let assistant = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:00.000Z","sessionId":"S1",\
        "message":{"model":"claude-opus-5","usage":{"input_tokens":2,\
        "cache_read_input_tokens":940000,"cache_creation_input_tokens":923},"content":[]}}
        """
        let boundary = """
        {"type":"system","subtype":"compact_boundary","timestamp":"2026-08-01T00:01:00.000Z",\
        "sessionId":"S1","compactMetadata":{"trigger":"auto","preTokens":999564,"postTokens":15178}}
        """
        c.apply(TranscriptParser.parse(Data(assistant.utf8), fallbackSession: "S1"))
        c.selectedSession = "S1"
        assert(c.reading.stage == .warning, "行から警報まで届かない（実際: \(c.reading.stage)）")
        c.apply(TranscriptParser.parse(Data(boundary.utf8), fallbackSession: "S1"))
        assert(c.reading.tokens == 15_178 && c.reading.compactions == 1, "圧縮の行が届いていない")
    }

    /// `spend` の重み（価格比）を固定する。**実装ではなく仕様を検査する**——
    /// レートリミットの実際の計算式は非公開で、ここは代理指標として選んだ重みそのものなので、
    /// この検査は「実装が正しいか」ではなく「今どの数字を仕様として選んだか」を凍結する。
    /// `contextTokens` と混同すると、按分も台帳の絶対値も静かにずれるので別物であることも固定する
    static func weighsWhatEachTurnCost() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

        let input = TranscriptParser.spend(["input_tokens": 1000])
        assert(near(input, 1000), "input_tokens の重み。実際: \(input)")

        let cacheCreation = TranscriptParser.spend(["cache_creation_input_tokens": 1000])
        assert(near(cacheCreation, 1250), "cache_creation_input_tokens の重み。実際: \(cacheCreation)")

        let cacheRead = TranscriptParser.spend(["cache_read_input_tokens": 1000])
        assert(near(cacheRead, 100), "cache_read_input_tokens の重み。実際: \(cacheRead)")

        let output = TranscriptParser.spend(["output_tokens": 1000])
        assert(near(output, 5000), "output_tokens の重み。実際: \(output)")

        let all: [String: Any] = ["input_tokens": 1000, "cache_creation_input_tokens": 1000,
                                  "cache_read_input_tokens": 1000, "output_tokens": 1000]
        let allSpend = TranscriptParser.spend(all)
        assert(near(allSpend, 7350), "4つ全部入りの合計。実際: \(allSpend)")

        assert(near(TranscriptParser.spend([:]), 0), "空の辞書で0にならない")
        assert(near(TranscriptParser.spend(["totally_unknown_key": 1000]), 0),
               "知らないキーだけで0にならない")

        // `contextTokens` とは別物：同じ usage を両方に通して値が食い違うことを確かめる。
        // contextTokens は出力を数えず、重みも掛けない「今読んでいる量」のスナップショット
        let usage: [String: Any] = ["input_tokens": 1, "cache_read_input_tokens": 236_780,
                                    "cache_creation_input_tokens": 3_659, "output_tokens": 894]
        let ctx = TranscriptParser.contextTokens(usage)
        let sp = TranscriptParser.spend(usage)
        assert(ctx == 240_440, "contextTokens が実測とずれた。実際: \(ctx)")
        assert(!near(Double(ctx), sp),
               "spend が contextTokens と同じ値になった（別物のはず）。ctx: \(ctx) / spend: \(sp)")
    }

    /// 直したバグの固定：サブエージェントの文脈が親セッションの雪だるまに混入しないこと。
    /// メインセッション行（`agentId` を持たず `agent == session`）だけが雪だるまを動かし、
    /// サブエージェント行（`agent != session`）は台帳に消費を積むだけで readings[session] には触れない。
    /// ここを戻すと、サブエージェントが読むたびにメインの雪だるまが伸び縮みして誤警報・見逃しが起きる
    static func keepsSubagentSpendOffTheSnowman() {
        let c = Cockpit()
        func feed(_ line: String) {
            c.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: "S9"))
        }

        // メインセッション行。大きな usage を通して雪だるまを育てる
        let main = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:00.000Z","sessionId":"S9",\
        "message":{"model":"claude-opus-5","usage":{"input_tokens":2,\
        "cache_read_input_tokens":500000,"cache_creation_input_tokens":1000,\
        "output_tokens":100},"content":[]}}
        """
        feed(main)
        c.selectedSession = "S9"
        let afterMain = c.reading.tokens
        assert(afterMain == 501_002, "メイン行が雪だるまに届いていない。実際: \(afterMain)")

        // サブエージェント行。同じセッションだが agentId を持ち、usage は小さい
        let sub = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:05.000Z","sessionId":"S9",\
        "agentId":"sub1","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":1,\
        "cache_read_input_tokens":100,"cache_creation_input_tokens":50,\
        "output_tokens":10},"content":[]}}
        """
        feed(sub)
        assert(c.reading.tokens == afterMain,
               "サブエージェントの文脈が親の雪だるまに混入した。メイン: \(afterMain) → 実際: \(c.reading.tokens)")

        // 一方で、サブエージェントの消費そのものは台帳に積まれている
        let chips = c.snapshot(now: TranscriptParser.date("2026-08-01T00:01:00.000Z")!, mode: .work).chips
        guard let subChip = chips.first(where: { $0.id == "sub1" }) else {
            fatalError("サブエージェントのチップが台帳に無い")
        }
        assert(subChip.spent > 0, "サブエージェントの消費が台帳に積まれていない")

        guard let mainChip = chips.first(where: { $0.id == "S9" }) else {
            fatalError("メインセッションのチップが台帳に無い")
        }
        assert(mainChip.spent > 0, "メインセッションの消費が台帳に積まれていない")
    }

    /// 同じセッション内で消費量の比に沿って `share` が按分されること、
    /// 別セッションのエージェントが分母に混ざらないことを固定する
    static func splitsSpendAcrossAgents() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

        let c = Cockpit()
        func feed(_ line: String) {
            c.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: "S1"))
        }
        func turn(session: String, agent: String?, at: String, inputTokens: Int) -> String {
            let agentField = agent.map { ",\"agentId\":\"\($0)\"" } ?? ""
            return """
            {"type":"assistant","sessionId":"\(session)"\(agentField),"timestamp":"\(at)",\
            "message":{"model":"claude-opus-5","usage":{"input_tokens":\(inputTokens)},"content":[]}}
            """
        }

        // メイン1000 / sub1 2000 / sub2 3000。合計6000で比は 1:2:3
        feed(turn(session: "S1", agent: nil, at: "2026-08-01T00:00:00.000Z", inputTokens: 1000))
        feed(turn(session: "S1", agent: "sub1", at: "2026-08-01T00:00:01.000Z", inputTokens: 2000))
        feed(turn(session: "S1", agent: "sub2", at: "2026-08-01T00:00:02.000Z", inputTokens: 3000))
        // MCP ワーカーも同じセッションに混ぜる。`spent == 0` なので合計からは除いて検算する
        feed(#"{"type":"assistant","sessionId":"S1","timestamp":"2026-08-01T00:00:03.000Z","message":{"content":[{"type":"tool_use","id":"m1","name":"mcp__codex__codex","input":{"prompt":"調査"}}]}}"#)

        let now = TranscriptParser.date("2026-08-01T00:01:00.000Z")!
        let chips = c.snapshot(now: now, mode: .work).chips
        guard let mainChip = chips.first(where: { $0.id == "S1" }),
              let sub1 = chips.first(where: { $0.id == "sub1" }),
              let sub2 = chips.first(where: { $0.id == "sub2" }),
              let mcp = chips.first(where: { $0.model == "MCP" })
        else { fatalError("按分の検算に必要なチップが揃わない") }

        assert(near(mainChip.share, 1.0 / 6.0), "メインの割合。実際: \(mainChip.share)")
        assert(near(sub1.share, 2.0 / 6.0), "sub1 の割合。実際: \(sub1.share)")
        assert(near(sub2.share, 3.0 / 6.0), "sub2 の割合。実際: \(sub2.share)")
        assert(sub2.share > mainChip.share, "多く食ったエージェントの割合が大きくならない")
        assert(mcp.spent == 0 && mcp.share == 0, "spentが0のMCPワーカーに割合が付いた")

        let spentShares = [mainChip, sub1, sub2].map(\.share)
        assert(near(spentShares.reduce(0, +), 1.0),
               "spentが0のチップを除いた合計が1.0にならない。実際: \(spentShares.reduce(0, +))")

        // 別セッションのエージェントを足しても、元のセッションの割合は変わらない
        feed(turn(session: "S2", agent: nil, at: "2026-08-01T00:00:04.000Z", inputTokens: 100_000))
        let after = c.snapshot(now: now, mode: .work).chips
        let mainAfter = after.first { $0.id == "S1" }
        assert(mainAfter.map { near($0.share, mainChip.share) } == true,
               "別セッションのエージェントが分母に混ざった。前: \(mainChip.share) 後: \(mainAfter?.share ?? -1)")

        // 消費が1件も無ければ、全チップの share は0で、割り算で落ちない
        let empty = Cockpit()
        empty.apply([.agentActivity(agent: "z1", session: "Z", model: "opus-5", at: now),
                     .agentActivity(agent: "z2", session: "Z", model: "opus-5", at: now)])
        let emptyChips = empty.snapshot(now: now, mode: .work).chips
        assert(!emptyChips.isEmpty && emptyChips.allSatisfy { $0.share == 0 },
               "消費0件のときにshareが0以外になった、または割り算で落ちた")

        // chipTrailing: 表示に出す割合の丸め・しきい値を固定する。
        // ここに置くのは、割合ロジックの置き場所（CockpitLayout）が p0-selfcheck の
        // 検査対象だとコメントで明示されているのと、直前で share の値そのものを作っているため
        func chip(share: Double, model: String = "opus-5", work: Int = 3) -> AgentChip {
            AgentChip(id: "x", role: "role", model: model, depth: 0, parent: nil,
                      work: work, doing: "", done: false, busy: false,
                      target: nil, kind: nil, lastAt: .distantPast,
                      instruction: "", counts: [], spent: share > 0 ? 1 : 0, share: share)
        }
        let sixtyTwo = CockpitLayout.chipTrailing(chip(share: 0.62))
        assert(sixtyTwo.contains("62%"), "62%の表示が出ない。実際: \(sixtyTwo)")

        let underOnePercent = CockpitLayout.chipTrailing(chip(share: 0.004))
        assert(!underOnePercent.contains("%"), "1%未満なのに%が出た。実際: \(underOnePercent)")

        let rounded = CockpitLayout.chipTrailing(chip(share: 0.015))
        assert(rounded.contains("2%"), "四捨五入が崩れた。実際: \(rounded)")

        let bare = chip(share: 0, model: "", work: 0)
        assert(CockpitLayout.chipTrailing(bare).isEmpty,
               "modelが空・workが0なのに何か出た。実際: \(CockpitLayout.chipTrailing(bare))")
    }

    /// `share` の分母は「表示中のチップ」ではなく「そのセッションの全履歴」（畳んだ分・消した分も含む）。
    /// **これは意図した挙動**——`buildChips` のコメント参照。「非アクティブを消す」で
    /// 大食いのエージェントを畳んだあと、残った側が 5% / 3% と出るのは「多く食ったのは畳んだ側」
    /// という正しい情報で、ここで表示中だけに揃えて 100% に再正規化すると、
    /// 残っただけの脇役を大食いの犯人と誤認させてしまう。
    /// **この検査は、将来ここを「バグ」だと誤解して直そうとした人が、検査が落ちた時点で
    /// 「これは意図的だった」と気づけるようにするための固定**
    static func clearsDoNotRenormalizeShare() {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

        let base = Date(timeIntervalSince1970: 80_000_000)
        let recent = base.addingTimeInterval(10_000)   // clearIdleAgents の直前まで動いていた
        let old = base                                  // 無音窓(15秒)よりずっと前で止まっている

        let c = Cockpit()
        // main と visible は直近に動いたので busy のまま残る。hidden は古いまま止まっていて畳まれる対象
        c.apply([.context(session: "S5", agent: "S5", tokens: 100, spend: 100, at: recent),
                 .context(session: "S5", agent: "visible", tokens: 100, spend: 100, at: recent),
                 .context(session: "S5", agent: "hidden", tokens: 800, spend: 800, at: old)])

        // hidden から見ると無音窓を越えているが、main / visible から見ればまだ越えていない時刻
        let now = recent.addingTimeInterval(5)
        c.clearIdleAgents(now: now)

        let chips = c.snapshot(now: now, mode: .work).chips
        assert(!chips.contains { $0.id == "hidden" },
               "この検査の前提が崩れている（畳まれるはずの hidden がまだ見えている）")
        guard let main = chips.first(where: { $0.id == "S5" }),
              let visible = chips.first(where: { $0.id == "visible" })
        else { fatalError("残るはずのチップが見つからない") }

        // 畳む前の分母は 1000（100 + 100 + 800）のまま。畳んでも分母は動かさない設計なので、
        // 消費量に対する share（0.1 ずつ）は畳む前と変わらない
        assert(near(main.share, 0.1) && near(visible.share, 0.1),
               "分母を表示中のチップだけに揃え直した——ここは意図的に全履歴を分母にしている。"
               + "実際: main=\(main.share) visible=\(visible.share)")

        // 残った側だけで合計しても 1.0 未満（= 800 ぶんの大食いが畳んだ側にいたという情報が消えていない）
        let visibleTotal = main.share + visible.share
        assert(visibleTotal < 0.99,
               "畳んだ分が分母から抜けて、残ったチップだけでほぼ 1.0 に再正規化された。実際: \(visibleTotal)")
    }

    /// モデルの言葉。tool_use しか見ていなかったので、これまで1文字も出ていなかった
    static func readsWhatModelSaid() {
        let line = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:00.000Z","sessionId":"S1",\
        "message":{"model":"claude-opus-5","content":[\
        {"type":"thinking","thinking":"どこを直すか考える"},\
        {"type":"text","text":"Gate.swift を直します"},\
        {"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/p/Gate.swift"}}]}}
        """
        let c = Cockpit()
        c.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: "S1"))
        assert(c.messages.count == 2, "言葉が2件取れていない: \(c.messages.count)")
        assert(c.messages.contains { !$0.thinking && $0.text == "Gate.swift を直します" }, "発言が取れない")
        assert(c.messages.contains { $0.thinking && $0.text == "どこを直すか考える" }, "思考が取れない")

        // **実データの thinking は本文が空**（実測で全12セッション458件すべて `signature` だけ）。
        // 本文を条件にすると「考えた」印が実データで一度も立たず、
        // 司令塔が思考中もアイドルに見える元の症状に戻る
        let redacted = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:01.000Z","sessionId":"S1",\
        "message":{"content":[{"type":"thinking","thinking":"","signature":"abc"}]}}
        """
        c.apply(TranscriptParser.parse(Data(redacted.utf8), fallbackSession: "S1"))
        assert(c.messages.count == 3, "本文の無い思考を落とした（実データはこれしか来ない）")
        assert(c.messages.last?.thinking == true && c.messages.last?.text.isEmpty == true)

        // 発言の方は空なら積まない。空の吹き出しが並ぶだけで何も伝わらない
        let empty = """
        {"type":"assistant","timestamp":"2026-08-01T00:00:02.000Z","sessionId":"S1",\
        "message":{"content":[{"type":"text","text":""}]}}
        """
        c.apply(TranscriptParser.parse(Data(empty.utf8), fallbackSession: "S1"))
        assert(c.messages.count == 3, "空の発言を積んだ")

        // 送る側の1行。実測でこの形が通ることを確かめてある
        let payload = Launcher.messageLine("直して\"引用\"入り")
        assert(payload?.last == 0x0A, "改行が無いと相手が読み始めない")
        let decoded = (try? JSONSerialization.jsonObject(with: payload!)) as? [String: Any]
        assert(decoded?["type"] as? String == "user", "type が user でない")
        let content = ((decoded?["message"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        assert(content?["text"] as? String == "直して\"引用\"入り", "引用符が壊れた")
    }

    /// `TranscriptParser.humanText(from:)` と、user 行から `.said(speaker: .human)` が出ること。
    /// **人間の発言が出ないと司令塔との窓口が会話にならない**ので、拾い漏れ・混入の両方を固定する
    static func showsWhatTheHumanSaid() {
        // content が素の文字列
        assert(TranscriptParser.humanText(from: ["content": "直して"]) == "直して",
               "素の文字列の content が取れない")

        // content が配列（text ブロック1件）
        let single: [String: Any] = ["content": [["type": "text", "text": "直して"]]]
        assert(TranscriptParser.humanText(from: single) == "直して", "配列の text ブロックが取れない")

        // text ブロックが複数 → 連結される
        let multi: [String: Any] = ["content": [["type": "text", "text": "直し"],
                                                 ["type": "text", "text": "て"]]]
        assert(TranscriptParser.humanText(from: multi) == "直して", "複数の text ブロックが連結されない")

        // tool_result のみ → ツールの返答は人間の言葉ではない
        let toolResultOnly: [String: Any] = ["content": [["type": "tool_result", "tool_use_id": "t1",
                                                           "content": "結果"]]]
        assert(TranscriptParser.humanText(from: toolResultOnly) == nil, "tool_result を人間の発言と誤認した")

        // isMeta: true（message の中）
        let meta: [String: Any] = ["isMeta": true, "content": "直して"]
        assert(TranscriptParser.humanText(from: meta) == nil, "isMeta を無視して拾ってしまった")

        // 空文字・空白のみ
        assert(TranscriptParser.humanText(from: ["content": ""]) == nil, "空文字を発言として拾った")
        assert(TranscriptParser.humanText(from: ["content": "   \n"]) == nil, "空白のみを発言として拾った")

        // content が無い
        assert(TranscriptParser.humanText(from: [:]) == nil, "content が無いのに発言が出た")

        // 通し: 生 JSON の user 行 → TranscriptParser.parse → Cockpit.apply →
        // messages に speaker == .human の1件が入ること
        let userLine = """
        {"type":"user","sessionId":"S1","timestamp":"2026-08-01T00:00:00.000Z",\
        "message":{"role":"user","content":"直して"}}
        """
        let c = Cockpit()
        c.apply(TranscriptParser.parse(Data(userLine.utf8), fallbackSession: "S1"))
        assert(c.messages.count == 1, "人間の発言が1件取れていない: \(c.messages.count)")
        // `Speaker` は Equatable を宣言していないため `==` は使わない（パターンマッチで見る）
        if case .human? = c.messages.first?.speaker {} else { fatalError("話し手が human でない") }
        assert(c.messages.first?.text == "直して", "人間の発言の中身が違う: \(c.messages.first?.text ?? "無し")")

        // toolUseResult を持つ行を流しても発言は増えない
        let toolLine = """
        {"type":"user","sessionId":"S1","timestamp":"2026-08-01T00:00:01.000Z",\
        "toolUseResult":{"filePath":"/p/a.swift"},\
        "message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"結果"}]}}
        """
        c.apply(TranscriptParser.parse(Data(toolLine.utf8), fallbackSession: "S1"))
        assert(c.messages.count == 1, "toolUseResult を持つ行で発言が増えた: \(c.messages.count)")

        // isMeta: true が行の直下にある行でも増えない
        let metaLine = """
        {"type":"user","sessionId":"S1","timestamp":"2026-08-01T00:00:02.000Z","isMeta":true,\
        "message":{"role":"user","content":"直して2"}}
        """
        c.apply(TranscriptParser.parse(Data(metaLine.utf8), fallbackSession: "S1"))
        assert(c.messages.count == 1, "isMeta の行で発言が増えた: \(c.messages.count)")

        // 人間の発言でチップが「思考中」にならないこと。
        // thoughtAt は speaker == .model && thinking の時だけ進むはずで、人間の発言では動かない
        let chip = c.snapshot(now: Date(timeIntervalSince1970: 1_700_000_100), mode: .work)
            .chips.first { $0.id == "S1" }
        assert(chip?.doing.hasPrefix("思考中") != true,
               "人間の発言なのに思考中と出た: \(chip?.doing ?? "無し")")
    }

    /// 司令塔は考えている間ツールを呼ばない。沈黙だけで見るとアイドルに落ちる
    static func orchestratorStaysBusyWhileThinking() {
        let t0 = Date(timeIntervalSince1970: 70_000_000)
        let c = Cockpit()
        c.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0),
                 .agentAction(id: "a1", agent: "S1", session: "S1", kind: .search,
                              detail: "grep Snowman", at: t0)])

        // activeWindow(15秒) を越えて沈黙すると、transcript だけではアイドルに見える
        let later = t0.addingTimeInterval(60)
        var chips = c.snapshot(now: later, mode: .work).chips
        assert(chips.first(where: { $0.id == "S1" })?.busy == false,
               "この検査の前提が崩れている（沈黙しても busy のまま）")

        // Claude Code 自身が busy と言っていれば、そちらが真値
        c.liveSessions = [LiveSession(id: "S1", name: "S1", cwd: "/p", busy: true)]
        chips = c.snapshot(now: later, mode: .work).chips
        let root = chips.first { $0.id == "S1" }
        assert(root?.busy == true, "セッションが busy なのに司令塔がアイドルのまま")

        // 考えている間は「1つ前にやったこと」を今やっているかのように出さない。
        // 本文が空なのは実データそのままの形（thinking の中身は残らない）
        c.apply([.said(agent: "S1", session: "S1", text: "", speaker: .model, thinking: true,
                       at: t0.addingTimeInterval(30))])
        let thinking = c.snapshot(now: later, mode: .work).chips.first { $0.id == "S1" }
        assert(thinking?.doing.hasPrefix("思考中") == true, "実際: \(thinking?.doing ?? "無し")")
        assert(thinking?.doing.contains("30秒") == true, "考えている長さが出ていない")

        // ツールを呼んだらそちらが新しい。考えた印が残っていても作業の方を出す
        c.apply([.agentAction(id: "a2", agent: "S1", session: "S1", kind: .edit,
                              detail: "Gate.swift", at: t0.addingTimeInterval(40))])
        let acting = c.snapshot(now: later, mode: .work).chips.first { $0.id == "S1" }
        assert(acting?.doing == "編集 Gate.swift", "実際: \(acting?.doing ?? "無し")")

        // サブエージェントはセッションの busy を借りない（親が動いていても子は子）
        c.apply([.agentMeta(agent: "w0", session: "S1", role: "ワーカー", depth: 1, parentCall: "c0"),
                 .agentActivity(agent: "w0", session: "S1", model: "haiku-4.5", at: t0)])
        let worker = c.snapshot(now: later, mode: .work).chips.first { $0.id == "w0" }
        assert(worker?.busy == false, "止まっている子が親の busy を借りた")

        // 承認ダイアログ中。sessions/<pid>.json の実測の形（v2.1.282）をそのまま通す
        assert(Cockpit.waitingLabel(status: "waiting", waitingFor: "permission prompt") == "承認待ち")
        assert(Cockpit.waitingLabel(status: "waiting", waitingFor: "input needed") == "入力待ち")
        assert(Cockpit.waitingLabel(status: "busy", waitingFor: nil) == nil)
        c.liveSessions = [LiveSession(id: "S1", name: "S1", cwd: "/p", busy: false,
                                      waiting: Cockpit.waitingLabel(status: "waiting",
                                                                    waitingFor: "permission prompt"))]
        let chipsWaiting = c.snapshot(now: later, mode: .work).chips
        let asking = chipsWaiting.first { $0.id == "S1" }
        // 待っている道具（直前の作業）まで出す。止まっているので「思考中」でも内訳でもない
        assert(asking?.waiting == "承認待ち" && asking?.doing == "承認待ち · 編集 Gate.swift",
               "実際: \(asking?.doing ?? "無し")")
        assert(chipsWaiting.first { $0.id == "w0" }?.waiting == nil, "セッションの待ちが子に載った")
        // 直前に動いていても（最後の作業から1秒後）、待っている間は稼働中にしない
        let justAsked = c.snapshot(now: t0.addingTimeInterval(41), mode: .work).chips.first { $0.id == "S1" }
        assert(justAsked?.waiting == "承認待ち" && justAsked?.busy == false, "承認待ちなのに稼働中のランプが点く")
    }

    // MARK: 門（人間の介入）

    /// `claude` に渡す引数。ここが狂うと、起こしたセッションを AT22 が見失う
    static func buildsClaudeArguments() {
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
        func args(_ level: Gate.Level, tools: [String] = []) -> [String] {
            Launcher.arguments(sessionID: id,
                               config: Launcher.Config(cwd: "/proj", level: level,
                                                       prompt: "直して", allowedTools: tools))
        }
        let normal = args(.normal)

        // transcript のファイル名は小文字。大文字のまま渡すと、起こした本人を引けない
        let session = normal[normal.firstIndex(of: "--session-id")! + 1]
        assert(session == "3f2504e0-4f89-11d3-9a0c-0305e82c3301",
               "セッションIDが小文字になっていない: \(session)")
        assert(normal.contains("-p"), "端末の無い GUI から対話モードで起こそうとしている")
        // **指示は argv に置かない。** 置くと1往復で stdin が閉じてセッションごと終わり、
        // 後から割り込めなくなる。最初の指示も割り込みも同じ stdin を通す
        assert(!normal.contains("直して"), "指示が argv に載っている（1往復で終わってしまう）")
        assert(normal.contains("--input-format") && normal.contains("stream-json"),
               "割り込める形で起こしていない")
        // claude 側の要求。欠けると起動そのものが弾かれる
        assert(normal.contains("--verbose"), "--output-format stream-json に --verbose が要る")

        func mode(_ level: Gate.Level) -> String {
            let a = args(level)
            return a[a.firstIndex(of: "--permission-mode")! + 1]
        }
        assert(mode(.plan) == "plan", "壁打ちが編集できる段に落ちた")
        assert(mode(.each) == "acceptEdits" && mode(.normal) == "acceptEdits",
               "段の違いは門が持つ。permission-mode で分けるものではない")
        assert(mode(.auto) == "bypassPermissions" && mode(.unattended) == "bypassPermissions",
               "任せてる／留守番が確認を求める段に落ちた")
        // 端末が無いので manual は使えない。誰も答えられないまま待ち続ける
        assert(!Gate.Level.allCases.contains { $0.permissionMode == "manual" },
               "訊く相手が居ない段で manual を渡している")

        // 無人で走るのは留守番だけ
        for level in Gate.Level.allCases {
            assert(args(level).contains("--bg") == (level == .unattended),
                   "\(level.title) の --bg が違う")
        }

        // 白名簿は渡した時だけ出す（空で渡すと claude 側が全部禁止と解釈しうる）
        let listed = args(.normal, tools: ["Read", "Grep"])
        assert(listed.contains("--allowedTools") && listed.contains("Grep"), "白名簿が渡らない")
        assert(!normal.contains("--allowedTools"), "空の白名簿でフラグだけ渡した")

        // シェルの返事。**実体と PATH は片方だけ取れることがある**——
        // 実測で、GUI と同じ最小環境では `command -v claude` だけが空を返した。
        // そこで PATH まで捨てると、npm 入れの claude を node の無い PATH で起こすことになる
        let both = Launcher.parseShellReply("/bin/sh\n\n/usr/bin:/bin")
        assert(both.executable?.path == "/bin/sh" && both.path == "/usr/bin:/bin", "両方取れていない")
        let pathOnly = Launcher.parseShellReply("\n/usr/bin:/bin")
        assert(pathOnly.executable == nil && pathOnly.path == "/usr/bin:/bin",
               "実体が空の時に PATH まで捨てた")
        assert(Launcher.parseShellReply("").executable == nil, "空の返事で落ちた")
        // 実行できないものを掴まない（同名のディレクトリやテキストを渡された場合）
        assert(Launcher.parseShellReply("/etc/hosts\n/usr/bin").executable == nil,
               "実行できないものを claude として掴んだ")
    }

    /// 既にあるセッションの続きに繋ぐ引数。**`--resume` と `--session-id` は排他**で、
    /// 両方渡すと claude が弾く。ここが狂うと履歴から開いた会話に一言も送れない
    static func resumesWithoutMintingANewSession() {
        let config = Launcher.Config(cwd: "/proj", level: .normal, prompt: "続けて")
        let args = Launcher.resumeArguments(sessionID: "7E04693D-3B1A-4111-A60D-DF295E96D95F",
                                            config: config)

        assert(!args.contains("--session-id"), "--resume と --session-id を同時に渡している")
        let id = args[args.firstIndex(of: "--resume")! + 1]
        // transcript のファイル名は小文字。大文字のまま渡すと繋ぐ先を取り違える
        assert(id == "7e04693d-3b1a-4111-a60d-df295e96d95f", "セッションIDが小文字になっていない: \(id)")

        // 送る口は起こす時とまったく同じ形でないといけない。
        // ここが欠けると繋がっても言葉が通らない
        assert(args.contains("-p") && args.contains("--verbose"), "起こす時と形が違う")
        assert(args.contains("--input-format") && args.contains("stream-json"),
               "繋いでも言葉を送れない形になっている")
        assert(!args.contains("続けて"), "指示が argv に載っている（1往復で終わってしまう）")

        // 承認の段とモデルは起こす時と同じ規則で乗ること
        assert(args[args.firstIndex(of: "--permission-mode")! + 1] == "acceptEdits")
        let plain = Launcher.resumeArguments(sessionID: "s1", config: config)
        assert(!plain.contains("--model"), "モデル未指定なのに --model を渡した（元の設定を潰す）")
        let picked = Launcher.resumeArguments(
            sessionID: "s1",
            config: Launcher.Config(cwd: "/p", level: .normal, prompt: "", model: "sonnet"))
        assert(picked[picked.firstIndex(of: "--model")! + 1] == "sonnet", "選んだモデルが渡らない")

        // codex の続き。`exec resume` は -C / --sandbox を弾くので、sandbox は -c で渡す
        let codex = CodexLauncher.Config(cwd: "/proj", level: .normal, prompt: "", model: "gpt-5.4")
        let resumed = CodexLauncher.resumeArguments(threadID: "t1", prompt: "続けて", config: codex)
        assert(!resumed.contains("-C") && !resumed.contains("--sandbox"), "resume が弾く引数を渡している: \(resumed)")
        assert(resumed[resumed.firstIndex(of: "-c")! + 1] == #"sandbox_mode="workspace-write""#, "\(resumed)")
        let unattended = CodexLauncher.Config(cwd: "/proj", level: .unattended, prompt: "", model: "gpt-5.4")
        assert(CodexLauncher.resumeArguments(threadID: "t1", prompt: "x", config: unattended)
            .contains("--dangerously-bypass-approvals-and-sandbox"), "Lv.5 の段が resume で落ちた")
    }

    /// 会話に出す「誰を何のために呼んだか」。**`description` は以前まで捨てていた**ので、
    /// 拾えていることと、時刻順に並ぶことの両方を押さえる
    static func remembersWhoWasCalledAndWhatFor() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 61_000_000)
        c.apply([.agentSpawn(call: "c2", by: "S1", session: "S1", type: "Explore",
                             title: "凡例の実装箇所を探す", at: t0.addingTimeInterval(10)),
                 .agentSpawn(call: "c1", by: "S1", session: "S1", type: "general-purpose",
                             title: "p0 に検査を足す", at: t0),
                 // 別セッションのぶんは混ざらない
                 .agentSpawn(call: "x1", by: "S2", session: "S2", type: "Explore",
                             title: "よそ", at: t0)])

        let mine = c.agentCalls(session: "S1")
        assert(mine.count == 2, "セッションで絞れていない (実際: \(mine.count))")
        assert(mine.map(\.title) == ["凡例の実装箇所を探す", "p0 に検査を足す"],
               "作業内容のタイトルを拾えていない")
        assert(mine.contains { $0.type == "Explore" }, "subagent_type を拾えていない")
        // 会話に混ぜる側が時刻で並べ替えるので、ここは届いた順で持っていればよい
        assert(c.agentCalls(session: nil).count == 3, "セッション未選択で全部出ない")

        // 同じ呼び出しを二度読んでも増えない（transcript は末尾から読み直されうる）
        c.apply([.agentSpawn(call: "c1", by: "S1", session: "S1", type: "general-purpose",
                             title: "p0 に検査を足す", at: t0)])
        assert(c.agentCalls(session: "S1").count == 2, "同じ呼び出しが二重に積まれた")

        // 実体が結びつくと終わったかどうかが引ける
        assert(c.callFinished("c1") == nil, "まだ結びついていない呼び出しが状態を返した")
        c.apply([.agentMeta(agent: "w1", session: "S1", role: "検査", depth: 1, parentCall: "c1"),
                 .agentActivity(agent: "w1", session: "S1", model: "haiku-4.5", at: t0)])
        assert(c.callFinished("c1") == false, "走っている呼び出しが終了扱いになった")
        c.apply([.agentEnded(agent: "w1", at: t0.addingTimeInterval(30))])
        assert(c.callFinished("c1") == true, "終わった呼び出しが実行中のまま")
    }

    /// stdout の1行を `StreamEvent` に変換する。**この窓は司令塔との窓口なので、
    /// 「失敗したのに成功に見える」ことが最大の欠陥**。そこを重点的に固定する
    static func readsStdoutWithoutLying() {
        func parse(_ json: String) -> Launcher.StreamEvent? {
            Launcher.parseStreamLine(Data(json.utf8))
        }

        // 部分テキスト
        let delta = """
        {"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"あ"}}}
        """
        guard case let .partialText(text) = parse(delta) else { fatalError("部分テキストが取れない") }
        assert(text == "あ", "部分テキストの中身が違う: \(text)")

        // 正常終了
        let success = """
        {"type":"result","subtype":"success","is_error":false}
        """
        guard case .turnEnded = parse(success) else { fatalError("正常終了が turnEnded にならない") }

        // **失敗が握り潰されていないこと。** 理由に本文がそのまま残っているかまで見る
        let failed = """
        {"type":"result","subtype":"error_during_execution","is_error":true,"result":"落ちた"}
        """
        guard case let .turnFailed(reason) = parse(failed) else {
            fatalError("失敗が turnFailed にならない（司令塔に成功と誤報している）")
        }
        assert(reason.contains("落ちた"), "失敗理由が握り潰されている: \(reason)")

        // subtype が無くても is_error だけで失敗と分かる
        let noSubtype = """
        {"type":"result","is_error":true}
        """
        guard case .turnFailed = parse(noSubtype) else { fatalError("subtype が無い失敗を見逃した") }

        // success 以外の subtype は知らない値でも全部失敗として扱う
        let unknownSubtype = """
        {"type":"result","subtype":"知らない値"}
        """
        guard case .turnFailed = parse(unknownSubtype) else {
            fatalError("知らない subtype を成功扱いした")
        }

        // 割り込みの受領確認。request_id と内訳の両方が正しく取れること
        let ack = """
        {"type":"control_response","response":{"subtype":"success","request_id":"r1","response":{"still_queued":["a","b"],"cancelled":["c"]}}}
        """
        guard case let .interruptAcknowledged(requestID, stillQueued, cancelled) = parse(ack) else {
            fatalError("割り込み受領が取れない")
        }
        assert(requestID == "r1", "request_id が違う: \(requestID)")
        assert(stillQueued == 2, "stillQueued が違う: \(stillQueued)")
        assert(cancelled == 1, "cancelled が違う: \(cancelled)")

        // 古い版（response が空オブジェクト）。stillQueued/cancelled は0として扱い、
        // エラー扱いにしない裏取り
        let oldAck = """
        {"type":"control_response","response":{"subtype":"success","request_id":"r1","response":{}}}
        """
        guard case let .interruptAcknowledged(_, stillQueuedOld, cancelledOld) = parse(oldAck) else {
            fatalError("古い版の受領確認が取れない")
        }
        assert(stillQueuedOld == 0 && cancelledOld == 0,
               "古い版なのに内訳が0でない: \(stillQueuedOld)/\(cancelledOld)")

        // 弾かれた割り込み（実測の文言そのまま）。受領扱いにすると止まったと思い込む
        let rejected = """
        {"type":"control_response","response":{"subtype":"error","request_id":"r1","error":"Unsupported control request subtype: undefined"}}
        """
        guard case let .error(why) = parse(rejected), why.contains("Unsupported") else {
            fatalError("弾かれた割り込みを受領扱いした")
        }

        // API 再試行。文言に理由が残っていること
        let retry = """
        {"type":"system","subtype":"api_retry","error":"rate_limit","attempt":2,"max_retries":5}
        """
        guard case let .error(message) = parse(retry) else { fatalError("api_retry が error にならない") }
        assert(message.contains("rate_limit"), "rate_limit の文言が消えている: \(message)")

        // セッションの立ち上がり
        let initLine = """
        {"type":"system","subtype":"init"}
        """
        guard case .initialized = parse(initLine) else { fatalError("init が initialized にならない") }

        // サブエージェントの言葉。司令塔の言葉に混ぜてはいけない
        let subAgentDelta = """
        {"type":"stream_event","parent_tool_use_id":"parent1",\
        "event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"子"}}}
        """
        assert(parse(subAgentDelta) == nil, "サブエージェントの部分テキストを拾ってしまった")

        // parent_tool_use_id が null の行は通常どおり拾える
        let nullParent = """
        {"type":"stream_event","parent_tool_use_id":null,\
        "event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"い"}}}
        """
        guard case let .partialText(text2) = parse(nullParent) else {
            fatalError("parent_tool_use_id が null の行を落とした")
        }
        assert(text2 == "い", "parent_tool_use_id が null の行の中身が違う: \(text2)")

        // 壊れた JSON・空データ・知らない type は nil で落ちない
        assert(parse("{not json") == nil, "壊れた JSON を通してしまった")
        assert(Launcher.parseStreamLine(Data()) == nil, "空データを通してしまった")
        let unknownType = """
        {"type":"知らない型"}
        """
        assert(parse(unknownType) == nil, "知らない type を通してしまった")
    }

    /// 走っているターンを止める1行。**改行が無いと相手が読み始めない**のは messageLine と同じだが、
    /// 中身は別物（`control_request` / `interrupt`）——ここを messageLine と混同すると、
    /// 止めたつもりの行がただの発言として処理され、ターンは止まらないまま新しい発言だけが積まれる
    static func interruptLineStopsWithoutKilling() {
        guard let payload = Launcher.interruptLine() else { fatalError("interruptLine が nil を返した") }
        assert(payload.last == 0x0A, "改行が無いと相手が読み始めない")

        let decoded = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
        assert(decoded?["type"] as? String == "control_request",
               "type が control_request でない (実際: \(decoded?["type"] ?? "nil"))")
        let request = decoded?["request"] as? [String: Any]
        // キーは subtype。type で送ると claude が弾いてターンが止まらない（v2.1.282 実測）
        assert(request?["subtype"] as? String == "interrupt",
               "request.subtype が interrupt でない (実際: \(request ?? [:]))")
        let requestID = decoded?["request_id"] as? String
        assert(requestID?.isEmpty == false, "request_id が空文字")

        // 明示した ID を渡せば、そのままの値が入ること
        guard let explicit = Launcher.interruptLine(requestID: "fixed-id-1") else {
            fatalError("requestID を指定した呼び出しが nil を返した")
        }
        let explicitDecoded = (try? JSONSerialization.jsonObject(with: explicit)) as? [String: Any]
        assert(explicitDecoded?["request_id"] as? String == "fixed-id-1",
               "指定した request_id が入っていない (実際: \(explicitDecoded?["request_id"] ?? "nil"))")

        // 既定引数では毎回違う ID になること。固定だと、前の割り込みへの受領確認と
        // 新しい割り込みの受領確認を相手側が取り違えかねない
        guard let firstData = Launcher.interruptLine(), let secondData = Launcher.interruptLine() else {
            fatalError("既定引数の呼び出しが nil を返した")
        }
        let firstID = ((try? JSONSerialization.jsonObject(with: firstData)) as? [String: Any])?["request_id"] as? String
        let secondID = ((try? JSONSerialization.jsonObject(with: secondData)) as? [String: Any])?["request_id"] as? String
        assert(firstID != nil && secondID != nil && firstID != secondID,
               "既定引数なのに request_id が固定されている (1回目: \(firstID ?? "nil"), 2回目: \(secondID ?? "nil"))")

        // messageLine とは別物であること。type が同じだと、割り込みのつもりの行が
        // ただの発言として処理され、止まってほしいターンが止まらない
        guard let messageData = Launcher.messageLine("待って") else { fatalError("messageLine が nil を返した") }
        let messageType = ((try? JSONSerialization.jsonObject(with: messageData)) as? [String: Any])?["type"] as? String
        assert(messageType == "user" && decoded?["type"] as? String == "control_request"
               && messageType != decoded?["type"] as? String,
               "interruptLine と messageLine の type が区別できていない (messageLine: \(messageType ?? "nil"), interruptLine: \(decoded?["type"] ?? "nil"))")
    }

    /// 門を読む。**答えの無いものだけ**が開いていて、`call` の無い門は捨てる——
    /// 誰を待たせているのか分からない門は、答えても届かないまま画面に居座る
    static func readsPendingGates() {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("at22-gate-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: base) }
        let memory = base.appendingPathComponent("memory")
        let dir = memory.appendingPathComponent(Gate.directory)
        try! manager.createDirectory(at: dir, withIntermediateDirectories: true)

        func put(_ name: String, _ text: String) {
            try! text.write(to: dir.appendingPathComponent(name), atomically: false, encoding: .utf8)
        }
        put("a.md", "---\ncall: t1\nby: S1\nto: Explore\nrisk: high\nissued: 2026-08-01T12:00:00Z\n---\n依存を洗う\n")
        put("b.md", "---\ncall: t2\nby: S1\nto: general-purpose\nissued: 2026-08-01T12:00:30Z\n---\n実装する\n")
        put("c.md", "---\nby: S1\nto: 迷子\nissued: 2026-08-01T11:00:00Z\n---\ncall が無い\n")
        put("d.md", "---\ncall: t4\nby: S1\nissued: 壊れた日付\n---\n日付が壊れている\n")
        put("e.md", "---\ncall: t5\nby: S1\nissued: 2026-08-01T12:00:10Z\n---\nもう答えた\n")
        put("e.verdict", "---\nverdict: allow\n---\n")

        let open = Gate.pending(memoryRoot: memory)
        let calls = open.map(\.call)
        assert(!calls.contains("t5"), "答えた門がまだ開いている")
        assert(open.count == 3, "開いている門の数が違う: \(calls)")
        assert(!calls.contains(where: \.isEmpty), "call の無い門を出した")
        // 発行順。並列に投げた分が同時に開くので、順番だけが手掛かりになる
        assert(calls.first == "t4", "壊れた日付が先頭に来ていない（遠い過去に落ちる約束）")
        assert(Array(calls.suffix(2)) == ["t1", "t2"], "発行順に並んでいない: \(calls)")

        let high = open.first { $0.call == "t1" }!
        assert(high.risk == "high" && high.to == "Explore" && high.by == "S1", "頭の値が取れていない")
        assert(high.instruction == "依存を洗う", "指示の本文が取れていない: \(high.instruction)")
        assert(high.waited(now: Date(timeIntervalSince1970: 0)) == 0, "待ち時間が負になった")
        // `to` が無ければ call で代用する。空欄のまま画面に出さない
        assert(open.first { $0.call == "t4" }!.to == "t4", "宛先の代用が効いていない")

        // 置き場ごと無くても落ちない（司令塔がまだ何も書いていない状態）
        assert(Gate.pending(memoryRoot: base.appendingPathComponent("無い")).isEmpty, "無い置き場で落ちた")
    }

    /// 門の答えは**まだ無いファイル**として生まれる。新規作成だからといって
    /// `memory/` の外へ出られてはいけない（記憶DBの保存と同じガードを通す）
    static func gateVerdictWritesOnlyInsideMemory() {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("at22-verdict-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: base) }
        let projects = base.appendingPathComponent("projects")
        let project = projects.appendingPathComponent("project")
        let memory = project.appendingPathComponent("memory")
        try! manager.createDirectory(at: memory, withIntermediateDirectories: true)
        let session = "verdict-probe"
        try! Data().write(to: project.appendingPathComponent("\(session).jsonl"))

        let cockpit = Cockpit(projectsRoot: projects)
        cockpit.selectedSession = session
        cockpit.refreshMemory()

        // `gate/` をまだ掘っていない状態から答えられる（司令塔が先に作るとは限らない）
        let gate = memory.appendingPathComponent(Gate.directory).appendingPathComponent("x.md")
        let request = Gate.Request(id: gate.path, call: "t1", by: "S1", to: "Explore",
                                   risk: "high", issued: Date(timeIntervalSince1970: 0),
                                   instruction: "元の指示")
        assert(cockpit.answer(request, .revise, revised: "書き換えた指示") == .saved,
               "gate/ が無い状態で答えられない")
        let written = try! String(contentsOfFile: Gate.verdictPath(for: request), encoding: .utf8)
        assert(written.contains("verdict: revise"), "答えの種類が書かれていない")
        assert(written.contains("書き換えた指示"), "書き換えた本文が落ちた")

        // 許可・却下は本文を持たない。持たせると司令塔が元の指示を捨ててしまう
        let plain = Gate.verdictText(.allow, at: Date(timeIntervalSince1970: 0), revised: "無視される")
        assert(!plain.contains("無視される"), "許可なのに本文が付いた")

        // 置き場の外へは作れない
        let outside = base.appendingPathComponent("outside").appendingPathComponent("x.verdict")
        assert(cockpit.saveNote(path: outside.path, text: "侵入", creating: true) == .failed,
               "memory/ の外に新規作成できた")
        assert(!manager.fileExists(atPath: outside.path), "置き場の外にファイルを作った")

        // memory/ がリンクでも外に出ない
        let elsewhere = base.appendingPathComponent("elsewhere")
        try! manager.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let linked = projects.appendingPathComponent("linked")
        try! manager.createDirectory(at: linked, withIntermediateDirectories: true)
        try! Data().write(to: linked.appendingPathComponent("linked-probe.jsonl"))
        try! manager.createSymbolicLink(at: linked.appendingPathComponent("memory"),
                                        withDestinationURL: elsewhere)
        let escaping = Cockpit(projectsRoot: projects)
        escaping.selectedSession = "linked-probe"
        escaping.refreshMemory()
        assert(escaping.saveNote(path: linked.appendingPathComponent("memory/gate/x.verdict").path,
                                 text: "侵入", creating: true) == .failed,
               "memory/ のリンク越しに新規作成できた")
        assert(!manager.fileExists(atPath: elsewhere.appendingPathComponent("gate/x.verdict").path),
               "リンクの先にファイルを作った")

        // 承認モードもファイルが正。書けて、読み戻せる
        assert(cockpit.setGateLevel(.each) == .saved, "承認モードを書けない")
        assert(Gate.level(memoryRoot: memory) == .each, "書いた承認モードを読み戻せない")
        // 二度目は既にあるファイルへの上書きになる（新規作成の経路を通らない）
        assert(cockpit.setGateLevel(.auto) == .saved, "承認モードを変えられない")
        assert(Gate.level(memoryRoot: memory) == .auto, "変えた承認モードが残っていない")

        // 門は記憶DBの一覧に出さない。答えられない場所に並べても邪魔になるだけ
        cockpit.refreshMemory()
        assert(!Memory.load(projectRoot: project).contains { $0.relative.hasPrefix(Gate.directory + "/") },
               "門がノート一覧に混ざった")
    }

    /// 承認の強さ。**保存値は変えられない**——司令塔も同じファイルを読むので、
    /// 名前を変えると既に置かれた LEVEL が黙って既定に落ちる
    static func approvalLevelDecidesWhatStops() {
        assert(!Gate.Level.plan.stops(risk: "high"), "壁打ちで門が立った")
        assert(Gate.Level.each.stops(risk: "") && Gate.Level.each.stops(risk: "high"),
               "隣で見てるが全部を止めていない")
        assert(Gate.Level.normal.stops(risk: "high") && !Gate.Level.normal.stops(risk: "low"),
               "気にかけてるが高リスクだけを止めていない")
        assert(Gate.Level.normal.stops(risk: "HIGH"), "risk の大文字小文字で判定が変わった")
        assert(!Gate.Level.auto.stops(risk: "high") && !Gate.Level.unattended.stops(risk: "high"),
               "任せてる／留守番が止まった")

        // v0.1.0 期に書かれた LEVEL がそのまま読める
        for raw in ["plan", "each", "normal", "auto", "unattended"] {
            assert(Gate.Level(rawValue: raw) != nil, "保存値 \(raw) が読めなくなった")
        }
        assert(Gate.Level.allCases.count == 5, "段の数が違う")
        assert(Gate.Level.allCases.first == .plan && Gate.Level.allCases.last == .unattended,
               "段が弱い順に並んでいない（Picker がこの順で出る）")
        assert(Gate.Level.allCases.filter(\.needsConfirmation) == [.auto, .unattended],
               "人間の承認なしに書き換える段に断りが入っていない")
        // 表示名は視点のモードと衝突するので Lv 番号で見分ける
        assert(Gate.Level.plan.title != CockpitMode.memory.title, "壁打ちの表示が2つとも同じ")

        // 壊れた LEVEL・空・ファイル無しは既定に落ちる。ここで落ちると司令塔の値も決まらない
        let manager = FileManager.default
        let memory = manager.temporaryDirectory.appendingPathComponent("at22-level-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: memory) }
        let dir = memory.appendingPathComponent(Gate.directory)
        try! manager.createDirectory(at: dir, withIntermediateDirectories: true)
        assert(Gate.level(memoryRoot: memory) == Gate.defaultLevel, "ファイル無しで既定に落ちない")
        let file = dir.appendingPathComponent(Gate.levelFile)
        for junk in ["", "  ", "全開"] {
            try! junk.write(to: file, atomically: false, encoding: .utf8)
            assert(Gate.level(memoryRoot: memory) == Gate.defaultLevel,
                   "壊れた値「\(junk)」で既定に落ちない")
        }
        // 人間が手で直す場所なので、末尾の改行が付いていても読める
        try! "auto\n".write(to: file, atomically: false, encoding: .utf8)
        assert(Gate.level(memoryRoot: memory) == .auto, "末尾の改行で読めなくなった")
    }

    /// 止まった指示は**線の上に停まる**。押せなければ司令塔は永久に待つので、
    /// 矩形を必ず持つことと、どこにも重ならないことの両方を見る
    static func stoppedOrderParksOnTheLine() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 60_000_000)
        c.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0)])
        c.apply([.agentMeta(agent: "w0", session: "S1", role: "ワーカー", depth: 1, parentCall: "call0"),
                 .agentSpawn(call: "call0", by: "S1", session: "S1", type: "Explore",
                             title: "依存を洗う", at: t0),
                 .agentActivity(agent: "w0", session: "S1", model: "haiku-4.5", at: t0)])
        c.apply(read("w0", "/proj/App.swift", "r1", at: t0))

        func gate(_ id: String, by: String, at: TimeInterval = 0) -> Gate.Request {
            Gate.Request(id: id, call: id, by: by, to: "Explore", risk: "high",
                         issued: t0.addingTimeInterval(at), instruction: "依存を洗ってください")
        }
        c.loadGatesForProbe([gate("/g/a.md", by: "S1"),
                             gate("/g/b.md", by: "S1", at: 1),
                             gate("/g/orphan.md", by: "まだ画面に居ない")])
        let snap = c.snapshot(now: t0.addingTimeInterval(2), mode: .work)
        let layout = CockpitLayout.compute(snap, width: 1100)

        // 全部が矩形を持つ。相手が分からない門も捨てない（捨てると向こうが待ち続ける）
        for g in snap.gates {
            assert(layout.rect(forGate: g.id) != nil, "門 \(g.id) が押せない")
            assert(layout.paper(forGate: g.id) != nil, "門 \(g.id) の紙が置かれていない")
        }
        let a = layout.paper(forGate: "/g/a.md")!
        let b = layout.paper(forGate: "/g/b.md")!
        let orphan = layout.paper(forGate: "/g/orphan.md")!

        // 紙はレールの右横に立つ。行の欄に食い込むと行の字と重なる
        for r in [a, b, orphan] {
            assert(r.minX > layout.railX, "紙がレールの左に出た (\(r))")
            assert(r.maxX < CockpitLayout.margin + CockpitLayout.rowOffset,
                   "紙が行の欄に食い込んだ (\(r))")
        }

        // 門は縦に積む。相手が分かるかどうかに関わらず順に並ぶ
        assert(!a.intersects(b), "同じ相手の門が重なった")
        assert(!a.intersects(orphan) && !b.intersects(orphan), "迷子の門が他と重なった")
        for r in [a, b, orphan] {
            assert(r.minX >= 0 && r.maxX <= 1100 + 0.01, "紙が画面の外 (\(r))")
            assert(r.size == CockpitLayout.gatePaper, "紙の寸法が変わった")
        }

        // 押した点が正しい門に当たる。**紙と行のどちらでも開く**
        assert(layout.gate(at: CGPoint(x: a.midX, y: a.midY)) == "/g/a.md", "紙を押しても当たらない")
        assert(layout.gate(at: CGPoint(x: a.minX - 40, y: a.midY)) != "/g/a.md", "紙の左で当たった")
        let rows = layout.chips.filter(\.gate)
        assert(rows.count == snap.gates.count, "止まった相手の行が足りない (実際: \(rows.count))")
        for row in rows {
            assert(layout.gate(at: CGPoint(x: row.rect.midX, y: row.rect.midY)) != nil,
                   "行を押しても門が開かない")
        }

        // 帯が伸びて下のカードに被らない。被ると紙もカードも読めなくなる
        let cards = layout.cards.map(\.rect)
        assert(!cards.isEmpty, "カードが1枚も出ていない（この検査が空回りしている）")
        for r in [a, b, orphan] {
            for card in cards { assert(!r.intersects(card), "紙がカードに被った (\(r) / \(card))") }
        }

        // 作業モード以外には出さない。線を出していない場所に紙だけが浮く
        assert(CockpitLayout.compute(c.snapshot(now: t0, mode: .structure), width: 1100)
                .gates.isEmpty, "構造モードに門が出た")
        assert(CockpitLayout.compute(c.snapshot(now: t0, mode: .memory), width: 1100)
                .gates.isEmpty, "壁打ちモードに門が出た")
    }

    /// 指示は Markdown で来る（codex に渡すプロンプトは実測5000字近い md）。    /// 指示は Markdown で来る（codex に渡すプロンプトは実測5000字近い md）。
    /// 1行に押し込む場所で生の記号が出ると読めない
    static func flattensMarkdownForOneLine() {
        func plain(_ s: String) -> String { CockpitLayout.plainLine(s) }
        assert(plain("## 工程A: MCP の連携") == "工程A: MCP の連携", "実際: \(plain("## 工程A: MCP の連携"))")
        assert(plain("- **受け入れ基準**を満たす") == "受け入れ基準を満たす",
               "実際: \(plain("- **受け入れ基準**を満たす"))")
        assert(plain("`Cockpit.swift` を直す") == "Cockpit.swift を直す")
        assert(plain("1行目\n2行目\n3行目") == "1行目 2行目 3行目", "改行が潰れていない")
        assert(plain("> 引用文") == "引用文")
        assert(plain("   前後の空白   ") == "前後の空白")
        assert(plain("") == "")
        // 文中の記号は残す（消しすぎると意味が変わる）
        assert(plain("A-B の対応") == "A-B の対応", "文中のハイフンまで消した")
        assert(plain("5 * 3 の計算") == "5 3 の計算" || plain("5 * 3 の計算").contains("3"),
               "実際: \(plain("5 * 3 の計算"))")
    }

    /// 「特大」は絶対量ではなく表示中の上位2%。
    /// 絶対値で決めると、大きく書いた日は画面じゅうが特大になって目印にならない
    static func hugeIsRelative() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 18_000_000)
        // 100行以上が20ファイル。上位2% ＝ 1ファイルだけが特大
        for i in 0..<20 {
            c.apply(write("a", "/p/dir/F\(i).swift", "e\(i)", at: t0.addingTimeInterval(Double(i)),
                          added: 100 + i * 10))
        }
        var snap = c.snapshot(now: t0.addingTimeInterval(30), mode: .work)
        var layout = CockpitLayout.compute(snap, width: 1200)
        var huge = layout.cards.flatMap(\.cells).filter(\.huge)
        assert(huge.count == 1, "上位2%は1ファイル (実際: \(huge.count))")
        assert(huge[0].cell.name == "F19.swift", "一番書かれたものが特大 (実際: \(huge[0].cell.name))")

        // 全部が小さければ誰も特大にならない
        let small = Cockpit()
        for i in 0..<20 {
            small.apply(write("a", "/p/dir/S\(i).swift", "s\(i)", at: t0, added: 5))
        }
        snap = small.snapshot(now: t0.addingTimeInterval(30), mode: .work)
        layout = CockpitLayout.compute(snap, width: 1200)
        huge = layout.cards.flatMap(\.cells).filter(\.huge)
        assert(huge.isEmpty, "100行未満しか無ければ特大は出ない (実際: \(huge.count))")

        // 1つだけ巨大なら、それが特大
        small.apply(write("a", "/p/dir/Big.swift", "big", at: t0.addingTimeInterval(40), added: 900))
        layout = CockpitLayout.compute(small.snapshot(now: t0.addingTimeInterval(50), mode: .work), width: 1200)
        huge = layout.cards.flatMap(\.cells).filter(\.huge)
        assert(huge.count == 1 && huge[0].cell.name == "Big.swift", "実際: \(huge.map(\.cell.name))")
    }

    /// 起動時に遡れる量が足りないと、参照回数が黙って減ってフラグが消える。
    /// 予算が尽きる時は必ず古いファイルから捨てること
    static func initialBudgetPrefersNewest() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("at22-budget-\(ProcessInfo.processInfo.processIdentifier)")
        let dir = root.appendingPathComponent("proj")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 3本、それぞれ Read 1件ぶん。更新時刻を古い順にずらす
        // （24時間の対象窓の内側に収める。外に出すと予算以前にスキップされる）
        let base = Date()
        for (i, name) in ["old", "mid", "new"].enumerated() {
            let line = readLine.replacingOccurrences(of: "/p/docs/spec.md", with: "/p/\(name).md")
            let file = dir.appendingPathComponent("\(name).jsonl")
            try? Data((line + "\n").utf8).write(to: file)
            try? FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(Double(i - 3) * 60)], ofItemAtPath: file.path)
        }
        let lineSize = UInt64(readLine.utf8.count + 1)

        // 予算が2本ぶんしか無ければ、新しい2本だけが読まれる
        var seen: [String] = []
        let tight = TranscriptWatcher(root: root, tailBytes: lineSize, initialTotalBudget: lineSize * 2)
        tight.onEvents = { events in
            for e in events {
                if case let .touchStarted(_, _, _, path, _, _) = e { seen.append(path) }
            }
        }
        tight.poll(initial: true)
        assert(seen.count == 2, "予算どおり2本だけ読む (実際: \(seen.count) \(seen))")
        assert(Set(seen) == ["/p/new.md", "/p/mid.md"],
               "古い方から捨てる (実際: \(seen))")

        // 予算が足りれば全部読める
        var all: [String] = []
        let loose = TranscriptWatcher(root: root, tailBytes: lineSize, initialTotalBudget: lineSize * 10)
        loose.onEvents = { events in
            for e in events {
                if case let .touchStarted(_, _, _, path, _, _) = e { all.append(path) }
            }
        }
        loose.poll(initial: true)
        assert(all.count == 3, "予算が足りれば全部読む (実際: \(all.count))")
    }

    static func laysOutWithoutOverlap() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        for i in 0..<14 {
            c.apply(write("agent\(i % 3)", "/proj/src/dir\(i % 4)/File\(i)Name.swift", "e\(i)",
                          at: t0.addingTimeInterval(Double(i))))
        }
        let snap = c.snapshot(now: t0.addingTimeInterval(20), mode: .work)
        let layout = CockpitLayout.compute(snap, width: 1100)

        assert(layout.chips.count == 3)
        assert(layout.cards.count == 4, "ディレクトリ4つ (実際: \(layout.cards.count))")
        assert(layout.contentHeight > layout.busY, "高さが出ている")

        // セルは全部カードの内側に収まっていること
        for card in layout.cards {
            for box in card.cells {
                assert(card.rect.contains(box.rect),
                       "セル \(box.cell.name) がカード \(card.title) からはみ出している")
            }
        }
        // カード同士が重なっていないこと
        for (i, a) in layout.cards.enumerated() {
            for b in layout.cards[(i + 1)...] {
                assert(!a.rect.intersects(b.rect), "カード \(a.title) と \(b.title) が重なっている")
            }
        }
        // ビームの行き先が引けること
        let target = snap.chips.compactMap(\.target).first
        if let target { assert(layout.rect(forFile: target) != nil, "ビームの行き先が見つからない") }

        // 幅を狭めると折り返して縦に伸びる
        let narrow = CockpitLayout.compute(snap, width: 500)
        assert(narrow.contentHeight > layout.contentHeight, "狭い幅では縦に伸びる")

        // 全角ファイル名でも幅を2文字分として数えている
        assert(CockpitLayout.textWidth("あい") > CockpitLayout.textWidth("ai"))
    }

    /// 長いファイル名・長いディレクトリ名でカードを突き抜けないこと。
    /// セル幅を名前の実寸から決めていた頃はここで破綻していた
    static func longNamesStayInsideCards() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 7_000_000)
        let longDir = "/Users/someone/.claude/jobs/7e04693d-3b1a-4111-a60d-df295e96d95f/tasks"
        c.apply(write("a", longDir + "/AT22 (アットデュエット) オーケストレーターソフト(仮称).md", "e1",
                      at: t0, added: 1234))
        c.apply(write("a", longDir + "/b.txt", "e2", at: t0.addingTimeInterval(1)))
        c.apply(read("a", "/p/x.md", "r1", at: t0.addingTimeInterval(2)))

        for width in [420.0, 700.0, 1400.0] {
            let snap = c.snapshot(now: t0.addingTimeInterval(60), mode: .work)
            let layout = CockpitLayout.compute(snap, width: width)
            for card in layout.cards {
                assert(card.rect.width <= width - CockpitLayout.margin,
                       "カードが画面幅を超えた (幅 \(width))")
                for box in card.cells {
                    assert(card.rect.contains(box.rect),
                           "幅 \(width) でセル \(box.display) がカードからはみ出した")
                    // 省略後の文字列が、左右のティック欄を除いたセル内に収まっていること
                    let used = CockpitLayout.textWidth(box.display) + CockpitLayout.tickColumn * 2
                    assert(used <= box.rect.width, "文字がセル幅を超えた: \(box.display)")
                }
                assert(CockpitLayout.textWidth(card.title) <= card.rect.width,
                       "カード名がカード幅を超えた: \(card.title)")
            }
        }

        // 省略の仕方：ファイル名は中央を削って拡張子を残す
        let short = CockpitLayout.truncateMiddle("VeryLongFileNameIndeed.swift", toWidth: 90)
        assert(short.contains("…") && short.hasSuffix("t"), "中央省略で末尾が残る (実際: \(short))")
        assert(CockpitLayout.textWidth(short) <= 90)
        // ディレクトリ名は頭を削って深い方を残す
        let dir = CockpitLayout.truncateHead("…/7e04693d-3b1a-4111-a60d-df295e96d95f/tasks", toWidth: 80)
        assert(dir.hasPrefix("…") && dir.hasSuffix("tasks"), "頭省略で末尾が残る (実際: \(dir))")
        assert(CockpitLayout.textWidth(dir) <= 80)
    }

    /// 書かれた瞬間だけ光の帯を流すので、書き込み時刻が要る
    static func recordsWriteMoment() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 17_000_000)
        c.apply(read("a", "/p/Spec.md", "r1", at: t0))
        var cell = c.snapshot(now: t0.addingTimeInterval(1), mode: .work).cards.flatMap(\.files)[0]
        assert(cell.lastWriteAt == nil, "読んだだけでは帯を流さない")

        c.apply(write("a", "/p/Spec.md", "w1", at: t0.addingTimeInterval(10), added: 5))
        cell = c.snapshot(now: t0.addingTimeInterval(11), mode: .work).cards.flatMap(\.files)[0]
        assert(cell.lastWriteAt != nil, "書き込み時刻が入る")

        // 二度目の書き込みで時刻が進む（帯がもう一度流れる）
        c.apply(write("a", "/p/Spec.md", "w2", at: t0.addingTimeInterval(60), added: 3))
        let again = c.snapshot(now: t0.addingTimeInterval(61), mode: .work).cards.flatMap(\.files)[0]
        assert(again.lastWriteAt! > cell.lastWriteAt!, "書くたびに更新される")
    }

    /// 実測で全268体中186体が `general-purpose`。オーケストレーターを回すと
    /// 実装もレビューも全部これになるので、agentType だけでは役割名にならない
    static func roleFallsBackToDescription() {
        // 具体的な種別はそのまま使う
        assert(TranscriptParser.roleName(type: "Explore", description: "何かの調査") == "Explore")
        assert(TranscriptParser.roleName(type: "Plan", description: "設計") == "Plan")
        // 汎用種別は description が本当の役割
        assert(TranscriptParser.roleName(type: "general-purpose", description: "Haiku 実装ワーカー")
               == "Haiku 実装ワーカー")
        assert(TranscriptParser.roleName(type: "claude", description: "Sonnet レビュー Round 2")
               == "Sonnet レビュー Round 2")
        // description が無ければ種別に戻る（空文字で潰さない）
        assert(TranscriptParser.roleName(type: "general-purpose", description: nil) == "general-purpose")
        assert(TranscriptParser.roleName(type: "general-purpose", description: "") == "general-purpose")

        // 完了報告には description が無いので、後から来ても meta.json の具体名を潰さないこと
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 13_000_000)
        c.apply([.agentMeta(agent: "w2", session: "S1", role: "W2: 承認タブ実装",
                            depth: 1, parentCall: "toolu_X")])
        c.apply(work("w2", 3, at: t0))
        c.apply([.agentDone(agent: "w2", session: "S1", role: "general-purpose", model: "haiku-4.5",
                            toolCalls: 9, at: t0.addingTimeInterval(5))])
        let chip = c.snapshot(now: t0.addingTimeInterval(6), mode: .work).chips.first { $0.id == "w2" }
        assert(chip?.role == "W2: 承認タブ実装",
               "完了報告が具体名を general-purpose で上書きしている (実際: \(chip?.role ?? "nil"))")
        assert(chip?.work == 9)
    }

    static func shortensModelNames() {
        assert(TranscriptParser.shortModel("claude-opus-5") == "opus-5")
        assert(TranscriptParser.shortModel("claude-haiku-4-5-20251001") == "haiku-4.5",
               "実際: \(TranscriptParser.shortModel("claude-haiku-4-5-20251001"))")
        assert(TranscriptParser.shortModel("claude-fable-5") == "fable-5")
        assert(TranscriptParser.shortModel("claude-sonnet-5") == "sonnet-5")
    }

    /// チップの2行目。動いている間は「今していること」、止まれば「してきたこと」
    static func showsWhatAgentIsDoing() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 15_000_000)
        c.apply([.agentMeta(agent: "w", session: "S1", role: "Explore", depth: 1, parentCall: "t"),
                 .agentActivity(agent: "w", session: "S1", model: "opus-5", at: t0)])
        c.apply((0..<12).map { i in
            .agentAction(id: "search-\(i)", agent: "w", session: "S1",
                         kind: .search, detail: "grep", at: t0) })
        c.apply((0..<5).map { i in
            .agentAction(id: "read-\(i)", agent: "w", session: "S1",
                         kind: .read, detail: "cat", at: t0) })
        c.apply([.agentAction(id: "build", agent: "w", session: "S1",
                              kind: .build, detail: "swift", at: t0)])

        // 動いている間は最後の動作
        var chip = c.snapshot(now: t0.addingTimeInterval(2), mode: .work).chips.first { $0.id == "w" }
        assert(chip?.busy == true)
        assert(chip?.doing == "ビルド swift", "今していること (実際: \(chip?.doing ?? "nil"))")

        // 止まったら内訳（多い順に3つまで）
        chip = c.snapshot(now: t0.addingTimeInterval(Cockpit.activeWindow + 5), mode: .work).chips.first { $0.id == "w" }
        assert(chip?.busy == false)
        assert(chip?.doing == "検索12 読取5 ビルド1", "してきたことの内訳 (実際: \(chip?.doing ?? "nil"))")
        assert(chip?.work == 18, "労働量は内訳の合計 (実際: \(chip?.work ?? -1))")

        // 待機（sleep）は労働量にも内訳にも入れない
        let idle = Cockpit()
        idle.apply([.agentActivity(agent: "z", session: "S1", model: "opus-5", at: t0)])
        idle.apply((0..<20).map { i in
            .agentAction(id: "wait-\(i)", agent: "z", session: "S1",
                         kind: .wait, detail: "sleep", at: t0) })
        idle.apply([.agentAction(id: "search", agent: "z", session: "S1",
                                 kind: .search, detail: "grep", at: t0)])
        let quiet = idle.snapshot(now: t0.addingTimeInterval(Cockpit.activeWindow + 5), mode: .work)
            .chips.first { $0.id == "z" }
        assert(quiet?.work == 1, "sleep を労働量から除く (実際: \(quiet?.work ?? -1))")
        assert(quiet?.doing == "検索1", "sleep を内訳から除く (実際: \(quiet?.doing ?? "nil"))")

        // ファイルを触る作業も同じ枠に出る
        let f = Cockpit()
        f.apply(read("r", "/p/Spec.md", "r1", at: t0))
        f.apply([.agentAction(id: "read", agent: "r", session: "S1",
                              kind: .read, detail: "Spec.md", at: t0)])
        let reading = f.snapshot(now: t0.addingTimeInterval(1), mode: .work).chips.first { $0.id == "r" }
        assert(reading?.doing == "読取 Spec.md", "実際: \(reading?.doing ?? "nil")")
    }

    /// セル右肩から行数を外したので、内訳はクリックした先でしか読めない。
    /// 絞り込みが畳み込みとずれると、画面に出ていない書き込みまで数に入る
    static func showsWriteHistoryOnDemand() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 20_000_000)
        c.apply([.agentMeta(agent: "w1", session: "S1", role: "W1: 実装", depth: 1, parentCall: "")])
        c.apply(write("w1", "/p/App.swift", "e1", at: t0, added: 12))
        c.apply(write("w1", "/p/App.swift", "e2", at: t0.addingTimeInterval(10), added: 3))
        c.apply(read("w1", "/p/App.swift", "r1", at: t0.addingTimeInterval(20)))
        c.apply(write("w1", "/p/Other.swift", "e3", at: t0.addingTimeInterval(30), added: 99))

        let h = c.writeHistory(of: "/p/App.swift")
        assert(h.count == 2, "読み取りが履歴に混ざっている (実際: \(h.count))")
        assert(h[0].added == 3 && h[1].added == 12, "新しい順になっていない")
        assert(h[0].role == "W1: 実装", "実際: \(h[0].role)")
        assert(c.writeHistory(of: "/p/nope.swift").isEmpty, "触っていないファイルに履歴が出た")

        // 参照は誰が何回かで出す。右端の点はしきい値までしか埋まらないので、正確な数はここだけ
        let reads = c.readCounts(of: "/p/App.swift")
        assert(reads.count == 1 && reads[0].role == "W1: 実装" && reads[0].count == 1,
               "実際: \(reads)")
        assert(c.readCounts(of: "/p/Other.swift").isEmpty, "書いただけのファイルに参照が出た")

        // 別セッションの分は混ざらない
        c.selectedSession = "S2"
        assert(c.writeHistory(of: "/p/App.swift").isEmpty, "選択外のセッションの書き込みが出た")
        assert(c.readCounts(of: "/p/App.swift").isEmpty, "選択外のセッションの参照が出た")
        c.selectedSession = nil

        // 「クリア」より前の分も落とす（畳み込みと同じ扱い）
        c.clear()
        assert(c.writeHistory(of: "/p/App.swift").isEmpty, "クリアしたはずの書き込みが残っている")
    }

    /// オフセット記録と「改行で切れなかった端数の持ち越し」がこのアプリで一番壊れやすいので、
    /// 実ファイルに追記しながら検査する。行の途中で切れた状態で走査が走っても取りこぼさないこと。
    static func tailsAppendsAcrossPartialLines() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("at22-p0-\(ProcessInfo.processInfo.processIdentifier)")
        let dir = root.appendingPathComponent("proj")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = dir.appendingPathComponent("S1.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        var received: [TranscriptEvent] = []
        let watcher = TranscriptWatcher(root: root)
        watcher.onEvents = { received += $0.filter { switch $0 { case .agentActivity, .agentAction: return false; default: return true } } }

        func append(_ text: String) {
            let handle = try! FileHandle(forWritingTo: file)
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        }

        // 1回目：完結した1行
        append(startLine + "\n")
        watcher.poll(initial: true)
        assert(received.count == 1, "1行目を拾えていない (実際: \(received.count))")

        // 2回目：行の途中まで。まだ何も出てはいけない
        let half = finishLine.prefix(finishLine.count / 2)
        append(String(half))
        watcher.poll(initial: false)
        assert(received.count == 1, "未完の行を早まって解釈した (実際: \(received.count))")

        // 3回目：残りと改行。持ち越した端数と繋がって1件になる
        append(String(finishLine.dropFirst(half.count)) + "\n")
        watcher.poll(initial: false)
        assert(received.count == 2, "持ち越した端数が繋がっていない (実際: \(received.count))")
        guard case let .touchFinished(id, added, removed, _) = received[1] else {
            fatalError("2件目が touchFinished ではない")
        }
        assert(id == "toolu_A" && added == 2 && removed == 1)

        // 4回目：追記が無ければ何も増えない（同じ範囲を二度読まない）
        watcher.poll(initial: false)
        assert(received.count == 2, "同じ行を二度読んでいる (実際: \(received.count))")

        // 起動時に既存ファイルを見つけた場合、途中から読んだ先頭の壊れた行は捨てる
        let late = TranscriptWatcher(root: root)
        var lateEvents: [TranscriptEvent] = []
        late.onEvents = { lateEvents += $0.filter { switch $0 { case .agentActivity, .agentAction: return false; default: return true } } }
        late.poll(initial: true)
        assert(lateEvents.count == 2, "起動時の遡り読みで件数が合わない (実際: \(lateEvents.count))")
    }

    /// 書き込み量はティックの本数で表す。下線の長さで表すと
    /// ファイル名の長さが量として紛れ込むので、段階は固定寸法で数えられること
    static func writeVolumeTicks() {
        assert(CockpitLayout.writeTicks(0) == 0, "未変更は0本")
        assert(CockpitLayout.writeTicks(1) == 1)
        assert(CockpitLayout.writeTicks(9) == 1, "T1 は 1–9 行")
        assert(CockpitLayout.writeTicks(10) == 2, "T2 は 10–99 行")
        assert(CockpitLayout.writeTicks(99) == 2)
        assert(CockpitLayout.writeTicks(100) == 3, "T3 は 100 行以上")
        assert(CockpitLayout.writeTicks(9999) == CockpitLayout.maxTicks, "上限を超えない")

        // 名前の長さは本数に影響しない（下線案を却下した理由）
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 16_000_000)
        c.apply(write("a", "/p/a.ts", "e1", at: t0, added: 620))
        c.apply(write("a", "/p/ApplicationCoordinatorWithAVeryLongName.ts", "e2", at: t0, added: 4))
        let files = Dictionary(uniqueKeysWithValues:
            c.snapshot(now: t0.addingTimeInterval(1), mode: .work).cards.flatMap(\.files).map { ($0.name, $0) })
        assert(CockpitLayout.writeTicks(files["a.ts"]!.added) == 3, "短い名前でも大量なら3本")
        assert(CockpitLayout.writeTicks(files["ApplicationCoordinatorWithAVeryLongName.ts"]!.added) == 1,
               "長い名前でも少量なら1本")

        // ティック欄のぶんセルが広がり、名前が押し出されてもはみ出さない
        let layout = CockpitLayout.compute(c.snapshot(now: t0.addingTimeInterval(1), mode: .work), width: 900)
        for card in layout.cards {
            for box in card.cells {
                assert(card.rect.contains(box.rect), "ティック追加でセルがはみ出した: \(box.display)")
                // 左（書き込み量）と右（参照回数）の2欄ぶん
                let used = CockpitLayout.tickColumn * 2 + CockpitLayout.textWidth(box.display)
                assert(used <= box.rect.width, "ティック込みで文字が溢れた: \(box.display)")
            }
        }
    }

    // MARK: 進行表

    /// TaskCreate の本文は tool_use 側、番号は結果側に来る。
    /// 順番から番号を推測すると、セッション再開や並行実行でずれる
    static func buildsRoadmapFromTaskTools() {
        func create(_ call: String, _ subject: String, _ active: String, _ detail: String) -> String {
            #"{"type":"assistant","sessionId":"S1","timestamp":"2026-07-31T09:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(call)","name":"TaskCreate","input":{"subject":"\#(subject)","activeForm":"\#(active)","description":"\#(detail)"}}]}}"#
        }
        func numbered(_ call: String, _ id: String) -> String {
            #"{"type":"user","sessionId":"S1","timestamp":"2026-07-31T09:00:01.000Z","toolUseResult":{"task":{"id":"\#(id)","subject":"x"}},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(call)"}]}}"#
        }
        func update(_ id: String, _ status: String, _ time: String) -> String {
            #"{"type":"assistant","sessionId":"S1","timestamp":"2026-07-31T09:\#(time).000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"u\#(id)\#(status)","name":"TaskUpdate","input":{"taskId":"\#(id)","status":"\#(status)"}}]}}"#
        }

        let c = Cockpit()
        func feed(_ line: String) {
            c.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: "S1"))
        }

        // 2件を作ってから番号が返る。返る順をわざと逆にして、順番で決めていないことを見る
        feed(create("tc_a", "Phase 1: 取り込み", "取り込み中", "パーサに3つ足す"))
        feed(create("tc_b", "Phase 2: 表示", "表示を作成中", "帯を1本足す"))
        feed(numbered("tc_b", "2"))
        feed(numbered("tc_a", "1"))

        var road = c.allTasks(session: "S1")
        assert(road.count == 2, "2件積まれていない (実際: \(road.count))")
        assert(road[0].subject == "Phase 1: 取り込み" && road[0].number == 1,
               "番号順になっていない (実際: \(road.map(\.subject)))")
        assert(road[1].number == 2)
        assert(road.allSatisfy { $0.status == .pending }, "作った直後は未着手")
        assert(road[0].detail == "パーサに3つ足す", "description を落としている")
        assert(road[1].activeForm == "表示を作成中", "activeForm を落としている")

        // 進んで、終わる
        feed(update("1", "in_progress", "10:00"))
        road = c.allTasks(session: "S1")
        assert(road[0].status == .inProgress && road[1].status == .pending, "実際: \(road.map(\.status))")

        feed(update("1", "completed", "20:00"))
        feed(update("2", "in_progress", "20:01"))
        road = c.allTasks(session: "S1")
        assert(road[0].status == .completed && road[1].status == .inProgress, "実際: \(road.map(\.status))")

        // 番号を知らないタスクの更新は捨てる。勝手に増やさない
        feed(update("99", "completed", "20:02"))
        assert(c.allTasks(session: "S1").count == 2)

        // 帳簿づけは労働量に数えない。実測で司令塔の労働331のうち58件（17.5%）を占め、
        // 進行表の帯にも出るので、数えると二重計上のうえ本当の作業が順位から落ちる
        let chip = c.snapshot(now: Date(timeIntervalSince1970: 1), mode: .work).chips.first { $0.id == "S1" }
        assert(chip?.work == 0, "TaskCreate / TaskUpdate が労働量に入っている (実際: \(chip?.work ?? -1))")
        assert(chip?.doing.isEmpty == true, "内訳に帳簿づけが出ている (実際: \(chip?.doing ?? "nil"))")
        // 知らない状態も捨てる（完了扱いにしない）
        assert(TranscriptParser.taskStatus("cancelled") == nil)
        assert(TranscriptParser.taskStatus("completed") == .completed)
    }

    /// 「クリア」は溜まった集計を落とすためのもの。これから何をするかの表まで消すと先が見えなくなる。
    /// 完了が溜まったら畳む（実測で1セッション最大200件）。
    ///
    /// 畳むのは**最上段の帯だけ**（`Cockpit.progressStrip`）。帯は1行しかないので、
    /// 古い完了は番号だけを詰めて連結する。一覧（`allTasks`）は畳まない
    static func roadmapSurvivesClearAndFolds() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 21_000_000)
        for i in 1...8 {
            c.apply([.taskDeclared(call: "c\(i)", session: "S1", subject: "Phase \(i)",
                                   activeForm: "Phase \(i) 中", detail: "", at: t0),
                     .taskNumbered(call: "c\(i)", id: "\(i)")])
        }
        // 1〜6 が完了、7 が進行中、8 は未着手
        for i in 1...6 {
            c.apply([.taskStatus(session: "S1", id: "\(i)", status: .completed, at: t0)])
        }
        c.apply([.taskStatus(session: "S1", id: "7", status: .inProgress, at: t0)])

        var strip = Cockpit.progressStrip(c.allTasks(session: "S1"))
        assert(strip.foldedNumbers == "123",
               "古い完了が番号だけに畳まれていない (実際: \(strip.foldedNumbers))")
        assert(strip.recent.map(\.number) == [4, 5, 6],
               "直近の完了が keptCompleted 件残っていない (実際: \(strip.recent.map(\.number)))")
        assert(strip.current?.number == 7, "進行中が立っていない (実際: \(strip.current?.number ?? -1))")
        assert(strip.upcoming.map(\.number) == [8],
               "未着手が出ていない (実際: \(strip.upcoming.map(\.number)))")
        // 赤が付くのは進行中の1件だけ。ここが2件になると「いま」が指せなくなる
        assert(c.allTasks(session: "S1").filter { $0.status == .inProgress }.count == 1,
               "進行中が複数ある")

        // ファイルとチップは落ちるが、進行表は残る
        c.apply(write("a", "/p/App.swift", "e1", at: t0))
        c.clear()
        let snap = c.snapshot(now: t0.addingTimeInterval(2), mode: .work)
        assert(snap.cards.isEmpty, "クリアでファイルが落ちていない")
        assert(c.allTasks(session: "S1").count == 8, "クリアで進行表まで落ちた")

        // 別セッションとは混ざらない
        assert(c.allTasks(session: "S2").isEmpty, "他セッションの進行表が出た")

        // 完了が keptCompleted 以下なら連結は出さない（`0102…` が1件だけ出ると読めない）
        let few = Cockpit()
        for i in 1...3 {
            few.apply([.taskDeclared(call: "f\(i)", session: "S1", subject: "P\(i)",
                                     activeForm: "", detail: "", at: t0),
                       .taskNumbered(call: "f\(i)", id: "\(i)")])
            few.apply([.taskStatus(session: "S1", id: "\(i)", status: .completed, at: t0)])
        }
        strip = Cockpit.progressStrip(few.allTasks(session: "S1"))
        assert(strip.foldedNumbers.isEmpty, "畳む必要が無いのに連結が出た (実際: \(strip.foldedNumbers))")
        assert(strip.recent.count == 3 && strip.current == nil && strip.upcoming.isEmpty)

        // 空でも落ちない
        let empty = Cockpit.progressStrip([])
        assert(empty.foldedNumbers.isEmpty && empty.recent.isEmpty
               && empty.current == nil && empty.upcoming.isEmpty, "空の進行表で何か出た")
    }

    /// 一覧用の `allTasks` は完了を畳まない。畳むのは進行表の帯（`buildRoadmap`）だけで、
    /// キャンバスの帯が横に伸びないための都合であって、一覧まで畳むと完了ぶんを見返せなくなる。
    /// 同じ入力で両者の挙動が食い違うこと（畳む／畳まない）を対比して確認する
    static func listsEveryTaskIncludingDone() {
        func create(_ session: String, _ call: String, _ subject: String) -> String {
            #"{"type":"assistant","sessionId":"\#(session)","timestamp":"2026-07-31T09:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(call)","name":"TaskCreate","input":{"subject":"\#(subject)","activeForm":"進行中","description":""}}]}}"#
        }
        func numbered(_ session: String, _ call: String, _ id: String) -> String {
            #"{"type":"user","sessionId":"\#(session)","timestamp":"2026-07-31T09:00:01.000Z","toolUseResult":{"task":{"id":"\#(id)","subject":"x"}},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(call)"}]}}"#
        }
        func update(_ session: String, _ id: String, _ status: String, _ time: String) -> String {
            #"{"type":"assistant","sessionId":"\#(session)","timestamp":"2026-07-31T09:\#(time).000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"u\#(session)\#(id)\#(status)\#(time)","name":"TaskUpdate","input":{"taskId":"\#(id)","status":"\#(status)"}}]}}"#
        }

        let c = Cockpit()
        func feed(_ line: String, session: String) {
            c.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: session))
        }

        // 8件作り、6件を完了・1件を進行中・1件を未着手にする（keptCompleted=3 を超える完了数）
        for i in 1...8 {
            feed(create("S1", "c\(i)", "Phase \(i)"), session: "S1")
            feed(numbered("S1", "c\(i)", "\(i)"), session: "S1")
        }
        for i in 1...6 {
            feed(update("S1", "\(i)", "completed", "10:0\(i)"), session: "S1")
        }
        feed(update("S1", "7", "in_progress", "10:07"), session: "S1")

        let all = c.allTasks(session: "S1")
        assert(all.count == 8, "完了が溜まると畳まれてしまった (実際: \(all.count)件)")
        assert(all.map(\.number) == [1, 2, 3, 4, 5, 6, 7, 8],
               "番号順になっていない (実際: \(all.map(\.number)))")
        assert(all.filter { $0.status == .completed }.count == 6, "完了の件数が変わった")

        // 帯（progressStrip）側は従来どおり畳まれる。同じ入力で挙動が対比できること
        let strip = Cockpit.progressStrip(all)
        assert(strip.foldedNumbers == "123",
               "帯側の畳み込みが変わった (実際: \(strip.foldedNumbers))")
        let shown = strip.recent.count + (strip.current == nil ? 0 : 1) + strip.upcoming.count
        assert(all.count > shown,
               "一覧が帯と同じところまで畳まれた（allTasks は畳まないはず）")

        // 別セッションで同じ番号 "1" のタスクを作る
        feed(create("S2", "d1", "S2のPhase 1"), session: "S2")
        feed(numbered("S2", "d1", "1"), session: "S2")

        // session: nil の並びが決定的であること（2回呼んで同じ順序）
        let mixedA = c.allTasks(session: nil).map(\.id)
        let mixedB = c.allTasks(session: nil).map(\.id)
        assert(mixedA == mixedB, "同じデータで呼ぶたびに並びが変わった（決定的でない）")

        // 同番号 "1" が2件あるとき、session 文字列順（S1 < S2）で決まっていること
        let ones = c.allTasks(session: nil).filter { $0.number == 1 }
        assert(ones.map(\.session) == ["S1", "S2"],
               "同番号のときの並びが session 順になっていない (実際: \(ones.map(\.session)))")

        // session を指定するとそのセッションだけになる
        assert(c.allTasks(session: "S2").map(\.subject) == ["S2のPhase 1"],
               "セッション絞り込みが効いていない")
        assert(c.allTasks(session: "S1").allSatisfy { $0.session == "S1" },
               "他セッションのタスクが混ざった")

        // タスクが1件も無ければ空配列で落ちない
        assert(Cockpit().allTasks(session: nil).isEmpty, "空でも安全に空配列を返すこと")
    }

    /// 参照回数は「企画書を何度も読み返している」に気づくためのもの。
    /// フラグ（しきい値以上＋編集ゼロ）が立つ前に、埋まっていく過程が見えること
    static func readTicksFillTowardFlag() {
        assert(CockpitLayout.readTicks(0, threshold: 3) == 0, "読んでいなければ0個")
        assert(CockpitLayout.readTicks(1, threshold: 3) == 1)
        assert(CockpitLayout.readTicks(2, threshold: 3) == 2)
        assert(CockpitLayout.readTicks(3, threshold: 3) == 3, "しきい値で埋まりきる")
        assert(CockpitLayout.readTicks(99, threshold: 3) == 3, "埋まりきったら増えない")
        // しきい値を変えたら追従する（外から変えられる値なので固定してはいけない）
        assert(CockpitLayout.readTicks(4, threshold: 5) == 4)
        assert(CockpitLayout.readTicks(9, threshold: 5) == 5)
        assert(CockpitLayout.readTicks(1, threshold: 0) == 1, "0でも1個は出す（0除算・不可視を避ける）")

        // しきい値は設定画面から変えられるので、点がセルの高さを超えないこと
        assert(CockpitLayout.readTicks(99, threshold: 99) == CockpitLayout.maxReadTicks,
               "上限を超えて積んでいる")
        let n = CGFloat(CockpitLayout.maxReadTicks)
        let stack = n * CockpitLayout.tickSize + (n - 1) * CockpitLayout.tickGap
        assert(stack <= CockpitLayout.cellHeight,
               "点の列がセルからはみ出す (\(stack) > \(CockpitLayout.cellHeight))")

        // フラグ側も同じしきい値で動くこと（点だけ埋まって橙が立たない、の逆も無い）
        let tuned = Cockpit()
        let t1 = Date(timeIntervalSince1970: 22_500_000)
        tuned.flagReadThreshold = 5
        for i in 0..<4 { tuned.apply(read("a", "/p/spec.md", "q\(i)", at: t1.addingTimeInterval(Double(i)))) }
        var cell = tuned.snapshot(now: t1.addingTimeInterval(60), mode: .work).cards
            .flatMap(\.files).first { $0.id == "/p/spec.md" }!
        assert(cell.state != .flagged, "しきい値5なのに4回で立った")
        assert(CockpitLayout.readTicks(cell.reads, threshold: 5) == 4)
        tuned.apply(read("a", "/p/spec.md", "q4", at: t1.addingTimeInterval(5)))
        cell = tuned.snapshot(now: t1.addingTimeInterval(60), mode: .work).cards
            .flatMap(\.files).first { $0.id == "/p/spec.md" }!
        assert(cell.state == .flagged, "しきい値に届いたのに立たない")
        assert(CockpitLayout.readTicks(cell.reads, threshold: 5) == 5, "埋まりきりとフラグがずれている")

        // 実際のセルに乗り、埋まりきった時にフラグと一致すること
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 22_000_000)
        for i in 0..<3 { c.apply(read("a", "/p/spec.md", "r\(i)", at: t0.addingTimeInterval(Double(i)))) }
        c.apply(read("a", "/p/other.md", "r9", at: t0))

        let snap = c.snapshot(now: t0.addingTimeInterval(60), mode: .work)
        let boxes = Dictionary(uniqueKeysWithValues:
            CockpitLayout.compute(snap, width: 900).cards.flatMap(\.cells).map { ($0.cell.id, $0) })
        assert(boxes["/p/spec.md"]!.readTicks == 3, "3回読んだのに埋まっていない")
        assert(boxes["/p/spec.md"]!.cell.state == .flagged, "埋まりきったのにフラグが立っていない")
        assert(boxes["/p/other.md"]!.readTicks == 1)
        assert(boxes["/p/other.md"]!.cell.state != .flagged, "1回でフラグが立った")
    }

    /// meta.json は .jsonl より後に書かれることがある（実測 273体中62体、遅れの中央値341秒）。
    /// 初見の1回で諦めると、そのチップは hex の羅列のまま親子の破線も引かれない
    static func labelsAgentWhenMetaArrivesLate() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("at22-late-\(ProcessInfo.processInfo.processIdentifier)")
        let dir = root.appendingPathComponent("proj/S1/subagents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonl = dir.appendingPathComponent("agent-x1.jsonl")
        try? Data((readLine + "\n").utf8).write(to: jsonl)

        var metas: [TranscriptEvent] = []
        let watcher = TranscriptWatcher(root: root)
        watcher.onEvents = { events in
            metas += events.filter { if case .agentMeta = $0 { return true } else { return false } }
        }

        // 1回目：meta.json はまだ無い
        watcher.poll(initial: true)
        assert(metas.isEmpty, "meta.json が無いのに役割が付いた")

        // 後から書かれる
        let meta = #"{"agentType":"general-purpose","description":"W4: 統合・ビルド修正","spawnDepth":1,"toolUseId":"toolu_P"}"#
        try? Data(meta.utf8).write(to: dir.appendingPathComponent("agent-x1.meta.json"))

        // 2回目：追記が無くても読み直すこと
        watcher.poll(initial: false)
        guard metas.count == 1, case let .agentMeta(agent, session, role, depth, parentCall) = metas[0] else {
            fatalError("後から来た meta.json を拾えていない（実際: \(metas.count)件）")
        }
        assert(agent == "x1" && session == "S1", "実際: \(agent) / \(session)")
        assert(role == "W4: 統合・ビルド修正", "実際: \(role)")
        assert(depth == 1 && parentCall == "toolu_P")

        // 読めた後は繰り返さない
        watcher.poll(initial: false)
        assert(metas.count == 1, "ラベル済みを読み直している (実際: \(metas.count))")
    }

    /// 選択中のセッションが終わるとタブが消え、選択だけが残って畳み込みが全件落ちる。
    /// v0.1.0 は画面が真っ白になり、「すべて」を押すまで戻れなかった
    static func keepsTabForEndedSession() {
        let a = LiveSession(id: "S1", name: "alpha", cwd: "/a", busy: true)
        let b = LiveSession(id: "S2", name: "bravo", cwd: "/b", busy: false)

        // 両方生きていれば名前順にそのまま
        assert(Cockpit.tabs(live: [b, a], selected: "S1", previous: []).map(\.id) == ["S1", "S2"])

        // 見ているセッションが終わってもタブは残る
        let kept = Cockpit.tabs(live: [b], selected: "S1", previous: [a, b])
        assert(kept.map(\.id) == ["S1", "S2"], "見ていたタブが消えた (実際: \(kept.map(\.id)))")
        assert(kept[0].busy == false, "終わったのに稼働中のままになっている")
        assert(kept[0].name == "alpha", "名前を持ち越せていない")

        // 見ていないものは終わったら消える
        assert(Cockpit.tabs(live: [b], selected: "S2", previous: [a, b]).map(\.id) == ["S2"])
        assert(Cockpit.tabs(live: [b], selected: nil, previous: [a, b]).map(\.id) == ["S2"])

        // 生きているものを二重に足さない
        assert(Cockpit.tabs(live: [a, b], selected: "S1", previous: [a, b]).count == 2)

        // メニューから読んだ履歴は、選択を外しても稼働中一覧の更新で失わない
        let history = LiveSession(id: "H1", name: "history", cwd: "/history", busy: false)
        assert(Cockpit.tabs(live: [b], selected: nil, previous: [a, b, history], loaded: [history])
            .map(\.id) == ["S2", "H1"], "読み込み済みの履歴タブが消えた")
    }

    /// ホバーで関係先が同時に色づく。線を1本も引かずに「どこと繋がっているか」を出す仕掛けなので、
    /// ここが片方向になると「呼ばれている元」が沈んだまま見えなくなる
    static func hoverLightsRelatedFiles() {
        let g = Structure.build([
            "/p/App.swift":    "let x = Engine()",          // App → Engine
            "/p/Engine.swift": "struct Engine {}\nlet y = Codec()",   // Engine → Codec
            "/p/Codec.swift":  "struct Codec {}",
            "/p/Alone.swift":  "struct Alone {}",
        ])
        func rel(_ p: String) -> Set<String> {
            g.related(to: p)
        }
        // 真ん中のファイルは、呼んでいる先と呼ばれている元の両方が点く
        assert(rel("/p/Engine.swift") == ["/p/App.swift", "/p/Codec.swift"],
               "両方向を集めていない (実際: \(rel("/p/Engine.swift")))")
        assert(rel("/p/App.swift") == ["/p/Engine.swift"])
        assert(rel("/p/Codec.swift") == ["/p/Engine.swift"], "呼ばれている元だけのファイルが繋がらない")
        assert(rel("/p/Alone.swift").isEmpty, "無関係なファイルが繋がった")
        assert(rel("/p/nope.swift").isEmpty, "知らないパスで落ちる")
        // 自分自身は関係先に入れない（入れると「起点」と「関係先」の塗り分けが崩れる）
        assert(!rel("/p/Engine.swift").contains("/p/Engine.swift"))
    }

    /// エゴビュー。グリッドに辺を敷き詰めず、押した1件のまわりだけを開く。
    /// 幾何が崩れると箱と曲線が繋がらないので、寸法は純関数のうちに押さえる
    static func egoViewFramesOneFile() {
        let graph = Structure.build([
            "/p/src/Model.swift":  "/// 台帳。全部ここを通る\nstruct Ledger {}\nlet h = Helper()",
            "/p/src/A.swift":      "let a = Ledger()",
            "/p/src/B.swift":      "let b = Ledger()",
            "/p/src/Helper.swift": "struct Helper {}",
            "/p/README.md":        "Model.swift が台帳を持つ",
        ])
        let size = CGSize(width: 1200, height: 760)
        let hubPath = "/p/src/Model.swift"
        let view = CockpitLayout.ego(path: hubPath, graph: graph, lastEdit: 87, size: size)
        let hub = view.panels[0]

        // 左＝呼ばれている元とノート、中央＝そのファイル、右＝呼んでいる先
        let ins = view.relations.filter { $0.marker == .calledBy || $0.marker == .note }
        let outs = view.relations.filter { $0.marker == .calling }
        assert(ins.count == 3, "呼ばれている元2件とノート1件 (実際: \(ins.count))")
        assert(outs.count == 1, "呼んでいる先 (実際: \(outs.count))")
        for r in ins { assert(r.rect.maxX < hub.minX, "左の列がハブに被った") }
        for r in outs { assert(r.rect.minX > hub.maxX, "右の列がハブに被った") }
        assert(hub.minX >= 0 && hub.maxX <= size.width, "ハブが画面外")

        // 矢印。向きが呼び出しの向きと一致すること
        assert(view.links.count == ins.count + outs.count, "矢印の数が行と合わない")
        for link in view.links {
            switch link.marker {
            case .calling:
                assert(link.from.x >= hub.maxX && link.to.x > link.from.x,
                       "呼んでいる先の矢がハブから出ていない")
            case .calledBy, .note:
                // 左の列はハブより左なので、こちらも左から右へ進んでハブの左端に刺さる。
                // 向きの違いは矢の位置（ハブ側か行側か）で出る
                assert(link.to.x <= hub.minX && link.to.x > link.from.x,
                       "呼ばれている元の矢がハブに入っていない")
            default: assert(false, "印の無い行に矢を引いた")
            }
        }

        // 余白＝ハブの下。解説と数値がそこに入り、ハブや左右の列と重ならない
        assert(view.memoTop > hub.maxY, "解説がハブに被った")
        assert(view.memo.joined().contains("台帳"), "解説が出ていない (実際: \(view.memo))")
        assert(view.stats.count == 3)
        assert(view.stats[0].value == "1", "定義された型 (実際: \(view.stats[0].value))")
        assert(view.stats[1].value == "2", "被参照 (実際: \(view.stats[1].value))")
        assert(view.stats[2].value == "+87", "直近の編集 (実際: \(view.stats[2].value))")
        assert(CockpitLayout.ego(path: hubPath, graph: graph, lastEdit: nil, size: size)
                .stats[2].value == "—", "編集が無い時に数字を捏造している")
        for stat in view.stats {
            assert(stat.rect.minY > hub.maxY, "数値タイルがハブに被った")
            for r in ins { assert(stat.rect.minX > r.rect.maxX, "数値タイルが左の列に被った") }
            for r in outs { assert(stat.rect.maxX < r.rect.minX, "数値タイルが右の列に被った") }
        }

        // ノートは依存グラフに混ぜない。混ぜると README が全ファイルを呼んでいることになる
        assert(graph.dependsOn["/p/README.md"] == nil)
        assert(view.relations.contains { $0.marker == .note && $0.label.hasSuffix(".md") },
               "関連ノートが出ていない")
        assert(view.relations.contains { $0.marker == .calledBy && $0.label == "A" },
               "呼ばれている元が拡張子付きのまま出ている")

        // 中央のハブ・数値タイル・解説の本文は押しても閉じない。
        // 一番ボタンに見えるハブを押すと画面ごと消える、が一番いらつく
        assert(view.holdsFocus(at: CGPoint(x: hub.midX, y: hub.midY)), "ハブを押すと閉じる")
        for stat in view.stats {
            assert(view.holdsFocus(at: CGPoint(x: stat.rect.midX, y: stat.rect.midY)),
                   "数値タイルを押すと閉じる")
        }
        if !view.memo.isEmpty {
            assert(view.holdsFocus(at: CGPoint(x: view.stats[0].rect.minX + 4, y: view.memoTop)),
                   "解説の本文を押すと閉じる")
        }
        // 何も無い余白は閉じてよい（そこが唯一の閉じ方）
        assert(!view.holdsFocus(at: CGPoint(x: 4, y: size.height - 4)), "余白でも閉じない")
        // 行の上は「飛ぶ」が優先。閉じ判定に食われない
        for row in view.relations where !row.path.isEmpty {
            let p = CGPoint(x: row.rect.midX, y: row.rect.midY)
            assert(view.file(at: p) != nil, "行が引けない")
        }

        // 押した先へ飛べる。押せない行（残件数）は飛ばない
        for row in view.relations where !row.path.isEmpty {
            assert(graph.files.contains(row.path), "実在しないパスへ飛ぶ行: \(row.path)")
            assert(view.file(at: CGPoint(x: row.rect.midX, y: row.rect.midY)) == row.path,
                   "行の中心を押しても引けない: \(row.label)")
        }
        assert(view.file(at: CGPoint(x: 2, y: 2)) == nil, "余白が当たっている")
        let next = view.relations.first { $0.marker == .calledBy }!.path
        let jumped = CockpitLayout.ego(path: next, graph: graph, lastEdit: nil, size: size)
        assert(jumped.name == (next as NSString).lastPathComponent, "飛んだ先が違う")
        assert(jumped.relations.contains { $0.marker == .calling }, "飛んだ先の関係が組み直されていない")

        // 片側の上限と残件数
        var many: [String: String] = ["/p/Hub.swift": "struct Hub {}"]
        for i in 0..<12 { many["/p/User\(i).swift"] = "let x = Hub()" }
        let big = Structure.build(many)
        let wide = CockpitLayout.ego(path: "/p/Hub.swift", graph: big, lastEdit: nil, size: size)
        assert(wide.relations.filter { $0.marker == .calledBy }.count == CockpitLayout.egoMaxSide)
        assert(wide.relations.contains { $0.path.isEmpty && $0.label.contains("他") }, "残件数が出ない")
        assert(wide.links.count == CockpitLayout.egoMaxSide, "押せない行にも矢を引いた")

        // 折り返しは省略しない
        let long = String(repeating: "あ", count: 60)
        let wrapped = CockpitLayout.wrap(long, toWidth: 170, size: 14, maxLines: 10)
        assert(wrapped.count > 1 && !wrapped.contains { $0.contains("…") }, "折り返しで削っている")
        assert(CockpitLayout.wrap(String(repeating: "い", count: 900),
                                  toWidth: 170, size: 14, maxLines: 10).count == 10, "行数の上限が効かない")
        assert(CockpitLayout.wrap("", toWidth: 170, size: 14, maxLines: 10).isEmpty)
    }

    // MARK: MCP・詳細・履歴セッション

    static func buildsMcpWorkerChips() {
        let c = Cockpit()
        func feed(_ line: String) {
            c.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: "S1"))
        }
        let first = #"{"type":"assistant","sessionId":"S1","timestamp":"2026-08-01T09:00:00.000Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"m1","name":"mcp__codex__codex","input":{"prompt":"最初の実装指示"}}]}}"#
        let firstResult = #"{"type":"user","sessionId":"S1","timestamp":"2026-08-01T09:00:01.000Z","toolUseResult":"{\"threadId\":\"thread-1\",\"content\":\"完了\"}","message":{"content":[{"type":"tool_result","tool_use_id":"m1","content":"{\"threadId\":\"thread-1\",\"content\":\"完了\"}"}]}}"#
        let second = #"{"type":"assistant","sessionId":"S1","timestamp":"2026-08-01T09:00:02.000Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"m2","name":"mcp__codex__codex-reply","input":{"threadId":"thread-1","prompt":"二回目の修正指示を全文で残す"}}]}}"#
        let secondResult = firstResult
            .replacingOccurrences(of: "09:00:01", with: "09:00:03")
            .replacingOccurrences(of: "m1", with: "m2")

        feed(first)
        var snap = c.snapshot(now: TranscriptParser.date("2026-08-01T09:00:00.500Z")!, mode: .work)
        var mcp = snap.chips.first { $0.model == "MCP" }
        assert(mcp?.busy == true && mcp?.done == false, "結果前のMCPが稼働にならない")
        feed(firstResult)
        snap = c.snapshot(now: TranscriptParser.date("2026-08-01T09:00:01.500Z")!, mode: .work)
        mcp = snap.chips.first { $0.model == "MCP" }
        assert(mcp?.busy == false && mcp?.done == true, "結果後のMCPが終了にならない")

        feed(second)
        feed(secondResult)
        snap = c.snapshot(now: TranscriptParser.date("2026-08-01T09:00:04.000Z")!, mode: .work)
        let workers = snap.chips.filter { $0.model == "MCP" }
        assert(workers.count == 1, "同じthreadIdが分裂した (実際: \(workers.count))")
        guard let worker = workers.first else { fatalError() }
        assert(worker.work == 2 && worker.role == "codex" && worker.parent == "S1")
        assert(worker.depth == 1 && worker.done && !worker.busy)
        assert(worker.doing == "二回目の修正指示を全文で残す"
               && worker.instruction == worker.doing, "最後のpromptが残っていない")

        // threadId が無くても呼び出しIDを鍵に1体残り、文字列の形では落ちない
        let loose = #"{"type":"assistant","sessionId":"S1","timestamp":"2026-08-01T09:00:05.000Z","message":{"content":[{"type":"tool_use","id":"m3","name":"mcp__claude_ai_Slack__search","input":{"query":"検索語"}}]}}"#
        let plain = #"{"type":"user","sessionId":"S1","timestamp":"2026-08-01T09:00:06.000Z","toolUseResult":"plain string","message":{"content":[{"type":"tool_result","tool_use_id":"m3","content":"plain string"}]}}"#
        let looseShape = loose.replacingOccurrences(of: "m3", with: "m4")
            .replacingOccurrences(of: "09:00:05", with: "09:00:07")
        let otherShape = plain.replacingOccurrences(of: "m3", with: "m4")
            .replacingOccurrences(of: "09:00:06", with: "09:00:08")
            .replacingOccurrences(of: "plain string", with: "{}")
        feed(loose)
        feed(plain)
        feed(looseShape)
        feed(otherShape)
        snap = c.snapshot(now: TranscriptParser.date("2026-08-01T09:00:09.000Z")!, mode: .work)
        // prompt の無い呼び出しは道具の利用。呼び出しごとに分裂させず、サーバ単位で1体に束ねて回数を積む
        // （実測でブラウザ操作85回が85行になり、エージェントの帯を埋めていた）
        let slacks = snap.chips.filter { $0.role == "claude_ai_Slack" }
        assert(slacks.count == 1, "道具として呼んだMCPが呼び出しごとに分裂した: \(slacks.map(\.id))")
        let slack = slacks.first
        assert(slack?.done == true && slack?.work == 2, "束ねた回数か完了が違う: \(String(describing: slack?.work))")
        assert(slack?.doing == "search" && slack?.instruction == "search",
               "promptが無いMCPでツール名へ戻らない")

        let root = snap.chips.first { $0.id == "S1" }!
        assert(root.counts.first { $0.kind == .spawn }?.count == 4,
               "MCPが起動に数えられていない (実際: \(root.counts))")
        assert(root.counts.first { $0.kind == .other } == nil, "MCPが他にも二重計上された")

        // threadId はサーバー内の識別子なので、別サーバーの同名スレッドを融合させない
        let collision = Cockpit()
        func collide(_ line: String) {
            collision.apply(TranscriptParser.parse(Data(line.utf8), fallbackSession: "S2"))
        }
        collide(#"{"type":"assistant","sessionId":"S2","timestamp":"2026-08-01T09:01:00.000Z","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codex__codex","input":{"prompt":"実装"}},{"type":"tool_use","id":"c2","name":"mcp__claude_ai_Slack__search","input":{"prompt":"検索"}}]}}"#)
        collide(#"{"type":"user","sessionId":"S2","timestamp":"2026-08-01T09:01:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"c1","content":"{\"threadId\":\"shared\"}"}]}}"#)
        collide(#"{"type":"user","sessionId":"S2","timestamp":"2026-08-01T09:01:02.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"c2","content":"{\"threadId\":\"shared\"}"}]}}"#)
        let distinct = collision.snapshot(
            now: TranscriptParser.date("2026-08-01T09:01:03.000Z")!, mode: .work).chips
        assert(distinct.contains { $0.id == "mcp-thread:codex#shared" && $0.role == "codex" })
        assert(distinct.contains {
            $0.id == "mcp-thread:claude_ai_Slack#shared" && $0.role == "claude_ai_Slack"
        }, "別サーバーの同じthreadIdが融合した")

        // 応答を取りこぼしても脈を流し続けず、通常の非アクティブ削除で畳める。
        // 上限はエージェントの stuckAfter ではなく mcpStuckAfter。MCP は結果が返るまで
        // 1行も出さないので、120秒で切ると実測15〜40分の codex が飛行中に全件消える
        let stale = Cockpit()
        let staleAt = Date(timeIntervalSince1970: 31_000_000)
        stale.apply([.mcpCalled(call: "stale", session: "S3", by: "S3", server: "codex",
                                tool: "codex", prompt: "応答待ち", at: staleAt)])
        assert(stale.snapshot(now: staleAt.addingTimeInterval(Cockpit.stuckAfter + 1), mode: .work)
                .chips.first { $0.model == "MCP" }?.busy == true,
               "エージェントの無音窓でMCPを止めている（長い外部呼び出しが消える）")
        var staleSnapshot = stale.snapshot(now: staleAt.addingTimeInterval(Cockpit.mcpStuckAfter + 1),
                                           mode: .work)
        assert(staleSnapshot.chips.first { $0.model == "MCP" }?.busy == false,
               "古いMCPが稼働のまま残った")
        stale.clearIdleAgents(now: staleAt.addingTimeInterval(Cockpit.mcpStuckAfter + 1))
        staleSnapshot = stale.snapshot(now: staleAt.addingTimeInterval(Cockpit.mcpStuckAfter + 2), mode: .work)
        assert(!staleSnapshot.chips.contains { $0.model == "MCP" }, "古いMCPを手動で畳めない")

        let auto = Cockpit()
        let old = Date(timeIntervalSince1970: 50_000_000)
        let far = old.addingTimeInterval(Cockpit.mcpStuckAfter + Cockpit.autoHideAfter + 1)
        auto.apply([.mcpCalled(call: "auto", session: "S4", by: "S4", server: "codex",
                               tool: "codex", prompt: "応答待ち", at: old)])
        auto.foldIdleAgents(now: far)
        assert(!auto.snapshot(now: far, mode: .work).chips.contains { $0.model == "MCP" },
               "古いMCPが自動で畳まれない")
    }

    /// MCP ワーカーは結果が返るまで1行も出さないので、沈黙＝停止ではない。
    /// エージェント側の stuckAfter(120秒) を当てると、実測15〜40分かかる codex が
    /// 飛行中に全件畳まれ、しかも完了しても戻らなくなる（lastAt が呼び出し時刻で止まるため）
    static func mcpWorkerSurvivesLongFlight() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 31_000_000)
        c.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0),
                 .mcpCalled(call: "c1", session: "S1", by: "S1", server: "codex", tool: "codex",
                            prompt: "5工程を実装して", at: t0)])
        func worker(_ now: Date) -> AgentChip? {
            c.snapshot(now: now, mode: .work).chips.first { $0.model == "MCP" }
        }
        // 実測の codex は15〜40分。その間ずっと進行中でなければ、動いている外部作業が画面から消える
        assert(worker(t0.addingTimeInterval(5))?.busy == true, "呼び出し直後に稼働扱いでない")
        assert(worker(t0.addingTimeInterval(600))?.busy == true,
               "10分で停止扱いになった（codex は15〜40分かかる）")
        assert(worker(t0.addingTimeInterval(1800))?.busy == true, "30分で停止扱いになった")

        // 手動の非アクティブ削除が回っても、飛行中は畳まない
        c.clearIdleAgents(now: t0.addingTimeInterval(600))
        assert(worker(t0.addingTimeInterval(600))?.busy == true, "飛行中に畳まれた")

        // 完了したら lastAt が進み、畳まれていても戻る
        c.apply([.touchFinished(id: "c1", added: 0, removed: 0, at: t0.addingTimeInterval(1500))])
        let done = worker(t0.addingTimeInterval(1505))
        assert(done != nil, "完了したワーカーが消えた")
        assert(done?.busy == false && done?.done == true, "完了が反映されていない")

        // 一度隠してから完了しても戻ってくること（前回のループで開いた穴の回帰）
        let late = Cockpit()
        late.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0),
                    .mcpCalled(call: "c2", session: "S1", by: "S1", server: "codex", tool: "codex",
                               prompt: "長い作業", at: t0)])
        late.clearIdleAgents(now: t0.addingTimeInterval(Cockpit.mcpStuckAfter + 10))
        assert(!late.snapshot(now: t0.addingTimeInterval(Cockpit.mcpStuckAfter + 10), mode: .work)
                .chips.contains { $0.model == "MCP" }, "返らないワーカーが畳まれない")
        late.apply([.touchFinished(id: "c2", added: 0, removed: 0,
                                   at: t0.addingTimeInterval(Cockpit.mcpStuckAfter + 60))])
        assert(late.snapshot(now: t0.addingTimeInterval(Cockpit.mcpStuckAfter + 65), mode: .work)
                .chips.contains { $0.model == "MCP" },
               "畳まれた後に完了しても戻らない（lastAt が進んでいない）")
    }

    static func chipDetailsListWhatItTouched() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 27_000_000)
        c.apply(read("worker", "/p/App.swift", "r1", at: t0))
        c.apply(read("worker", "/p/App.swift", "r2", at: t0.addingTimeInterval(1)))
        c.apply(write("worker", "/p/App.swift", "w1", at: t0.addingTimeInterval(2)))
        c.apply([.touchStarted(id: "s2", session: "S2", agent: "worker",
                               path: "/q/Other.swift", kind: .write, at: t0),
                 .touchFinished(id: "s2", added: 4, removed: 0, at: t0.addingTimeInterval(0.1))])

        c.selectedSession = "S1"
        var files = c.touchedFiles(by: "worker")
        assert(files.count == 1 && files[0].path == "/p/App.swift"
               && files[0].reads == 2 && files[0].writes == 1, "実際: \(files)")
        assert(c.writeHistory(of: "/p/App.swift").count == 1)
        assert(c.touchedFiles(by: "nobody").isEmpty, "触っていないエージェントにファイルが出た")
        let layout = CockpitLayout.compute(c.snapshot(now: t0.addingTimeInterval(3), mode: .work), width: 900)
        let chip = layout.chips.first { $0.chip.id == "worker" }!
        assert(layout.chip(at: CGPoint(x: chip.rect.midX, y: chip.rect.midY)) == "worker",
               "描いたチップを押しても引けない")

        c.selectedSession = "S2"
        files = c.touchedFiles(by: "worker")
        assert(files.count == 1 && files[0].path == "/q/Other.swift" && files[0].writes == 1)
        assert(c.writeHistory(of: "/p/App.swift").isEmpty, "履歴とセッション窓がずれた")

        c.selectedSession = nil
        c.clear()
        assert(c.touchedFiles(by: "worker").isEmpty
               && c.writeHistory(of: "/p/App.swift").isEmpty, "クリア窓が履歴とずれた")
    }

    static func foldsChipsOverTheLimit() {
        let t0 = Date(timeIntervalSince1970: 28_000_000)
        let c = Cockpit()
        for i in 0...Cockpit.maxChips {
            c.apply([.agentActivity(agent: "a\(i)", session: "S1", model: "opus", at: t0)])
        }
        let snap = c.snapshot(now: t0.addingTimeInterval(1), mode: .work)
        assert(snap.chips.count == Cockpit.maxChips && snap.hiddenChips == 1,
               "上限と畳んだ数が違う: \(snap.chips.count) / \(snap.hiddenChips)")
        let layout = CockpitLayout.compute(snap, width: 900)
        guard let summary = layout.chips.last, summary.chip.id.isEmpty else {
            fatalError("他N体のチップが無い")
        }
        assert(summary.role == "他 1 体")
        assert(layout.chip(at: CGPoint(x: summary.rect.midX, y: summary.rect.midY)) == nil,
               "まとめチップが押せてしまう")

        let exact = Cockpit()
        for i in 0..<Cockpit.maxChips {
            exact.apply([.agentActivity(agent: "b\(i)", session: "S1", model: "opus", at: t0)])
        }
        let under = exact.snapshot(now: t0.addingTimeInterval(1), mode: .work)
        assert(under.chips.count == Cockpit.maxChips && under.hiddenChips == 0)
    }

    static func listsRecentSessions() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("at22-recent-\(UUID().uuidString)")
        let alpha = root.appendingPathComponent("alpha")
        let beta = root.appendingPathComponent("beta")
        try! FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let base = Date(timeIntervalSince1970: 30_000_000)
        for i in 0..<35 {
            let project = i.isMultiple(of: 2) ? alpha : beta
            let id = String(format: "S%02d", i)
            let file = project.appendingPathComponent(id + ".jsonl")
            let text: String
            if i == 34 {
                text = #"{"type":"assistant","sessionId":"S34","cwd":"/tmp/ProjectAlpha","timestamp":"2026-08-01T10:00:00.000Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"edit34","name":"Edit","input":{"file_path":"/tmp/ProjectAlpha/App.swift"}}]}}"#
                    + "\n" + #"{"type":"user","sessionId":"S34","timestamp":"2026-08-01T10:00:01.000Z","toolUseResult":{"structuredPatch":[]},"message":{"content":[{"type":"tool_result","tool_use_id":"edit34"}]}}"# + "\n"
            } else {
                text = "{}\n"
            }
            try! Data(text.utf8).write(to: file)
            try! FileManager.default.setAttributes([.modificationDate: base.addingTimeInterval(Double(i))],
                                                    ofItemAtPath: file.path)
        }

        let sub = alpha.appendingPathComponent("S34/subagents")
        try! FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let subLine = #"{"type":"assistant","sessionId":"S34","agentId":"sub34","cwd":"/tmp/ProjectAlpha","timestamp":"2026-08-01T10:00:02.000Z","message":{"model":"claude-haiku-4-5-20251001","stop_reason":"end_turn","content":[{"type":"tool_use","id":"read34","name":"Read","input":{"file_path":"/tmp/ProjectAlpha/Spec.md"}}]}}"# + "\n"
        try! Data(subLine.utf8).write(to: sub.appendingPathComponent("agent-sub34.jsonl"))
        let meta = #"{"agentType":"general-purpose","description":"履歴ワーカー","spawnDepth":1,"toolUseId":"spawn34"}"#
        try! Data(meta.utf8).write(to: sub.appendingPathComponent("agent-sub34.meta.json"))

        let recent = Cockpit.listRecentSessions(root: root)
        assert(recent.count == Cockpit.maxRecentSessions, "全体30件になっていない: \(recent.count)")
        for group in Dictionary(grouping: recent, by: \.project).values {
            assert(group.map(\.modifiedAt) == group.map(\.modifiedAt).sorted(by: >),
                   "プロジェクト内が新しい順でない")
        }
        assert(recent.first?.id == "S34" && !recent.contains { $0.id == "S00" },
               "全体の古い方を落としていない")

        let c = Cockpit(projectsRoot: root)
        await c.loadSession(recent[0])
        var snap = c.snapshot(now: TranscriptParser.date("2026-08-01T10:00:03.000Z")!, mode: .work)
        assert(c.selectedSession == "S34")
        assert(c.liveSessions.first { $0.id == "S34" }?.cwd == "/tmp/ProjectAlpha",
               "replayからcwdをタブへ載せていない")
        assert(Set(snap.cards.flatMap(\.files).map(\.name)) == ["App.swift", "Spec.md"],
               "親とsubagentsを丸ごと読めていない")
        assert(snap.chips.contains { $0.id == "S34" }
               && snap.chips.contains { $0.id == "sub34" && $0.role == "履歴ワーカー" },
               "履歴のエージェントが載らない")
        let firstRoot = snap.chips.first { $0.id == "S34" }
        assert(firstRoot?.work == 1 && firstRoot?.counts.first { $0.kind == .edit }?.count == 1,
               "初回読み込みの作業量が違う")
        await c.loadSession(recent[0])
        snap = c.snapshot(now: TranscriptParser.date("2026-08-01T10:00:03.000Z")!, mode: .work)
        assert(c.touchedFiles(by: "S34").first?.writes == 1, "同じセッションを二度読んだ")
        let secondRoot = snap.chips.first { $0.id == "S34" }
        assert(secondRoot?.work == 1 && secondRoot?.counts.first { $0.kind == .edit }?.count == 1,
               "二度読みで作業量を二重計上した")

        // 追記監視が先に同じ行を読んでいても、一括読み込みで内訳を増やさない
        let overlap = Cockpit(projectsRoot: root)
        let watcher = TranscriptWatcher(root: root)
        watcher.onEvents = { overlap.apply($0) }
        watcher.poll(initial: false)
        overlap.selectedSession = "S34"
        var overlapRoot = overlap.snapshot(
            now: TranscriptParser.date("2026-08-01T10:00:03.000Z")!, mode: .work)
            .chips.first { $0.id == "S34" }
        assert(overlapRoot?.work == 1 && overlapRoot?.counts.first { $0.kind == .edit }?.count == 1)
        await overlap.loadSession(recent[0])
        overlapRoot = overlap.snapshot(
            now: TranscriptParser.date("2026-08-01T10:00:03.000Z")!, mode: .work)
            .chips.first { $0.id == "S34" }
        assert(overlapRoot?.work == 1 && overlapRoot?.counts.first { $0.kind == .edit }?.count == 1,
               "ウォッチャーと一括読み込みで作業量を二重計上した")

        // await中に選択が動いた場合だけ、その操作を完了通知より優先する
        assert(Cockpit.selectionAfterLoading("S34", from: "S1", current: "S1") == "S34")
        assert(Cockpit.selectionAfterLoading("S34", from: "S1", current: "S2") == "S2",
               "読み込み完了が途中のタブ選択を奪った")

        // 一括読み込みも監視と同じ末尾窓を使い、巨大な親transcriptを全量展開しない
        let capProject = root.appendingPathComponent("cap")
        try! FileManager.default.createDirectory(at: capProject, withIntermediateDirectories: true)
        let capURL = capProject.appendingPathComponent("BIG.jsonl")
        let early = #"{"type":"assistant","sessionId":"BIG","cwd":"/tmp/Capped","timestamp":"2026-08-01T08:00:00.000Z","message":{"content":[{"type":"tool_use","id":"early","name":"Edit","input":{"file_path":"/tmp/Capped/Early.swift"}}]}}"# + "\n"
        let padding = String(repeating: "x", count: Int(TranscriptWatcher.defaultTailBytes)) + "\n"
        let late = #"{"type":"assistant","sessionId":"BIG","cwd":"/tmp/Capped","timestamp":"2026-08-01T11:00:00.000Z","message":{"content":[{"type":"tool_use","id":"late","name":"Edit","input":{"file_path":"/tmp/Capped/Late.swift"}}]}}"# + "\n"
        try! Data((early + padding + late).utf8).write(to: capURL)
        let capped = RecentSession(id: "BIG", project: "cap", projectURL: capProject,
                                   transcriptURL: capURL, modifiedAt: base)
        let cappedCockpit = Cockpit(projectsRoot: root)
        await cappedCockpit.loadSession(capped)
        let cappedFiles = Set(cappedCockpit.snapshot(
            now: TranscriptParser.date("2026-08-01T11:00:01.000Z")!, mode: .work)
            .cards.flatMap(\.files).map(\.name))
        assert(cappedFiles.contains("Late.swift") && !cappedFiles.contains("Early.swift"),
               "一括読み込みの末尾上限が効いていない")
    }

    /// 一覧のセルはモードで寸法を変えない。解説は解説画面に置いたので2行ぶんの高さは要らない。
    /// 高さが変わると、モードを切り替えるたびに並びが飛んで目が迷子になる
    static func cellsKeepTheSameSizeInBothModes() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 24_000_000)
        c.adopt(Structure.build([
            "/p/App.swift":   "/// 入口。ここから始まる\nstruct App {}",
            "/p/Other.swift": "struct Other {}",
        ]))
        c.apply(write("a", "/p/App.swift", "w1", at: t0, added: 5))

        func heights(_ mode: CockpitMode) -> [CGFloat] {
            CockpitLayout.compute(c.snapshot(now: t0.addingTimeInterval(1), mode: mode), width: 900)
                .cards.flatMap(\.cells).map(\.rect.height)
        }
        assert(heights(.work) == [CockpitLayout.cellHeight], "作業モードの寸法が変わった")
        assert(Set(heights(.structure)) == [CockpitLayout.cellHeight],
               "構造モードだけセルの高さが違う (実際: \(Set(heights(.structure))))")

        // 解説は一覧に出さない。出す場所は解説画面だけ
        let view = CockpitLayout.ego(path: "/p/App.swift", graph: c.structure,
                                     lastEdit: nil, size: CGSize(width: 1200, height: 700))
        assert(view.memo.joined().contains("入口"), "解説画面から解説が消えた")
    }

    /// `FileCategory.classify` の判定表そのものを固定する。実装がどう書かれているかではなく
    /// この表を検査する——実装が表からズレたら、書き方に関係なくここで落ちるのが正しい
    static func classifiesFilesByCategory() {
        let table: [(String, FileCategory)] = [
            ("/p/Sources/AT22/Gate.swift", .source),
            ("latest.swift", .source),
            ("FooTests.swift", .test),
            ("foo_test.go", .test),
            ("foo.test.ts", .test),
            ("FooSpec.rb", .test),
            ("p0-selfcheck.swift", .test),
            ("latest_test.swift", .test),
            ("README.md", .note),
            ("contest.md", .note),
            ("testament.txt", .note),
            ("Package.resolved", .config),
            (".gitignore", .config),
            ("Makefile", .config),
            ("icon.png", .asset),
            ("index.html", .asset),
            ("", .other),
            ("mystery.xyz", .other),
        ]
        for (path, expected) in table {
            let actual = FileCategory.classify(path: path)
            assert(actual == expected, "「\(path)」は \(expected) のはずが \(actual) だった")
        }

        // 拡張子は大文字小文字を問わない
        assert(FileCategory.classify(path: "README.MD") == .note,
               "拡張子の大文字小文字で判定がぶれた")

        // フルパスでもファイル名だけでも同じ結果になる
        assert(FileCategory.classify(path: "/a/b/c/FooTests.swift")
               == FileCategory.classify(path: "FooTests.swift"),
               "フルパスとファイル名だけで結果が違う")

        // 純関数：同じ入力を2回呼んでも同じ結果
        assert(FileCategory.classify(path: "latest_test.swift")
               == FileCategory.classify(path: "latest_test.swift"),
               "同じ入力で結果が変わった（純関数になっていない）")

        // 6種類・title はどれも空でない・rawValue は全て異なる
        assert(FileCategory.allCases.count == 6, "6種類のはずが \(FileCategory.allCases.count)種類だった")
        assert(FileCategory.allCases.allSatisfy { !$0.title.isEmpty }, "title が空のケースがある")
        assert(Set(FileCategory.allCases.map(\.rawValue)).count == FileCategory.allCases.count,
               "rawValue が重複している")
    }

    /// `CockpitLayout.compute` が作る `CellBox` にカテゴリが載ることを、レイアウト経由で確認する。
    /// `CellBox` の生成箇所は通常のカード折り返し（作業/構造モード）と、壁打ちモード専用の
    /// 1列レイアウト（`placeCard`）の2箇所に分かれているので、片方だけ直す事故を防ぐため両方通す
    static func cellsCarryTheirCategory() {
        // 作業モード：実際にファイルを触らせて通常のカード折り返し経路を通す
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 26_000_000)
        c.apply(write("a", "/p/src/Impl.swift", "w1", at: t0))
        c.apply(write("a", "/p/docs/README.md", "w2", at: t0.addingTimeInterval(1)))

        let workSnap = c.snapshot(now: t0.addingTimeInterval(2), mode: .work)
        let workBoxes = Dictionary(uniqueKeysWithValues:
            CockpitLayout.compute(workSnap, width: 900).cards.flatMap(\.cells).map { ($0.cell.id, $0) })
        assert(workBoxes["/p/src/Impl.swift"]?.category == .source,
               "作業モードで .swift のセルが .source になっていない (実際: \(workBoxes["/p/src/Impl.swift"]?.category.rawValue ?? "nil"))")
        assert(workBoxes["/p/docs/README.md"]?.category == .note,
               "作業モードで .md のセルが .note になっていない (実際: \(workBoxes["/p/docs/README.md"]?.category.rawValue ?? "nil"))")

        // 壁打ちモード：`placeCard` の1列経路。記憶DB以外のカードは出ないので、
        // 材料を直接 CockpitSnapshot に載せてこの経路だけを狙って通す
        var memorySnap = CockpitSnapshot()
        memorySnap.mode = .memory
        memorySnap.cards = [DirCard(id: "db:test", dir: "記憶", files: [
            FileCell(id: "/m/Note.swift", name: "Note.swift", lastAt: t0),
            FileCell(id: "/m/Note.md", name: "Note.md", lastAt: t0),
        ])]
        let memoryBoxes = Dictionary(uniqueKeysWithValues:
            CockpitLayout.compute(memorySnap, width: 900).cards.flatMap(\.cells).map { ($0.cell.id, $0) })
        assert(memoryBoxes["/m/Note.swift"]?.category == .source,
               "壁打ちモードで .swift のセルが .source になっていない (実際: \(memoryBoxes["/m/Note.swift"]?.category.rawValue ?? "nil"))")
        assert(memoryBoxes["/m/Note.md"]?.category == .note,
               "壁打ちモードで .md のセルが .note になっていない (実際: \(memoryBoxes["/m/Note.md"]?.category.rawValue ?? "nil"))")
    }

    /// クリックの当たり判定。GUI を動かさずに検査できるよう純関数に出してあるので、
    /// 「押したのに違うものが開く／何も開かない」はここで落ちる
    static func clicksResolveToWhatWasDrawn() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 23_000_000)
        for i in 1...4 {
            c.apply([.taskDeclared(call: "c\(i)", session: "S1", subject: "Phase \(i): 何かをする",
                                   activeForm: "Phase \(i) 中", detail: "詳細", at: t0),
                     .taskNumbered(call: "c\(i)", id: "\(i)")])
        }
        c.apply([.taskStatus(session: "S1", id: "1", status: .inProgress, at: t0)])
        for i in 0..<6 {
            c.apply(write("a", "/p/dir\(i % 2)/File\(i).swift", "e\(i)",
                          at: t0.addingTimeInterval(Double(i))))
        }
        c.apply(read("a", "/p/docs/spec.md", "r1", at: t0.addingTimeInterval(9)))

        let snap = c.snapshot(now: t0.addingTimeInterval(10), mode: .work)
        let layout = CockpitLayout.compute(snap, width: 900)
        assert(!layout.cards.isEmpty, "検査の前提が組めていない")

        // 描いた矩形の真ん中を押したら、それが返ること。
        // **進行表は当たり判定を持たない**——最上段の帯は SwiftUI の部品になったので、
        // Canvas の座標には出てこない（押せるのはファイル・チップ・門の3つだけ）
        for card in layout.cards {
            for box in card.cells {
                let hit = layout.file(at: CGPoint(x: box.rect.midX, y: box.rect.midY))
                assert(hit == box.cell.id, "セルの中心が引けない: \(box.cell.name) → \(hit ?? "nil")")
            }
        }

        // 何も無いところは nil。押すたびに前の吹き出しが閉じる
        let empty = CGPoint(x: 5, y: layout.busY + 2)
        assert(layout.file(at: empty) == nil, "余白がどれかに当たっている")

        // 帯に出す並びは、一覧の実体から必ず引けること（引けないと押した先が空になる）
        let strip = Cockpit.progressStrip(c.allTasks(session: "S1"))
        let ids = Set(c.allTasks(session: "S1").map(\.id))
        for task in strip.recent + strip.upcoming + [strip.current].compactMap({ $0 }) {
            assert(ids.contains(task.id), "帯に実体が無いID: \(task.id)")
        }
    }

    // MARK: コード構造

    /// import では辺が張れない（Swift の単一モジュールにはファイル間 import が無い）ので、
    /// 「宣言した名前を誰が使っているか」で張る。誤って張ると存在しない依存を見せることになる
    static func buildsDependencyGraphFromSymbols() {
        let files = [
            "/p/Model.swift": "struct TaskItem { let id: Int }\nenum Priority { case high }",
            "/p/View.swift":  "func body() { let a = TaskItem(id: 1); _ = Priority.high }",
            "/p/Util.swift":  "func clamp(_ x: Int) -> Int { x }",
        ]
        let g = Structure.build(files)
        assert(g.dependsOn["/p/View.swift"] == ["/p/Model.swift"],
               "使っている先が引けない (実際: \(g.dependsOn["/p/View.swift"] ?? []))")
        assert(g.usedBy["/p/Model.swift"] == ["/p/View.swift"], "逆引きが張れていない")
        assert(g.dependsOn["/p/Model.swift"] == nil, "宣言しただけのファイルに辺が出た")
        assert(g.dependsOn["/p/Util.swift"] == nil, "何も使っていないファイルに辺が出た")
        assert(g.scanned == 3 && g.edges == 1, "実際: \(g.scanned) / \(g.edges)")

        // 自分の宣言を自分で使っても辺にしない
        assert(Structure.build(["/p/A.swift": "struct Alpha {}\nlet x = Alpha()"]).isEmpty,
               "自己参照で辺が出た")

        // 同じ名前を2ファイルが宣言していたら、どちらを指すか決められないので捨てる
        let dup = Structure.build([
            "/p/A.swift": "struct Config {}",
            "/p/B.swift": "struct Config {}",
            "/p/C.swift": "let c = Config()",
        ])
        assert(dup.isEmpty, "曖昧な名前で当てずっぽうの辺を張った (実際: \(dup.dependsOn))")

        // `type` は TypeScript だけ。Swift で拾うと `obj["type"] as? String` の
        // String が「宣言された型」になり、全ファイルが1ファイルに繋がる
        let swiftish = Structure.build([
            "/p/A.swift": #"let t = obj["type"] as? String"#,
            "/p/B.swift": "let s: String = \"x\"",
        ])
        assert(swiftish.isEmpty, "Swift で type を宣言として拾っている (実際: \(swiftish.dependsOn))")
        let ts = Structure.build([
            "/p/model.ts": "export type Ticket = { id: number }",
            "/p/view.ts":  "const t: Ticket = { id: 1 }",
        ])
        assert(ts.dependsOn["/p/view.ts"] == ["/p/model.ts"],
               "TypeScript の type が拾えていない (実際: \(ts.dependsOn))")

        // 「何をするやつか」の取り方。人のコメントが最優先、無ければ宣言している型
        let noted = Structure.build([
            "/p/Engine.swift": "/// 音を鳴らす側の入口。再生と停止だけを持つ\nstruct Engine {}\nenum Voice {}",
            "/p/Mixer.swift":  "struct Mixer {}\nenum Bus {}",
        ])
        let engine = noted.notes["/p/Engine.swift"]!
        assert(engine.memo == "音を鳴らす側の入口。再生と停止だけを持つ", "実際: \(engine.memo)")
        assert(engine.headline == engine.memo, "人の説明があるのに型一覧を出した")
        let mixer = noted.notes["/p/Mixer.swift"]!
        assert(mixer.memo.isEmpty && mixer.declared == ["Mixer", "Bus"], "実際: \(mixer.declared)")
        assert(mixer.headline == "Mixer +1型", "説明が無いファイルの代わりが出ない (実際: \(mixer.headline))")

        // ファイル名と同じ型が主役。出現順のままだと先頭の小さな型が見出しを名乗る
        let stemFirst = Structure.build(["/p/Player.swift": "enum PlayerMode {}\nstruct Player {}"])
        assert(stemFirst.notes["/p/Player.swift"]?.declared.first == "Player",
               "ファイル名と同じ型が先頭に来ない")

        // MARK を挟んだ先の `///` はその型の説明。ファイルの説明として拾ってはいけない
        let sectioned = Structure.build([
            "/p/Codec.swift": "import Foundation\n\n// MARK: - 変換\n\n/// 1フレームの向き\nenum Facing {}",
        ])
        assert(sectioned.notes["/p/Codec.swift"]?.memo.isEmpty == true,
               "MARK の後ろの型コメントを拾った")

        // Xcode の自動ヘッダは役割を語らないので落とす
        let boiler = Structure.build([
            "/p/View.swift": "//  View.swift\n//  MyApp\n//\n//  Created by Someone on 2025/09/26.\n//\n\nstruct Screen {}",
        ])
        assert(boiler.notes["/p/View.swift"]?.memo.isEmpty == true,
               "Xcode の自動ヘッダを役割として拾った")
        assert(boiler.notes["/p/View.swift"]?.headline == "Screen", "代わりの型一覧が出ない")

        // 小文字始まりと短すぎる名前は拾わない（メソッド名とジェネリクスで誤爆する）
        let noisy = Structure.build([
            "/p/A.swift": "struct T {}\nclass update {}",
            "/p/B.swift": "let x: T = t; update()",
        ])
        assert(noisy.isEmpty, "1文字の型名や小文字の宣言を拾っている (実際: \(noisy.dependsOn))")

        // 実物で確かめる。AT22 自身の Sources に掛けて、既知の依存が出ること
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Sources/AT22")
        guard FileManager.default.fileExists(atPath: sources.path) else { return }
        let real = Structure.scan(roots: [sources])
        func has(_ from: String, _ to: String) -> Bool {
            real.dependsOn.first { $0.key.hasSuffix(from) }?.value.contains { $0.hasSuffix(to) } ?? false
        }
        assert(real.scanned >= 5, "自分の Sources を読めていない (実際: \(real.scanned))")
        assert(has("Cockpit.swift", "Transcript.swift"), "既知の依存が出ていない")
        assert(has("CockpitLayout.swift", "Cockpit.swift"), "既知の依存が出ていない")
        // AT22App.swift は起点なので誰からも使われない。ここに逆向きの辺が出たら誤検出が混ざっている。
        // （以前は Structure.swift の「辺ゼロ」を見ていたが、そのファイルのコメントが
        //   他ファイルの型名に言及した途端に辺が立って落ちた。コメントも語として拾う仕様どおりの挙動で、
        //   検査の前提の方が壊れやすかったため、コメントに出にくい「被依存ゼロ」へ移した）
        assert(real.usedBy.first { $0.key.hasSuffix("AT22App.swift") } == nil,
               "起点のファイルが誰かに使われている（誤検出）")

        // 「何をするやつか」が全ファイルに付くこと。人のコメントは半分のファイルにしか無いので、
        // 無い分は宣言している型で埋まる（空欄のセルを出さないための代替）
        let notes = real.notes
        assert(notes.count == real.scanned, "役割の付いていないファイルがある")
        assert(notes.values.allSatisfy { !$0.headline.isEmpty }, "見出しが空のファイルがある")
        assert(notes.first { $0.key.hasSuffix("CockpitLayout.swift") }?.value.memo
                .contains("画面の座標") == true, "人が書いた説明を拾えていない")
        // MARK の後ろの `///` はその型の説明であってファイルの説明ではない。取り違えると別物を見せる
        assert(notes.first { $0.key.hasSuffix("Transcript.swift") }?.value.memo.isEmpty == true,
               "MARK の後ろの型コメントをファイルの説明として拾っている")
    }

    // MARK: 実データのリプレイ

    static func replayRealTranscriptIfGiven() {
        let args = CommandLine.arguments.dropFirst()
        guard let path = args.first else {
            print("p0: 実 transcript のリプレイはスキップ（引数にパスかセッションディレクトリを渡すと実行）")
            return
        }

        // ディレクトリを渡された場合は、そこの transcript とサブエージェントを全部流し込む
        // （親子の解決は親の transcript と meta.json が両方揃って初めて効く）
        var sources: [String] = []
        var metas: [String] = []
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue {
            let all = FileManager.default.enumerator(atPath: path)?.allObjects as? [String] ?? []
            for rel in all {
                if rel.hasSuffix(".jsonl") { sources.append((path as NSString).appendingPathComponent(rel)) }
                if rel.hasSuffix(".meta.json") { metas.append((path as NSString).appendingPathComponent(rel)) }
            }
            // セッションディレクトリ（`<sessionUUID>/`）を渡された場合、親の transcript は
            // その中ではなく兄弟の `<sessionUUID>.jsonl` にある。これが無いと親子が繋がらない
            let sibling = path + ".jsonl"
            if FileManager.default.fileExists(atPath: sibling) { sources.append(sibling) }
        } else {
            sources = [path]
        }
        guard !sources.isEmpty else { fatalError("transcript が見つからない: \(path)") }

        let cockpit = Cockpit()
        // 過去の記録を丸ごと見るので、チップの沈黙窓は外す
        
        // meta.json から役割・階層・親の呼び出しID
        for meta in metas {
            let name = ((meta as NSString).lastPathComponent as NSString).deletingPathExtension
            let id = String(name.replacingOccurrences(of: ".meta", with: "").dropFirst("agent-".count))
            guard let data = FileManager.default.contents(atPath: meta),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = obj["agentType"] as? String else { continue }
            let role = TranscriptParser.roleName(type: type, description: obj["description"] as? String)
            cockpit.apply([.agentMeta(agent: id, session: "replay", role: role,
                                      depth: obj["spawnDepth"] as? Int ?? 1,
                                      parentCall: obj["toolUseId"] as? String ?? "")])
        }

        var reads = 0, writes = 0, finished = 0, totalLines = 0
        var latest = Date(timeIntervalSince1970: 0)
        for source in sources {
            guard let data = FileManager.default.contents(atPath: source) else { continue }
            for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                totalLines += 1
                let events = TranscriptParser.parse(Data(line), fallbackSession: "replay")
                for e in events {
                    if case let .touchStarted(_, _, _, _, kind, at) = e {
                        if kind == .read { reads += 1 } else { writes += 1 }
                        latest = max(latest, at)
                    }
                    if case .touchFinished = e { finished += 1 }
                }
                cockpit.apply(events)
            }
        }

        // 録画された最後の触り時点から見る（実時刻だと全部アイドルになって状態が検査できない）
        let snap = cockpit.snapshot(now: latest, mode: .work)
        let files = snap.cards.flatMap(\.files)
        let layout = CockpitLayout.compute(snap, width: 1100)
        print("p0: \(sources.count)本 \(totalLines)行 / 参照 \(reads) / 書き込み \(writes) / 完了 \(finished)")
        print("p0: カード \(snap.cards.count) / ファイル \(files.count) / エージェント \(snap.chips.count) / フラグ \(snap.flagCount) / 高さ \(Int(layout.contentHeight))")
        for chip in snap.chips {
            let parent = chip.parent.map { " ←親 \($0.suffix(6))" } ?? ""
            let state = chip.done ? "終了" : (chip.busy ? "稼働" : "待機")
            print("p0:   \(String(repeating: "  ", count: chip.depth))\(chip.role) [\(chip.model)] 労働\(chip.work) \(state)\(parent)")
            print("p0:   \(String(repeating: "  ", count: chip.depth))  └ \(chip.doing)")
        }

        let allTasks = cockpit.allTasks(session: cockpit.selectedSession)
        if !allTasks.isEmpty {
            let strip = Cockpit.progressStrip(allTasks)
            print("p0: 進行表 \(allTasks.count)件 / 帯に畳んだ番号 \(strip.foldedNumbers)")
            for task in allTasks {
                let mark = switch task.status {
                case .pending: "・" ; case .inProgress: "▶" ; case .completed: "✓"
                }
                print("p0:   \(mark) #\(task.number) \(task.subject)")
            }
            assert(allTasks.map(\.number) == allTasks.map(\.number).sorted(),
                   "進行表が番号順に並んでいない")
            assert(allTasks.allSatisfy { !$0.subject.isEmpty }, "件名が空のタスクがある")
            // 帯に出る件数は必ず一覧より少ない（1行に収まる形になっている）
            let shown = strip.recent.count + (strip.current == nil ? 0 : 1) + strip.upcoming.count
            assert(shown <= allTasks.count, "帯が一覧より多い")
        }

        if !metas.isEmpty {
            let subs = snap.chips.filter { $0.depth > 0 }
            assert(!subs.isEmpty, "サブエージェントが1体も出ていない")
            assert(subs.contains { $0.parent != nil },
                   "実データで親子が1件も解決できていない（meta.json の呼び出しIDと Agent の tool_use が繋がっていない）")
            assert(snap.chips.contains { $0.depth == 0 && $0.role == Cockpit.rootRole },
                   "階層の頂点が出ていない")
            assert(snap.chips.allSatisfy { !$0.model.isEmpty }, "モデル名が取れていないエージェントがいる")
            // 中断されたエージェントには終了報告が来ないので、全員が done にはならない
            assert(subs.contains { $0.done }, "終了報告が1件も終了扱いになっていない")
            assert(subs.allSatisfy { $0.work > 0 }, "労働量が取れていないサブエージェントがいる")
            // 同じ階層内は労働量の多い順
            let depths = Set(snap.chips.map(\.depth))
            for d in depths {
                let row = snap.chips.filter { $0.depth == d }.map(\.work)
                assert(row == row.sorted(by: >), "階層 \(d) が労働量順に並んでいない: \(row)")
            }
        }
        assert(reads + writes > 0, "実 transcript から触りが1件も拾えていない")
        assert(!files.isEmpty, "ファイルが1つも出ていない")
        assert(finished > 0, "tool_result で閉じられた触りが1件も無い")
        for card in layout.cards {
            for box in card.cells {
                assert(card.rect.contains(box.rect), "実データでセルがカードからはみ出した: \(box.cell.name)")
            }
        }
    }

    /// 「特大＝上位2%」は値で切ると同点で崩れる。同じ量のファイルが並ぶと
    /// 画面じゅうが虹になり、虹は常時アニメーションなので描画も道連れで重くなる
    static func hugeStaysRareWhenVolumesTie() {
        func snap(_ volumes: [Int]) -> CockpitSnapshot {
            var s = CockpitSnapshot()
            let cells = volumes.enumerated().map { i, v in
                FileCell(id: "/p/F\(i).swift", name: "F\(i).swift", touched: true,
                         added: v, removed: 0, lastAt: Date())
            }
            s.cards = [DirCard(id: "/p", dir: "p", files: cells)]
            return s
        }
        func hugeCount(_ volumes: [Int]) -> Int {
            let t = CockpitLayout.hugeThreshold(snap(volumes))
            return volumes.filter { $0 >= t }.count
        }

        // 全部が同じ量なら特大は0件。何もかもが特大では目印にならない
        assert(hugeCount(Array(repeating: 500, count: 48)) == 0,
               "同点で画面じゅうが特大になった (\(hugeCount(Array(repeating: 500, count: 48)))件)")
        // 頭だけ抜けていれば、その1本だけ
        assert(hugeCount([900] + Array(repeating: 500, count: 47)) == 1,
               "突出した1本を特大にできていない")
        // 100行未満は母数にすら入らない（T3 の量が要る）
        assert(hugeCount(Array(repeating: 20, count: 40)) == 0, "小さい書き込みが特大になった")
        // 母数が2%に満たない時は最大の1本だけ
        assert(hugeCount([800, 300]) == 1, "母数が少ない時に特大が出ない/増えすぎた")
        assert(hugeCount([]) == 0)
        // 同点が上位に固まっていても、切る位置の外に出た分は特大にしない
        assert(hugeCount([700, 700, 700] + Array(repeating: 150, count: 97)) == 3,
               "上位2%（3件）を超えて特大が出た (\(hugeCount([700, 700, 700] + Array(repeating: 150, count: 97)))件)")
    }

    /// 画面を「止まっている層（3fps）」と「動く層（30fps）」に割る。
    /// 文字はほぼ全部が止まっている側に居ないと、分けた意味が無い
    static func stillAndLiveLayersSplitTheScreen() {
        let now = Date(timeIntervalSince1970: 70_000_000)
        func cell(_ name: String, state: FileState = .idle, wroteAgo: TimeInterval? = nil,
                  huge: Bool = false) -> CockpitLayout.CellBox {
            var c = FileCell(id: "/p/" + name, name: name, touched: true, lastAt: now)
            c.state = state
            if let ago = wroteAgo { c.lastWriteAt = now.addingTimeInterval(-ago) }
            return CockpitLayout.CellBox(cell: c, display: name, note: "", trace: "",
                                         readTicks: 0, rect: .zero, huge: huge, category: .other)
        }

        // 動く側：書込中・読取中・虹・掃引の途中
        assert(CockpitLayout.moves(cell("w", state: .writing), steady: now))
        assert(CockpitLayout.moves(cell("r", state: .reading), steady: now))
        assert(CockpitLayout.moves(cell("h", huge: true), steady: now), "虹は止まらないので動く側")
        assert(CockpitLayout.moves(cell("s", wroteAgo: 0.1), steady: now), "掃引の最中が止まる側に落ちた")
        // 止まる側：何も起きていない・掃引が終わった・フラグだけ
        assert(!CockpitLayout.moves(cell("i"), steady: now))
        assert(!CockpitLayout.moves(cell("old", wroteAgo: CockpitLayout.sweepDuration + 0.1), steady: now),
               "掃引が終わったセルが動く側に残った")
        assert(!CockpitLayout.moves(cell("f", state: .flagged), steady: now),
               "フラグは静止しているのに動く側へ入れた")
        // 未来に書かれた記録（時計のずれ）で掃引を始めない
        assert(!CockpitLayout.moves(cell("future", wroteAgo: -5), steady: now))

        // どちらの層も、担当する要素をちょうど1回ずつ描く（重ねても足りなくてもいけない）
        for moving in [true, false] {
            let drawn = [CockpitLayout.Layer.still, .live].filter {
                CockpitLayout.draws($0, moving: moving)
            }
            assert(drawn.count == 1, "\(moving ? "動く" : "止まる")要素を描く層が\(drawn.count)個ある")
        }
        assert(CockpitLayout.draws(.both, moving: true) && CockpitLayout.draws(.both, moving: false),
               "1枚で描く時に抜けが出る")

        // 丸めた時刻は刻みの幅で1つずつ進み、同じ刻みの中では動かない
        let step = CockpitLayout.steadyStep
        let a = CockpitLayout.steadyDate(now.addingTimeInterval(0.01))
        let b = CockpitLayout.steadyDate(now.addingTimeInterval(step * 0.9))
        let c2 = CockpitLayout.steadyDate(now.addingTimeInterval(step * 1.1))
        assert(a == b, "同じ刻みの中で止まっている層を描き直している")
        assert(c2 > a, "刻みをまたいでも止まっている層が更新されない")
        // 1970年からの秒数は10桁あり、倍精度の刻みは 1e-7 前後。1/3 秒を測るには十分で、
        // ここを 1e-9 で見ると丸め誤差だけで落ちる
        assert(abs(c2.timeIntervalSince(a) - step) < 1e-6, "刻みの幅が steadyStep と違う")

        // 実データ相当の場面で、文字を持つセルの大半が止まっている側に居ること
        let cockpit = Cockpit()
        var events: [TranscriptEvent] = []
        for i in 0..<400 {
            let at = now.addingTimeInterval(-800 + Double(i) * 2)
            events.append(.touchStarted(id: "t\(i)", session: "S", agent: "A",
                                        path: "/p/dir\(i % 6)/F\(i % 60).swift",
                                        kind: i % 5 == 0 ? .write : .read, at: at))
            events.append(.touchFinished(id: "t\(i)", added: 3 + (i % 37) * 5, removed: i % 11,
                                         at: at.addingTimeInterval(0.1)))
        }
        cockpit.apply(events)
        let layout = CockpitLayout.compute(cockpit.snapshot(now: now, mode: .work), width: 1100)
        let cells = layout.cards.flatMap(\.cells)
        let moving = cells.filter { CockpitLayout.moves($0, steady: now) }.count
        assert(cells.count > 20, "母数が足りず判定になっていない")
        assert(Double(moving) / Double(cells.count) < 0.2,
               "動く側に寄りすぎて分けた意味が無い (\(moving)/\(cells.count))")
    }
}
