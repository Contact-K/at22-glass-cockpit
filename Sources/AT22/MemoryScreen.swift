import SwiftUI

// MARK: - 04 MEMORY

/// 記憶DB。司令塔が節目ごとに書き足したノート（`Memory.protocolText` の約束）を3段で並べ、
/// 右の列から PROJECT.md へ清書する。AT22 はノートを書かない——押すと読むだけの板で開く
struct MemoryScreen: View {
    let cockpit: Cockpit
    let workspace: String?
    let width: CGFloat
    let height: CGFloat
    let onOpen: (String) -> Void

    @State private var nodes: [Memory.Node] = []
    @Environment(\.frozenTime) private var frozen

    var body: some View {
        let outline = Memory.outline(nodes)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SectionMark(number: "04", title: "MEMORY", jp: "記憶")
                Text("What we've learned.").font(.display(52))
                Text(workspace == nil
                     ? "管制塔で worktree を選ぶと、そのリポジトリの記憶DBが並びます。"
                     : "司令塔が節目ごとに書き足したノートです。右の「清書」で PROJECT.md を企画書にまとめます。"
                       + (outline.done > 0 ? "（完了 \(outline.done) 件は畳んでいます）" : ""))
                    .font(.bodyJP(15)).foregroundStyle(Palette.Light.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 14)
            LiveScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(outline.rows.enumerated()), id: \.offset) { _, row in
                        if let node = row.node {
                            line(node, label: row.label)
                        } else {
                            Text("// " + row.label.uppercased()).font(.mono(10)).tracking(Palette.caps(10))
                                .foregroundStyle(Palette.Light.fg2)
                                .padding(.top, 14).padding(.bottom, 4)
                        }
                    }
                }
            }
        }
        .foregroundStyle(Palette.Light.fg)
        .frame(width: width, height: height - 100, alignment: .topLeading)
        // ponytail: 2秒ごとに読み直す。ノートは数十本。増えたら fs の通知に替える
        .task(id: workspace) {
            guard let workspace else { nodes = []; return }
            let root = URL(fileURLWithPath: cockpit.memoryDirectory(cwd: workspace)).deletingLastPathComponent()
            repeat {
                nodes = Memory.load(projectRoot: root)
                if frozen != nil { return }
                try? await Task.sleep(for: .seconds(2))
            } while !Task.isCancelled
        }
    }

    private func line(_ node: Memory.Node, label: String) -> some View {
        Button { onOpen(node.id) } label: {
            HStack(spacing: 10) {
                Rectangle().fill(node.hasState ? Palette.pink : Palette.Light.line).frame(width: 6, height: 6)
                Text(node.name == (label as NSString).deletingPathExtension ? label : node.name)
                    .font(.bodyJP(14)).lineLimit(1)
                Text(node.summary).font(.bodyJP(12)).foregroundStyle(Palette.Light.fg2).lineLimit(1)
                Spacer(minLength: 8)
                Text(node.modified.formatted(.dateTime.month().day().hour().minute()))
                    .font(.mono(10)).foregroundStyle(Palette.Light.fg3).lineLimit(1)
            }
            .padding(.vertical, 7).padding(.leading, 0)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.Light.line).frame(height: 1) }
        }
        .buttonStyle(PressStyle())
        .help(node.relative)
    }
}

/// 右の列。PROJECT.md の頭と「清書」
struct MemoryPanels: View {
    let cockpit: Cockpit
    let workspace: String?
    let height: CGFloat
    let onTalk: () -> Void

    @State private var project: (text: String, at: Date)?
    @State private var note: String?

    var body: some View {
        let session = workspace.flatMap { cockpit.composing[$0] }
        let working = session.map { cockpit.isWorking($0) } ?? false
        SumiPanel(number: "04", title: "COMPOSE", jp: "清書",
                  right: project.map { "PROJECT.md · " + $0.at.formatted(.dateTime.month().day().hour().minute()) } ?? "PROJECT.md なし") {
            Text(project?.text ?? "まだ清書していません。「清書 ▸」で記憶DBを読み、企画書（目的・決めたこと・未決・次の一手）にまとめます。")
                .font(.bodyJP(13)).foregroundStyle(project == nil ? Palette.Light.fg2 : Palette.Light.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            HStack(spacing: 8) {
                if working {
                    InkLoader(status: "write", pitch: 1.4)
                    Text("清書しています")
                } else {
                    Text(note ?? "書けるのは PROJECT.md だけ")
                }
                Spacer(minLength: 0)
                if let session {
                    Button("会話で見る") { cockpit.selectedSession = session; onTalk() }.buttonStyle(.plain)
                }
                Button("清書 ▸") {
                    guard let workspace else { return }
                    note = cockpit.compose(workspace: workspace) == nil
                        ? (cockpit.launchError ?? "清書を起こせませんでした") : nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(workspace == nil || working ? Palette.Light.fg3 : Palette.blue)
                .disabled(workspace == nil || working)
            }
        }
        .frame(width: 352, height: height - 136)
        .task(id: (workspace ?? "") + (working ? "|w" : "")) { read() }
    }

    /// PROJECT.md の本文の頭。清書が終わると working が切り替わるので、その時に読み直す
    private func read() {
        guard let workspace else { project = nil; return }
        let path = Memory.projectNotePath(dir: cockpit.memoryDirectory(cwd: workspace))
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { project = nil; return }
        let at = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
        project = (Memory.body(text).split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(24).joined(separator: "\n"), at)
    }
}
