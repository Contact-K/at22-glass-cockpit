import SwiftUI
import AppKit

@main
struct AT22App: App {
    @State private var cockpit = Cockpit()
    @State private var watcher = TranscriptWatcher()

    init() {
        // 書体は何より先に登録する。`--shot` も同じ書体で焼かないと、実機と見え方が食い違う
        SumiFonts.register()

        // 見え方を画像に焼いて確かめる口。**画面を開かずに** PNG を1枚吐いて終わる。
        //
        //     swift run AT22 --shot /tmp/cockpit.png [幅 高さ] [--mode talk|files|spar|review|git|settings] [--tower]
        //                    [--transcript <path.jsonl>] [--gate] [--approval]
        //
        // 動き（墨流し・ドット・InkLoader）は時刻を固定した1コマしか写らない
        if let path = Self.shotPath() {
            Snapshot.write(to: path, size: Self.shotSize(), tab: Self.shotTab(),
                           tower: CommandLine.arguments.contains("--tower"),
                           transcript: Self.shotTranscript(),
                           gate: CommandLine.arguments.contains("--gate"),
                           approval: CommandLine.arguments.contains("--approval"),
                           workspaces: CommandLine.arguments.contains("--workspaces"),
                           menu: Self.argument("--menu"))
            exit(0)
        }
        // swift build が吐く素の実行ファイルは既定で accessory 扱いになり、Dock にも前面にも出ない。
        // ponytail: 開発中に `swift run` で直接動かすための1行。配布物はこれに頼っていない——
        // package.sh が Info.plist と .icns 入りの AT22.app を組むので、バンドル内では重複した無害な指定
        NSApplication.shared.setActivationPolicy(.regular)

        // **Sumi は白地に青インクの明るい面で固定する。** システムの外観に従わせると、
        // ダークモードの機械では設定画面・Picker・TextEditor・alert だけが暗くなり、白い五角形の上で浮く
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    private static func shotPath() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--shot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--mode` でどのタブを焼くか（既定は 01 TALK。v10 の work / structure / memory も受ける）
    private static func shotTab() -> V11Tab {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--mode"), i + 1 < args.count else { return .talk }
        return V11Tab(rawValue: args[i + 1]) ?? CockpitMode(rawValue: args[i + 1]).map(V11Tab.init) ?? .talk
    }

    private static func argument(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--transcript <path>` を足すと、その1本を流し込んだ状態で焼く
    private static func shotTranscript() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--transcript"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func shotSize() -> CGSize {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--shot"), i + 3 < args.count,
              let w = Double(args[i + 2]), let h = Double(args[i + 3]) else {
            return CGSize(width: 1440, height: 900)      // モックの実寸
        }
        return CGSize(width: w, height: h)
    }

    var body: some Scene {
        Window("AT22 Glass Cockpit", id: "cockpit") {
            CockpitView(cockpit: cockpit)
                .task {
                    watcher.onEvents = { [cockpit] events in cockpit.apply(events) }
                    watcher.start()
                    NSApp.activate(ignoringOtherApps: true)
                }
                // 下限は右の列（540）＋会話の欄（最小 380）＋左の余白（220）と、
                // ACTIONS と PLAN が重ならない高さ
                .frame(minWidth: 1200, minHeight: 760)
                // 窓の地を面と同じ白にする。`.hiddenTitleBar` で中身は上端まで届くが、
                // 窓自体の地が違う色だと信号機のまわりだけが抜ける
                .containerBackground(Palette.Light.bg, for: .window)
        }
        .defaultSize(width: 1440, height: 900)
        // 帯を自前で描くので、システムのタイトルバーは畳む。
        // **信号機だけは OS が同じ位置に描き続ける**ので、上帯は左端を 78pt 空けてある
        .windowStyle(.hiddenTitleBar)

        // ⌘, で開く。しきい値は環境と使い方で最適値が動くので、外から変えられるようにしておく
        Settings {
            ThresholdSettings(cockpit: cockpit)
        }
    }
}

private struct ThresholdSettings: View {
    let cockpit: Cockpit

