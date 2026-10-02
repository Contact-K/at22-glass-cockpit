import Foundation

// MARK: - AI バックエンド選択

/// Claude と Codex を切り替える。AT22 が打ち上げるセッションの身元を定める。
enum Backend: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    /// Grok Build。`grok agent stdio` を ACP（Agent Client Protocol）で話す
    case grok
    /// Hermes Agent（Nous Research）。`hermes acp`。プロバイダとモデルは Hermes 自身の設定に従う
    case hermes

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .hermes: "Hermes"
        }
    }

    /// ACP で話す相手。Gemini CLI（`--experimental-acp`）や OpenCode（`acp`）も同じ口なので、
    /// 入れたらここと `Cockpit.acpArguments` に1行ずつ足せば繋がる
    var isACP: Bool { self == .grok || self == .hermes }

    /// ログインを起こすコマンド（CLI の後ろに付ける）。**トークンは各 CLI が持つ**——AT22 は起こすだけ
    var loginArguments: [String] {
        switch self {
        case .claude: ["auth", "login"]
        case .codex: ["login"]
        case .grok: ["login"]
        case .hermes: ["setup"]
        }
    }

    /// 探す時のコマンド名。ログインシェルの `-c` に埋め込むので、ここに書いた名前だけを使う
    var command: String { rawValue }
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

    /// Grok の既成モデル。id はそのまま `grok agent -m` に渡る（`session/new` の configOptions で実測）
    static let grokModels = [
        ModelChoice(backend: .grok, id: "grok-4.7", title: "Grok 4.7"),
        ModelChoice(backend: .grok, id: "grok-4.7-build-fast", title: "Grok 4.7 Fast"),
        ModelChoice(backend: .grok, id: "grok-4.6", title: "Grok 4.6"),
    ]

    static func models(for backend: Backend) -> [ModelChoice] {
        switch backend {
        case .claude: claudeModels
        case .codex: codexModels
        case .grok: grokModels
        case .hermes: []        // Hermes 自身の既定（hermes model で選ぶ）
        }
    }

    /// UIが入力させたカスタムモデル。backend と id で作る
    nonisolated static func custom(backend: Backend, id: String) -> ModelChoice {
        ModelChoice(backend: backend, id: id, title: id)
    }
}
