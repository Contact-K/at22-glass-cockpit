import Foundation

// MARK: - リモート（SSH）

/// SSH の先のマシンでエージェントを動かす。作業場所を `ssh://<相手>/<パス>` と書くと、
/// `Launcher.spawn` が手元のコマンドの代わりに `ssh <相手> -- <ログインシェル> -lc 'cd <パス> && <コマンド>'` を起こす。
/// stdio はそのまま繋がるので、stream-json も ACP もほかと同じ配管で話せる。
///
/// ponytail: 相手のマシンの transcript・記憶DB・門（`memory/gate`）は読めない。会話は stdout から、
/// 門の段は手元の値を相手に渡さない（相手の claude は相手の `~/.claude` を見る）。要れば相手に AT22 の門を入れる
enum Remote {
    struct Host: Codable, Identifiable, Equatable {
        var id = UUID()
        /// 表示名
        var name: String
        /// `ssh` に渡す相手（`user@host` や `~/.ssh/config` の Host 名）
        var target: String
        /// 相手のマシンの作業フォルダ（絶対パス）
        var path: String

        /// 作業場所としての書き方
        var workspace: String { Remote.workspace(target: target, path: path) }
    }

    static let hostsKey = "remoteHosts"
    static let scheme = "ssh://"

    static func workspace(target: String, path: String) -> String {
        scheme + target + (path.hasPrefix("/") ? path : "/" + path)
    }

    nonisolated static func isRemote(_ cwd: String) -> Bool { cwd.hasPrefix(scheme) }

    /// `ssh://user@host/abs/path` → (相手, パス)
    nonisolated static func parse(_ cwd: String) -> (target: String, path: String)? {
        guard isRemote(cwd) else { return nil }
        let rest = cwd.dropFirst(scheme.count)
        guard let slash = rest.firstIndex(of: "/") else { return (String(rest), "~") }
        let target = String(rest[..<slash])
        guard !target.isEmpty else { return nil }
        return (target, String(rest[slash...]))
    }

    /// シェルの1語として安全に引用する
    nonisolated static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// 相手のマシンで走らせる ssh の引数。コマンドは相手の PATH で引くので名前だけ渡す。
    /// 相手のログインシェルを通す——素の ssh のシェルには `~/.local/bin` などが入っていない
    nonisolated static func sshArguments(target: String, path: String, command: String, arguments: [String],
                                         environment: [String: String]) -> [String] {
        let env = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\(quote($0.value))" }.joined(separator: " ")
        let cd = path == "~" ? "cd" : "cd \(quote(path))"
        let inner = "\(cd) && exec \(env.isEmpty ? "" : "env \(env) ")\(([command] + arguments).map(quote).joined(separator: " "))"
        return ["-T", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=30", target, "--",
                "exec \"${SHELL:-/bin/sh}\" -lc \(quote(inner))"]
    }

    @MainActor static var hosts: [Host] {
        get {
            guard let data = UserDefaults.standard.data(forKey: hostsKey),
                  let list = try? JSONDecoder().decode([Host].self, from: data) else { return [] }
            return list
        }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: hostsKey) } }
    }
}

// MARK: - 起こし方の上書き（Orca の Args / Env）

/// コマンド名ごとに、前に足す引数と足す環境変数。設定の Link で書く。
/// claude / codex / ACP のどれも `Launcher.spawn` を通るので、ここ1か所で効く
enum LaunchOverrides {
    static func argsKey(_ command: String) -> String { "agentArgs." + command }
    static func envKey(_ command: String) -> String { "agentEnv." + command }

    /// 引数は空白で区切る。ponytail: 引用符は解さない（空白を含む値は環境変数で渡す）
    nonisolated static func arguments(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// 環境変数は `K=V` を `;` か改行で区切る
    nonisolated static func environment(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for item in raw.split(whereSeparator: { $0 == ";" || $0.isNewline }) {
            let parts = item.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { out[key] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
        }
        return out
    }

    nonisolated static func current(for command: String) -> (arguments: [String], environment: [String: String]) {
        let d = UserDefaults.standard
        return (arguments(d.string(forKey: argsKey(command)) ?? ""), environment(d.string(forKey: envKey(command)) ?? ""))
    }
}