    /// 上限は参照の点の数（Cockpit.maxReadTicks）に合わせる。
    /// ここを超えると点が埋まりきったまま増えず、「あと何回でフラグか」が読めなくなる
    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    /// 連携機能は既定オフ。**入れただけで LLM を起こすアプリにはしない**
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    /// CLI の場所を人が指定する口。空ならログインシェルに訊く
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""
    @AppStorage(Cockpit.grokPathKey) private var grokPath = ""
    /// 各 CLI のログインの状態。開いた時と、ログインを押して戻った時に読み直す
    @State private var logins: [Backend: String] = [:]
    @State private var loginProblem: String?

    var body: some View {
        Form {
            Section {
                Stepper("フラグを立てる参照回数: \(threshold)回",
                        value: $threshold, in: 2...Cockpit.maxReadTicks)
                note("同じエージェントがこの回数以上読み、一度も書いていないファイルに ⚑ を立てる。"
                     + "実 transcript 2478組の分布から既定は3回（当てはまるのは全体の1.4%）。")
            } header: { chapter("01", "表示") }

            Section {
                Toggle("セッションを起こす／続きを送る", isOn: $launcherEnabled)
                note("既定でオフなのは、AT22 が入れただけで LLM を起動するアプリにしないため。"
                     + "AT22 は API キーも OAuth トークンも保存せず、"
                     + "あなたが既にログイン済みの CLI（claude / codex / grok / hermes）を起こすだけで、"
                     + "通信はそのプロセスが行う。「ログイン」は各 CLI 自身のログインを Terminal で起こす。")

                // 見つかった場所を必ず出す。**以前は見つからない時しか何も出ず**、
                // 「探しに行ったのか」「見つけたのか」が画面から分からなかった
                ForEach(Backend.allCases, id: \.self) { backend in
                    agentRow(backend)
                }
                if let loginProblem {
                    Text(loginProblem).font(.system(size: 11)).foregroundStyle(Palette.Light.danger)
                }

                note("GUI アプリの `PATH` には `~/.local/bin` も `/opt/homebrew/bin` も無いので、"
                     + "通常はログインシェルを1回通して自動で見つける。"
                     + "見つからない環境だけ絶対パスを書く。")
            } header: { chapter("02", "連携") }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .task(id: cockpit.found.keys.sorted { $0.rawValue < $1.rawValue }) { await readLogins() }
    }

    /// 1つのエージェントの行。見つかった場所・ログインの状態・ログインの口・場所の手入力
    @ViewBuilder
    private func agentRow(_ backend: Backend) -> some View {
        found(backend.command, cockpit.found[backend]?.executable.path)
        if cockpit.found[backend] != nil {
            HStack(spacing: Palette.Space.s2) {
                Text(logins[backend] ?? "…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.Light.fg2)
                    .lineLimit(1)
                Spacer()
                Button("ログイン") {
                    loginProblem = cockpit.login(backend)
                    // Terminal で済ませて戻ってきた頃に読み直す
                    Task {
                        try? await Task.sleep(for: .seconds(20))
                        await readLogins()
                    }
                }
                .font(.system(size: 11))
                .help("\(backend.command) \((backend.loginArguments).joined(separator: " ")) を Terminal で開く")
            }
        }
        if let path = pathBinding(backend) {
            TextField("\(backend.command) の場所（空ならログインシェルに訊く）", text: path)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private func pathBinding(_ backend: Backend) -> Binding<String>? {
        switch backend {
        case .claude: $claudePath
        case .codex: $codexPath
        case .grok: $grokPath
        case .hermes: nil
        }
    }

    private func readLogins() async {
        for backend in Backend.allCases where cockpit.found[backend] != nil {
            logins[backend] = await cockpit.loginStatus(backend)
        }
    }

    /// 本編と同じ章見出しの形（番号 → 章名）
    private func chapter(_ number: String, _ title: String) -> some View {
        HStack(spacing: Palette.Space.s2) {
            Text(number).foregroundStyle(Palette.pink)
            Text("// " + title).foregroundStyle(Palette.Light.fg2)
        }
        .font(.mono(11))
        .tracking(Palette.caps(11))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func found(_ name: String, _ path: String?) -> some View {
        HStack(spacing: Palette.Space.s2) {
            Image(systemName: path == nil ? "xmark.circle" : "checkmark.circle")
                .foregroundStyle(path == nil ? Palette.Light.danger : Palette.Light.success)
            Text(path ?? "\(name) が見つからない。下の欄に絶対パスを書く")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(path == nil ? Palette.Light.danger : Palette.Light.fg2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
