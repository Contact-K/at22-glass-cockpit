import Foundation

/// 接続の通し: 手元に入っている claude（haiku）・grok・hermes を使い捨てのリポジトリで本当に起こし、
/// 「OK とだけ返して」が往復するか（起きる → 発言が届く → ターンが終わる）を見る。
/// claude はもう1つ、気にかけてる（acceptEdits）で `rm` を頼み、承認が AT22 に届くか（勝手に通らないか）を見る。
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

        // acceptEdits で rm が AT22 まで来るか
        if cockpit.found[.claude] != nil,
           let id = cockpit.launch(prompt: "Bash で `rm probe.txt` を実行して、終わったら「消した」とだけ返事してください。",
                                   cwd: repo, backend: .claude, model: "haiku", level: .normal)?.uuidString.lowercased() {
            let asked = await wait(id, seconds: 120) {
                cockpit.approvals.contains { $0.session == id } || !fm.fileExists(atPath: repo + "/probe.txt")
            }
            let approval = cockpit.approvals.first { $0.session == id }
            if let approval { _ = cockpit.answer(approval, allow: false, input: nil) }
            let note = approval.map { "承認が届いた: \($0.tool) \($0.detail.prefix(40))" }
                ?? (fm.fileExists(atPath: repo + "/probe.txt") ? "時間切れ" : "承認なしで消えた（acceptEdits が通した）")
            results.append(("claude rm（気にかけてる）", asked && approval != nil, note))
            _ = await wait(id, seconds: 60) { !cockpit.isWorking(id) }
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
