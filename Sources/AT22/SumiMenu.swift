import SwiftUI

// MARK: - メニューの状態

/// 開いているメニュー1つぶん。時刻で動くもの（ドット・線）は始めた時刻だけを持つ
struct MenuState: Equatable {
    enum Kind: Equatable {
        /// M。白い面にドットが育つ。root（プロジェクト）→ proj（worktree）→ ws（タブ）
        case menu
        /// ⌘J。青い面に斜線、全エージェントを あなた待ち → 作業中 → 完了 → 待機 の順に
        case jump
    }
    enum Level: Equatable { case root, project, workspace }

    let kind: Kind
    let opened: Date
    var closing: Date?
    /// ドットが育ちきったか。立つと面の時計が止まる
    var settled = false
    var level: Level = .workspace
    /// 見ているプロジェクト（リポジトリのパス）とワークスペース（worktree のパス）
    var project: String?
    var workspace: String?
    var highlight: Int
    /// 階層を移るたびに増える。項目の迫り出しをやり直す
    var turn = 0

    init(kind: Kind, opened: Date, highlight: Int) {
        self.kind = kind
        self.opened = opened
        self.highlight = highlight
    }
}

/// メニューの1行。`key` で何を押したかを持ち主へ返す
struct MenuRow: Identifiable {
    let key: String
    let num: String
    let en: String
    let jp: String
    let desc: String
    var tag: String? = nil
    var wait = false
    var id: String { key }
}

/// パンくずの1段（`~/code / AT22 / .worktrees/legend-fix`）
struct MenuCrumb {
    let title: String
    let level: MenuState.Level
}

// MARK: - M のメニュー

/// 白い面（会話の「<」の形）に、斜線から離れる順にドットが育って広がる → 項目が斜線に沿って並ぶ。
/// 選んだ行だけ青い板（右端が尖る）。閉じる時はドットが縮んで消える（v11 `V11MenuW`）
struct WedgeMenu: View {
    let state: MenuState
    let rows: [MenuRow]
    let crumbs: [MenuCrumb]
    let size: CGSize
    let onPick: (Int) -> Void
    let onHover: (Int) -> Void
    let onCrumb: (MenuState.Level) -> Void
    let onUp: () -> Void
    let onClose: () -> Void

    @Environment(\.frozenTime) private var frozen

    private static let tan18 = CGFloat(tan(18 * Double.pi / 180))
    static let openTime = 0.30, closeTime = 0.22

