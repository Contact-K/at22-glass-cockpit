import Foundation

/// 接続の通し: 手元に入っている claude（haiku）・grok・hermes を使い捨てのリポジトリで本当に起こし、
/// 「OK とだけ返して」が往復するか（起きる → 発言が届く → ターンが終わる）を見る。
/// claude は段の通しも見る（気にかけてるの rm は訊く・書き込みは猶予の後に通る、留守番の rm は要判断に積む）。
/// 料金がかかるので p0 には入れない。組み方は hydra-check と同じ（p0-selfcheck.swift の代わりにこれを並べる）
@main
struct AgentsCheck {
    @MainActor static func main() async {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: "/tmp").appendingPathComponent("at22-agents-\(UUID().uuidString.prefix(6).lowercased())")
        let repo = base.appendingPathComponent("repo").path
        try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        func sh(_ cmd: String) { _ = try? Worktree.run("/bin/zsh", ["-lc", cmd], in: repo, withErrors: true) }
        sh("git init -q -b main && git config user.email t@t && git config user.name t && echo '# agents test' > README.md && echo probe > probe.txt && git add -A && git commit -qm init")
        print("repo:", repo)

        UserDefaults.standard.set(true, forKey: Cockpit.launcherEnabledKey)
        let cockpit = Cockpit()
        cockpit.findCLIs(force: true)
        let wanted: [Backend] = [.claude, .grok, .hermes]
        for _ in 0..<60 where wanted.contains(where: { cockpit.found[$0] == nil }) { try? await Task.sleep(for: .milliseconds(500)) }
        let watcher = TranscriptWatcher()
        watcher.onEvents = { cockpit.apply($0) }
        watcher.start()

        var results: [(String, Bool, String)] = []

        func wait(_ session: String, seconds: Double, until done: () -> Bool) async -> Bool {
            let start = Date()
            while Date().timeIntervalSince(start) < seconds {
                cockpit.housekeeping()
                if done() { return true }
                try? await Task.sleep(for: .milliseconds(500))
            }
            return false
        }

        for backend in wanted {
            guard cockpit.found[backend] != nil else { results.append((backend.title, false, "見つからない")); continue }
            let errorBefore = cockpit.launchError
            let start = Date()
            guard let id = cockpit.launch(prompt: "これは AT22 の接続確認です。道具は使わず「OK」とだけ返事してください。",
                                          cwd: repo, backend: backend, model: backend == .claude ? "haiku" : "",
                                          level: .normal)?.uuidString.lowercased() else {
                results.append((backend.title, false, "起こせない: \(cockpit.launchError ?? "")")); continue
            }
            let replied = await wait(id, seconds: 150) {
                cockpit.messages.contains { $0.session == id && $0.speaker == .model && !$0.thinking }
                    && !cockpit.isWorking(id)
            }
            let reply = cockpit.messages.last { $0.session == id && $0.speaker == .model && !$0.thinking }?.text ?? "-"
            let error = cockpit.launchError != errorBefore ? cockpit.launchError ?? "" : ""
            results.append((backend.title, replied && error.isEmpty,
                            String(format: "%.1fs 返事=%@ %@", Date().timeIntervalSince(start), String(reply.prefix(40)), error)))
        }

        // 段の通し（claude）: 承認を AT22 が段で決めているか
        func scenario(_ name: String, level: Gate.Level, prompt: String, seconds: Double = 120,
                      check: @escaping (String) -> (done: Bool, ok: Bool, note: String)) async {
            guard cockpit.found[.claude] != nil else { return }
            cockpit.setGateLevel(level, cwd: repo)
            guard let id = cockpit.launch(prompt: prompt, cwd: repo, backend: .claude, model: "haiku",
                                          level: level)?.uuidString.lowercased() else {
                results.append((name, false, "起こせない")); return
            }
            _ = await wait(id, seconds: seconds) { check(id).done }
            let r = check(id)
            results.append((name, r.ok, r.note))
            // 片付け: 残った承認は断り、ターンの終わりを待つ
            for a in cockpit.approvals where a.session == id { _ = cockpit.answer(a, allow: false, input: nil) }
            _ = await wait(id, seconds: 60) { !cockpit.isWorking(id) }
        }
        let probe = repo + "/probe.txt", hello = repo + "/hello.txt"

        // 気にかけてる: rm は高 → 人に訊く（勝手に消さない）
        await scenario("段 Lv.2 rm は訊く", level: .normal,
                       prompt: "Bash で `rm probe.txt` を実行して、終わったら「消した」とだけ返事してください。") { id in
            let a = cockpit.approvals.first { $0.session == id }
            let gone = !fm.fileExists(atPath: probe)
            return (a != nil || gone, a != nil && a?.autoAt == nil && !gone,
                    a.map { "承認が届いた（猶予なし）: \($0.tool)" } ?? (gone ? "承認なしで消えた" : "時間切れ"))
        }
        // 気にかけてる: worktree の中の書き込みは低 → 猶予の後に AT22 が通す
        await scenario("段 Lv.2 書き込みは猶予の後に通る", level: .normal,
                       prompt: "Write ツールで hello.txt に hello と1行だけ書いて、書いたら「できた」とだけ返事してください。", seconds: 150) { id in
            let wrote = fm.fileExists(atPath: hello)
            let graced = cockpit.activity.contains { $0.session == id && $0.text.hasPrefix("猶予の後に通した") }
            return (wrote, wrote && graced, wrote ? (graced ? "猶予の後に通って書けた" : "猶予を通らずに書けた") : "時間切れ")
        }
        // 留守番: rm は高 → 要判断に積んで断る（消さない・止まらない）
        await scenario("段 Lv.4 rm は要判断に積む", level: .unattended,
                       prompt: "Bash で `rm probe.txt` を実行してください。断られたら「飛ばした」とだけ返事してください。", seconds: 150) { id in
            let queued = cockpit.deferred.contains { $0.session == id }
            let gone = !fm.fileExists(atPath: probe)
            let ended = queued && !cockpit.isWorking(id)
            return (ended || gone, queued && !gone && ended,
                    gone ? "消えた" : queued ? (ended ? "要判断に積まれ、相手はターンを終えた" : "積まれたがターンが終わらない") : "時間切れ")
        }

        print("")
        for (name, ok, note) in results { print(ok ? "PASS" : "FAIL", name, "—", note) }

        // 片付け: 使い捨てのリポジトリ、その transcript・記憶の置き場、このプログラムの defaults
        let slugs = [base.path, base.resolvingSymlinksInPath().path, "/private" + base.path].map(Cockpit.projectSlug)
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        for name in (try? fm.contentsOfDirectory(atPath: projects.path)) ?? [] where slugs.contains(where: name.hasPrefix) {
            try? fm.removeItem(at: projects.appendingPathComponent(name))
        }
        try? fm.removeItem(at: base)
        UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        exit(results.allSatisfy(\.1) ? 0 : 1)
    }
}
