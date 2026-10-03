import Foundation

// MARK: - リモート（SSH）

/// SSH の先のマシンでエージェントを動かす。作業場所を `ssh://<相手>/<パス>` と書くと、
/// `Launcher.spawn` が手元のコマンドの代わりに `ssh <相手> -- <ログインシェル> -lc 'cd <パス> && <コマンド>'` を起こす。
/// stdio はそのまま繋がるので、stream-json も ACP もほかと同じ配管で話せる。
///
/// ponytail: 相手のマシンの transcript・記憶DB・門（`memory/gate`）は読めない。会話は stdout から、
/// 門の段は手元の値を相手に渡さない（相手の claude は相手の `~/.claude` を見る）。要れば相手に AT22 の門を入れる
enum Remote {
    /// どう繋ぐか。VPN（WireGuard など）は繋がっていれば素の ssh で届くので、選ぶのは2つだけ
    enum Via: String, Codable, CaseIterable {
        /// 素の ssh（鍵は ~/.ssh に任せる）。踏み台やポートは `options` に書く（-J bastion / -p 2222）
        case ssh
        /// Tailscale SSH。鍵を置かずに、Tailscale のログインで入る（相手で `tailscale up --ssh` が要る）
        case tailscale

        var title: String { self == .ssh ? "SSH" : "Tailscale" }
    }

    struct Host: Codable, Identifiable, Equatable {
        var id = UUID()
        /// 表示名
        var name: String
        /// 相手（`user@host`・`~/.ssh/config` の Host 名・Tailscale のマシン名）
        var target: String
        /// 相手のマシンの作業フォルダ（絶対パス）
        var path: String
        /// 前の版の保存には無いので Optional（無ければ ssh）
        var via: Via?
        /// ssh に足すオプション（例 `-J bastion -p 2222`）。Tailscale では使わない
        var options: String?

        /// 作業場所としての書き方
        var workspace: String { Remote.workspace(target: target, path: path, via: via ?? .ssh, options: options ?? "") }
    }

    struct Place: Equatable {
        var target: String
        var path: String
        var via: Via = .ssh
        var options = ""
    }

    static let hostsKey = "remoteHosts"
    static let scheme = "ssh://"

    /// `ssh://相手/パス`。経由とオプションは `?via=tailscale&opt=…` に載せる（作業場所の文字列1本で起こせるように）
    nonisolated static func workspace(target: String, path: String, via: Via = .ssh, options: String = "") -> String {
        var out = scheme + target + (path.hasPrefix("/") ? path : "/" + path)
        var query: [URLQueryItem] = []
        if via != .ssh { query.append(.init(name: "via", value: via.rawValue)) }
        if !options.trimmingCharacters(in: .whitespaces).isEmpty { query.append(.init(name: "opt", value: options)) }
        if !query.isEmpty {
            var c = URLComponents()
            c.queryItems = query
            out += "?" + (c.percentEncodedQuery ?? "")
        }
        return out
    }

    nonisolated static func isRemote(_ cwd: String) -> Bool { cwd.hasPrefix(scheme) }

    /// `ssh://user@host/abs/path?via=…&opt=…` → 相手・パス・経由・オプション
    nonisolated static func parse(_ cwd: String) -> Place? {
        guard isRemote(cwd) else { return nil }
        let body = cwd.dropFirst(scheme.count)
        let (head, query) = body.firstIndex(of: "?").map { (body[..<$0], String(body[body.index(after: $0)...])) } ?? (body, "")
        var c = URLComponents()
        c.percentEncodedQuery = query
        let items = c.queryItems ?? []
        let via = items.first { $0.name == "via" }?.value.flatMap(Via.init(rawValue:)) ?? .ssh
        let options = items.first { $0.name == "opt" }?.value ?? ""
        guard let slash = head.firstIndex(of: "/") else {
            return head.isEmpty ? nil : Place(target: String(head), path: "~", via: via, options: options)
        }
        let target = String(head[..<slash])
        guard !target.isEmpty else { return nil }
        return Place(target: target, path: String(head[slash...]), via: via, options: options)
    }

    /// シェルの1語として安全に引用する
    nonisolated static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// 相手のマシンで走らせるコマンド（相手のログインシェルを通す——素のシェルには `~/.local/bin` などが入っていない）
    nonisolated static func remoteCommand(path: String, command: String, arguments: [String], environment: [String: String]) -> String {
        let env = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\(quote($0.value))" }.joined(separator: " ")
        let cd = path == "~" ? "cd" : "cd \(quote(path))"
        let inner = "\(cd) && exec \(env.isEmpty ? "" : "env \(env) ")\(([command] + arguments).map(quote).joined(separator: " "))"
        return "exec \"${SHELL:-/bin/sh}\" -lc \(quote(inner))"
    }

    /// 手元で起こすもの（実行ファイルと引数）。ssh は直に、Tailscale は手元のログインシェル越しに `tailscale ssh`
    nonisolated static func local(_ place: Place, command: String, arguments: [String],
                                  environment: [String: String]) -> (executable: URL, arguments: [String]) {
        let remote = remoteCommand(path: place.path, command: command, arguments: arguments, environment: environment)
        switch place.via {
        case .ssh:
            let options = place.options.split(whereSeparator: \.isWhitespace).map(String.init)
            return (URL(fileURLWithPath: "/usr/bin/ssh"),
                    ["-T", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=30"] + options + [place.target, "--", remote])
        case .tailscale:
            return (URL(fileURLWithPath: "/bin/zsh"),
                    ["-lc", "exec \(quote(tailscaleBinary)) ssh \(quote(place.target)) \(quote(remote))"])
        }
    }

    /// Tailscale の CLI。Mac App Store 版・公式アプリ版はアプリの中、brew 版は PATH の tailscale
    nonisolated static var tailscaleBinary: String {
        let app = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        return FileManager.default.isExecutableFile(atPath: app) ? app : "tailscale"
    }

    /// Tailscale の相手の一覧（`tailscale status --json` の Peer）。MagicDNS の名前、無ければホスト名
    nonisolated static func tailscalePeers() -> Result<[(name: String, online: Bool, os: String)], Error> {
        Result {
            let out = try Worktree.run("/bin/zsh", ["-lc", "\(quote(tailscaleBinary)) status --json"], in: NSHomeDirectory(), withErrors: true)
            guard let object = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] else {
                throw Worktree.Failure(message: out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return Self.peers(object)
        }
    }

    nonisolated static func peers(_ status: [String: Any]) -> [(name: String, online: Bool, os: String)] {
        ((status["Peer"] as? [String: Any]) ?? [:]).values.compactMap { value in
            guard let p = value as? [String: Any] else { return nil }
            let dns = (p["DNSName"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let name = dns.isEmpty ? (p["HostName"] as? String ?? "") : dns
            return name.isEmpty ? nil : (name, p["Online"] as? Bool ?? false, p["OS"] as? String ?? "")
        }
        .sorted { ($0.online ? 0 : 1, $0.name) < ($1.online ? 0 : 1, $1.name) }
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
