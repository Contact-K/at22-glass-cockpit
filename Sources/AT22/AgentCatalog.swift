import Foundation

/// エージェントごとのモデルの一覧と、モデルごとのエフォートの段（Orca と同じ二層: 固定の初期一覧 → CLI から取れたら置き換え）。
///
/// - claude: `claude -p --input-format stream-json` に `control_request` の `list_models` を流す（**API のターンは起きない**）
/// - grok: `grok models` の出力
/// - codex: `codex app-server` の `model/list` があるが、手元に codex が無いので初期一覧のまま
///
/// SwiftUI に依存しない（p0 で検査）
enum AgentCatalog {
    struct Model: Equatable, Sendable, Identifiable {
        /// CLI に渡す値（`--model` / `-m`）
        let id: String
        let label: String
        let detail: String
        /// 選べるエフォートの段（低い順）。空ならエフォートを渡さない
        let efforts: [String]
        /// 固定の版（`claude-opus-4-8` など）。false は別名（`opus` は各マシンの最新に解決される）
        let pinned: Bool
        /// 別名の解決先（`opus` → `claude-opus-5-5`）。transcript に残るのはこちらの名前
        var resolved = ""

        /// 会話が実際に使っているモデル名（正式名のこともある）と同じものか
        func matches(_ name: String) -> Bool { !name.isEmpty && (id == name || resolved == name) }
    }

    static let claudeEfforts = ["low", "medium", "high", "xhigh", "max"]
    static let codexEfforts = ["minimal", "low", "medium", "high"]
    static let grokEfforts = ["low", "medium", "high", "xhigh"]

    /// 既定のエフォート（Orca と同じ: claude high / codex medium / grok high）
    static func defaultEffort(_ backend: Backend) -> String {
        switch backend {
        case .claude, .grok: "high"
        case .codex: "medium"
        case .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi: ""
        }
    }

    /// CLI から取れなかった時の一覧（2026-10 の手元の claude 2.1.288 / grok の実測から）
    static func seed(_ backend: Backend) -> [Model] {
        switch backend {
        case .claude:
            return [
                Model(id: "opus", label: "Opus", detail: "最新の Opus（いまは 5.5）", efforts: claudeEfforts, pinned: false),
                Model(id: "fable", label: "Fable", detail: "最新の Fable（いまは 5.1）", efforts: claudeEfforts, pinned: false),
                Model(id: "sonnet", label: "Sonnet", detail: "最新の Sonnet（いまは 5.5）", efforts: claudeEfforts, pinned: false),
                Model(id: "haiku", label: "Haiku", detail: "最新の Haiku（いまは 4.5）", efforts: [], pinned: false),
                Model(id: "claude-opus-5", label: "Opus 5", detail: "", efforts: claudeEfforts, pinned: true),
                Model(id: "claude-sonnet-5", label: "Sonnet 5", detail: "", efforts: claudeEfforts, pinned: true),
                Model(id: "claude-fable-5", label: "Fable 5", detail: "", efforts: claudeEfforts, pinned: true),
                Model(id: "claude-opus-4-8", label: "Opus 4.8", detail: "", efforts: claudeEfforts, pinned: true),
                Model(id: "claude-opus-4-6", label: "Opus 4.6", detail: "", efforts: ["low", "medium", "high", "max"], pinned: true),
            ]
        case .codex:
            return ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.2-codex"].map {
                Model(id: $0, label: $0, detail: "", efforts: codexEfforts, pinned: true)
            }
        case .grok:
            return ["grok-4.7", "grok-4.7-build-fast", "grok-4.6", "grok-4.5"].enumerated().map { i, id in
                Model(id: id, label: id, detail: i == 0 ? "既定" : "", efforts: grokEfforts, pinned: true)
            }
        case .hermes:
            return [Model(id: "", label: "既定", detail: "hermes model で選ぶ", efforts: [], pinned: false)]
        case .gemini, .qwen, .goose, .opencode, .copilot, .kimi:
            return [Model(id: "", label: "既定", detail: "\(backend.command) 自身の設定に従う", efforts: [], pinned: false)]
        }
    }

    /// `list_models` の応答（`response.models`）。`default` の行と使えない行は捨てる
    static func parseClaude(_ json: Data) -> [Model] {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [] }
        let response = (object["response"] as? [String: Any])?["response"] as? [String: Any] ?? object
        guard let models = response["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard let value = m["value"] as? String, value != "default", m["disabled"] as? Bool != true else { return nil }
            let efforts = (m["supportsEffort"] as? Bool == true) ? (m["supportedEffortLevels"] as? [String] ?? claudeEfforts) : []
            return Model(id: value, label: m["displayName"] as? String ?? value, detail: m["description"] as? String ?? "",
                         efforts: efforts, pinned: value.hasPrefix("claude-"), resolved: m["resolvedModel"] as? String ?? "")
        }
    }

    /// `grok models` の出力（`* grok-4.7 (default)` / `- grok-4.6`）
    static func parseGrok(_ text: String) -> [Model] {
        text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("* ") || t.hasPrefix("- ") else { return nil }
            let rest = t.dropFirst(2)
            let id = String(rest.prefix { !$0.isWhitespace })
            guard id.hasPrefix("grok") else { return nil }
            return Model(id: id, label: id, detail: rest.contains("(default)") ? "既定" : "", efforts: grokEfforts, pinned: true)
        }
    }

    /// 選んでいるモデルのエフォートの段。モデルが空（既定）なら一覧の先頭の段
    static func efforts(for model: String, in list: [Model]) -> [String] {
        (list.first { $0.matches(model) } ?? list.first)?.efforts ?? []
    }
}
