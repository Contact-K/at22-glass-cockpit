import SwiftUI
import SwiftTerm

// MARK: - 09 TERMINAL

/// worktree ごとの端末。**切り替えても消えない**（シェルはアプリが閉じるまで生きている）。
/// 端末の中で人が打ったものは人の操作。AT22 はここに何も書き込まない（開く時に頼まれた `claude --resume` だけ）
// ponytail: 端末はアプリの寿命まで。再起動をまたぐ常駐（Orca のデーモン）は要望が出てから
@MainActor @Observable
final class Terminals {
    /// SwiftTerm は既定で主キューから呼ぶので、主アクターのまま受ける（違えば実行時に止まる）
    @MainActor final class Session: NSObject, Identifiable, @preconcurrency LocalProcessTerminalViewDelegate {
        let id = UUID()
        let name: String
        let view: LocalProcessTerminalView
        weak var owner: Terminals?

        init(name: String, view: LocalProcessTerminalView) {
            self.name = name
            self.view = view
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        /// `exit` で閉じたら、そのタブも畳む
        func processTerminated(source: TerminalView, exitCode: Int32?) { owner?.remove(self) }
    }

    private(set) var byPath: [String: [Session]] = [:]
    var current: [String: Int] = [:]

    func sessions(_ path: String) -> [Session] { byPath[path] ?? [] }

    /// ログインシェルを worktree で起こす。`command` は起きた直後に打ち込む（シェルの履歴にも残る）
    @discardableResult
    func add(_ path: String, name: String = "zsh", command: String? = nil) -> Session {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        let font = SumiFonts.mono.flatMap { NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 13) }
            ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.font = font
        view.nativeBackgroundColor = NSColor(Palette.blue)
        view.nativeForegroundColor = .white
        view.caretColor = NSColor(Palette.pink)
        view.selectedTextBackgroundColor = NSColor(Palette.navy)
        let session = Session(name: name, view: view)
        session.owner = self
        view.processDelegate = session
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("SHELL=" + shell)
        // `-zsh` の名で起こすとログインシェルになり、PATH はその人の設定から組まれる
        view.startProcess(executable: shell, args: [], environment: env,
                          execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: path)
        if let command { view.send(data: ArraySlice(Array((command + "\n").utf8))) }
        byPath[path, default: []].append(session)
        current[path] = byPath[path]!.count - 1
        return session
    }

    func remove(_ session: Session) {
        for (path, list) in byPath {
            guard let i = list.firstIndex(where: { $0 === session }) else { continue }
            byPath[path]!.remove(at: i)
            current[path] = max(0, min((current[path] ?? 0), byPath[path]!.count - 1))
        }
    }

    func close(_ path: String, at index: Int) {
        guard sessions(path).indices.contains(index) else { return }
        let session = sessions(path)[index]
        session.view.terminate()
        remove(session)
    }
}

/// SwiftTerm の NSView をそのまま載せる。持ち主は `Terminals`（ここで作らない＝切り替えで消えない）
private struct TermHost: NSViewRepresentable {
    let view: LocalProcessTerminalView
    let focus: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView { view }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if focus, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }
}

