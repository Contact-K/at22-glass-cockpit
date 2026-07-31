import SwiftUI
import AppKit

@main
struct AT22App: App {
    @State private var cockpit = Cockpit()
    @State private var watcher = TranscriptWatcher()

    init() {
        // ponytail: swift build が吐く素の実行ファイルは既定で accessory 扱いになり、
        // Dock にも前面にも出ない。この1行で .app バンドルを作らずに済ませる。
        // メニューバーやアイコンが要るようになったら Info.plist 付きバンドルに切り替える
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("AT22 Glass Cockpit", id: "cockpit") {
            CockpitView(cockpit: cockpit)
                .task {
                    watcher.onEvents = { [cockpit] events in cockpit.apply(events) }
                    watcher.start()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1100, height: 780)
    }
}
