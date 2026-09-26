import SwiftUI
import AppKit
import UserNotifications

// MARK: - ワークスペースの木

/// プロジェクト → ワークスペース（git worktree）→ エージェント。Orca のサイドバーと同じ組み方。
///
/// 登録したリポジトリに加えて、動いているセッションの在り処からもリポジトリを見つけて並べる——
/// 端末や `claude -w` で始めた作業も、登録しないまま木に出る。
/// 行を押すとそのエージェントの会話を開く（過去のセッションは読み込み、Codex / Grok は続きに繋ぐ）
struct WorkspaceSidebar: View {
    let cockpit: Cockpit
    /// 行を押した後に会話欄を開く
    let onOpen: () -> Void
    /// 画像焼きの時だけ偽。ImageRenderer は ScrollView の中身を組まない
    var scrolls = true

    @State private var creatingIn: CreateTarget?
    @State private var deleting: Cockpit.WorkspaceNode?
    @State private var problem: String?

    static let width: CGFloat = 248

    private struct CreateTarget: Identifiable {
        let repo: String
        var id: String { repo }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            let tree = cockpit.workspaceTree()
            if tree.isEmpty {
                empty
            } else if scrolls {
                ScrollView { rows(tree) }
            } else {
                rows(tree)
                Spacer(minLength: 0)
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .onTapGesture { self.problem = nil }
            }
        }
        .frame(width: Self.width)
        .background(CockpitCanvas.background)
        .sheet(item: $creatingIn) { target in
            NewWorkspaceSheet(cockpit: cockpit, repo: target.repo) { creatingIn = nil }
        }
        .sheet(item: $deleting) { workspace in
            DeleteWorkspaceSheet(cockpit: cockpit, workspace: workspace) { message in
                deleting = nil
                problem = message
            }
        }
    }

    private func rows(_ tree: [Cockpit.ProjectNode]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tree) { project in projectSection(project) }
        }
        .padding(.bottom, Palette.Space.s3)
    }

    private var header: some View {
        HStack {
            Text("ワークスペース")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Spacer()
            Button { addProject() } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("リポジトリを登録する（worktree の中を選んでも本体が登録される）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var empty: some View {
        VStack(spacing: Palette.Space.s2) {
            Spacer()
            Text("リポジトリがまだ無い")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CockpitCanvas.dim)
            Button("リポジトリを登録…") { addProject() }
                .font(.system(size: 11, design: .monospaced))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 段

    private func projectSection(_ project: Cockpit.ProjectNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Palette.Space.s1) {
                Text(project.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button { creatingIn = CreateTarget(repo: project.id) } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("このリポジトリにワークスペースを作る（⌘N）")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contextMenu {
                Button("Finder で開く") { NSWorkspace.shared.open(URL(fileURLWithPath: project.id)) }
                if project.registered {
                    Button("登録を外す") { cockpit.removeProject(project.id) }
                }
            }

            ForEach(project.workspaces) { workspace in workspaceCard(workspace) }
        }
    }

    private func workspaceCard(_ workspace: Cockpit.WorkspaceNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: workspace.isMain ? "house" : "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundStyle(CockpitCanvas.dim)
                Text(workspace.name)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                // AT22 が作った枝（at22/<名前>）は名前の繰り返しなので出さない。端末や claude -w で作った枝だけ
                if let branch = workspace.branch, !workspace.isMain, branch != Worktree.branch(for: workspace.name) {
                    Text(branch)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            if let pending = workspace.pending {
                HStack(spacing: 6) {
                    if pending == "作成中" { ProgressView().controlSize(.mini) }
                    Text(pending)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(pending == "作成中" ? CockpitCanvas.dim : CockpitCanvas.error)
                        .fixedSize(horizontal: false, vertical: true)
                    if pending != "作成中" {
                        Button("閉じる") { cockpit.dismissPending(workspace.id) }
                            .font(.system(size: 10, design: .monospaced))
                            .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
            }

            ForEach(workspace.agents) { row in agentRow(row) }
        }
        .contextMenu {
            Button("Finder で開く") { NSWorkspace.shared.open(URL(fileURLWithPath: workspace.id)) }
            if !workspace.isMain && workspace.pending == nil {
                Divider()
                Button("削除…") { deleting = workspace }
            }
        }
    }

    private func agentRow(_ row: Cockpit.AgentRow) -> some View {
        Button { open(row) } label: {
            HStack(spacing: 6) {
                StatusGlyph(status: row.status)
                Text(row.title)
                    .font(.system(size: 11, weight: row.unread ? .bold : .regular))
                    .foregroundStyle(row.status == .idle && !row.unread ? CockpitCanvas.dim : Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if row.backend != .claude {
                    Text(row.backend.title)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(CockpitCanvas.dim)
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(cockpit.selectedSession == row.id ? CockpitCanvas.agentOn.opacity(0.12) : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // 生の TUI が要る時の逃げ道。AT22 の接続は先に閉じる（2つのプロセスで同じ会話を書かない）
            Button("Terminal で開く") { problem = cockpit.openInTerminal(row.id) }
        }
    }

    // MARK: 操作

    private func open(_ row: Cockpit.AgentRow) {
        Task {
            await cockpit.open(row)
            onOpen()
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "登録"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { problem = await cockpit.addProject(containing: url.path) }
    }
}

/// 状態の印。**人の番（琥珀）と失敗（赤系）だけが強く光る**。作業中は「いま」の赤、完了は緑、待機は無彩色
struct StatusGlyph: View {
    let status: Cockpit.AgentStatus

    var body: some View {
        Group {
            switch status {
            case .waiting:
                Image(systemName: "questionmark.circle.fill").foregroundStyle(Palette.warning)
            case .working:
                Circle().fill(Palette.accent).frame(width: 7, height: 7)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.danger)
            case .done:
                Circle().fill(Palette.success).frame(width: 7, height: 7)
            case .idle:
                Circle().stroke(Palette.inkDisabled, lineWidth: 1).frame(width: 7, height: 7)
            }
        }
        .font(.system(size: 10))
        .frame(width: 12, height: 12)
    }
}

// MARK: - 作る

/// ワークスペースを作り、そこでエージェントを起こす。**作成は裏で進む**ので、押したらすぐ閉じる
/// （カードに「作成中」が出て、失敗したら理由が残る）
struct NewWorkspaceSheet: View {
    let cockpit: Cockpit
    let repo: String
    let onClose: () -> Void

    @AppStorage("launchBackend") private var launchBackend: String = Backend.claude.rawValue
    @AppStorage("launchModel") private var launchModel = ""
    @State private var name = ""
    @State private var base = ""
    @State private var prompt = ""
    @State private var level = Gate.defaultLevel

    private var backend: Backend { Backend(rawValue: launchBackend) ?? .claude }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ワークスペースを作る — \((repo as NSString).lastPathComponent)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            TextField("名前（ブランチは at22/<名前>）", text: $name)
            TextField("基点（枝・コミット）", text: $base)
            Picker("エージェント", selection: $launchBackend) {
                ForEach(Backend.allCases.filter { cockpit.found[$0] != nil }, id: \.self) { backend in
                    Text(backend.title).tag(backend.rawValue)
                }
            }
            Picker("モデル", selection: $launchModel) {
                Text("既定").tag("")
                ForEach(ModelChoice.models(for: backend), id: \.id) { Text($0.title).tag($0.id) }
            }
            Picker("承認の段", selection: $level) {
                ForEach(Gate.Level.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("最初の指示（空ならワークスペースだけ作る）")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            TextEditor(text: $prompt)
                .font(.system(size: 12))
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.border))
            HStack {
                Spacer()
                Button("やめる", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("作る") {
                    cockpit.createWorkspace(repo: repo, name: name, base: base.isEmpty ? "HEAD" : base,
                                            backend: backend, model: launchModel, prompt: prompt, level: level)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || (!prompt.isEmpty && cockpit.found[backend] == nil))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(18)
        .frame(width: 440)
        .task {
            // 基点の既定はいま居る枝。**SHA ではなく名前で見せる**（人が読んで分かる方）
            let current = await Task.detached { Worktree.currentBranch(repo: repo) }.value
            if base.isEmpty { base = current }
            if cockpit.found[backend] == nil, let first = Backend.allCases.first(where: { cockpit.found[$0] != nil }) {
                launchBackend = first.rawValue
            }
        }
    }
}

// MARK: - 消す

/// 消す前に**未コミットの変更を並べて見せる**。変更がある時だけ「変更ごと消す」になる（force）。
/// 枝は `-d` で消すので、マージされていなければ git が断り、残る
struct DeleteWorkspaceSheet: View {
    let cockpit: Cockpit
    let workspace: Cockpit.WorkspaceNode
    let onDone: (String?) -> Void

    @State private var dirty: [String]?
    @State private var deleteBranch = true
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ワークスペースを消す — \(workspace.name)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            if let dirty {
                if dirty.isEmpty {
                    Text("未コミットの変更は無い。")
                        .font(.system(size: 12))
                } else {
                    Text("未コミットの変更が \(dirty.count) 件ある。消すとこの変更は失われる：")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.danger)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(dirty, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let branch = workspace.branch {
                Toggle("枝 \(branch) も消す（マージされていなければ残す）", isOn: $deleteBranch)
                    .font(.system(size: 11))
            }
            Text("このワークスペースで AT22 が繋いでいるエージェントは、消す前に閉じる。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("やめる", role: .cancel) { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(dirty?.isEmpty == false ? "変更ごと消す" : "消す", role: .destructive) {
                    working = true
                    Task {
                        let message = await cockpit.deleteWorkspace(workspace.id, force: dirty?.isEmpty == false,
                                                                    deleteBranch: deleteBranch)
                        onDone(message)
                    }
                }
                .disabled(dirty == nil || working)
            }
        }
        .padding(18)
        .frame(width: 440)
        .task { dirty = await cockpit.dirtyFiles(of: workspace.id) }
    }
}

// MARK: - ⌘J

/// どのプロジェクトのどのエージェントへも飛ぶ。**人の番（承認待ち）→ 作業中 → 失敗 → 完了 → 待機**の順に並べ、
/// 上の6本は ⌘1〜⌘6、Return は先頭。打った文字でエージェント名・ワークスペース・プロジェクトを絞る
struct JumpPalette: View {
    let cockpit: Cockpit
    let onPick: (Cockpit.AgentRow) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Hit: Identifiable {
        let row: Cockpit.AgentRow
        let place: String
        var id: String { row.id }
    }

    private var hits: [Hit] {
        let all = cockpit.workspaceTree().flatMap { project in
            project.workspaces.flatMap { workspace in
                workspace.agents.map { Hit(row: $0, place: project.name + " / " + workspace.name) }
            }
        }
        let words = query.lowercased().split(separator: " ")
        let matched = words.isEmpty ? all : all.filter { hit in
            let text = (hit.row.title + " " + hit.place).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        // 未読は同じ状態の中で先に
        return matched.sorted { ($0.row.status, $0.row.unread ? 0 : 1) < ($1.row.status, $1.row.unread ? 0 : 1) }
            .prefix(12).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("エージェント・ワークスペースを探す", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .focused($focused)
                .onSubmit { if let first = hits.first { pick(first.row) } }
            Divider()
            if hits.isEmpty {
                Text(cockpit.workspaceTree().isEmpty ? "リポジトリを登録すると、ここに並ぶ" : "当てはまるものが無い")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CockpitCanvas.dim)
                    .padding(12)
            }
            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                Button { pick(hit.row) } label: {
                    HStack(spacing: 8) {
                        StatusGlyph(status: hit.row.status)
                        Text(hit.row.title)
                            .font(.system(size: 12, weight: hit.row.unread ? .bold : .regular))
                            .lineLimit(1)
                        Text(hit.place)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(CockpitCanvas.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if index < 6 {
                            Text("⌘\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CockpitCanvas.dim)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(index < 6 ? KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command) : nil)
            }
        }
        .frame(width: 520)
        .background(CockpitCanvas.background)
        .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Palette.Radius.sm).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private func pick(_ row: Cockpit.AgentRow) {
        onPick(row)
        onClose()
    }
}

// MARK: - 通知

/// 見ていない間にターンが終わった・承認を求めてきた時の通知。**アプリが前に出ている間は出さない**
/// （サイドバーの太字と Dock のバッジで足りる）
enum Notifier {
    /// 通知は bundle ID のある .app（package.sh で組んだもの）の時だけ。
    /// `swift run` の素の実行ファイルで通知の口を叩くと落ちる
    @MainActor
    static func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
