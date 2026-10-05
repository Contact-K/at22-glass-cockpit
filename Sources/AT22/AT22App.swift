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
        //     swift run AT22 --shot /tmp/cockpit.png [幅 高さ] [--mode talk|files|review|git|settings] [--tower]
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
                           menu: Self.argument("--menu"), sheet: Self.argument("--sheet"),
                           review: Self.argument("--review"),
                           term: CommandLine.arguments.contains("--term"),
                           ripple: Self.argument("--ripple"))
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
                    cockpit.watchedFrom = { [watcher] in watcher.startOffsets }
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
        // 設定は 10 SETTINGS の1か所。⌘, は別窓ではなくそのタブを開く
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("設定…") { NotificationCenter.default.post(name: .at22OpenSettings, object: nil) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    /// ⌘, → 10 SETTINGS
    static let at22OpenSettings = Notification.Name("at22.openSettings")
}