/// 下から引き出す端末（青い面・白い線）。見出しに `09 // TERMINAL 端末`・タブ・＋・置き場・`[×] ⌃\``。
/// 2本以上あれば左右に並べる
struct TerminalDrawer: View {
    let terminals: Terminals
    let path: String
    let name: String
    let onClose: () -> Void
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let list = terminals.sessions(path)
        let cur = min(terminals.current[path] ?? 0, max(0, list.count - 1))
        // 撮影では殻を起こさないので、空の1枚を置く
        let panes = frozen != nil && list.isEmpty ? [0]
            : list.count < 2 ? Array(list.indices) : [min(cur, list.count - 2), min(cur, list.count - 2) + 1]
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) { Text("09").foregroundStyle(Palette.pink); Text("// TERMINAL") }
                        .font(.mono(10)).tracking(Palette.caps(10))
                    Text("端末").font(.brush(13))
                }
                .padding(.horizontal, 14)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    Button { terminals.current[path] = i } label: {
                        Text("\(s.name) · \(i + 1)").font(.mono(11)).tracking(0.4)
                            .foregroundStyle(i == cur ? Palette.blue : Palette.white)
                            .padding(.horizontal, 14).frame(maxHeight: .infinity)
                            .background(i == cur ? Palette.white : .clear)
                            .overlay(alignment: .leading) { Rectangle().fill(Palette.white).frame(width: 1) }
                    }
                    .buttonStyle(PressStyle())
                }
                Button { terminals.add(path) } label: {
                    Text("＋").font(.mono(13)).padding(.horizontal, 12).frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(Palette.white).frame(width: 1) }
                        .overlay(alignment: .trailing) { Rectangle().fill(Palette.white).frame(width: 1) }
                }
                .buttonStyle(PressStyle())
                .help("端末を足す")
                Spacer(minLength: 0)
                Text((path as NSString).abbreviatingWithTildeInPath + " · その場で直す").font(.mono(9)).tracking(0.9)
                    .foregroundStyle(Palette.Blue.fg2).lineLimit(1).truncationMode(.head)
                    .padding(.horizontal, 12)
                Button(action: onClose) {
                    Text("[×] ⌃`").font(.mono(10)).tracking(1).padding(.horizontal, 12).frame(maxHeight: .infinity)
                }
                .buttonStyle(PressStyle())
            }
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.white).frame(height: 2) }

            HStack(spacing: 0) {
                ForEach(panes, id: \.self) { i in
                    Group {
                        if frozen != nil {
                            Text("\(name) % ").font(.mono(13)).padding(.horizontal, 14).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            TermHost(view: list[i].view, focus: i == cur).padding(.horizontal, 8).padding(.vertical, 6)
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { terminals.current[path] = i })
                    .overlay(alignment: .leading) {
                        if i != panes.first { Rectangle().fill(Palette.white).frame(width: 1) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(Palette.white)
        .background(Palette.blue)
        .overlay(UnclosedBox().stroke(Palette.white, lineWidth: 1))
        .onAppear { if frozen == nil, list.isEmpty { terminals.add(path) } }
    }
}

/// 下の辺だけ無い枠（下帯に繋がって見える）
private struct UnclosedBox: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 0.5, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 0.5, y: r.minY + 0.5))
        p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
        p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.maxY))
        return p
    }
}

/// 引き出し。`open` が変わると下端から「∧」形のドット波紋が面を覆い、覆い切った所で中身を出し入れして抜ける。
/// 管制塔の切替と同じドット・24fps（v11 の V11Pull: 覆い8コマ・溜め2・抜け9）
struct PullDrawer<Content: View>: View {
    let open: Bool
    @ViewBuilder let content: () -> Content

    @State private var visible: Bool?
    @State private var started: Date?
    @State private var opening = true
    @Environment(\.frozenTime) private var frozen

    private static var frame: Double { 1.0 / 24 }

    var body: some View {
        let shown = visible ?? open
        ZStack {
            if shown { content() }
            Ticker(fps: 24, paused: started == nil) { now in
                if let started {
                    Canvas { ctx, size in draw(&ctx, size: size, n: Int(now.timeIntervalSince(started) / Self.frame)) }
                }
            }
            .allowsHitTesting(false)
        }
        .allowsHitTesting(shown)
        .onChange(of: open) {
            guard frozen == nil else { return }
            opening = open
            started = Date()
            let now = open
            DispatchQueue.main.asyncAfter(deadline: .now() + 8 * Self.frame) { visible = now }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20 * Self.frame) { if visible == now { started = nil } }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, n: Int) {
        let (c, h, r) = (8, 2, 9)
        guard n <= c + h + r else { return }
        let p: Double, covering: Bool
        if n < c { p = Double(n + 1) / Double(c); covering = true }
        else if n < c + h { p = 1; covering = true }
        else { p = max(0, 1 - Double(n - c - h + 1) / Double(r)); covering = false }
        let w = size.width, hh = size.height, maxK = hh + 0.37 * w / 2
        let up = opening
        DotWipeLayer.dots(&ctx, size: size, p: p, covering: covering, pc: 16) { x, y in
            Double(((up ? hh - y : y) + 0.37 * abs(x - w / 2)) / maxK)
        }
    }
}
