import Foundation

// MARK: - AI バックエンド選択

/// Claude と Codex を切り替える。AT22 が打ち上げるセッションの身元を定める。
enum Backend: String, CaseIterable, Sendable {
    case claude
    case codex

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex (OpenAI)"
        }
    }
}

/// 起動時のモデル選択肢。backend と id（CLI への渡し値）、表示用 title を持つ
struct ModelChoice: Identifiable, Hashable, Sendable {
    let backend: Backend
    let id: String
    let title: String
}

extension ModelChoice {
    /// Claude の既成モデル。id はそのまま `claude --model` に渡る
    static let claudeModels = [
        ModelChoice(backend: .claude, id: "opus", title: "Claude Opus"),
        ModelChoice(backend: .claude, id: "sonnet", title: "Claude Sonnet"),
        ModelChoice(backend: .claude, id: "haiku", title: "Claude Haiku"),
    ]

    /// Codex の既成モデル。id はそのまま `codex -m` に渡る
    static let codexModels = [
        ModelChoice(backend: .codex, id: "gpt-5.3-codex", title: "GPT-5.3 Codex"),
        ModelChoice(backend: .codex, id: "gpt-5.4", title: "GPT-5.4"),
    ]

    /// UIが入力させたカスタムモデル。backend と id で作る
    nonisolated static func custom(backend: Backend, id: String) -> ModelChoice {
        ModelChoice(backend: backend, id: id, title: id)
    }
}