    var body: some View {
        let full = frozen != nil || state.settled
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onClose)
            if full && state.closing == nil {
                BlueSheet.white(p: 1, size: size).fill(Palette.white)
            } else {
                WedgeDots(opened: state.opened, closing: state.closing)
            }
            Path { p in
                p.move(to: CGPoint(x: 166, y: 56))
                p.addLine(to: CGPoint(x: 166 + (size.height - 100) * 0.325, y: size.height - 44))
            }
            .stroke(Palette.blue, lineWidth: 3)
            .allowsHitTesting(false)
            BlueSheet.edge(p: 1, size: size).stroke(Palette.blue, lineWidth: 3).allowsHitTesting(false)
            if full || state.closing != nil { content.modifier(ExitFade(closing: state.closing != nil)) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var window: (start: Int, rows: ArraySlice<MenuRow>) {
        let n = rows.count, win = 8
        let start = max(0, min(state.highlight - 3, n - win))
        return (start, rows[start..<min(n, start + win)])
    }

    private var top0: CGFloat { (size.height / 2 + 36) - CGFloat(window.rows.count) * 84 / 2 }
    private func x0(_ y: CGFloat) -> CGFloat { 206 + (y + 30) * Self.tan18 - 40 }

    private var content: some View {
        let (start, visible) = window
        return ZStack(alignment: .topLeading) {
            crumbBar
                .frame(width: crumbRoom, alignment: .leading)
                .offset(x: x0(top0 - 60) + 18, y: top0 - 60)
                .modifier(Late(delay: 0.1))
            ForEach(Array(visible.enumerated()), id: \.element.id) { j, row in
                let i = start + j
                let y = top0 + CGFloat(j) * 84
                item(row, on: i == state.highlight)
                    .contentShape(Rectangle())
                    .onHover { if $0 { onHover(i) } }
                    .onTapGesture { onPick(i) }
                    .modifier(StepIn(delay: 0.12 + Double(j) * 0.03, trigger: state.turn))
                    .offset(x: x0(y), y: y)
            }
        }
    }

    private func item(_ row: MenuRow, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(row.num).font(.mono(12)).tracking(1.2).foregroundStyle(Palette.pink).frame(width: 30, alignment: .leading)
                Text(row.en).font(.display(44))
                Text(row.jp).font(.brush(16))
            }
            .lineLimit(1)
            .foregroundStyle(on ? Palette.white : Palette.blue)
            .opacity(on ? 1 : 0.6)
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 6, trailing: 60))
            if on && !row.desc.isEmpty {
                Text(row.desc).font(.bodyJP(13)).foregroundStyle(Palette.Blue.fg3).lineLimit(1)
                    .padding(EdgeInsets(top: 0, leading: 64, bottom: 8, trailing: 60))
            }
        }
        .fixedSize()
        .background { if on { Chevron(head: 30).fill(Palette.blue).padding(.trailing, -40) } }
    }

    /// パスの帯が使える幅。白い面の右の辺（「<」）まで、24pt 手前で止める
    private var crumbRoom: CGFloat {
        let y = top0 - 60 + 17, xc = size.width - 394, apex = size.width - 540, mid = size.height / 2
        let edge = y < mid ? xc - (xc - apex) * (y - 56) / (mid - 56) : apex + (xc - apex) * (y - mid) / (size.height - 44 - mid)
        return max(120, edge - (x0(top0 - 60) + 18) - 24)
    }

    /// 長い時は、いまの段の名前だけを真ん中で詰める（◂ と上の段は縮めない）
    private var crumbBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 0) {
                if state.level != .root {
                    Button(action: onUp) { Text("◂").padding(.horizontal, 8).padding(.vertical, 6) }
                        .buttonStyle(PressStyle())
                        .fixedSize()
                        .help("上の階層へ (←)")
                    Rectangle().fill(Palette.white.opacity(0.4)).frame(width: 1, height: 22)
                }
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, crumb in
                    let last = i == crumbs.count - 1
                    if i > 0 { Text("/").opacity(0.6).padding(.vertical, 6).fixedSize() }
                    Button { if !last { onCrumb(crumb.level) } } label: {
                        Text(crumb.title).underline(!last).lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 6).padding(.vertical, 6)
                    }
                    .fixedSize(horizontal: !last, vertical: false)
                    .buttonStyle(PressStyle())
                    .disabled(last)
                }
            }
            .font(.mono(10)).tracking(Palette.caps(10))
            .foregroundStyle(Palette.white)
            .background(Palette.blue)
        }
    }
}

/// 白い面に育つドット。斜線 x=166+(y-56)·0.325 から離れる順に、16pt の升が ピンク → 青 → 白 で育つ。
/// 24fps のコマ送り。開く 300ms、閉じる 220ms（閉じる時は逆に縮む）
private struct WedgeDots: View {
    let opened: Date
    let closing: Date?

