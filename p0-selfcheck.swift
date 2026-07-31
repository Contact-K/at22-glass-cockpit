// AT22 p0 セルフチェック（ターゲット外・SwiftUI 非依存）
//
// swiftc -parse-as-library Sources/AT22/Transcript.swift Sources/AT22/Cockpit.swift Sources/AT22/CockpitLayout.swift p0-selfcheck.swift -o /tmp/p0check && /tmp/p0check
//
// 実 transcript を1本渡すと、そのリプレイ結果も検査する:
//   /tmp/p0check ~/.claude/projects/<slug>/<sessionUUID>.jsonl

import Foundation

@main @MainActor
struct P0SelfCheck {

    static func main() {
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
        beamSurvivesFastTools()
        beamDotTravels()
        beamDirection()
        writeVolumeTicks()
        hugeIsRelative()
        recordsWriteMoment()
        beamPassesBehindCards()
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
        replayRealTranscriptIfGiven()
        print("p0: ok")
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
        + (0..<n).map { _ in
            .agentAction(agent: agent, session: "S1", kind: kind, detail: "grep", at: at)
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

        let snap = c.snapshot(now: t0.addingTimeInterval(30))
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
        let split = two.snapshot(now: t0.addingTimeInterval(5))
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

        let snap = c.snapshot(now: t0.addingTimeInterval(600))
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
        let loose = c.snapshot(now: t0.addingTimeInterval(600))
        let plan = loose.cards.flatMap(\.files).first { $0.name == "plan.md" }
        assert(plan?.state == .flagged, "しきい値を下げれば立つ")

        // 別のエージェントが1回ずつ読んだだけでは合算しない
        let split = Cockpit()
        for i in 0..<3 {
            split.apply(read("agent\(i)", "/proj/docs/spec.md", "x\(i)", at: t0))
        }
        let s = split.snapshot(now: t0.addingTimeInterval(600))
        assert(s.cards.flatMap(\.files)[0].state == .idle, "エージェントをまたいだ合計では立てない")
        assert(s.cards.flatMap(\.files)[0].reads == 3, "表示上の参照回数は合計でよい")
    }

    static func statePrecedence() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        // 完了していない＝進行中
        c.apply([.touchStarted(id: "r", session: "S1", agent: "a", path: "/p/X.swift", kind: .read, at: t0)])
        assert(c.snapshot(now: t0.addingTimeInterval(5)).cards[0].files[0].state == .reading)

        c.apply([.touchStarted(id: "w", session: "S1", agent: "a", path: "/p/X.swift", kind: .write, at: t0)])
        assert(c.snapshot(now: t0.addingTimeInterval(5)).cards[0].files[0].state == .writing,
               "書き込み中は読み取り中より強い")

        assert(c.snapshot(now: t0.addingTimeInterval(300)).cards[0].files[0].state == .idle,
               "取り残しは進行中のまま固まらない")

        // チップは触っているファイルを指す
        let live = c.snapshot(now: t0.addingTimeInterval(5))
        assert(live.chips[0].busy)
        assert(live.chips[0].target == "/p/X.swift")
        assert(live.chips[0].kind == .write)
    }

