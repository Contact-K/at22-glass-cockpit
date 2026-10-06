import Foundation

/// Hydra の通し: 本物の claude（haiku）を司令塔にし、```hydra の囲み → 門（Lv.3 で自動許可）→ worktree → head を起こす →
/// 最初の報告が司令塔へ返る → 頭の枝が司令塔の worktree に取り込まれる、まで。AT22 と同じ部品（Cockpit・TranscriptWatcher）を画面なしで回す
@main
struct HydraCheck {
    @MainActor static func main() async {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: "/tmp").appendingPathComponent("at22-hydra-\(UUID().uuidString.prefix(6).lowercased())")
        let repo = base.appendingPathComponent("repo").path
        try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        func sh(_ cmd: String) { _ = try? Worktree.run("/bin/zsh", ["-lc", cmd], in: repo, withErrors: true) }
        sh("git init -q -b main && git config user.email t@t && git config user.name t && echo '# hydra test' > README.md && git add -A && git commit -qm init")
        print("repo:", repo)

        UserDefaults.standard.set(true, forKey: Cockpit.launcherEnabledKey)
        let cockpit = Cockpit()
        cockpit.findCLIs(force: false)
        for _ in 0..<40 where cockpit.claude == nil { try? await Task.sleep(for: .milliseconds(500)) }
        guard cockpit.claude != nil else { print("FAIL: claude が見つからない"); return }
        cockpit.setGateLevel(.auto, cwd: repo)

        let watcher = TranscriptWatcher()
        watcher.onEvents = { cockpit.apply($0) }
        watcher.start()

        let prompt = """
        これは AT22 の Hydra の動作確認です。自分ではファイルを触らず、道具も使わず、返事の最後に次の囲みをそのまま書いて終えてください。
        ```hydra
        [{"name":"hello","agent":"claude","model":"haiku","task":"hello.txt を作る","prompt":"hello.txt というファイルに hello と1行だけ書いてください。書いたら『できた』とだけ返事してください。"}]
        ```
        """
        guard let lead = cockpit.launch(prompt: prompt, cwd: repo, backend: .claude, model: "haiku", level: .auto)?
            .uuidString.lowercased() else { print("FAIL: 司令塔を起こせない:", cockpit.launchError ?? ""); return }
        print("lead:", lead)

        let start = Date()
        var seen: Set<String> = []
        func step(_ key: String, _ text: String) { if seen.insert(key).inserted { print(String(format: "%5.1fs", Date().timeIntervalSince(start)), text) } }
        var ok = false
        while Date().timeIntervalSince(start) < 150 {
            cockpit.housekeeping()
            let leadSaid = cockpit.messages.filter { $0.session == lead }
            if leadSaid.contains(where: { $0.speaker == .model && $0.text.contains("```hydra") }) { step("block", "司令塔が ```hydra を書いた") }
            let worktrees = (try? fm.contentsOfDirectory(atPath: repo + "/.claude/worktrees")) ?? []
            if !worktrees.isEmpty { step("wt", "worktree ができた: \(worktrees)") }
            if let wt = worktrees.first, fm.fileExists(atPath: repo + "/.claude/worktrees/\(wt)/hello.txt") {
                step("file", "head が hello.txt を書いた")
            }
            let heads = cockpit.liveSessions.filter { $0.id != lead }
            if !heads.isEmpty { step("head", "head のセッション: \(heads.map(\.id))") }
            if let report = leadSaid.first(where: { $0.speaker == .human && $0.text.hasPrefix("[Hydra] head") }) {
                step("report", "報告が司令塔に届いた:\n" + report.text.prefix(400))
            }
            // Lv.3 なので、全員の報告が揃ったら AT22 が頭の枝を司令塔の worktree（ここでは本体）に取り込む
            if let land = leadSaid.first(where: { $0.speaker == .human && $0.text.contains("全員の報告が揃った") }) {
                step("land", "取り込みの結果が司令塔に届いた:\n" + land.text.prefix(400))
                if fm.fileExists(atPath: repo + "/hello.txt") { step("landed", "本体に hello.txt が入った"); ok = true; break }
            }
            if let e = cockpit.launchError, !e.isEmpty { step("err:" + e, "launchError: " + e) }
            let gateDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects/\(Cockpit.projectSlug(repo))/memory/gate").path
            let gateFiles = ((try? fm.contentsOfDirectory(atPath: gateDir)) ?? []).sorted()
            step("gates:" + gateFiles.joined(separator: ","), "gate/: \(gateFiles)")
            for h in cockpit.liveSessions where h.cwd.contains("/.claude/worktrees/") {
                let said = cockpit.messages.filter { $0.session == h.id }
                step("h:\(h.id):\(cockpit.isWorking(h.id)):\(said.count)",
                     "head \(h.id.prefix(8)) working=\(cockpit.isWorking(h.id)) messages=\(said.count) last=\(said.last.map { "\($0.speaker) " + $0.text.prefix(60) } ?? "-")")
            }
            step("leadw:\(cockpit.isWorking(lead))", "lead working=\(cockpit.isWorking(lead)) canSend=\(cockpit.canSend(to: lead))")
            try? await Task.sleep(for: .seconds(1))
        }
        print(ok ? "PASS" : "FAIL: 時間切れ")
        let gateDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects/\(Cockpit.projectSlug(repo))/memory/gate").path
        for f in ((try? fm.contentsOfDirectory(atPath: gateDir)) ?? []).sorted() {
            print("---- " + f); print((try? String(contentsOfFile: gateDir + "/" + f, encoding: .utf8)) ?? "")
        }
        // 片付け: 使い捨てのリポジトリと、その記憶・transcript の置き場
        // claude は /tmp を実体の /private/tmp で記録するので、両方の名前で片付ける
        let slugs = [base.path, base.resolvingSymlinksInPath().path, "/private" + base.path].map(Cockpit.projectSlug)
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        for name in (try? fm.contentsOfDirectory(atPath: projects.path)) ?? [] where slugs.contains(where: name.hasPrefix) {
            try? fm.removeItem(at: projects.appendingPathComponent(name))
        }
        try? fm.removeItem(at: base)
        UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        exit(ok ? 0 : 1)
    }
}
