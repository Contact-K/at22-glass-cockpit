import Foundation

/// 入っているスキルを探して見せる（Orca と同じく**変換はしない**。読む・見せる・置き場所を揃えるだけ）。
///
/// 探す場所: `~/.claude/skills`・`~/.agents/skills`（共有）・`~/.codex/skills`・`~/.grok/skills`・
/// リポジトリの `.claude/skills` / `.agents/skills`、それに Claude のプラグイン（`installed_plugins.json` の
/// 各 `installPath/skills` のうち、settings.json の `enabledPlugins` が true のもの）。
/// 入力欄からは claude / grok なら `/名前`、codex なら `$名前` として差し込む。
/// SwiftUI に依存しない（p0 で検査）
enum Skills {
    enum Source: String, Sendable {
        case claude, agents, codex, grok, plugin, repo

        var label: String {
            switch self {
            case .claude: "~/.claude/skills"
            case .agents: "~/.agents/skills（共有）"
            case .codex: "~/.codex/skills"
            case .grok: "~/.grok/skills"
            case .plugin: "プラグイン"
            case .repo: "リポジトリ"
            }
        }
    }

    struct Skill: Equatable, Sendable, Identifiable {
        let name: String
        let description: String
        let source: Source
        /// SKILL.md のある場所
        let path: String
        /// プラグイン名（プラグインのスキルだけ）
        var plugin = ""
        var id: String { source.rawValue + ":" + plugin + ":" + name }
    }

    /// 入っているスキル。置き場が違えば同じ名前も別に出す（見えるエージェントが違う）。同じ置き場の重複だけ除く
    static func discover(home: String = NSHomeDirectory(), repo: String? = nil) -> [Skill] {
        var out: [Skill] = []
        let dirs: [(String, Source)] = [
            (home + "/.claude/skills", .claude), (home + "/.agents/skills", .agents),
            (home + "/.codex/skills", .codex), (home + "/.grok/skills", .grok),
        ]
        for (dir, source) in dirs { out += scan(dir, source: source) }
        out += pluginSkills(home: home)
        if let repo {
            out += scan(repo + "/.claude/skills", source: .repo)
            out += scan(repo + "/.agents/skills", source: .repo)
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// その置き場の直下の `<名前>/SKILL.md`（シンボリックリンクも辿る）
    static func scan(_ dir: String, source: Source, plugin: String = "") -> [Skill] {
        let manager = FileManager.default
        let names = ((try? manager.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return names.compactMap { name in
            let skillFile = (dir as NSString).appendingPathComponent(name + "/SKILL.md")
            guard let text = try? String(contentsOfFile: skillFile, encoding: .utf8) else { return nil }
            let front = Memory.frontMatter(text)
            return Skill(name: front["name"].flatMap { $0.isEmpty ? nil : $0 } ?? name,
                         description: front["description"] ?? "", source: source,
                         path: (dir as NSString).appendingPathComponent(name), plugin: plugin)
        }
    }

    /// 有効な Claude のプラグインのスキル
    static func pluginSkills(home: String) -> [Skill] {
        let registry = home + "/.claude/plugins/installed_plugins.json"
        guard let data = FileManager.default.contents(atPath: registry),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let plugins = object["plugins"] as? [String: Any] else { return [] }
        let enabled = enabledPlugins(home: home)
        var out: [Skill] = []
        for (key, value) in plugins.sorted(by: { $0.key < $1.key }) where enabled[key] == true {
            let installs = value as? [[String: Any]] ?? []
            guard let path = installs.compactMap({ $0["installPath"] as? String }).last else { continue }
            out += scan(path + "/skills", source: .plugin, plugin: String(key.prefix { $0 != "@" }))
        }
        return out
    }

    private static func enabledPlugins(home: String) -> [String: Bool] {
        var merged: [String: Bool] = [:]
        for file in ["/.claude/settings.json", "/.claude/settings.local.json"] {
            guard let data = FileManager.default.contents(atPath: home + file),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let map = object["enabledPlugins"] as? [String: Bool] else { continue }
            merged.merge(map) { _, new in new }
        }
        return merged
    }

    /// そのエージェントから見えるスキル（Orca の isNativeChatSkillForAgent と同じ考え方）
    static func visible(_ skills: [Skill], to backend: Backend) -> [Skill] {
        skills.filter { s in
            switch backend {
            case .claude: [.claude, .plugin, .repo].contains(s.source)
            case .codex: [.agents, .codex].contains(s.source)
            case .grok: [.agents, .grok].contains(s.source)
            case .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi, .openclaw: false
            }
        }
    }

    /// 入力欄に差し込む呼び名
    static func invocation(_ skill: Skill, for backend: Backend) -> String {
        (backend == .codex ? "$" : "/") + skill.name
    }

    /// ほかのエージェントにも見せる: `~/.agents/skills/<名前>`（codex が読む）と `~/.grok/skills/<名前>` に
    /// リンクを張る。既にあれば触らない。**人が押した時だけ書く**
    static func share(_ skill: Skill, home: String = NSHomeDirectory()) throws -> [String] {
        let manager = FileManager.default
        var made: [String] = []
        for dir in [home + "/.agents/skills", home + "/.grok/skills"] {
            let link = (dir as NSString).appendingPathComponent((skill.path as NSString).lastPathComponent)
            guard (try? manager.destinationOfSymbolicLink(atPath: link)) == nil, !manager.fileExists(atPath: link) else { continue }
            try manager.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try manager.createSymbolicLink(atPath: link, withDestinationPath: skill.path)
            made.append(link)
        }
        return made
    }
}