    var body: some View {
        Ticker(fps: 24) { now in
            Canvas { ctx, size in
                let start = closing ?? opened
                let duration = closing == nil ? WedgeMenu.openTime : WedgeMenu.closeTime
                let frame = 1.0 / 24
                let k = min(1, floor(now.timeIntervalSince(start) / frame) * frame / duration)
                Self.draw(&ctx, size: size, p: closing == nil ? k : 1 - k)
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated static func draw(_ ctx: inout GraphicsContext, size: CGSize, p: Double) {
        guard p > 0 else { return }
        let pc: CGFloat = 16
        let apex = (56 + size.height - 44) / 2
        let xc = size.width - 394, xt = size.width - 540
        func edge(_ y: CGFloat) -> CGFloat {
            y < apex ? xc - (y - 56) / (apex - 56) * (xc - xt) : xt + (y - apex) / (size.height - 44 - apex) * (xc - xt)
        }
        func line(_ y: CGFloat) -> CGFloat { 166 + (y - 56) * 0.325 }
        let maxD = max(line(56), xc - line(56), line(size.height - 44), xc - line(size.height - 44))
        ctx.clip(to: BlueSheet.white(p: 1, size: size))
        let p2 = p * 1.4
        var y: CGFloat = 56
        while y < size.height - 44 {
            var x: CGFloat = 0
            let limit = edge(y < apex ? y + pc : y)
            while x < limit {
                let d = Double(abs(x + 8 - line(y + 8)) / maxD)
                let f = p2 - d
                let s = max(0, min(1, f / 0.4))
                if s > 0 {
                    let sz = ceil(CGFloat(s) * pc), inset = floor((pc - sz) / 2)
                    let color = f < 0.08 ? Palette.pink : f < 0.4 ? Palette.blue : Palette.white
                    ctx.fill(Path(CGRect(x: x + inset, y: y + inset, width: sz, height: sz)), with: .color(color))
                }
                x += pc
            }
            y += pc
        }
    }
}

// MARK: - ⌘J

/// 斜線の世界。青い面が斜線（286→578）から開き、項目が線に沿って並ぶ。選んだ行だけ白い板
struct JumpMenu: View {
    let state: MenuState
    let rows: [MenuRow]
    let size: CGSize
    let onPick: (Int) -> Void
    let onHover: (Int) -> Void
    let onClose: () -> Void

    @State private var reveal = 0
    @Environment(\.frozenTime) private var frozen

    private static let tan18 = CGFloat(tan(18 * Double.pi / 180))

    var body: some View {
        let n = rows.count, win = 8
        let start = max(0, min(state.highlight - 3, n - win))
        let visible = Array(rows[start..<min(n, start + win)].enumerated())
        ZStack(alignment: .topLeading) {
            // 斜線から全面へ開く（`v11open` 260ms・6コマ）
            Rectangle().fill(Palette.blue)
                .clipShape(OpenFromSlash(k: CGFloat(frozen != nil ? 6 : reveal) / 6))
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onClose)
            Path { p in
                p.move(to: CGPoint(x: 286, y: 0))
                p.addLine(to: CGPoint(x: 286 + size.height * Self.tan18, y: size.height))
            }
            .stroke(Palette.white, lineWidth: 3)
            .allowsHitTesting(false)
            HStack(spacing: 16) {
                Text("⌘J JUMP 移動").font(.mono(10)).tracking(Palette.caps(10))
                    .foregroundStyle(Palette.blue)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Palette.white)
                Text("あなた待ち → 作業中 → 完了 → 待機 · ⌘1–6 で直に").font(.mono(9)).tracking(1.1)
                    .foregroundStyle(Palette.Blue.fg3)
            }
            .offset(x: 310, y: 24)
            .modifier(Late(delay: 0.26))
            if rows.isEmpty {
                Text("動いているエージェントはいない").font(.bodyJP(15)).foregroundStyle(Palette.white)
                    .offset(x: 360, y: 140)
            }
            ForEach(visible, id: \.element.id) { j, row in
                let i = start + j, on = i == state.highlight
                let y = 110 + CGFloat(j) * 82
                item(row, on: on)
                    .contentShape(Rectangle())
                    .onHover { if $0 { onHover(i) } }
                    .onTapGesture { onPick(i) }
                    .modifier(StepIn(delay: 0.08 + Double(j) * 0.03, trigger: 0))
                    .offset(x: 286 + (y + 30) * Self.tan18 + 28, y: y)
            }
            VStack(alignment: .leading, spacing: 12) {
                Mascot(pitch: 9, lookRight: true, pose: .one, color: Palette.white)
                Text("[×] CLOSE · ESC").font(.mono(10)).tracking(Palette.caps(10)).foregroundStyle(Palette.white)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 40)
            .padding(.bottom, 64)
            .modifier(Late(delay: 0.26))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .modifier(ExitFade(closing: state.closing != nil))
        .task {
            guard frozen == nil else { return }
            for k in 1...6 { try? await Task.sleep(for: .milliseconds(43)); reveal = k }
        }
    }

    private func item(_ row: MenuRow, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(row.num).font(.mono(12)).tracking(1.2)
                    .foregroundStyle(on ? Palette.pink : Palette.white).frame(width: 34, alignment: .leading)
                Text(row.en).font(.display(44))
                Text(row.jp).font(.brush(16))
                if let tag = row.tag {
                    HStack(spacing: 8) {
                        if row.wait { Blink() }
                        Text(tag).font(.mono(10)).tracking(Palette.caps(10))
                    }
                }
            }
            .lineLimit(1)
            .foregroundStyle(on ? Palette.blue : Palette.white)
            .opacity(on ? 1 : 0.55)
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 6, trailing: 60))
            if on && !row.desc.isEmpty {
                Text(row.desc).font(.bodyJP(13)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                    .padding(EdgeInsets(top: 0, leading: 68, bottom: 8, trailing: 60))
            }
        }
        .fixedSize()
        .background { if on { Chevron(head: 30).fill(Palette.white).padding(.trailing, -40) } }
    }
}

