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
    // ここから下は ACP で話す CLI。起こし方は ACP の registry（agentclientprotocol/registry の agent.json）の実物。
    // モデル・ログインはどれも CLI 自身の設定に従う
    case gemini     // `gemini --acp`
    case qwen       // `qwen --acp`
    case goose      // `goose acp`
    case opencode   // `opencode acp`
    case copilot    // `copilot --acp`
    case kimi       // `kimi acp`

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .hermes: "Hermes"
        case .gemini: "Gemini"
        case .qwen: "Qwen Code"
        case .goose: "Goose"
        case .opencode: "OpenCode"
        case .copilot: "Copilot"
        case .kimi: "Kimi"
        }
    }

    /// ACP で話す相手。Gemini CLI（`--experimental-acp`）や OpenCode（`acp`）も同じ口なので、
    /// 入れたらここと `Cockpit.acpArguments` に1行ずつ足せば繋がる
    var isACP: Bool { self != .claude && self != .codex }

    /// ログインを起こすコマンド（CLI の後ろに付ける）。**トークンは各 CLI が持つ**——AT22 は起こすだけ
    var loginArguments: [String] {
        switch self {
        case .claude: ["auth", "login"]
        case .codex: ["login"]
        case .grok: ["login"]
        case .hermes: ["setup"]
        case .opencode: ["auth", "login"]
        case .goose: ["configure"]
        // CLI を開けば中でログインを訊いてくる
        case .gemini, .qwen, .copilot, .kimi: []
        }
    }

    /// 探す時のコマンド名。ログインシェルの `-c` に埋め込むので、ここに書いた名前だけを使う
    var command: String { rawValue }

    /// 初めからある4つ。ほかは設定の Link で「足す」まで選ぶ口に出さない
    static let builtIn: [Backend] = [.claude, .codex, .grok, .hermes]

    /// 入れ方と使い方の案内（設定の Docs / Install）。Orca と同じく、AT22 はインストールを走らせない
    var homepage: URL {
        switch self {
        case .claude: URL(string: "https://code.claude.com/docs/en/setup")!
        case .codex: URL(string: "https://github.com/openai/codex")!
        case .grok: URL(string: "https://docs.x.ai")!
        case .hermes: URL(string: "https://github.com/nousresearch/hermes-agent")!
        case .gemini: URL(string: "https://github.com/google-gemini/gemini-cli")!
        case .qwen: URL(string: "https://github.com/QwenLM/qwen-code")!
        case .goose: URL(string: "https://github.com/block/goose")!
        case .opencode: URL(string: "https://opencode.ai/docs/cli/")!
        case .copilot: URL(string: "https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli")!
        case .kimi: URL(string: "https://github.com/MoonshotAI/kimi-cli")!
        }
    }

    /// ログインが対話式（質問に答えながら進む）か。対話式は裏で起こせないので Terminal で開く
    var loginIsInteractive: Bool { ![.claude, .codex, .grok].contains(self) }

    /// 無効にしたエージェント（設定の Agents で切る）。選ぶ口に出さない。値は rawValue をカンマで
    static let disabledKey = "disabledAgents"

    /// 足したプロバイダ（初めからある4つ以外）。値は rawValue をカンマで
    static let addedKey = "addedAgents"

    /// 選ぶ口に出すもの: 初めからある4つ＋足したもの、から無効にしたものを除く
    static func enabled(disabled raw: String, added: String = UserDefaults.standard.string(forKey: addedKey) ?? "") -> [Backend] {
        let off = Set(raw.split(separator: ",").map(String.init))
        let on = Set(added.split(separator: ",").map(String.init))
        return allCases.filter { (builtIn.contains($0) || on.contains($0.rawValue)) && !off.contains($0.rawValue) }
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
        case .hermes, .gemini, .qwen, .goose, .opencode, .copilot, .kimi: []   // 各 CLI 自身の既定
        }
    }

    /// UIが入力させたカスタムモデル。backend と id で作る
    nonisolated static func custom(backend: Backend, id: String) -> ModelChoice {
        ModelChoice(backend: backend, id: id, title: id)
    }
}