    static func sessionFilter() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        c.apply([.touchStarted(id: "a", session: "S1", agent: "a", path: "/p/A.swift", kind: .write, at: t0),
                 .touchStarted(id: "b", session: "S2", agent: "b", path: "/p/B.swift", kind: .write, at: t0)])
        assert(c.snapshot(now: t0).cards.flatMap(\.files).count == 2)
        c.selectedSession = "S2"
        let filtered = c.snapshot(now: t0).cards.flatMap(\.files)
        assert(filtered.count == 1 && filtered[0].name == "B.swift", "セッション絞り込み")
    }

    /// Read も Edit も 0.1 秒で終わるので、開始と完了が同じ取り込みバッチで届く。
    /// 「未完了だけを進行中とみなす」設計だとビームが一度も出ない
    static func beamSurvivesFastTools() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 6_000_000)
        // 開始と完了を一度に流し込む（実際の取り込みと同じ形）
        c.apply(read("worker", "/proj/docs/spec.md", "r1", at: t0))

        let during = c.snapshot(now: t0.addingTimeInterval(1))
        assert(during.cards[0].files[0].state == .reading, "終わった直後も余韻で光る")
        assert(during.chips[0].busy, "チップが稼働表示になる")
        assert(during.chips[0].target == "/proj/docs/spec.md", "ビームの行き先がある")
        assert(during.chips[0].kind == .read, "破線ビームとして描かれる")

        let after = c.snapshot(now: t0.addingTimeInterval(Cockpit.afterglow + 1))
        assert(after.cards[0].files[0].state == .idle, "余韻が切れたら消える")
        assert(after.chips[0].target == nil, "ビームも消える")

        // 書き込みも同じ
        let w = Cockpit()
        w.apply(write("worker", "/proj/src/A.swift", "w1", at: t0))
        let wDuring = w.snapshot(now: t0.addingTimeInterval(1))
        assert(wDuring.cards[0].files[0].state == .writing)
        assert(wDuring.chips[0].kind == .write, "実線ビームとして描かれる")
    }

    /// ビームの走る点が経路の上を端から端まで動くこと
    static func beamDotTravels() {
        let path = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 10)]
        assert(CockpitLayout.pointOnPolyline(path, 0) == CGPoint(x: 0, y: 0))
        assert(CockpitLayout.pointOnPolyline(path, 1) == CGPoint(x: 10, y: 10))
        assert(CockpitLayout.pointOnPolyline(path, 0.5) == CGPoint(x: 0, y: 10), "折れ点をまたぐ")
    }

    /// 行き先が下のカードにある時、途中のカードとビームが重なる。
    /// カードの後ろを通すので、カード矩形がちゃんと引けること（＝前面に出す最後のひと伸びが決まること）
    static func beamPassesBehindCards() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 9_000_000)
        // 上の方に大量のカードを作ってから、一番下のファイルを触る
        for i in 0..<12 {
            c.apply(write("a", "/proj/dir\(i)/File\(i).swift", "e\(i)", at: t0.addingTimeInterval(Double(i))))
        }
        c.apply(read("a", "/proj/zzz/target.md", "r1", at: t0.addingTimeInterval(100)))

        let snap = c.snapshot(now: t0.addingTimeInterval(101))
        let layout = CockpitLayout.compute(snap, width: 700)
        let target = "/proj/zzz/target.md"

        guard let cell = layout.rect(forFile: target),
              let card = layout.cardRect(forFile: target) else {
            fatalError("行き先のセルとカードが引けない")
        }
        assert(card.contains(cell), "カード矩形が自分のセルを含んでいる")
        assert(cell.minY > card.minY, "前面に出す区間が正の長さを持つ")

        // 途中のカードを実際に跨いでいること（＝後ろに回す意味がある状況を検査できている）
        let beamX = cell.midX
        let crossed = layout.cards.filter {
            $0.rect.minY < card.minY && $0.rect.minX <= beamX && beamX <= $0.rect.maxX
        }
        assert(!crossed.isEmpty, "上のカードと重なる配置になっていない（検査として無意味）")
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
        var chip = c.snapshot(now: t0.addingTimeInterval(1)).chips.first { $0.id == "sub9" }
        assert(chip != nil, "起動直後もチップに出る")
        assert(chip?.done == false, "起動直後は終了扱いにしない")

        c.apply(work("sub9", 12, at: t0.addingTimeInterval(10)))
        chip = c.snapshot(now: t0.addingTimeInterval(11)).chips.first { $0.id == "sub9" }
        assert(chip?.work == 12, "進行中は観測できたぶんが労働量 (実際: \(chip?.work ?? -1))")
        assert(chip?.done == false)

        c.apply([.agentDone(agent: "sub9", session: "S1", role: "Explore", model: "opus-5",
                            toolCalls: 37, at: t0.addingTimeInterval(20))])
        chip = c.snapshot(now: t0.addingTimeInterval(21)).chips.first { $0.id == "sub9" }
        assert(chip?.done == true, "完了で灰色になる")
        assert(chip?.work == 37, "完了後は報告された確定値 (実際: \(chip?.work ?? -1))")
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

        var chip = c.snapshot(now: t0.addingTimeInterval(3)).chips.first { $0.id == "grepper" }
        assert(chip != nil, "ファイルを触らないエージェントもチップに出る")
        assert(chip?.busy == true, "Bash だけでも稼働中に見えること")
        assert(chip?.target == nil, "行き先が無いのでビームは出ない（これは仕様）")
        assert(chip?.work == 4)

        // 無音が続けば待機に落ちる
        chip = c.snapshot(now: t0.addingTimeInterval(Cockpit.activeWindow + 5)).chips.first { $0.id == "grepper" }
        assert(chip?.busy == false, "無音が続けば待機に落ちる")

        // 動き出せばまた稼働に戻る
        c.apply(work("grepper", 2, at: t0.addingTimeInterval(60)))
        chip = c.snapshot(now: t0.addingTimeInterval(62)).chips.first { $0.id == "grepper" }
        assert(chip?.busy == true, "再び動けば稼働に戻る")
        assert(chip?.work == 6)

        // 終了したら、直後でも稼働扱いにしない
        c.apply([.agentEnded(agent: "grepper", at: t0.addingTimeInterval(61))])
        chip = c.snapshot(now: t0.addingTimeInterval(62)).chips.first { $0.id == "grepper" }
        assert(chip?.busy == false, "終了したら脈打たせない")
        assert(chip?.done == true)
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
        assert(kind("cat README.md") == .view)
        assert(kind("sleep 5") == .wait)

        // 先頭の飾りは読み飛ばす（実測で Bash の80%が連結コマンド）
        assert(kind("cd /proj && grep -n foo bar.swift") == .search, "cd を読み飛ばす")
        assert(kind("rtk proxy grep -n foo bar.swift") == .search, "rtk proxy を読み飛ばす")
        assert(kind("FOO=1 git status") == .git, "環境変数の代入を読み飛ばす")
        // パイプの先ではなく先頭語で決める（`xcodebuild | grep` を検索にしない）
        assert(kind("xcodebuild build 2>&1 | grep error") == .build)
        // 表に無いコマンドは「他」で、名前だけ残す
        let (k, word) = TranscriptParser.classifyBash("pkill -x AT22")
        assert(k == .other && word == "pkill", "実際: \(k) \(word)")

        // 実行ファイルのフルパスでもコマンド名で判定する
        assert(kind("/usr/bin/grep -n foo bar.swift") == .search)
    }

    /// チップの2行目。動いている間は「今していること」、止まれば「してきたこと」
    static func showsWhatAgentIsDoing() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 15_000_000)
        c.apply([.agentMeta(agent: "w", session: "S1", role: "Explore", depth: 1, parentCall: "t"),
                 .agentActivity(agent: "w", session: "S1", model: "opus-5", at: t0)])
        c.apply((0..<12).map { _ in
            .agentAction(agent: "w", session: "S1", kind: .search, detail: "grep", at: t0) })
        c.apply((0..<5).map { _ in
            .agentAction(agent: "w", session: "S1", kind: .view, detail: "cat", at: t0) })
        c.apply([.agentAction(agent: "w", session: "S1", kind: .build, detail: "swift", at: t0)])

        // 動いている間は最後の動作
        var chip = c.snapshot(now: t0.addingTimeInterval(2)).chips.first { $0.id == "w" }
        assert(chip?.busy == true)
        assert(chip?.doing == "ビルド swift", "今していること (実際: \(chip?.doing ?? "nil"))")

        // 止まったら内訳（多い順に3つまで）
        chip = c.snapshot(now: t0.addingTimeInterval(Cockpit.activeWindow + 5)).chips.first { $0.id == "w" }
        assert(chip?.busy == false)
        assert(chip?.doing == "検索12 閲覧5 ビルド1", "してきたことの内訳 (実際: \(chip?.doing ?? "nil"))")
        assert(chip?.work == 18, "労働量は内訳の合計 (実際: \(chip?.work ?? -1))")

        // 待機（sleep）は労働量にも内訳にも入れない
        let idle = Cockpit()
        idle.apply([.agentActivity(agent: "z", session: "S1", model: "opus-5", at: t0)])
        idle.apply((0..<20).map { _ in
            .agentAction(agent: "z", session: "S1", kind: .wait, detail: "sleep", at: t0) })
        idle.apply([.agentAction(agent: "z", session: "S1", kind: .search, detail: "grep", at: t0)])
        let quiet = idle.snapshot(now: t0.addingTimeInterval(Cockpit.activeWindow + 5))
            .chips.first { $0.id == "z" }
        assert(quiet?.work == 1, "sleep を労働量から除く (実際: \(quiet?.work ?? -1))")
        assert(quiet?.doing == "検索1", "sleep を内訳から除く (実際: \(quiet?.doing ?? "nil"))")

        // ファイルを触る作業も同じ枠に出る
        let f = Cockpit()
        f.apply(read("r", "/p/Spec.md", "r1", at: t0))
        f.apply([.agentAction(agent: "r", session: "S1", kind: .read, detail: "Spec.md", at: t0)])
        let reading = f.snapshot(now: t0.addingTimeInterval(1)).chips.first { $0.id == "r" }
        assert(reading?.doing == "読取 Spec.md", "実際: \(reading?.doing ?? "nil")")
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
        var chip = c.snapshot(now: t0.addingTimeInterval(11)).chips.first { $0.id == "sub7" }
        assert(chip?.done == true, "end_turn で灰色になる")
        assert(chip?.work == 5, "労働量は観測できたぶんが残る (実際: \(chip?.work ?? -1))")

        c.apply(work("sub7", 3, at: t0.addingTimeInterval(20)))
        chip = c.snapshot(now: t0.addingTimeInterval(21)).chips.first { $0.id == "sub7" }
        assert(chip?.done == false, "再開したら灰色が解ける")
        assert(chip?.work == 8)
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
        let chip = c.snapshot(now: t0.addingTimeInterval(6)).chips.first { $0.id == "w2" }
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

    /// チップはプロジェクト名ではなく役割＋モデルを出し、親子で階層化する
    static func agentHierarchy() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 10_000_000)

        // 司令塔（メインセッション）がサブエージェントを2体起こす
        c.apply([.agentActivity(agent: "S1", session: "S1", model: "opus-5", at: t0),
                 .agentSpawn(call: "toolu_T1", by: "S1"),
                 .agentSpawn(call: "toolu_T2", by: "S1"),
                 .agentMeta(agent: "sub1", session: "S1", role: "Explore", depth: 1, parentCall: "toolu_T1"),
                 .agentMeta(agent: "sub2", session: "S1", role: "general-purpose", depth: 1, parentCall: "toolu_T2"),
                 .agentActivity(agent: "sub1", session: "S1", model: "sonnet-5", at: t0),
                 .agentActivity(agent: "sub2", session: "S1", model: "haiku-4.5", at: t0)])
        c.apply(write("S1", "/p/A.swift", "e1", at: t0))
        c.apply(read("sub1", "/p/B.swift", "r1", at: t0.addingTimeInterval(1)))
        c.apply(read("sub2", "/p/C.swift", "r2", at: t0.addingTimeInterval(2)))

        let snap = c.snapshot(now: t0.addingTimeInterval(3))
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
        let flagged = f.snapshot(now: t0.addingTimeInterval(60)).cards.flatMap(\.files)[0]
        assert(flagged.flaggedBy == "実装", "実際: \(flagged.flaggedBy ?? "nil")")
    }

    /// 書き込みはエージェントからファイルへ、読み取りはファイルからエージェントへ流れる。
    /// 走る点は折れ線の順に進むので、点の並びがそのまま向きになる
    static func beamDirection() {
        let dot = CGPoint(x: 100, y: 40)
        let cell = CGRect(x: 300, y: 200, width: 120, height: 30)

        let write = CockpitLayout.beamPoints(from: dot, to: cell, corridor: 90, kind: .write)
        assert(write.first == dot, "書き込みはエージェントから出る")
        assert(write.last?.y == cell.minY - 5, "書き込みはファイルで終わる")
        assert(write.last?.x == cell.midX)

        let read = CockpitLayout.beamPoints(from: dot, to: cell, corridor: 90, kind: .read)
        assert(read.first?.y == cell.minY - 5, "読み取りはファイルから出る（逆流）")
        assert(read.last == dot, "読み取りはエージェントで終わる")
        assert(read == write.reversed(), "経路は同じで向きだけ逆")

        // 走る点も向きに従う
        assert(CockpitLayout.pointOnPolyline(write, 0) == dot)
        assert(CockpitLayout.pointOnPolyline(read, 0) != dot)
        assert(CockpitLayout.pointOnPolyline(read, 1) == dot)

        // 指示は親から子へ
        let parent = CGRect(x: 20, y: 20, width: 160, height: 46)
        let child = CGRect(x: 46, y: 80, width: 160, height: 46)
        let order = CockpitLayout.orderPoints(from: parent, to: child)
        assert(order.first?.y == parent.maxY, "指示は親の下端から出る")
        assert(order.last?.x == child.minX, "指示は子の左端に入る")
        assert(order.last?.y == child.midY)
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
            c.snapshot(now: t0.addingTimeInterval(1)).cards.flatMap(\.files).map { ($0.name, $0) })
        assert(CockpitLayout.writeTicks(files["a.ts"]!.added) == 3, "短い名前でも大量なら3本")
        assert(CockpitLayout.writeTicks(files["ApplicationCoordinatorWithAVeryLongName.ts"]!.added) == 1,
               "長い名前でも少量なら1本")

        // ティック欄のぶんセルが広がり、名前が押し出されてもはみ出さない
        let layout = CockpitLayout.compute(c.snapshot(now: t0.addingTimeInterval(1)), width: 900)
        for card in layout.cards {
            for box in card.cells {
                assert(card.rect.contains(box.rect), "ティック追加でセルがはみ出した: \(box.display)")
                let used = CockpitLayout.tickColumn + CockpitLayout.textWidth(box.display)
                    + (box.badge.isEmpty ? 0 : CockpitLayout.textWidth(box.badge, size: CockpitLayout.badgeFont))
                assert(used <= box.rect.width, "ティック込みで文字が溢れた: \(box.display)")
            }
        }
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
        var snap = c.snapshot(now: t0.addingTimeInterval(30))
        var layout = CockpitLayout.compute(snap, width: 1200)
        var huge = layout.cards.flatMap(\.cells).filter(\.huge)
        assert(huge.count == 1, "上位2%は1ファイル (実際: \(huge.count))")
        assert(huge[0].cell.name == "F19.swift", "一番書かれたものが特大 (実際: \(huge[0].cell.name))")

        // 全部が小さければ誰も特大にならない
        let small = Cockpit()
        for i in 0..<20 {
            small.apply(write("a", "/p/dir/S\(i).swift", "s\(i)", at: t0, added: 5))
        }
        snap = small.snapshot(now: t0.addingTimeInterval(30))
        layout = CockpitLayout.compute(snap, width: 1200)
        huge = layout.cards.flatMap(\.cells).filter(\.huge)
        assert(huge.isEmpty, "100行未満しか無ければ特大は出ない (実際: \(huge.count))")

        // 1つだけ巨大なら、それが特大
        small.apply(write("a", "/p/dir/Big.swift", "big", at: t0.addingTimeInterval(40), added: 900))
        layout = CockpitLayout.compute(small.snapshot(now: t0.addingTimeInterval(50)), width: 1200)
        huge = layout.cards.flatMap(\.cells).filter(\.huge)
        assert(huge.count == 1 && huge[0].cell.name == "Big.swift", "実際: \(huge.map(\.cell.name))")
    }

    /// 書かれた瞬間だけ光の帯を流すので、書き込み時刻が要る
    static func recordsWriteMoment() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 17_000_000)
        c.apply(read("a", "/p/Spec.md", "r1", at: t0))
        var cell = c.snapshot(now: t0.addingTimeInterval(1)).cards.flatMap(\.files)[0]
        assert(cell.lastWriteAt == nil, "読んだだけでは帯を流さない")

        c.apply(write("a", "/p/Spec.md", "w1", at: t0.addingTimeInterval(10), added: 5))
        cell = c.snapshot(now: t0.addingTimeInterval(11)).cards.flatMap(\.files)[0]
        assert(cell.lastWriteAt != nil, "書き込み時刻が入る")

        // 二度目の書き込みで時刻が進む（帯がもう一度流れる）
        c.apply(write("a", "/p/Spec.md", "w2", at: t0.addingTimeInterval(60), added: 3))
        let again = c.snapshot(now: t0.addingTimeInterval(61)).cards.flatMap(\.files)[0]
        assert(again.lastWriteAt! > cell.lastWriteAt!, "書くたびに更新される")
    }

    // MARK: レイアウト

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
            let snap = c.snapshot(now: t0.addingTimeInterval(60))
            let layout = CockpitLayout.compute(snap, width: width)
            for card in layout.cards {
                assert(card.rect.width <= width - CockpitLayout.margin,
                       "カードが画面幅を超えた (幅 \(width))")
                for box in card.cells {
                    assert(card.rect.contains(box.rect),
                           "幅 \(width) でセル \(box.display) がカードからはみ出した")
                    // 省略後の文字列がセル内に収まっていること
                    let used = CockpitLayout.textWidth(box.display)
                        + (box.badge.isEmpty ? 0 : CockpitLayout.textWidth(box.badge, size: CockpitLayout.badgeFont))
                    assert(used <= box.rect.width, "文字がセル幅を超えた: \(box.display) \(box.badge)")
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

    static func laysOutWithoutOverlap() {
        let c = Cockpit()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        for i in 0..<14 {
            c.apply(write("agent\(i % 3)", "/proj/src/dir\(i % 4)/File\(i)Name.swift", "e\(i)",
                          at: t0.addingTimeInterval(Double(i))))
        }
        let snap = c.snapshot(now: t0.addingTimeInterval(20))
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

    // MARK: 追記の追いかけ

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
        let snap = cockpit.snapshot(now: latest)
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
}
