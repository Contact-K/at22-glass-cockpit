import SwiftUI
import AppKit

@main
struct AT22App: App {
    @State private var cockpit = Cockpit()
    @State private var watcher = TranscriptWatcher()

    init() {
        // 見え方を画像に焼いて確かめる口。**画面を開かずに** PNG を1枚吐いて終わる。
        //
        //     swift run AT22 --shot /tmp/cockpit.png [幅 高さ]
        //
        // 半透明の二重掛けで線が消える・暗い地の上で沈む——この筐体でいちばん多い壊れ方は
        // どれも「動かしてみないと分からない」ものだった。目視の前に1枚出せると差分が追える
        if let path = Self.shotPath() {
            Snapshot.write(to: path, size: Self.shotSize(), mode: Self.shotMode(),
                           transcript: Self.shotTranscript(), gate: CommandLine.arguments.contains("--gate"))
            exit(0)
        }
        // 書体は SwiftPM の `resources:` を通さず、起動時にこのプロセスへ登録する（Palette.registerFonts）
        Palette.registerFonts()
        // swift build が吐く素の実行ファイルは既定で accessory 扱いになり、Dock にも前面にも出ない。
        // ponytail: 開発中に `swift run` で直接動かすための1行。配布物はこれに頼っていない——
        // package.sh が Info.plist と .icns 入りの AT22.app を組むので、バンドル内では重複した無害な指定
        NSApplication.shared.setActivationPolicy(.regular)

        // **外観は明るい側で固定する。** Sumi v10 は白地が主の面なので、システムがダークでも
        // Picker / TextEditor / alert が白地の上で黒く浮かないようにする（`Snapshot` も .light で焼く）
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    private static func shotPath() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--shot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--mode work|structure|memory` でどの画面を焼くか
    private static func shotMode() -> CockpitMode {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--mode"), i + 1 < args.count,
              let mode = CockpitMode(rawValue: args[i + 1]) else { return .work }
        return mode
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
                // v10 は 1440×900。左の会話（220 + 380）と右の列（376）と五角形の尖りが
                // 重ならない幅、ACTIONS と PLAN が重ならない高さを下限にする
                .frame(minWidth: 1200, minHeight: 760)
                // 窓の地は青帯と同じ青。`.hiddenTitleBar` で中身は上端まで届くが、
                // 窓自体の地が違う色だと信号機のまわりだけが抜ける
                .containerBackground(Palette.blue, for: .window)
        }
        .defaultSize(width: 1440, height: 900)
        // 帯を自前で描くので、システムのタイトルバーは畳む。
        // **信号機だけは OS が同じ位置に描き続ける**ので、TopBand は左端 78pt を空けてある
        .windowStyle(.hiddenTitleBar)

        // ⌘, で開く。しきい値は環境と使い方で最適値が動くので、外から変えられるようにしておく
        Settings {
            ThresholdSettings(cockpit: cockpit)
        }
    }
}

private struct ThresholdSettings: View {
    let cockpit: Cockpit

    /// 上限は参照の点の上限（Cockpit.maxReadTicks）に合わせる。
    /// ここを超えると点が埋まりきったまま増えず、「あと何回でフラグか」が読めなくなる
    @AppStorage(Cockpit.thresholdKey) private var threshold = 3
    /// 連携機能は既定オフ。**入れただけで LLM を起こすアプリにはしない**
    @AppStorage(Cockpit.launcherEnabledKey) private var launcherEnabled = false
    /// CLI の場所を人が指定する口。空ならログインシェルに訊く
    @AppStorage(Cockpit.claudePathKey) private var claudePath = ""
    @AppStorage(Cockpit.codexPathKey) private var codexPath = ""

    var body: some View {
        Form {
            Section {
                Stepper("フラグを立てる参照回数: \(threshold)回",
                        value: $threshold, in: 2...Cockpit.maxReadTicks)
                note("同じエージェントがこの回数以上読み、一度も書いていないファイルに橙を立てる。"
                     + "セル右端の丸もこの数で埋まりきる。"
                     + "実 transcript 2478組の分布から既定は3回（当てはまるのは全体の1.4%）。")
            } header: { chapter("01", "表示") }

            Section {
                Toggle("セッションを起こす／続きを送る", isOn: $launcherEnabled)
                note("既定でオフなのは、AT22 が入れただけで LLM を起動するアプリにしないため。"
                     + "AT22 は API キーも OAuth トークンも保存せず、"
                     + "あなたが既にログイン済みの `claude` / `codex` コマンドを起こすだけで、"
                     + "通信はそのプロセスが行う。")

                // 見つかった場所を必ず出す。**以前は見つからない時しか何も出ず**、
                // 「探しに行ったのか」「見つけたのか」が画面から分からなかった
                found("claude", cockpit.claude?.executable.path)
                TextField("claude の場所（空ならログインシェルに訊く）", text: $claudePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                found("codex", cockpit.codexFound?.executable.path)
                TextField("codex の場所（空ならログインシェルに訊く）", text: $codexPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                note("GUI アプリの `PATH` には `~/.local/bin` も `/opt/homebrew/bin` も無いので、"
                     + "通常はログインシェルを1回通して自動で見つける。"
                     + "見つからない環境だけ絶対パスを書く。")
            } header: { chapter("02", "連携") }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    /// 本編と同じ章見出しの形（番号 → 章名）
    private func chapter(_ number: String, _ title: String) -> some View {
        HStack(spacing: Palette.Space.s2) {
            Text(number)
                .font(Palette.mono(11))
                .foregroundStyle(Palette.pink)
            Text("// " + title)
                .caps(11)
                .foregroundStyle(Palette.Light.fg2)
        }
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
                .foregroundStyle(path == nil ? Palette.danger : Palette.success)
            Text(path ?? "\(name) が見つからない。下の欄に絶対パスを書く")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(path == nil ? Palette.danger : Palette.Light.fg2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