/// `polygon(286 0,286 0,578 900,578 900)` → 全面。斜線を軸に左右へ開く
private struct OpenFromSlash: Shape {
    var k: CGFloat

    nonisolated func path(in r: CGRect) -> Path {
        let tan18 = CGFloat(tan(18 * Double.pi / 180))
        let top = 286 * (1 - k), bottom = (286 + r.height * tan18) * (1 - k)
        let rightTop = 286 + (r.width - 286) * k, rightBottom = 286 + r.height * tan18 + (r.width - 286 - r.height * tan18) * k
        var p = Path()
        p.move(to: CGPoint(x: top, y: 0))
        p.addLine(to: CGPoint(x: rightTop, y: 0))
        p.addLine(to: CGPoint(x: rightBottom, y: r.height))
        p.addLine(to: CGPoint(x: bottom, y: r.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - 部品の動き（時計を回さずに、`task` の中で数コマだけ進める）

/// 遅れて現れる（`sm-late`: 指定の時間だけ隠れてから、1コマで出る）
struct Late: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.frozenTime) private var frozen

    func body(content: Content) -> some View {
        content
            .opacity(shown || frozen != nil ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                shown = true
            }
    }
}

/// 迫り出し（`v11in`: 左上 12,4 から 160ms・3コマで定位置へ）
private struct StepIn: ViewModifier {
    let delay: Double
    let trigger: Int
    @State private var k = 0
    @Environment(\.frozenTime) private var frozen

    func body(content: Content) -> some View {
        let p = CGFloat(frozen != nil ? 3 : k) / 3
        return content
            .opacity(Double(p))
            .offset(x: -12 * (1 - p), y: -4 * (1 - p))
            .task(id: trigger) {
                guard frozen == nil else { return }
                k = 0
                try? await Task.sleep(for: .seconds(delay))
                for step in 1...3 { k = step; try? await Task.sleep(for: .milliseconds(53)) }
            }
    }
}

/// 閉じる時の引き（`v11outW`: 140ms・3コマで右下へ消える）
private struct ExitFade: ViewModifier {
    let closing: Bool
    @State private var k = 0

    func body(content: Content) -> some View {
        let p = CGFloat(k) / 3
        return content
            .opacity(Double(1 - p))
            .offset(x: -14 * p, y: 4 * p)
            .task(id: closing) {
                guard closing else { k = 0; return }
                for step in 1...3 { try? await Task.sleep(for: .milliseconds(46)); k = step }
            }
    }
}
