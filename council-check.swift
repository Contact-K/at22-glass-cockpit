import Foundation

/// 合議の通し: 本物の claude（haiku）を司令塔にし、```council → 門（Lv.3 で自動許可）→ 読むだけの席（codex・grok・claude のうち
/// 入っているもの）が意見 → 反論 → 司令塔へまとめの依頼が届く、まで。席がファイルを書かないこと・司令塔の段が変わらないことも見る。
/// 料金がかかる（席は各 CLI の既定のモデル）。組み方は README の p0 と同じ Sources に Council.swift を足し、p0-selfcheck の代わりにこれ
@main
struct CouncilCheck {
    @MainActor static func main() async {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: "/tmp").appendingPathComponent("at22-council-\(UUID().uuidString.prefix(6).lowercased())")
        let repo = base.appendingPathComponent("repo").path
        try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        func sh(_ cmd: String) -> String { (try? Worktree.run("/bin/zsh", ["-lc", cmd], in: repo, withErrors: true)) ?? "" }
        _ = sh("git init -q -b main && git config user.email t@t && git config user.name t && printf 'func add(_ a: Int, _ b: Int) -> Int { a - b }\\n' > math.swift && git add -A && git commit -qm init")
        _ = sh("printf 'func add(_ a: Int, _ b: Int) -> Int { a - b }\\nfunc div(_ a: Int, _ b: Int) -> Int { a / b }\\n' > math.swift")
        print("repo:", repo)

        UserDefaults.standard.set(true, forKey: Cockpit.launcherEnabledKey)
        let cockpit = Cockpit()
        cockpit.findCLIs(force: false)
        for _ in 0..<40 where cockpit.claude == nil { try? await Task.sleep(for: .milliseconds(500)) }
        guard cockpit.claude != nil else { print("FAIL: claude が見つからない"); return }
        try? await Task.sleep(for: .seconds(3))
        print("found:", cockpit.found.keys.map(\.rawValue).sorted(), "→ 席:", Council.seats(found: Set(cockpit.found.keys)).map { "\($0.role)=\($0.agent.rawValue)" })
        cockpit.setGateLevel(.auto, cwd: repo)

        let watcher = TranscriptWatcher()
        watcher.onEvents = { cockpit.apply($0) }
        watcher.start()

        let prompt = """
        これは AT22 の合議の動作確認です。自分ではファイルを触らず、道具も使わず、返事の最後に次の囲みをそのまま書いて終えてください。
        ```council
        math.swift に div を足した。0 で割る所と add の中身を見てほしい
        ```
        """
        guard let lead = cockpit.launch(prompt: prompt, cwd: repo, backend: .claude, model: "haiku", level: .auto)?
            .uuidString.lowercased() else { print("FAIL: 司令塔を起こせない:", cockpit.launchError ?? ""); return }
        print("lead:", lead)

        let start = Date()
        var seen: Set<String> = []
        func step(_ key: String, _ text: String) { if seen.insert(key).inserted { print(String(format: "%5.1fs", Date().timeIntervalSince(start)), text) } }
        var ok = false
        while Date().timeIntervalSince(start) < 600 {
            cockpit.housekeeping()
            let leadSaid = cockpit.messages.filter { $0.session == lead }
            if leadSaid.contains(where: { $0.speaker == .model && $0.text.contains("```council") }) { step("block", "司令塔が ```council を書いた") }
            for s in cockpit.liveSessions where s.id != lead {
                let said = cockpit.messages.filter { $0.session == s.id }
                step("s:\(s.id):\(said.count)", "席 \(s.id.prefix(8)) \(cockpit.backend(of: s.id).rawValue) messages=\(said.count) last=\(said.last.map { "\($0.speaker) " + $0.text.prefix(80).replacingOccurrences(of: "\n", with: " ") } ?? "-")")
            }
            if let e = cockpit.launchError, !e.isEmpty { step("err:" + e, "launchError: " + e) }
            if let verdict = leadSaid.first(where: { $0.speaker == .human && $0.text.hasPrefix("[合議]") }) {
                step("verdict", "まとめの依頼が司令塔に届いた:\n" + verdict.text.prefix(1500))
                ok = true
                break
            }
            try? await Task.sleep(for: .seconds(1))
        }
        let level = cockpit.level(ofWorkspace: repo)
        let dirty = sh("git status --porcelain").split(separator: "\n").filter { !$0.hasSuffix("math.swift") }
        print("司令塔の段:", level.rawValue, level == .auto ? "（変わっていない）" : "← 変わった")
        print("席が書いたもの:", dirty.isEmpty ? "無し" : dirty.joined(separator: ", "))
        ok = ok && level == .auto && dirty.isEmpty
        print(ok ? "PASS" : "FAIL")
        // 片付け: 使い捨てのリポジトリと、その記憶・transcript の置き場（/tmp と /private/tmp の両方の名前で）
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
